import CarPlay
import UIKit

/// Bridges the app's existing playback engine and library into CarPlay. This
/// runs as a separate `UIScene` from the phone's SwiftUI window scene — see
/// `AppEnvironment` for why both read from the same shared `PlayerService` /
/// `LibraryStore` / `ModelContainer` instead of each building their own.
///
/// Routed here by the `UIApplicationSceneManifest` entry in Info.plist (see
/// `project.yml`) and, redundantly, by `AppDelegate.application(_:configurationForConnecting:options:)`.
///
/// Now Playing needs almost no code of its own: `PlayerService` already
/// drives `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter`
/// (`PlayerService.configureRemoteCommands`/`updateNowPlayingInfo`), and
/// `CPNowPlayingTemplate.shared` renders directly from those system APIs.
@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    private let templateBuilder = CarPlayTemplateBuilder()

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        templateBuilder.interfaceController = interfaceController

        // `LibraryStore.init` seeds from the on-disk cache, so this is
        // usually non-empty immediately — show it right away rather than
        // waiting on the scan.
        interfaceController.setRootTemplate(templateBuilder.makeRootTemplate(), animated: true, completion: nil)

        Task {
            // Idempotent: a no-op if the phone's WindowGroup already ran this
            // (normal case). Covers a cold launch straight into CarPlay,
            // where the phone window scene never mounted to trigger it.
            await AppEnvironment.shared.bootstrapIfNeeded()
            // Rebuild once the library has settled, in case the cache seed
            // above was stale or empty.
            interfaceController.setRootTemplate(templateBuilder.makeRootTemplate(), animated: false, completion: nil)
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        self.interfaceController = nil
        templateBuilder.interfaceController = nil
    }
}
