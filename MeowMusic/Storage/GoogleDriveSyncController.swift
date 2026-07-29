import Foundation
import Observation

/// Owns the running Google Drive sync `Task` and its progress state at app
/// scope (injected via `.environment`), rather than inside `SyncView` — so
/// switching tabs or the sync-source picker doesn't tear down an in-flight
/// sync's state or let the user start a second, overlapping one. Because
/// `GoogleDriveSyncEngine` only re-downloads files whose size/mod-date
/// differ from what's already stored locally, an interrupted sync (app
/// backgrounded, network drop) can simply be re-started and it resumes
/// where it left off — already-completed files are skipped. Mirrors
/// `WebDAVSyncController`.
@MainActor
@Observable
final class GoogleDriveSyncController {
    private(set) var isSyncing = false
    private(set) var completedUnits = 0
    private(set) var totalUnits = 0
    private(set) var lastResultText: String?
    private(set) var syncError: String?

    var progress: Double {
        totalUnits == 0 ? 0 : Double(completedUnits) / Double(totalUnits)
    }

    private var task: Task<Void, Never>?

    /// Takes the account store rather than a pre-fetched token, so a stale
    /// or expired access token is refreshed right before the sync starts.
    func startSync(rootFolderID: String, account: GoogleDriveAccountStore, library: LibraryStore) {
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
                let credentials = try await account.credentials()
                let stats = try await GoogleDriveSyncEngine.sync(rootFolderID: rootFolderID, credentials: credentials) { completed, total in
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
