import SwiftUI
import SwiftData

/// App root: hosts the tab bar (Now Playing / Favorites / Playlist / Browse /
/// Sync). The tab bar is always present; the metadata editor is reached from
/// the (i) button on the Now Playing tab instead of a separate pane.
///
/// `player`'s model context (for recently-played tracking) is wired once in
/// `AppEnvironment.init`, not here — that way it's set up before either scene
/// (this phone UI or CarPlay) connects.
struct RootContainerView: View {
    var body: some View {
        RootTabView()
            .background(Theme.background.ignoresSafeArea())
    }
}
