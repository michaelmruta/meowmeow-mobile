import Foundation

/// Mirrors files between the external sync folder and the app's internal
/// Downloads library — a pure-Swift stand-in for `rsync` (no shell access is
/// available in the iOS sandbox). Currently one-directional (external ->
/// internal); `SyncDirection` exists so internal -> external can be added
/// later without reshaping the call sites.
enum SyncDirection {
    case externalToInternal
}

struct SyncStats {
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

enum SyncEngine {
    /// Playlists live in a folder named `_playlist` alongside the artist
    /// folders at the root of the sync folder. Unlike audio files, playlists
    /// are merged rather than mirrored: a remote playlist overwrites a local
    /// one with the same file name, but a local playlist absent from the
    /// external `_playlist` folder is left alone rather than deleted.
    private static let playlistFolderName = "_playlist"
    private static let playlistExtensions: Set<String> = ["m3u", "m3u8"]

    enum SyncError: LocalizedError {
        case folderNotAccessible

        var errorDescription: String? {
            switch self {
            case .folderNotAccessible:
                return "Couldn't access the sync folder. Try choosing it again in the Sync tab."
            }
        }
    }

    /// Mirrors `externalRoot` onto the app's Documents/Downloads folder: files
    /// new or changed on the external side are copied in, and files that no
    /// longer exist externally are removed internally (matching `rsync --delete`
    /// semantics for this direction). `onProgress` is called with a 0...1
    /// fraction as each file is processed, for a progress bar.
    static func sync(
        direction: SyncDirection = .externalToInternal,
        externalRoot: URL,
        onProgress: @escaping @MainActor (Double, String?) -> Void = { _, _ in }
    ) async throws -> SyncStats {
        guard externalRoot.startAccessingSecurityScopedResource() else {
            throw SyncError.folderNotAccessible
        }
        defer { externalRoot.stopAccessingSecurityScopedResource() }

        await onProgress(0, nil)

        let internalRoot = await MainActor.run { LibraryStore.downloadsURL }
        let fm = FileManager.default
        try fm.createDirectory(at: internalRoot, withIntermediateDirectories: true)

        let allSourceFiles = LocalDirectorySnapshot.fileMap(root: externalRoot)
        let sourceFiles = allSourceFiles.filter { relativePath, _ in
            !relativePath.hasPrefix("\(playlistFolderName)/")
        }
        // Playlists live in a `_playlist` subfolder inside Downloads (see
        // `LibraryStore.playlistsURL`), so they must be excluded here —
        // otherwise the audio mirror below would see them as files absent
        // from the external side (they're never in `sourceFiles`, which
        // excludes `_playlist/` above) and delete them every sync.
        let destinationFiles = LocalDirectorySnapshot.fileMap(root: internalRoot).filter { relativePath, _ in
            !relativePath.hasPrefix("\(playlistFolderName)/")
        }

        let changedEntries = sourceFiles.filter { relativePath, sourceInfo in
            guard let existing = destinationFiles[relativePath] else { return true }
            return sourceInfo.size != existing.size || sourceInfo.modDate > existing.modDate
        }
        let deletedEntries = destinationFiles.filter { relativePath, _ in
            sourceFiles[relativePath] == nil
        }

        var sourcePlaylists: [String: LocalDirectorySnapshot.FileInfo] = [:]
        for (relativePath, info) in allSourceFiles
        where relativePath.hasPrefix("\(playlistFolderName)/")
            && playlistExtensions.contains((relativePath as NSString).pathExtension.lowercased()) {
            let fileName = String(relativePath.dropFirst(playlistFolderName.count + 1))
            guard !fileName.contains("/") else { continue }
            sourcePlaylists[fileName] = info
        }

        let playlistsRoot = await MainActor.run { LibraryStore.playlistsURL }
        try fm.createDirectory(at: playlistsRoot, withIntermediateDirectories: true)
        let destinationPlaylists = LocalDirectorySnapshot.fileMap(root: playlistsRoot)

        let changedPlaylists = sourcePlaylists.filter { fileName, sourceInfo in
            guard let existing = destinationPlaylists[fileName] else { return true }
            return sourceInfo.size != existing.size || sourceInfo.modDate > existing.modDate
        }

        var stats = SyncStats()
        let totalUnits = max(changedEntries.count + deletedEntries.count + changedPlaylists.count, 1)
        var completedUnits = 0

        for (relativePath, sourceInfo) in changedEntries {
            let destinationURL = internalRoot.appendingPathComponent(relativePath)
            let isNew = destinationFiles[relativePath] == nil
            try? fm.removeItem(at: destinationURL)
            try? fm.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: sourceInfo.url, to: destinationURL)
            if isNew { stats.added += 1 } else { stats.updated += 1 }

            completedUnits += 1
            await onProgress(Double(completedUnits) / Double(totalUnits), relativePath)
        }

        for (relativePath, existing) in deletedEntries {
            try? fm.removeItem(at: existing.url)
            stats.deleted += 1

            completedUnits += 1
            await onProgress(Double(completedUnits) / Double(totalUnits), relativePath)
        }

        for (fileName, sourceInfo) in changedPlaylists {
            let destinationURL = playlistsRoot.appendingPathComponent(fileName)
            try? fm.removeItem(at: destinationURL)
            try fm.copyItem(at: sourceInfo.url, to: destinationURL)
            stats.playlistsUpdated += 1

            completedUnits += 1
            await onProgress(Double(completedUnits) / Double(totalUnits), fileName)
        }

        LocalDirectorySnapshot.removeEmptySubdirectories(of: internalRoot)
        await onProgress(1, nil)
        return stats
    }
}
