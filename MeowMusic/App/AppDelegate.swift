import UIKit

/// Exists solely to route the CarPlay scene to `CarPlaySceneDelegate`. The
/// phone window scene is left untouched (SwiftUI's `WindowGroup` keeps owning
/// it) — this delegate must NOT return a configuration with a `delegateClass`
/// for the window role, or it replaces SwiftUI's own scene management and the
/// phone UI stops appearing.
///
/// This is belt-and-suspenders alongside the `UIApplicationSceneManifest`
/// entry in Info.plist (see `project.yml`), which declares the same CarPlay
/// role declaratively. Either mechanism alone is enough; keeping both is the
/// documented-safe way to add a UIKit-driven scene to a SwiftUI-lifecycle app.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if connectingSceneSession.role == .carTemplateApplication {
            let config = UISceneConfiguration(name: "CarPlay", sessionRole: connectingSceneSession.role)
            config.delegateClass = CarPlaySceneDelegate.self
            return config
        }
        return UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
    }
}
