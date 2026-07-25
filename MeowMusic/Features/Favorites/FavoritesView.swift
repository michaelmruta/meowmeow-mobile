import SwiftUI
import SwiftData

struct FavoritesView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerService.self) private var player
    @Environment(TabRouter.self) private var tabRouter
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FavoriteRecord.dateFavorited, order: .reverse) private var favorites: [FavoriteRecord]
    @State private var searchText = ""

    private var orderedFavoriteSongs: [Song] {
        favorites.compactMap { library.song(withID: $0.songPath) }
    }

    private var filteredSongs: [Song] {
        guard !searchText.isEmpty else { return orderedFavoriteSongs }
        return orderedFavoriteSongs.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.artist.localizedCaseInsensitiveContains(searchText) ||
            $0.album.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Group {
            if orderedFavoriteSongs.isEmpty {
                emptyState
            } else if filteredSongs.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List(filteredSongs) { song in
                    SongRow(song: song, isPlaying: player.currentSong == song)
                        .contentShape(Rectangle())
                        .onTapGesture { play(song) }
                        .listRowBackground(RowHighlightBackground(isActive: player.currentSong == song))
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                unfavorite(song)
                            } label: {
                                Label("Unfavorite", systemImage: "heart.slash.fill")
                            }
                        }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Theme.background)
        .navigationTitle("Favorites")
        .searchable(text: $searchText, prompt: "Search favorites")
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Favorites Yet",
            systemImage: "heart",
            description: Text("Tap the heart on any song to add it here.")
        )
    }

    private func play(_ song: Song) {
        player.play(song: song, in: orderedFavoriteSongs)
        tabRouter.select(.nowPlaying)
    }

    private func unfavorite(_ song: Song) {
        if let record = favorites.first(where: { $0.songPath == song.id }) {
            modelContext.delete(record)
        }
    }
}
