import SwiftUI
import SwiftData

/// Right-edge "recently played" panel, toggled by pressing Y on a hardware
/// keyboard (see `RootContainerView`). Backed by `PlayHistoryRecord`, one
/// row per song, so replaying a song moves it to the top instead of
/// spamming the list with duplicates.
struct HistorySidebarView: View {
    @Binding var isPresented: Bool

    @Environment(LibraryStore.self) private var library
    @Environment(PlayerService.self) private var player
    @Environment(TabRouter.self) private var tabRouter
    @Query(sort: \PlayHistoryRecord.playedAt, order: .reverse) private var historyRecords: [PlayHistoryRecord]

    private var historySongs: [Song] {
        historyRecords.compactMap { library.song(withID: $0.songPath) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Recently Played")
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.secondaryText)
                }
                .buttonStyle(.plain)
            }
            .padding()

            if historySongs.isEmpty {
                Spacer()
                Text("No songs played yet.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
            } else {
                List(historySongs) { song in
                    SongRow(song: song, isPlaying: player.currentSong == song)
                        .contentShape(Rectangle())
                        .onTapGesture { play(song) }
                        .listRowBackground(RowHighlightBackground(isActive: player.currentSong == song))
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Theme.card)
    }

    private func play(_ song: Song) {
        player.play(song: song, in: historySongs)
        tabRouter.select(.nowPlaying)
        isPresented = false
    }
}
