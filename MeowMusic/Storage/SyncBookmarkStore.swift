import Foundation
import Observation

/// Persists access to a user-chosen sync folder (picked via the system Files
/// picker, which surfaces external USB-C drives on supported iPhones) using a
/// security-scoped bookmark. `isReachable` is the closest iOS lets a sandboxed
/// app get to a "device connected" indicator — there is no hot-plug API for
/// arbitrary external volumes, so this is checked on demand / on foreground.
@MainActor
@Observable
final class SyncBookmarkStore {
    private let bookmarkKey = "syncFolderBookmark"
    private let displayNameKey = "syncFolderDisplayName"

    private(set) var folderDisplayName: String?
    private(set) var isReachable = false
    private var resolvedURL: URL?

    /// The bookmarked folder URL, for callers (like `SyncEngine`) that need to
    /// start/stop their own security-scoped access around a longer operation.
    var folderURL: URL? { resolvedURL }

    init() {
        restoreBookmark()
    }

    func setFolder(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            let bookmark = try url.bookmarkData()
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            UserDefaults.standard.set(url.lastPathComponent, forKey: displayNameKey)
            folderDisplayName = url.lastPathComponent
            resolvedURL = url
            checkReachability()
        } catch {
            // Keep previous state; picker access failed to bookmark.
        }
    }

    func clearFolder() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        UserDefaults.standard.removeObject(forKey: displayNameKey)
        folderDisplayName = nil
        resolvedURL = nil
        isReachable = false
    }

    func refreshReachability() {
        checkReachability()
    }

    private func restoreBookmark() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        folderDisplayName = UserDefaults.standard.string(forKey: displayNameKey)
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &isStale) else {
            isReachable = false
            return
        }
        resolvedURL = url
        checkReachability()
    }

    private func checkReachability() {
        guard let url = resolvedURL else {
            isReachable = false
            return
        }
        guard url.startAccessingSecurityScopedResource() else {
            isReachable = false
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        isReachable = (try? url.checkResourceIsReachable()) ?? false
    }
}
