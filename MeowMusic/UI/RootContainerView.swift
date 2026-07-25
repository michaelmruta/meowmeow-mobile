import SwiftUI

/// App root: hosts the tab bar (Now Playing / Favorites / Playlist / Browse /
/// Sync). The tab bar is always present; the metadata editor is reached from
/// the (i) button on the Now Playing tab instead of a separate pane.
struct RootContainerView: View {
    var body: some View {
        RootTabView()
            .background(Theme.background.ignoresSafeArea())
    }
}
