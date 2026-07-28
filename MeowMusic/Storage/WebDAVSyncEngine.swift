import Foundation

struct WebDAVSyncStats {
    var added = 0
    var updated = 0
    var deleted = 0

    var isEmpty: Bool { added == 0 && updated == 0 && deleted == 0 }

    var summaryText: String {
        guard !isEmpty else { return "Already up to date" }
        var parts: [String] = []
        if added > 0 { parts.append("\(added) added") }
        if updated > 0 { parts.append("\(updated) updated") }
        if deleted > 0 { parts.append("\(deleted) removed") }
        return parts.joined(separator: ", ")
    }
}

/// Mirrors a WebDAV server folder into the app's internal Downloads library,
/// the same way `SyncEngine` mirrors a local external folder: new/changed
/// audio files are downloaded in, and files that no longer exist on the
/// server are removed locally. Downloads run with bounded concurrency
/// (`WebDAVClient.maxConcurrentRequests` at a time) rather than one at a
/// time, since most of the wait on a sequential sync is network round trips
/// rather than transfer itself.
enum WebDAVSyncEngine {
    private static let audioExtensions: Set<String> = ["mp4", "m4a", "mp3", "wav", "aac", "flac"]

    /// `onProgress` reports (files completed so far, total files to sync) —
    /// e.g. (1, 1000) — rather than a single "current file", since multiple
    /// downloads are now in flight at once.
    static func sync(
        root: URL,
        credentials: WebDAVCredentials,
        onProgress: @escaping @MainActor (Int, Int) -> Void = { _, _ in }
    ) async throws -> WebDAVSyncStats {
        await onProgress(0, 0)

        let internalRoot = await MainActor.run { LibraryStore.downloadsURL }
        let fm = FileManager.default
        try fm.createDirectory(at: internalRoot, withIntermediateDirectories: true)

        let remoteEntries = try await WebDAVClient.listFiles(root: root, credentials: credentials)
        var sourceFiles: [String: WebDAVEntry] = [:]
        for entry in remoteEntries
        where !entry.url.lastPathComponent.hasPrefix(".")
            && audioExtensions.contains(entry.url.pathExtension.lowercased()) {
            sourceFiles[relativePath(of: entry.url, root: root)] = entry
        }

        let destinationFiles = LocalDirectorySnapshot.fileMap(root: internalRoot)

        let changedEntries = sourceFiles.filter { relativePath, sourceEntry in
            guard let existing = destinationFiles[relativePath] else { return true }
            return sourceEntry.size != existing.size || sourceEntry.modDate > existing.modDate
        }
        let deletedEntries = destinationFiles.filter { relativePath, _ in
            sourceFiles[relativePath] == nil
        }

        let totalUnits = changedEntries.count + deletedEntries.count
        var stats = WebDAVSyncStats()
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
                        try await WebDAVClient.download(from: job.sourceEntry.url, to: destinationURL, modificationDate: job.sourceEntry.modDate, credentials: credentials)
                        return job.isNew
                    }
                }

                for _ in 0..<min(WebDAVClient.maxConcurrentRequests, jobs.count) { addNext() }
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

        LocalDirectorySnapshot.removeEmptySubdirectories(of: internalRoot)
        await onProgress(totalUnits, totalUnits)
        return stats
    }

    nonisolated private static func relativePath(of url: URL, root: URL) -> String {
        url.path.replacingOccurrences(of: root.path + "/", with: "")
    }
}
