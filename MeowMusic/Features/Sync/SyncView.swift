import SwiftUI

struct SyncView: View {
    @Environment(SyncBookmarkStore.self) private var syncStore
    @Environment(LibraryStore.self) private var library
    @State private var isPresentingPicker = false
    @State private var isSyncing = false
    @State private var syncProgress: Double = 0
    @State private var lastResultText: String?
    @State private var syncError: String?

    var body: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(Theme.orange)
                    Text(syncStore.folderDisplayName ?? "Not Set")
                        .foregroundStyle(syncStore.folderDisplayName == nil ? Theme.secondaryText : Theme.primaryText)
                        .lineLimit(1)
                    Spacer()
                    Button("Choose…") { isPresentingPicker = true }
                        .foregroundStyle(Theme.orange)
                }
            } header: {
                Text("Sync Folder")
            } footer: {
                Text("Pick any folder the Files app can reach, including an external USB-C drive connected to this iPhone.")
            }
            .listRowBackground(Theme.card)

            Section("Device") {
                HStack(spacing: 10) {
                    Circle()
                        .fill(syncStore.isReachable ? Color.green : Color.gray)
                        .frame(width: 10, height: 10)
                    Text(syncStore.isReachable ? "Connected" : "Not Connected")
                        .foregroundStyle(Theme.primaryText)
                    Spacer()
                    Button {
                        syncStore.refreshReachability()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .foregroundStyle(Theme.orange)
                }
            }
            .listRowBackground(Theme.card)

            Section {
                Button {
                    performSync()
                } label: {
                    HStack {
                        Spacer()
                        if isSyncing {
                            ProgressView()
                                .tint(Theme.orange)
                        } else {
                            Text("Sync Now").fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .disabled(!canSync)
                .foregroundStyle(canSync ? Theme.orange : Theme.tertiaryText)

                if isSyncing {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: syncProgress)
                            .tint(Theme.orange)
                        Text("\(Int(syncProgress * 100))%")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                } else if let lastResultText {
                    Text(lastResultText)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                } else if let syncError {
                    Text(syncError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("External → App Library")
            } footer: {
                Text("Copies new and changed songs in from the sync folder, and removes songs here that no longer exist there. Syncing changes from the app back out to the folder isn't implemented yet.")
            }
            .listRowBackground(Theme.card)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Sync")
        .sheet(isPresented: $isPresentingPicker) {
            FolderPicker { url in
                syncStore.setFolder(url)
            }
            .ignoresSafeArea()
        }
    }

    private var canSync: Bool {
        syncStore.folderDisplayName != nil && !isSyncing
    }

    private func performSync() {
        guard let folderURL = syncStore.folderURL else { return }
        isSyncing = true
        syncProgress = 0
        syncError = nil
        lastResultText = nil

        Task {
            defer { isSyncing = false }
            do {
                let stats = try await SyncEngine.sync(externalRoot: folderURL) { progress in
                    syncProgress = progress
                }
                lastResultText = stats.summaryText
                await library.scan()
                syncStore.refreshReachability()
            } catch {
                syncError = error.localizedDescription
            }
        }
    }
}
