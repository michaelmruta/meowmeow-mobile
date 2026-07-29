import SwiftUI

struct BrowseView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerService.self) private var player
    @Environment(TabRouter.self) private var tabRouter
    @State private var searchText = ""
    @State private var searchScope: SearchScope = .all

    private enum SearchScope: String, CaseIterable {
        case all = "All", artists = "Artists", albums = "Albums", songs = "Songs", genre = "Genre"
    }

    private var searchResults: [Song] {
        guard !searchText.isEmpty else { return [] }
        return library.songs
            .filter { matches($0) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private func matches(_ song: Song) -> Bool {
        switch searchScope {
        case .all:
            return song.title.localizedCaseInsensitiveContains(searchText) ||
                song.artist.localizedCaseInsensitiveContains(searchText) ||
                song.album.localizedCaseInsensitiveContains(searchText) ||
                song.genre.localizedCaseInsensitiveContains(searchText)
        case .artists:
            return song.artist.localizedCaseInsensitiveContains(searchText)
        case .albums:
            return song.album.localizedCaseInsensitiveContains(searchText)
        case .songs:
            return song.title.localizedCaseInsensitiveContains(searchText)
        case .genre:
            return song.genre.localizedCaseInsensitiveContains(searchText)
        }
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
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    delete(song)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
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
        .searchScopes($searchScope) {
            ForEach(SearchScope.allCases, id: \.self) { scope in
                Text(scope.rawValue).tag(scope)
            }
        }
        .navigationDestination(for: String.self) { artist in
            ArtistAlbumsView(artist: artist)
        }
    }

    private func delete(_ song: Song) {
        if player.currentSong == song {
            player.pause()
        }
        library.delete(song)
    }
}
