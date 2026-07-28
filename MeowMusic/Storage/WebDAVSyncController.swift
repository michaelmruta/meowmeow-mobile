import Foundation
import Observation

/// Owns the running WebDAV sync `Task` and its progress state at app scope
/// (injected via `.environment`), rather than inside `SyncView` — so
/// switching tabs or the Local/WebDAV picker doesn't tear down an in-flight
/// sync's state or let the user start a second, overlapping one. Because
/// `WebDAVSyncEngine` only re-downloads files whose size/mod-date differ from
/// what's already stored locally, an interrupted sync (app backgrounded,
/// network drop) can simply be re-started and it resumes where it left off —
/// already-completed files are skipped.
@MainActor
@Observable
final class WebDAVSyncController {
    private(set) var isSyncing = false
    private(set) var completedUnits = 0
    private(set) var totalUnits = 0
    private(set) var lastResultText: String?
    private(set) var syncError: String?

    var progress: Double {
        totalUnits == 0 ? 0 : Double(completedUnits) / Double(totalUnits)
    }

    private var task: Task<Void, Never>?

    func startSync(root: URL, credentials: WebDAVCredentials, library: LibraryStore) {
        guard !isSyncing else { return }
        isSyncing = true
        completedUnits = 0
        totalUnits = 0
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
                let stats = try await WebDAVSyncEngine.sync(root: root, credentials: credentials) { completed, total in
                    self?.completedUnits = completed
                    self?.totalUnits = total
                }
                self?.lastResultText = stats.summaryText
                await library.scan()
            } catch {
                self?.syncError = error.localizedDescription
            }
        }
    }
}
