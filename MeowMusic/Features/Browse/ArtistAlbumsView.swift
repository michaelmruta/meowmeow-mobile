import SwiftUI
import UIKit

struct ArtistAlbumsView: View {
    let artist: String
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerService.self) private var player
    @Environment(TabRouter.self) private var tabRouter
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedAlbum: String?

    private var albums: [LibraryStore.AlbumGroup] { library.albums(forArtist: artist) }
    private var hasAnyArtwork: Bool { albums.contains { $0.artwork != nil } }

    private var displayedSongs: [Song] {
        let songs = library.songs(forArtist: artist)
        guard let selectedAlbum else {
            // When browsing all artist songs: sort by track number first, then natural title sort
            return songs.sorted { lhs, rhs in
                switch (lhs.trackNumber, rhs.trackNumber) {
                case let (l?, r?) where l != r:
                    return l < r
                case (nil, .some):
                    return false
                case (.some, nil):
                    return true
                default:
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
            }
        }
        // When viewing a specific album: sort by track number, then natural title sort
        return songs
            .filter { $0.album == selectedAlbum }
            .sorted { lhs, rhs in
                switch (lhs.trackNumber, rhs.trackNumber) {
                case let (l?, r?) where l != r:
                    return l < r
                case (nil, .some):
                    return false
                case (.some, nil):
                    return true
                default:
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            if hasAnyArtwork {
                albumSection
            }

            List(displayedSongs) { song in
                SongRow(song: song, isPlaying: player.currentSong == song, showArtist: false, showArtwork: false)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        player.play(song: song, in: displayedSongs)
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
        .background(Theme.background)
        .navigationTitle(artist)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func delete(_ song: Song) {
        if player.currentSong == song {
            player.pause()
        }
        library.delete(song)
    }

    /// On iPhone this is the original single-row horizontal scroll strip.
    /// On iPad (regular width) it becomes a multi-row grid instead, so the
    /// album art fills the wider detail pane rather than leaving it sparse.
    @ViewBuilder
    private var albumSection: some View {
        if horizontalSizeClass == .regular {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110, maximum: 160), spacing: 16)], spacing: 16) {
                    ForEach(albums) { group in
                        albumThumbnail(group)
                    }
                }
                .padding(16)
            }
            .frame(maxHeight: 280)
        } else {
            GeometryReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(albums) { group in
                            albumThumbnail(group)
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(minWidth: proxy.size.width, alignment: .leading)
                }
            }
            .frame(height: 140)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func albumThumbnail(_ group: LibraryStore.AlbumGroup) -> some View {
        let isSelected = selectedAlbum == group.album
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedAlbum = isSelected ? nil : group.album
            }
        } label: {
            VStack(spacing: 6) {
                Group {
                    if let data = group.artwork, let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Theme.card
                            .overlay { EighthNotePairIcon().padding(18) }
                    }
                }
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous)
                        .strokeBorder(Theme.orange, lineWidth: isSelected ? 3 : 0)
                }
                Text(group.album)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Theme.orange : Theme.secondaryText)
                    .lineLimit(1)
                    .frame(width: 96)
            }
        }
        .buttonStyle(.plain)
    }
}
