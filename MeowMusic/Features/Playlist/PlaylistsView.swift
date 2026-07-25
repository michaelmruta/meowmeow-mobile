import SwiftUI
import SwiftData

struct PlaylistsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LibraryStore.self) private var library
    @Query(sort: \PlaylistEntity.sortIndex) private var playlists: [PlaylistEntity]

    private enum AlertMode { case create, rename }
    @State private var alertMode: AlertMode = .create
    @State private var editingPlaylist: PlaylistEntity?
    @State private var nameFieldText = ""
    @State private var showingNameAlert = false

    var body: some View {
        Group {
            if playlists.isEmpty {
                ContentUnavailableView(
                    "No Playlists",
                    systemImage: "music.note.list",
                    description: Text("Tap + to create your first playlist.")
                )
            } else {
                List {
                    ForEach(playlists) { playlist in
                        NavigationLink(value: playlist.id) {
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous)
                                    .fill(Theme.card)
                                    .frame(width: 44, height: 44)
                                    .overlay {
                                        Image(systemName: "music.note.list")
                                            .foregroundStyle(Theme.orange)
                                    }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(playlist.name)
                                        .foregroundStyle(Theme.primaryText)
                                    Text("\(playlist.songs.count) song\(playlist.songs.count == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundStyle(Theme.secondaryText)
                                }
                            }
                        }
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                delete(playlist)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                beginRename(playlist)
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            .tint(Theme.orange)
                        }
                    }
                    .onMove(perform: move)
                    .onDelete(perform: delete)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Theme.background)
        .navigationTitle("Playlists")
        .task(id: library.songs.count) {
            importPlaylistsFromFiles()
        }
        .navigationDestination(for: UUID.self) { id in
            if let playlist = playlists.first(where: { $0.id == id }) {
                PlaylistDetailView(playlist: playlist)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    alertMode = .create
                    nameFieldText = ""
                    showingNameAlert = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert(alertMode == .create ? "New Playlist" : "Rename Playlist", isPresented: $showingNameAlert) {
            TextField("Name", text: $nameFieldText)
            Button("Cancel", role: .cancel) {}
            Button(alertMode == .create ? "Create" : "Save") {
                switch alertMode {
                case .create: createPlaylist(named: nameFieldText)
                case .rename:
                    if let playlist = editingPlaylist { rename(playlist, to: nameFieldText) }
                }
            }
        }
    }

    private func createPlaylist(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let playlist = PlaylistEntity(name: trimmed, sortIndex: playlists.count)
        modelContext.insert(playlist)
        PlaylistFileManager.write(name: trimmed, songPaths: [], library: library)
    }

    private func beginRename(_ playlist: PlaylistEntity) {
        alertMode = .rename
        editingPlaylist = playlist
        nameFieldText = playlist.name
        showingNameAlert = true
    }

    private func rename(_ playlist: PlaylistEntity, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != playlist.name else { return }
        PlaylistFileManager.rename(oldName: playlist.name, newName: trimmed)
        playlist.name = trimmed
    }

    private func delete(_ playlist: PlaylistEntity) {
        PlaylistFileManager.delete(name: playlist.name)
        modelContext.delete(playlist)
    }

    private func delete(at offsets: IndexSet) {
        var remaining = playlists
        remaining.remove(atOffsets: offsets)

        for offset in offsets {
            delete(playlists[offset])
        }

        for (index, playlist) in remaining.enumerated() {
            playlist.sortIndex = index
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var reordered = playlists
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, playlist) in reordered.enumerated() {
            playlist.sortIndex = index
        }
    }

    private func importPlaylistsFromFiles() {
        let playlistFiles = PlaylistFileManager.readExistingPlaylists(library: library)
        guard !playlistFiles.isEmpty else { return }

        var nextSortIndex = (playlists.map(\.sortIndex).max() ?? -1) + 1

        for playlistFile in playlistFiles {
            let playlist = playlists.first { $0.name == playlistFile.name } ?? {
                let entity = PlaylistEntity(name: playlistFile.name, sortIndex: nextSortIndex)
                nextSortIndex += 1
                modelContext.insert(entity)
                return entity
            }()

            replaceSongs(in: playlist, with: playlistFile.songPaths)
        }

        try? modelContext.save()
    }

    private func replaceSongs(in playlist: PlaylistEntity, with songPaths: [String]) {
        let existingPaths = playlist.songs
            .sorted { $0.sortIndex < $1.sortIndex }
            .map(\.songPath)

        guard existingPaths != songPaths else { return }

        for entry in Array(playlist.songs) {
            modelContext.delete(entry)
        }

        for (index, songPath) in songPaths.enumerated() {
            let entry = PlaylistSongEntity(songPath: songPath, sortIndex: index, playlist: playlist)
            modelContext.insert(entry)
        }
    }
}
