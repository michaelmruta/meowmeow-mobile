import SwiftUI

enum RootTab: Hashable {
    case nowPlaying, favorites, playlist, browse, sync
}

@MainActor
@Observable
final class TabRouter {
    var selection: RootTab = .nowPlaying
    private var pendingSelection: RootTab?
    private var isSelectionUpdateScheduled = false

    func select(_ tab: RootTab) {
        guard tab != selection else { return }

        pendingSelection = tab
        guard !isSelectionUpdateScheduled else { return }

        isSelectionUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            Task { @MainActor in
                self?.applyPendingSelection()
            }
        }
    }

    private func applyPendingSelection() {
        defer {
            pendingSelection = nil
            isSelectionUpdateScheduled = false
        }

        guard let pendingSelection, pendingSelection != selection else { return }
        selection = pendingSelection
    }
}

struct RootTabView: View {
    @Environment(TabRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selection) {
            NavigationStack {
                PlayerView()
            }
            .tabItem { Label("Now Playing", systemImage: "play.circle.fill") }
            .tag(RootTab.nowPlaying)

            NavigationStack {
                FavoritesView()
            }
            .tabItem { Label("Favorites", systemImage: "heart.fill") }
            .tag(RootTab.favorites)

            NavigationStack {
                PlaylistsView()
            }
            .tabItem { Label("Playlist", systemImage: "music.note.list") }
            .tag(RootTab.playlist)

            NavigationStack {
                BrowseView()
            }
            .tabItem { Label("Browse", systemImage: "square.grid.2x2.fill") }
            .tag(RootTab.browse)

            NavigationStack {
                SyncView()
            }
            .tabItem { Label("Sync", systemImage: "arrow.triangle.2.circlepath") }
            .tag(RootTab.sync)
        }
        .tint(Theme.orange)
    }
}
