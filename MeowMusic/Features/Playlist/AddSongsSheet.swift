import SwiftUI

struct AddSongsSheet: View {
    let existingPaths: Set<String>
    let onAdd: (Song) -> Void

    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var addedPaths: Set<String> = []

    private var filteredSongs: [Song] {
        let sorted = library.songs.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        guard !searchText.isEmpty else { return sorted }
        return sorted.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.artist.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List(filteredSongs) { song in
                let alreadyIn = existingPaths.contains(song.id) || addedPaths.contains(song.id)
                SongRow(song: song, isPlaying: false)
                    .contentShape(Rectangle())
                    .opacity(alreadyIn ? 0.4 : 1)
                    .overlay(alignment: .trailing) {
                        if alreadyIn {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Theme.orange)
                        }
                    }
                    .onTapGesture {
                        guard !alreadyIn else { return }
                        onAdd(song)
                        addedPaths.insert(song.id)
                    }
                    .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Add Songs")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search songs")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
