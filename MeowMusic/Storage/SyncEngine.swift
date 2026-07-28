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

enum SyncEngine {
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

        let sourceFiles = LocalDirectorySnapshot.fileMap(root: externalRoot)
        let destinationFiles = LocalDirectorySnapshot.fileMap(root: internalRoot)

        let changedEntries = sourceFiles.filter { relativePath, sourceInfo in
            guard let existing = destinationFiles[relativePath] else { return true }
            return sourceInfo.size != existing.size || sourceInfo.modDate > existing.modDate
        }
        let deletedEntries = destinationFiles.filter { relativePath, _ in
            sourceFiles[relativePath] == nil
        }

        var stats = SyncStats()
        let totalUnits = max(changedEntries.count + deletedEntries.count, 1)
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

        LocalDirectorySnapshot.removeEmptySubdirectories(of: internalRoot)
        await onProgress(1, nil)
        return stats
    }
}
