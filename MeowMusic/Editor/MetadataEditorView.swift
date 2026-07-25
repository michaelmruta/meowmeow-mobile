import SwiftUI

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
    @State private var lyricsPreview = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

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
                lyricsPreview = await LyricsService.loadRawText(for: song)
            }
            .alert("Couldn't Save", isPresented: Binding(
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
                TextField("Title", text: $titleText)
                TextField("Artist", text: $artistText)
                TextField("Album", text: $albumText)
            }
            .listRowBackground(Theme.card)

            Section("File") {
                LabeledContent("Duration", value: formattedDuration(song.duration))
                LabeledContent("Bitrate", value: formattedBitrate(song.bitrateKbps))
                LabeledContent("Format", value: song.fileURL.pathExtension.uppercased())
                LabeledContent("File Name", value: song.fileURL.lastPathComponent)
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
            fetchStubButton(title: "Fetch Album Art")
        }
        .padding(.top, 24)
    }

    @ViewBuilder
    private func lyricsTab() -> some View {
        VStack(spacing: 16) {
            fetchStubButton(title: "Fetch Lyrics")

            ScrollView {
                Text(lyricsPreview.isEmpty ? "No lyrics found." : lyricsPreview)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .padding(.top, 16)
    }

    private func fetchStubButton(title: String) -> some View {
        VStack(spacing: 6) {
            Button {
                // Fetching is not implemented yet.
            } label: {
                Label(title, systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.orange)
            .disabled(true)
            Text("Coming soon")
                .font(.caption)
                .foregroundStyle(Theme.tertiaryText)
        }
    }

    private func save() {
        guard let song = player.currentSong else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await MetadataWriter.write(
                    .init(title: titleText, artist: artistText, album: albumText, artwork: nil),
                    to: song
                )
                player.updateCurrentSongMetadata(title: titleText, artist: artistText, album: albumText)
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
