import SwiftUI
import SwiftData
import GoogleSignIn

@main
struct MeowMusicApp: App {
    @State private var library = LibraryStore()
    @State private var player = PlayerService()
    @State private var syncStore = SyncBookmarkStore()
    @State private var webDAVStore = WebDAVAccountStore()
    @State private var googleDriveStore = GoogleDriveAccountStore()
    @State private var localSyncController = LocalSyncController()
    @State private var webDAVSyncController = WebDAVSyncController()
    @State private var googleDriveSyncController = GoogleDriveSyncController()
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
                .environment(googleDriveStore)
                .environment(localSyncController)
                .environment(webDAVSyncController)
                .environment(googleDriveSyncController)
                .environment(tabRouter)
                .preferredColorScheme(.dark)
                .task {
                    configureGoogleSignIn()
                    await library.scan()
                    await googleDriveStore.restorePreviousSignIn()
#if DEBUG
                    configureScreenshotModeIfNeeded()
#endif
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        Task {
                            await library.scan()
                        }
                        syncStore.refreshReachability()
                    }
                }
                .onOpenURL { url in
                    _ = GIDSignIn.sharedInstance.handle(url)
                }
        }
        .modelContainer(modelContainer)
    }

    /// Loads the OAuth client ID from `GoogleService-Info.plist` and
    /// configures the GoogleSignIn SDK. No-ops if the plist isn't present
    /// yet, so Google Drive sign-in simply stays unavailable rather than
    /// crashing during setup.
    private func configureGoogleSignIn() {
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let clientID = plist["CLIENT_ID"] as? String else { return }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
    }

#if DEBUG
    /// Makes App Store screenshot capture deterministic without shipping demo
    /// content or test-only behavior in Release builds.
    private func configureScreenshotModeIfNeeded() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "--app-store-screenshot"),
              arguments.indices.contains(flagIndex + 1) else { return }

        switch arguments[flagIndex + 1] {
        case "player":
            guard let firstSong = library.songs.first else { return }
            player.play(song: firstSong, in: library.songs)
            tabRouter.selection = .nowPlaying
        case "browse":
            tabRouter.selection = .browse
        case "sync":
            tabRouter.selection = .sync
        default:
            break
        }
    }
#endif
}
