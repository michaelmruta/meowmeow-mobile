import Foundation
import Observation

/// Owns the "Store music in iCloud" toggle and the machinery behind it:
/// resolving the app's iCloud Drive container, publishing it to
/// `LibraryStorageState`, and migrating the on-disk `Downloads` library
/// between local storage and iCloud when the switch is flipped.
///
/// The container is resolved OFF the main thread (the call blocks and can take
/// a moment on first use), and a nil result is treated as "iCloud unavailable"
/// rather than "the library is empty" — see `LibraryStorageState` for why that
/// distinction matters.
@MainActor
@Observable
final class ICloudStorageStore {
    enum Status: Equatable {
        /// Storing locally on device (toggle off).
        case local
        /// Toggle on; resolving or migrating the iCloud container.
        case working
        /// Toggle on and the iCloud container is ready.
        case active
        /// Toggle on but iCloud can't be used right now; carries a reason.
        case unavailable(String)
    }

    private static let containerID = "iCloud.com.michaelruta.MeowMusic"
    private static let enabledKey = "storage.useICloud"

    private(set) var isEnabled: Bool
    private(set) var isBusy = false
    private(set) var status: Status

    init() {
        let enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        isEnabled = enabled
        status = enabled ? .working : .local
        // Publish the intent immediately so the very first scan knows it must
        // wait for the container (isBlocked) instead of scanning local.
        LibraryStorageState.shared.wantsICloud = enabled
    }

    /// Resolves the iCloud container (if the toggle is on) and publishes it to
    /// `LibraryStorageState`. Called once at launch, before the first scan, so
    /// the scan targets the right base. No-ops when the toggle is off.
    func resolveIfNeeded() async {
        guard isEnabled else {
            LibraryStorageState.shared.iCloudBase = nil
            status = .local
            return
        }
        status = .working
        if let base = await Self.resolveContainerDocuments() {
            LibraryStorageState.shared.iCloudBase = base
            status = .active
        } else {
            LibraryStorageState.shared.iCloudBase = nil
            status = .unavailable("iCloud is unavailable. Sign in to iCloud in Settings, then reopen the app.")
        }
    }

    /// Flips the toggle, migrating the `Downloads` library between local and
    /// iCloud storage, then rescans. On failure the toggle is left unchanged
    /// and `status` explains why.
    func setEnabled(_ enabled: Bool, library: LibraryStore) async {
        guard enabled != isEnabled, !isBusy else { return }
        isBusy = true
        status = .working
        defer { isBusy = false }

        if enabled {
            guard let base = await Self.resolveContainerDocuments() else {
                status = .unavailable("iCloud is unavailable. Sign in to iCloud in Settings, then try again.")
                return
            }
            let migrated = await Self.migrate(toICloud: true, iCloudDocuments: base)
            guard migrated else {
                status = .unavailable("Couldn't move your library to iCloud. Check that you're signed in and have enough iCloud storage.")
                return
            }
            LibraryStorageState.shared.wantsICloud = true
            LibraryStorageState.shared.iCloudBase = base
            isEnabled = true
            UserDefaults.standard.set(true, forKey: Self.enabledKey)
            status = .active
        } else {
            var base = LibraryStorageState.shared.iCloudBase
            if base == nil { base = await Self.resolveContainerDocuments() }
            if let base {
                let migrated = await Self.migrate(toICloud: false, iCloudDocuments: base)
                guard migrated else {
                    status = .unavailable("Couldn't move your library back from iCloud. Try again once iCloud is reachable.")
                    return
                }
            }
            LibraryStorageState.shared.wantsICloud = false
            LibraryStorageState.shared.iCloudBase = nil
            isEnabled = false
            UserDefaults.standard.set(false, forKey: Self.enabledKey)
            status = .local
        }

        await library.scan()
    }

    // MARK: - Container resolution

    /// Resolves `<container>/Documents`, creating the folder. Runs off the main
    /// thread because `url(forUbiquityContainerIdentifier:)` blocks. Returns
    /// nil when iCloud isn't signed in / available.
    private static func resolveContainerDocuments() async -> URL? {
        let containerID = Self.containerID
        return await Task.detached(priority: .userInitiated) {
            guard let container = FileManager.default.url(forUbiquityContainerIdentifier: containerID) else {
                return nil
            }
            let documents = container.appendingPathComponent("Documents", isDirectory: true)
            try? FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
            return documents
        }.value
    }

    // MARK: - Migration

    /// Moves the `Downloads` tree between local Documents and the iCloud
    /// container's Documents using `setUbiquitous`, off the main thread.
    /// Returns whether it succeeded (a missing source counts as success —
    /// there's simply nothing to move).
    private static func migrate(toICloud: Bool, iCloudDocuments: URL) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let local = LibraryStorageState.localDocumentsURL.appendingPathComponent("Downloads", isDirectory: true)
            let cloud = iCloudDocuments.appendingPathComponent("Downloads", isDirectory: true)
            let source = toICloud ? local : cloud
            let destination = toICloud ? cloud : local

            guard fm.fileExists(atPath: source.path) else { return true }

            do {
                if fm.fileExists(atPath: destination.path) {
                    // Destination already has a Downloads tree (e.g. a leftover
                    // or a partial prior migration) — move children in one at a
                    // time so we merge rather than fail outright.
                    let children = (try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)) ?? []
                    for child in children {
                        let childDest = destination.appendingPathComponent(child.lastPathComponent)
                        try? fm.removeItem(at: childDest)
                        try fm.setUbiquitous(toICloud, itemAt: child, destinationURL: childDest)
                    }
                    try? fm.removeItem(at: source)
                } else {
                    try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.setUbiquitous(toICloud, itemAt: source, destinationURL: destination)
                }
                return true
            } catch {
                return false
            }
        }.value
    }
}
