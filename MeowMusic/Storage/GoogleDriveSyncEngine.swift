import Foundation

struct GoogleDriveSyncStats {
    var added = 0
    var updated = 0
    var deleted = 0
    var playlistsUpdated = 0

    var isEmpty: Bool { added == 0 && updated == 0 && deleted == 0 && playlistsUpdated == 0 }

    var summaryText: String {
        guard !isEmpty else { return "Already up to date" }
        var parts: [String] = []
        if added > 0 { parts.append("\(added) added") }
        if updated > 0 { parts.append("\(updated) updated") }
        if deleted > 0 { parts.append("\(deleted) removed") }
        if playlistsUpdated > 0 { parts.append("\(playlistsUpdated) playlist\(playlistsUpdated == 1 ? "" : "s") synced") }
        return parts.joined(separator: ", ")
    }
}

/// Mirrors a Google Drive folder into the app's internal Downloads library,
/// the same way `WebDAVSyncEngine` mirrors a WebDAV share: new/changed audio
/// files are downloaded in, and files that no longer exist in Drive are
/// removed locally. Downloads run with bounded concurrency
/// (`GoogleDriveClient.maxConcurrentRequests` at a time) rather than one at a
/// time, since most of the wait on a sequential sync is network round trips
/// rather than transfer itself.
enum GoogleDriveSyncEngine {
    private static let audioExtensions: Set<String> = ["mp4", "m4a", "mp3", "wav", "aac", "flac"]

    /// Playlists live in a folder named `_playlist` alongside the artist
    /// folders at the root of the synced Drive folder. Unlike audio files,
    /// playlists are merged rather than mirrored: a remote playlist
    /// overwrites a local one with the same file name, but a local playlist
    /// absent from the remote `_playlist` folder is left alone rather than
    /// deleted.
    private static let playlistFolderName = "_playlist"
    private static let playlistExtensions: Set<String> = ["m3u", "m3u8"]

    /// `onProgress` reports (files completed so far, total files to sync) —
    /// e.g. (1, 1000) — rather than a single "current file", since multiple
    /// downloads are now in flight at once.
    static func sync(
        rootFolderID: String,
        credentials: GoogleDriveCredentials,
        onProgress: @escaping @MainActor (Int, Int) -> Void = { _, _ in }
    ) async throws -> GoogleDriveSyncStats {
        await onProgress(0, 0)

        let internalRoot = await MainActor.run { LibraryStore.downloadsURL }
        let fm = FileManager.default
        try fm.createDirectory(at: internalRoot, withIntermediateDirectories: true)

        let remoteEntries = try await GoogleDriveClient.listFiles(rootFolderID: rootFolderID, credentials: credentials)

        var sourceFiles: [String: GoogleDriveEntry] = [:]
        for entry in remoteEntries
        where !entry.relativePath.hasPrefix(".") && !entry.relativePath.contains("/.")
            && audioExtensions.contains(pathExtension(of: entry.relativePath)) {
            sourceFiles[entry.relativePath] = entry
        }

        // Playlists live in a `_playlist` subfolder inside Downloads (see
        // `LibraryStore.playlistsURL`), so they must be excluded here —
        // otherwise the audio mirror below would see them as files that no
        // longer exist remotely (they're never in `sourceFiles`, which is
        // audio-extensions only) and delete them every sync.
        let destinationFiles = LocalDirectorySnapshot.fileMap(root: internalRoot).filter { relativePath, _ in
            !relativePath.hasPrefix("\(playlistFolderName)/")
        }

        let changedEntries = sourceFiles.filter { relativePath, sourceEntry in
            guard let existing = destinationFiles[relativePath] else { return true }
            return sourceEntry.size != existing.size || sourceEntry.modDate > existing.modDate
        }
        let deletedEntries = destinationFiles.filter { relativePath, _ in
            sourceFiles[relativePath] == nil
        }

        var sourcePlaylists: [String: GoogleDriveEntry] = [:]
        for entry in remoteEntries
        where !entry.relativePath.hasPrefix(".")
            && playlistExtensions.contains(pathExtension(of: entry.relativePath))
            && entry.relativePath.hasPrefix("\(playlistFolderName)/") {
            let fileName = String(entry.relativePath.dropFirst(playlistFolderName.count + 1))
            guard !fileName.contains("/") else { continue }
            sourcePlaylists[fileName] = entry
        }

        let playlistsRoot = await MainActor.run { LibraryStore.playlistsURL }
        try fm.createDirectory(at: playlistsRoot, withIntermediateDirectories: true)
        let destinationPlaylists = LocalDirectorySnapshot.fileMap(root: playlistsRoot)

        let changedPlaylists = sourcePlaylists.filter { fileName, sourceEntry in
            guard let existing = destinationPlaylists[fileName] else { return true }
            return sourceEntry.size != existing.size || sourceEntry.modDate > existing.modDate
        }

        let totalUnits = changedEntries.count + deletedEntries.count + changedPlaylists.count
        var stats = GoogleDriveSyncStats()
        var completedUnits = 0
        await onProgress(completedUnits, totalUnits)

        if !changedEntries.isEmpty {
            let jobs = changedEntries.map { relativePath, sourceEntry in
                (relativePath: relativePath, sourceEntry: sourceEntry, isNew: destinationFiles[relativePath] == nil)
            }

            try await withThrowingTaskGroup(of: Bool.self) { group in
                var iterator = jobs.makeIterator()

                func addNext() {
                    guard let job = iterator.next() else { return }
                    let destinationURL = internalRoot.appendingPathComponent(job.relativePath)
                    group.addTask {
                        try await GoogleDriveClient.download(fileID: job.sourceEntry.id, to: destinationURL, modificationDate: job.sourceEntry.modDate, credentials: credentials)
                        return job.isNew
                    }
                }

                for _ in 0..<min(GoogleDriveClient.maxConcurrentRequests, jobs.count) { addNext() }
                while let isNew = try await group.next() {
                    if isNew { stats.added += 1 } else { stats.updated += 1 }
                    completedUnits += 1
                    await onProgress(completedUnits, totalUnits)
                    addNext()
                }
            }
        }

        for (_, existing) in deletedEntries {
            try? fm.removeItem(at: existing.url)
            stats.deleted += 1
            completedUnits += 1
            await onProgress(completedUnits, totalUnits)
        }

        if !changedPlaylists.isEmpty {
            try await withThrowingTaskGroup(of: Void.self) { group in
                var iterator = changedPlaylists.makeIterator()

                func addNext() {
                    guard let (fileName, sourceEntry) = iterator.next() else { return }
                    let destinationURL = playlistsRoot.appendingPathComponent(fileName)
                    group.addTask {
                        try await GoogleDriveClient.download(fileID: sourceEntry.id, to: destinationURL, modificationDate: sourceEntry.modDate, credentials: credentials)
                    }
                }

                for _ in 0..<min(GoogleDriveClient.maxConcurrentRequests, changedPlaylists.count) { addNext() }
                while try await group.next() != nil {
                    stats.playlistsUpdated += 1
                    completedUnits += 1
                    await onProgress(completedUnits, totalUnits)
                    addNext()
                }
            }
        }

        LocalDirectorySnapshot.removeEmptySubdirectories(of: internalRoot)
        await onProgress(totalUnits, totalUnits)
        return stats
    }

    nonisolated private static func pathExtension(of relativePath: String) -> String {
        (relativePath as NSString).pathExtension.lowercased()
    }
}
