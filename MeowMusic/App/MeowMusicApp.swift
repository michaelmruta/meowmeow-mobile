import SwiftUI
import SwiftData
import GoogleSignIn

@main
struct MeowMusicApp: App {
    // `library`, `player`, `iCloudStore`, and `modelContainer` live in
    // `AppEnvironment.shared` instead of here, so the CarPlay scene (a
    // separate UIScene with no access to this struct) can drive the exact
    // same instances. See AppEnvironment.swift.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let env = AppEnvironment.shared

    @State private var syncStore = SyncBookmarkStore()
    @State private var webDAVStore = WebDAVAccountStore()
    @State private var googleDriveStore = GoogleDriveAccountStore()
    @State private var localSyncController = LocalSyncController()
    @State private var webDAVSyncController = WebDAVSyncController()
    @State private var googleDriveSyncController = GoogleDriveSyncController()
    @State private var tabRouter = TabRouter()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootContainerView()
                .environment(env.library)
                .environment(env.player)
                .environment(syncStore)
                .environment(webDAVStore)
                .environment(googleDriveStore)
                .environment(env.iCloudStore)
                .environment(localSyncController)
                .environment(webDAVSyncController)
                .environment(googleDriveSyncController)
                .environment(tabRouter)
                .preferredColorScheme(.dark)
                .task {
                    configureGoogleSignIn()
                    // Resolves iCloud + runs the first scan exactly once,
                    // whichever scene (this one or CarPlay) connects first.
                    await env.bootstrapIfNeeded()
                    await googleDriveStore.restorePreviousSignIn()
#if DEBUG
                    configureScreenshotModeIfNeeded()
#endif
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        Task {
                            // Re-resolve iCloud first so a container that was
                            // unavailable at launch (not signed in yet) recovers
                            // on foreground before the scan reads storage.
                            await env.iCloudStore.resolveIfNeeded()
                            await env.library.scan()
                        }
                        syncStore.refreshReachability()
                    }
                }
                .onOpenURL { url in
                    _ = GIDSignIn.sharedInstance.handle(url)
                }
        }
        .modelContainer(env.modelContainer)
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
            guard let firstSong = env.library.songs.first else { return }
            env.player.play(song: firstSong, in: env.library.songs)
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
