import SwiftUI

enum RootTab: Hashable {
    case nowPlaying, favorites, playlist, browse, sync
}

@MainActor
@Observable
final class TabRouter {
    var selection: RootTab = .nowPlaying {
        didSet {
            guard oldValue != selection else { return }
            previousSelection = oldValue
        }
    }
    var browsePath: [String] = []
    private(set) var previousSelection: RootTab?
    private var pendingSelection: RootTab?
    private var isSelectionUpdateScheduled = false
    var showRecentlyPlayed = false

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

    func openArtist(_ artist: String) {
        browsePath = [artist]
        select(.browse)
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
        TabView(selection: Binding(
            get: { router.selection },
            set: { newValue in
                // If tapping the same tab, toggle Recently Played
                if newValue == .nowPlaying && router.selection == .nowPlaying {
                    router.showRecentlyPlayed.toggle()
                } else {
                    // Switching to a different tab
                    if newValue != .nowPlaying {
                        router.showRecentlyPlayed = false
                    }
                    router.selection = newValue
                }
            }
        )) {
            NavigationStack {
                Group {
                    if router.showRecentlyPlayed {
                        RecentlyPlayedView()
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    } else {
                        PlayerView()
                            .transition(.asymmetric(
                                insertion: .move(edge: .leading).combined(with: .opacity),
                                removal: .move(edge: .trailing).combined(with: .opacity)
                            ))
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: router.showRecentlyPlayed)
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

            NavigationStack(path: $router.browsePath) {
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
