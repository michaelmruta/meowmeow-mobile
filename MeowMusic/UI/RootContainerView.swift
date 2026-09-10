import SwiftUI
import SwiftData

/// App root: hosts the tab bar (Now Playing / Favorites / Playlist / Browse /
/// Sync). The tab bar is always present; the metadata editor is reached from
/// the (i) button on the Now Playing tab instead of a separate pane.
struct RootContainerView: View {
    @Environment(PlayerService.self) private var player
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        RootTabView()
            .background(Theme.background.ignoresSafeArea())
            .task {
                // Inject model context into player for recently played tracking
                player.setModelContext(modelContext)
            }
    }
}
