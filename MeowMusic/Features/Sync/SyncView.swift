import SwiftUI
import UIKit

private enum SyncSource: String, CaseIterable, Identifiable {
    case local = "Local Storage"
    case webdav = "WebDAV"
    case googleDrive = "Google Drive"

    var id: String { rawValue }
}

struct SyncView: View {
    @AppStorage("syncView.lastSource") private var source: SyncSource = .local
    @State private var isShowingAbout = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("Sync Source", selection: $source) {
                ForEach(SyncSource.allCases) { source in
                    Text(source.rawValue).tag(source)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            .background(Theme.background)

            switch source {
            case .local:
                LocalStorageSyncView()
            case .webdav:
                WebDAVSyncView()
            case .googleDrive:
                GoogleDriveSyncView()
            }
        }
        .background(Theme.background)
        .navigationTitle("Sync")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingAbout = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .accessibilityLabel("About Meow Music")
            }
        }
        .sheet(isPresented: $isShowingAbout) {
            AboutView()
        }
    }
}

private struct LocalStorageSyncView: View {
    @Environment(SyncBookmarkStore.self) private var syncStore
    @Environment(LibraryStore.self) private var library
    @Environment(LocalSyncController.self) private var syncController
    @State private var isPresentingPicker = false

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
                Text("Pick any folder the Files app can reach, including an external USB-C drive connected to this device.")
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
                        if syncController.isSyncing {
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
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }

                if syncController.isSyncing {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: syncController.progress)
                            .tint(Theme.orange)
                        Text("\(Int(syncController.progress * 100))%")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                        if let currentFileName = syncController.currentFileName {
                            Text(currentFileName)
                                .font(.caption2)
                                .foregroundStyle(Theme.tertiaryText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                } else if let lastResultText = syncController.lastResultText {
                    Text(lastResultText)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                } else if let syncError = syncController.syncError {
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
        .sheet(isPresented: $isPresentingPicker) {
            FolderPicker { url in
                syncStore.setFolder(url)
            }
            .ignoresSafeArea()
        }
    }

    private var canSync: Bool {
        syncStore.folderDisplayName != nil && !syncController.isSyncing
    }

    private func performSync() {
        guard let folderURL = syncStore.folderURL else { return }
        syncController.startSync(folderURL: folderURL, library: library, syncStore: syncStore)
    }
}

private struct WebDAVSyncView: View {
    @Environment(WebDAVAccountStore.self) private var account
    @Environment(LibraryStore.self) private var library
    @Environment(WebDAVSyncController.self) private var syncController

