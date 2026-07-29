import SwiftUI
import UIKit

struct MetadataEditorView: View {
    @Environment(PlayerService.self) private var player
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss

    private enum EditorTab: String, CaseIterable {
        case info = "Info", cover = "Cover", lyrics = "Lyrics"
    }

    @State private var selectedTab: EditorTab = .info
    @State private var titleText = ""
    @State private var artistText = ""
    @State private var albumText = ""
    @State private var albumArtistText = ""
    @State private var genreText = ""
    @State private var trackNumberText = ""
    @State private var yearText = ""
    @State private var composerText = ""
    @State private var lyricsPreview = ""
    @State private var isSaving = false
    @State private var isFetchingArt = false
    @State private var isFetchingLyrics = false
    @State private var errorMessage: String?

    private var displayLyricLines: [LyricLine] {
        guard !lyricsPreview.isEmpty else { return [] }
        let parsed = LyricsService.parseLRC(lyricsPreview)
        return parsed.isEmpty ? LyricsService.plainLines(lyricsPreview) : parsed
    }

    var body: some View {
        NavigationStack {
            Group {
                if let song = player.currentSong {
                    VStack(spacing: 0) {
                        Picker("", selection: $selectedTab) {
                            ForEach(EditorTab.allCases, id: \.self) { tab in
                                Text(tab.rawValue).tag(tab)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding()

                        Group {
                            switch selectedTab {
                            case .info: infoTab(song)
                            case .cover: coverTab(song)
                            case .lyrics: lyricsTab()
                            }
                        }
                        Spacer(minLength: 0)
                    }
                } else {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "pencil.slash")
                            .font(.system(size: 40))
                            .foregroundStyle(Theme.tertiaryText)
                        Text("Play a song to edit its info")
                            .foregroundStyle(Theme.secondaryText)
                        Spacer()
                    }
                }
            }
            .background(Theme.background)
            .navigationTitle("Edit Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                if player.currentSong != nil, selectedTab == .info {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save") { save() }
                            .disabled(isSaving)
                            .foregroundStyle(Theme.orange)
                    }
                }
            }
            .task(id: player.currentSong?.id) {
                guard let song = player.currentSong else { return }
                titleText = song.title
                artistText = song.artist
                albumText = song.album
                albumArtistText = song.albumArtist
                genreText = song.genre
                trackNumberText = song.trackNumber.map(String.init) ?? ""
                yearText = song.year.map(String.init) ?? ""
                composerText = song.composer
                lyricsPreview = await LyricsService.loadRawText(for: song)
            }
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private func infoTab(_ song: Song) -> some View {
        Form {
            Section("Details") {
                labeledField("Title", text: $titleText)
                labeledField("Artist", text: $artistText)
                labeledField("Album", text: $albumText)
                HStack(spacing: 16) {
                    labeledField("Year", text: $yearText, keyboardType: .numberPad)
                    labeledField("Track #", text: $trackNumberText, keyboardType: .numberPad)
                    labeledField("Genre", text: $genreText)
                }
                labeledField("Album Artist", text: $albumArtistText)
                labeledField("Composer", text: $composerText)
            }
            .listRowBackground(Theme.card)

            Section("File") {
                LabeledContent("Duration", value: formattedDuration(song.duration))
                LabeledContent("Bitrate", value: formattedBitrate(song.bitrateKbps))
                LabeledContent("Format", value: song.fileURL.pathExtension.uppercased())
                LabeledContent("Codec", value: song.codec ?? "Unknown")
            }
            .listRowBackground(Theme.card)

            if !MetadataWriter.supportsEmbeddedEditing(song) {
                Section {
                    Text("Editing embedded metadata is only supported for .mp4/.m4a files.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                .listRowBackground(Theme.card)
            }
        }
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func coverTab(_ song: Song) -> some View {
        VStack(spacing: 20) {
            ReflectedArtwork(artwork: song.artwork, size: 220)
            fetchButton(title: "Fetch Album Art", isLoading: isFetchingArt) {
                fetchArtwork(for: song)
            }
        }
        .padding(.top, 24)
    }

    @ViewBuilder
    private func lyricsTab() -> some View {
        VStack(spacing: 16) {
            fetchButton(title: "Fetch Lyrics", isLoading: isFetchingLyrics) {
                fetchLyrics()
            }

            ScrollView {
                if displayLyricLines.isEmpty {
                    Text("No lyrics found.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(displayLyricLines) { line in
                            HStack(alignment: .top, spacing: 10) {
                                if let time = line.time {
                                    Text(formattedDuration(time))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(Theme.tertiaryText)
                                        .frame(width: 44, alignment: .leading)
                                }
                                Text(line.text.isEmpty ? " " : line.text)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.secondaryText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .padding(.top, 16)
    }

    private func labeledField(_ label: String, text: Binding<String>, keyboardType: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.tertiaryText)
            TextField(label, text: text)
                .keyboardType(keyboardType)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fetchButton(title: String, isLoading: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if isLoading {
                ProgressView()
            } else {
                Label(title, systemImage: "sparkles")
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.orange)
        .disabled(isLoading)
    }

    private func fetchArtwork(for song: Song) {
        isFetchingArt = true
        Task {
            defer { isFetchingArt = false }
            do {
                let artwork = try await ArtworkFetchService.fetchArtwork(
                    artist: song.artist, album: song.album, title: song.title
                )
                try await MetadataWriter.write(.init(artwork: artwork), to: song)
                player.updateCurrentSongArtwork(artwork)
                await library.scan()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func fetchLyrics() {
        guard let song = player.currentSong else { return }
        isFetchingLyrics = true
        Task {
            defer { isFetchingLyrics = false }
            do {
                let lyrics = try await LyricsFetchService.fetchLyrics(artist: song.artist, title: song.title)
                LyricsService.save(lyrics, for: song)
                lyricsPreview = lyrics
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func save() {
        guard let song = player.currentSong else { return }
        isSaving = true
        let trackNumber = Int(trackNumberText.trimmingCharacters(in: .whitespaces))
        let year = Int(yearText.trimmingCharacters(in: .whitespaces))
        Task {
            defer { isSaving = false }
            do {
                try await MetadataWriter.write(
                    .init(
                        title: titleText,
                        artist: artistText,
                        album: albumText,
                        albumArtist: albumArtistText,
                        genre: genreText,
                        trackNumber: trackNumber,
                        year: year,
                        composer: composerText,
                        artwork: nil
                    ),
                    to: song
                )
                player.updateCurrentSongMetadata(
                    title: titleText,
                    artist: artistText,
                    album: albumText,
                    albumArtist: albumArtistText,
                    genre: genreText,
                    trackNumber: trackNumber,
                    year: year,
                    composer: composerText
                )
                await library.scan()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func formattedDuration(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else { return "0:00" }
        let total = Int(time)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func formattedBitrate(_ bitrateKbps: Int?) -> String {
        guard let bitrateKbps, bitrateKbps > 0 else { return "Unknown" }
        return "\(bitrateKbps) kbps"
    }
}
