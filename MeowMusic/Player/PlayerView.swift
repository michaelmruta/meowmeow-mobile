import SwiftUI
import SwiftData

struct PlayerView: View {
    @Environment(PlayerService.self) private var player
    @Environment(LibraryStore.self) private var library
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FavoriteRecord.dateFavorited, order: .reverse) private var favorites: [FavoriteRecord]

    @State private var showingLyrics = false
    @State private var lyricsLines: [LyricLine] = []
    @State private var isScrubbing = false
    @State private var scrubTime: TimeInterval = 0
    @State private var showingEditor = false

    private var isFavorite: Bool {
        guard let song = player.currentSong else { return false }
        return favorites.contains { $0.songPath == song.id }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let song = player.currentSong {
                Spacer(minLength: 24)

                GeometryReader { geo in
                    let artSize = min(geo.size.width - 64, geo.size.height * 0.64)
                    let artworkVerticalOffset = artSize * 0.16
                    ZStack {
                        ReflectedArtwork(artwork: song.artwork, size: artSize)
                            .opacity(showingLyrics ? 0.18 : 1)
                            .animation(.easeInOut(duration: 0.3), value: showingLyrics)

                        if showingLyrics {
                            LyricsView(lines: lyricsLines, currentTime: player.currentTime)
                                .frame(width: geo.size.width, height: artSize + 40)
                                .transition(.opacity)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .contentShape(Rectangle())
                    .offset(y: artworkVerticalOffset)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showingLyrics.toggle()
                        }
                    }
                }
                .padding(.horizontal, 32)

                VStack(spacing: 6) {
                    Text(song.title)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                    Text(song.artist)
                        .font(.headline)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
                .padding(.top, 20)
                .padding(.horizontal, 32)

                scrubber
                    .padding(.top, 20)
                    .padding(.horizontal, 32)

                transportControls
                    .padding(.top, 28)
                    .padding(.horizontal, 32)

                Spacer(minLength: 24)
            } else {
                placeholderPlayer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .navigationTitle("Now Playing")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingEditor = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .disabled(player.currentSong == nil)
            }
        }
        .sheet(isPresented: $showingEditor) {
            MetadataEditorView()
        }
        .task(id: player.currentSong?.id) {
            showingLyrics = false
            guard let song = player.currentSong else {
                lyricsLines = []
                return
            }
            lyricsLines = await LyricsService.load(for: song)
        }
    }

    private var placeholderPlayer: some View {
        Group {
            Spacer(minLength: 24)

            GeometryReader { geo in
                let artSize = min(geo.size.width - 64, geo.size.height * 0.64)
                let artworkVerticalOffset = artSize * 0.16
                ReflectedArtwork(artwork: nil, size: artSize)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .offset(y: artworkVerticalOffset)
            }
            .padding(.horizontal, 32)

            VStack(spacing: 6) {
                Text(" ")
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                Text(" ")
                    .font(.headline)
                    .lineLimit(1)
            }
            .padding(.top, 20)
            .padding(.horizontal, 32)

            scrubber
                .disabled(true)
                .padding(.top, 20)
                .padding(.horizontal, 32)

            transportControls
                .padding(.top, 28)
                .padding(.horizontal, 32)

            Spacer(minLength: 24)
        }
    }

    private var scrubber: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { isScrubbing ? scrubTime : player.currentTime },
                    set: { scrubTime = $0 }
                ),
                in: 0...max(player.duration, 1),
                onEditingChanged: { editing in
                    isScrubbing = editing
                    if !editing { player.seek(to: scrubTime) }
                }
            )
            .tint(Theme.orange)

            HStack {
                Text(formatted(isScrubbing ? scrubTime : player.currentTime))
                Spacer()
                Text(formatted(player.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(Theme.secondaryText)
        }
    }

    private var transportControls: some View {
        ZStack {
            HStack(spacing: 36) {
                Button { player.previous() } label: {
                    Image(systemName: "backward.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.primaryText)
                }
                .disabled(player.currentSong == nil)

                Button { playButtonTapped() } label: {
                    Image(systemName: player.isPlaying && player.currentSong != nil ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 58))
                        .foregroundStyle(Theme.orange)
                }
                .disabled(player.currentSong == nil && library.songs.isEmpty)

                Button { player.next() } label: {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.primaryText)
                }
                .disabled(player.currentSong == nil)
            }

            HStack {
                Button {
                    player.cyclePlaybackMode()
                } label: {
                    Image(systemName: playbackModeIconName)
                        .foregroundStyle(player.playbackMode == .off ? Theme.secondaryText : Theme.orange)
                }
                .disabled(player.currentSong == nil)
                Spacer()
                Button {
                    toggleFavorite()
                } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .foregroundStyle(isFavorite ? Theme.orange : Theme.secondaryText)
                }
                .disabled(player.currentSong == nil)
            }
            .font(.title3)
        }
    }

    private func playButtonTapped() {
        if player.currentSong == nil {
            startShuffledPlayback()
        } else {
            player.togglePlayPause()
        }
    }

    private func startShuffledPlayback() {
        guard let song = library.songs.randomElement() else { return }
        player.shuffle = true
        player.repeatMode = .off
        player.play(song: song, in: library.songs)
    }

    private var playbackModeIconName: String {
        switch player.playbackMode {
        case .off, .repeatAll: return "repeat"
        case .shuffle: return "shuffle"
        case .repeatOne: return "repeat.1"
        }
    }

    private func toggleFavorite() {
        guard let song = player.currentSong else { return }
        if let existing = favorites.first(where: { $0.songPath == song.id }) {
            modelContext.delete(existing)
        } else {
            modelContext.insert(FavoriteRecord(songPath: song.id))
        }
    }

    private func formatted(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else { return "0:00" }
        let total = Int(time)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
