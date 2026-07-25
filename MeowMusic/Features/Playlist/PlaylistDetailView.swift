import SwiftUI
import SwiftData

struct PlaylistDetailView: View {
    @Bindable var playlist: PlaylistEntity
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerService.self) private var player
    @Environment(TabRouter.self) private var tabRouter
    @Environment(\.modelContext) private var modelContext
    @Environment(\.editMode) private var editMode
    @State private var isPresentingAddSongs = false

    private var pairedItems: [(entry: PlaylistSongEntity, song: Song)] {
        playlist.songs
            .sorted { $0.sortIndex < $1.sortIndex }
            .compactMap { entry in
                guard let song = library.song(withID: entry.songPath) else { return nil }
                return (entry, song)
            }
    }

    var body: some View {
        Group {
            if pairedItems.isEmpty {
                ContentUnavailableView(
                    "No Songs",
                    systemImage: "music.note",
                    description: Text("Tap + to add songs to this playlist.")
                )
            } else {
                List {
                    ForEach(pairedItems, id: \.entry.id) { item in
                        SongRow(song: item.song, isPlaying: player.currentSong == item.song)
                            .contentShape(Rectangle())
                            .onTapGesture { play(item.song) }
                            .listRowBackground(RowHighlightBackground(isActive: player.currentSong == item.song))
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    remove(item.entry)
                                } label: {
                                    Label("Remove", systemImage: "minus.circle")
                                }
                            }
                    }
                    .onMove(perform: move)
                    .onDelete(perform: remove)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Theme.background)
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !pairedItems.isEmpty {
                    Button {
                        let isEditing = editMode?.wrappedValue.isEditing ?? false
                        editMode?.wrappedValue = isEditing ? .inactive : .active
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
                Button { isPresentingAddSongs = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $isPresentingAddSongs) {
            AddSongsSheet(existingPaths: Set(pairedItems.map { $0.song.id })) { song in
                add(song)
            }
        }
    }

    private func play(_ song: Song) {
        player.play(song: song, in: pairedItems.map(\.song))
        tabRouter.select(.nowPlaying)
    }

    private func add(_ song: Song) {
        let entry = PlaylistSongEntity(songPath: song.id, sortIndex: playlist.songs.count, playlist: playlist)
        modelContext.insert(entry)
        persist()
    }

    private func remove(_ entry: PlaylistSongEntity) {
        modelContext.delete(entry)
        persist(excluding: [entry.id])
    }

    private func remove(at offsets: IndexSet) {
        let items = pairedItems
        let removedEntries = offsets.map { items[$0].entry }
        let removedIDs = Set(removedEntries.map(\.id))

        for entry in removedEntries {
            modelContext.delete(entry)
        }

        persist(excluding: removedIDs)
    }

    private func move(from source: IndexSet, to destination: Int) {
        var items = pairedItems
        items.move(fromOffsets: source, toOffset: destination)
        for (index, item) in items.enumerated() {
            item.entry.sortIndex = index
        }
        persist()
    }

    private func persist(excluding removedEntryIDs: Set<PersistentIdentifier> = []) {
        let songPaths = pairedItems
            .filter { !removedEntryIDs.contains($0.entry.id) }
            .map { $0.song.id }
        PlaylistFileManager.write(name: playlist.name, songPaths: songPaths, library: library)
    }
}
