import Foundation
import Observation

/// Owns the running local-folder sync `Task` and its progress state at app
/// scope (injected via `.environment`), rather than inside `SyncView` — so
/// switching tabs or the Local/WebDAV picker doesn't tear down an in-flight
/// sync's state or let the user start a second, overlapping one.
@MainActor
@Observable
final class LocalSyncController {
    private(set) var isSyncing = false
    private(set) var progress: Double = 0
    private(set) var currentFileName: String?
    private(set) var lastResultText: String?
    private(set) var syncError: String?

    private var task: Task<Void, Never>?

    func startSync(folderURL: URL, library: LibraryStore, syncStore: SyncBookmarkStore) {
        guard !isSyncing else { return }
        isSyncing = true
        progress = 0
        currentFileName = nil
        syncError = nil
        lastResultText = nil
        IdleTimerGuard.begin()

        task = Task { [weak self] in
            defer {
                self?.isSyncing = false
                self?.task = nil
                IdleTimerGuard.end()
            }
            do {
                let stats = try await SyncEngine.sync(externalRoot: folderURL) { progress, fileName in
                    self?.progress = progress
                    self?.currentFileName = fileName
                }
                self?.lastResultText = stats.summaryText
                await library.scan()
                syncStore.refreshReachability()
            } catch {
                self?.syncError = error.localizedDescription
            }
        }
    }
}