    var body: some View {
        @Bindable var account = account

        Form {
            Section {
                LabeledContent("Server URL") {
                    TextField("https://example.com/dav", text: $account.serverURLString)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                LabeledContent("Folder") {
                    TextField("Music (optional)", text: $account.remotePath)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                LabeledContent("Username") {
                    TextField("username", text: $account.username)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                LabeledContent("Password") {
                    SecureField("password", text: $account.password)
                        .multilineTextAlignment(.trailing)
                }
            } header: {
                Text("WebDAV Server")
            } footer: {
                Text("Works with Nextcloud, ownCloud, Synology, and most other WebDAV servers. Credentials are stored in the Keychain.")
            }
            .listRowBackground(Theme.card)

            Section("Connection") {
                HStack(spacing: 10) {
                    Circle()
                        .fill(account.isConnected ? Color.green : Color.gray)
                        .frame(width: 10, height: 10)
                    Text(connectionStatusText)
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        Task { await account.testConnection() }
                    } label: {
                        if account.isTestingConnection {
                            ProgressView().tint(Theme.orange)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(account.isTestingConnection || !account.isConfigured)
                    .foregroundStyle(account.isConfigured && !account.isTestingConnection ? Theme.orange : Theme.tertiaryText)
                }
                if let connectionError = account.connectionError {
                    Text(connectionError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .listRowBackground(Theme.card)

            Section {
                Button {
                    performSync()
                } label: {
                    HStack {
                        Spacer()
                        if syncController.isSyncing {
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
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }

                if syncController.isSyncing {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: syncController.progress)
                            .tint(Theme.orange)
                        Text(syncController.totalUnits > 0 ? "\(syncController.completedUnits)/\(syncController.totalUnits) files" : "Preparing…")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                } else if let lastResultText = syncController.lastResultText {
                    Text(lastResultText)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                } else if let syncError = syncController.syncError {
                    Text(syncError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Server → App Library")
            } footer: {
                Text("Downloads new and changed songs from the server, and removes songs here that no longer exist there. Syncing changes from the app back out to the server isn't implemented yet.")
            }
            .listRowBackground(Theme.card)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
    }

    private var connectionStatusText: String {
        if account.isTestingConnection { return "Testing…" }
        if !account.isConfigured { return "Not Configured" }
        return account.isConnected ? "Connected" : "Not Connected"
    }

    private var canSync: Bool {
        account.isConfigured && !syncController.isSyncing
    }

    private func performSync() {
        guard let root = account.rootURL else { return }
        syncController.startSync(root: root, credentials: account.credentials, library: library)
    }
}

private struct GoogleDriveSyncView: View {
    @Environment(GoogleDriveAccountStore.self) private var account
    @Environment(LibraryStore.self) private var library
    @Environment(GoogleDriveSyncController.self) private var syncController

    var body: some View {
        @Bindable var account = account

        Form {
            Section {
                HStack {
                    Image(systemName: "person.crop.circle.fill")
                        .foregroundStyle(Theme.orange)
                    Text(account.currentUserEmail ?? "Not Signed In")
                        .foregroundStyle(account.currentUserEmail == nil ? Theme.secondaryText : Theme.primaryText)
                        .lineLimit(1)
                    Spacer()
                    if account.isSigningIn {
                        ProgressView().tint(Theme.orange)
                    } else if account.currentUserEmail == nil {
                        Button("Sign In") { signIn() }
                            .foregroundStyle(Theme.orange)
                    } else {
                        Button("Sign Out") { account.signOut() }
                            .foregroundStyle(Theme.orange)
                    }
                }
                LabeledContent("Folder") {
                    TextField("Drive root (optional)", text: $account.folderIDInput)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            } header: {
                Text("Google Drive")
            } footer: {
                Text("Paste a Drive folder link or ID, or leave blank to sync from the root of My Drive. Credentials are managed by Google Sign-In.")
            }
            .listRowBackground(Theme.card)

            Section("Connection") {
                HStack(spacing: 10) {
                    Circle()
                        .fill(account.isConnected ? Color.green : Color.gray)
                        .frame(width: 10, height: 10)
                    Text(connectionStatusText)
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        Task { await account.testConnection() }
                    } label: {
                        if account.isTestingConnection {
                            ProgressView().tint(Theme.orange)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(account.isTestingConnection || !account.isConfigured)
                    .foregroundStyle(account.isConfigured && !account.isTestingConnection ? Theme.orange : Theme.tertiaryText)
                }
                if let connectionError = account.connectionError {
                    Text(connectionError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .listRowBackground(Theme.card)

            Section {
                Button {
                    performSync()
                } label: {
                    HStack {
                        Spacer()
                        if syncController.isSyncing {
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
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }

                if syncController.isSyncing {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: syncController.progress)
                            .tint(Theme.orange)
                        Text(syncController.totalUnits > 0 ? "\(syncController.completedUnits)/\(syncController.totalUnits) files" : "Preparing…")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                } else if let lastResultText = syncController.lastResultText {
                    Text(lastResultText)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                } else if let syncError = syncController.syncError {
                    Text(syncError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Drive → App Library")
            } footer: {
                Text("Downloads new and changed songs from Drive, and removes songs here that no longer exist there. Syncing changes from the app back out to Drive isn't implemented yet.")
            }
            .listRowBackground(Theme.card)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
    }

    private var connectionStatusText: String {
        if account.isTestingConnection { return "Testing…" }
        if !account.isConfigured { return "Not Configured" }
        return account.isConnected ? "Connected" : "Not Connected"
    }

    private var canSync: Bool {
        account.isConfigured && !syncController.isSyncing
    }

    private func signIn() {
        guard let rootVC = UIApplication.shared.foregroundRootViewController else { return }
        Task { await account.signIn(presenting: rootVC) }
    }

    private func performSync() {
        syncController.startSync(rootFolderID: account.resolvedFolderID, account: account, library: library)
    }
}
