import SwiftUI

struct BrowseView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerService.self) private var player
    @Environment(TabRouter.self) private var tabRouter
    @State private var searchText = ""

    private var searchResults: [Song] {
        guard !searchText.isEmpty else { return [] }
        return library.songs
            .filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.artist.localizedCaseInsensitiveContains(searchText) ||
                $0.album.localizedCaseInsensitiveContains(searchText)
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        Group {
            if !searchText.isEmpty {
                if searchResults.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    List(searchResults) { song in
                        SongRow(song: song, isPlaying: player.currentSong == song, showArtwork: false)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                player.play(song: song, in: searchResults)
                                tabRouter.select(.nowPlaying)
                            }
                            .listRowBackground(RowHighlightBackground(isActive: player.currentSong == song))
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            } else if library.artistsAlphabetical.isEmpty && library.isScanning {
                ProgressView("Loading Library…")
                    .tint(Theme.orange)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if library.artistsAlphabetical.isEmpty {
                ContentUnavailableView(
                    "No Music Yet",
                    systemImage: "music.note",
                    description: Text("Add songs via Finder to Meow Music/Downloads/<Artist>/ and they'll show up here.")
                )
            } else {
                List(library.artistsAlphabetical, id: \.self) { artist in
                    NavigationLink(value: artist) {
                        Text(artist).foregroundStyle(Theme.primaryText)
                    }
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Theme.background)
        .navigationTitle("Browse")
        .searchable(text: $searchText, prompt: "Search artists, albums, songs")
        .navigationDestination(for: String.self) { artist in
            ArtistAlbumsView(artist: artist)
        }
    }
}
