import SwiftUI
import SwiftData

struct RecentlyPlayedView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerService.self) private var player
    @Environment(TabRouter.self) private var tabRouter
    @Query(sort: \RecentlyPlayedRecord.lastPlayedDate, order: .reverse) private var recentlyPlayed: [RecentlyPlayedRecord]
    
    private var songs: [Song] {
        recentlyPlayed.compactMap { record in
            library.song(withID: record.songPath)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if songs.isEmpty {
                emptyState
            } else {
                List(songs) { song in
                    SongRow(song: song, isPlaying: player.currentSong == song, showArtwork: true)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            player.play(song: song, in: songs, isRecentlyPlayed: true)
                            // Navigate back to Now Playing view
                            tabRouter.showRecentlyPlayed = false
                        }
                        .listRowBackground(RowHighlightBackground(isActive: player.currentSong == song))
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                delete(song)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .navigationTitle("Recently Played")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "clock")
                .font(.system(size: 48))
                .foregroundStyle(Theme.tertiaryText)
            Text("No Recently Played Songs")
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
            Text("Songs you play will appear here")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            Spacer()
        }
    }
    
    private func delete(_ song: Song) {
        guard let record = recentlyPlayed.first(where: { $0.songPath == song.id }) else { return }
        // Access modelContext through the environment
        if let context = recentlyPlayed.first?.modelContext {
            context.delete(record)
        }
    }
}
