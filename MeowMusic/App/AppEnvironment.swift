import Foundation
import SwiftData

/// Process-wide holder for the services a second `UIScene` (CarPlay) must
/// share with the phone's SwiftUI window scene: the single `PlayerService`
/// instance, the single `LibraryStore` instance, and the single
/// `ModelContainer` backing SwiftData. Two `ModelContainer`s over the same
/// on-disk store would fight each other as writers, and CarPlay must drive
/// the exact same `AVPlayer`/now-playing state the phone UI shows — so both
/// scenes read from here rather than each constructing their own.
///
/// `MeowMusicApp` injects `library`/`player` into the SwiftUI environment and
/// attaches `modelContainer` via `.modelContainer(...)`, same as before this
/// existed. `CarPlaySceneDelegate` reads the same three properties directly
/// (CarPlay has no `@Environment`/`@Query`).
@MainActor
final class AppEnvironment {
    static let shared = AppEnvironment()

    let modelContainer: ModelContainer
    let library: LibraryStore
    let player: PlayerService
    let iCloudStore: ICloudStorageStore

    private var didBootstrap = false

    private init() {
        modelContainer = Self.makeModelContainer()
        library = LibraryStore()
        player = PlayerService()
        iCloudStore = ICloudStorageStore()
        player.setModelContext(modelContainer.mainContext)
    }

    /// Resolves iCloud (if the user opted in) and runs the first library scan.
    /// Idempotent and safe to call from both the WindowGroup's `.task` and
    /// CarPlay's `didConnect` — whichever scene connects first runs it, so the
    /// library is ready even if the app launches straight into CarPlay without
    /// the phone window scene ever appearing.
    func bootstrapIfNeeded() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        await iCloudStore.resolveIfNeeded()
        await library.scan()
    }

    private static func makeModelContainer() -> ModelContainer {
        let schema = Schema([
            FavoriteRecord.self,
            PlaylistEntity.self,
            PlaylistSongEntity.self,
            RecentlyPlayedRecord.self
        ])
        let config = ModelConfiguration(schema: schema, cloudKitDatabase: .none)

        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            let fallbackConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            return try! ModelContainer(for: schema, configurations: [fallbackConfig])
        }
    }
}
