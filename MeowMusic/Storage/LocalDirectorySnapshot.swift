import Foundation

/// A snapshot of regular files under a directory, keyed by path relative to
/// that directory. Shared by `SyncEngine` and `WebDAVSyncEngine` so both can
/// diff a remote/external file listing against what's already in the app's
/// internal library folder.
enum LocalDirectorySnapshot {
    struct FileInfo {
        let url: URL
        let modDate: Date
        let size: Int
    }

    nonisolated static func fileMap(root: URL) -> [String: FileInfo] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return [:]
        }

        // The enumerator resolves symlinks in the paths it returns (e.g. iOS's
        // /var -> /private/var), while `root` itself typically doesn't, so
        // both sides are normalized the same way before stripping the prefix
        // — otherwise the substring match fails, every file's key comes out
        // mangled, and syncs treat everything as new on every run.
        let normalizedRootPath = root.resolvingSymlinksInPath().path

        var map: [String: FileInfo] = [:]
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey])
            guard values?.isRegularFile == true else { continue }
            let relativePath = url.resolvingSymlinksInPath().path.replacingOccurrences(of: normalizedRootPath + "/", with: "")
            map[relativePath] = FileInfo(
                url: url,
                modDate: values?.contentModificationDate ?? .distantPast,
                size: values?.fileSize ?? 0
            )
        }
        return map
    }

    nonisolated static func removeEmptySubdirectories(of root: URL) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        for entry in entries {
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: entry.path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
            let contents = (try? fm.contentsOfDirectory(atPath: entry.path)) ?? []
            if contents.isEmpty {
                try? fm.removeItem(at: entry)
            }
        }
    }
}
