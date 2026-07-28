import SwiftUI
import SwiftData

@main
struct MeowMusicApp: App {
    @State private var library = LibraryStore()
    @State private var player = PlayerService()
    @State private var syncStore = SyncBookmarkStore()
    @State private var webDAVStore = WebDAVAccountStore()
    @State private var localSyncController = LocalSyncController()
    @State private var webDAVSyncController = WebDAVSyncController()
    @State private var tabRouter = TabRouter()
    @Environment(\.scenePhase) private var scenePhase

    var modelContainer: ModelContainer = {
        let schema = Schema([FavoriteRecord.self, PlaylistEntity.self, PlaylistSongEntity.self])
        let config = ModelConfiguration(schema: schema, cloudKitDatabase: .none)

        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            let fallbackConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            return try! ModelContainer(for: schema, configurations: [fallbackConfig])
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootContainerView()
                .environment(library)
                .environment(player)
                .environment(syncStore)
                .environment(webDAVStore)
                .environment(localSyncController)
                .environment(webDAVSyncController)
                .environment(tabRouter)
                .preferredColorScheme(.dark)
                .task {
                    await library.scan()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        Task {
                            await library.scan()
                        }
                        syncStore.refreshReachability()
                    }
                }
        }
        .modelContainer(modelContainer)
    }
}
