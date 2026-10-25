import Foundation

/// Process-wide, thread-safe record of *where* the music library currently
/// lives on disk. `LibraryStore`'s file URLs are read from many threads
/// (detached scan tasks, the sync engines' task groups), so this is guarded by
/// a lock rather than isolated to an actor — the accessors need to be callable
/// from `nonisolated` static contexts.
///
/// The base is one of two places, kept structurally identical so a song's id
/// (its path relative to the base — e.g. `Downloads/Artist/Song.mp3`) is
/// unchanged when the library moves, which keeps favorites and playlists
/// matching:
///   - local:  `<app Documents>`
///   - iCloud: `<ubiquity container>/Documents`
///
/// When the user wants iCloud but the container hasn't resolved yet,
/// `libraryBaseURL` falls back to local so nothing crashes — but `isBlocked`
/// is true, and callers that must not operate in that degraded state (the
/// scanner, above all) check it first. This is the specific failure that made
/// a previous iCloud attempt wipe the library at random: a scan ran against
/// the wrong/empty base before the container was ready. See `LibraryStore`.
final class LibraryStorageState: @unchecked Sendable {
    static let shared = LibraryStorageState()

    private let lock = NSLock()
    private var _wantsICloud = false
    private var _iCloudBase: URL?

    private init() {}

    /// The app's real on-device Documents directory. Always available; used as
    /// the local base and as the source/destination for iCloud migration.
    static var localDocumentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Whether the user has switched on iCloud storage. Mirrored here from
    /// `ICloudStorageStore` so the nonisolated URL accessors can read it.
    var wantsICloud: Bool {
        get { lock.withLock { _wantsICloud } }
        set { lock.withLock { _wantsICloud = newValue } }
    }

    /// The resolved `<container>/Documents` URL, or nil until it resolves.
    var iCloudBase: URL? {
        get { lock.withLock { _iCloudBase } }
        set { lock.withLock { _iCloudBase = newValue } }
    }

    /// The base the library reads/writes right now. Falls back to local when
    /// iCloud is wanted but not yet available — check `isBlocked` before doing
    /// anything destructive in that window.
    var libraryBaseURL: URL {
        lock.withLock {
            if _wantsICloud, let base = _iCloudBase { return base }
            return Self.localDocumentsURL
        }
    }

    /// True when the user wants iCloud but the container hasn't resolved. The
    /// library must be treated as "temporarily unknown" here — never scanned.
    var isBlocked: Bool {
        lock.withLock { _wantsICloud && _iCloudBase == nil }
    }
}
