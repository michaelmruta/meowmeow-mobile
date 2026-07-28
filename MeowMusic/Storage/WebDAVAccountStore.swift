import Foundation
import Observation

/// Persists the configured WebDAV server (URL, optional remote folder,
/// username in UserDefaults; password in the Keychain) and tracks whether the
/// last connection attempt succeeded.
@MainActor
@Observable
final class WebDAVAccountStore {
    private let serverURLKey = "webdav.serverURL"
    private let usernameKey = "webdav.username"
    private let remotePathKey = "webdav.remotePath"
    private let keychainAccount = "webdav.password"

    var serverURLString: String {
        didSet { UserDefaults.standard.set(serverURLString, forKey: serverURLKey) }
    }
    var username: String {
        didSet { UserDefaults.standard.set(username, forKey: usernameKey) }
    }
    var remotePath: String {
        didSet { UserDefaults.standard.set(remotePath, forKey: remotePathKey) }
    }
    var password: String {
        didSet { KeychainStore.set(password, forAccount: keychainAccount) }
    }

    private(set) var isConnected = false
    private(set) var isTestingConnection = false
    private(set) var connectionError: String?

    init() {
        serverURLString = UserDefaults.standard.string(forKey: serverURLKey) ?? ""
        username = UserDefaults.standard.string(forKey: usernameKey) ?? ""
        remotePath = UserDefaults.standard.string(forKey: remotePathKey) ?? ""
        password = KeychainStore.get(forAccount: keychainAccount) ?? ""
    }

    var isConfigured: Bool {
        rootURL != nil && !username.isEmpty
    }

    var credentials: WebDAVCredentials {
        WebDAVCredentials(username: username, password: password)
    }

    /// The configured remote root: server URL plus the optional sub-folder.
    /// `nil` if the server URL isn't a valid http(s) URL.
    var rootURL: URL? {
        let trimmedServer = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedServer.isEmpty,
              let parsed = URL(string: trimmedServer),
              let scheme = parsed.scheme,
              ["http", "https"].contains(scheme.lowercased()),
              parsed.host != nil else { return nil }

        var absoluteString = parsed.absoluteString
        if !absoluteString.hasSuffix("/") { absoluteString += "/" }
        guard let serverRoot = URL(string: absoluteString) else { return nil }

        let trimmedPath = remotePath.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "/")))
        guard !trimmedPath.isEmpty else { return serverRoot }
        return serverRoot.appendingPathComponent(trimmedPath, isDirectory: true)
    }

    func testConnection() async {
        guard let root = rootURL else {
            connectionError = "Enter a valid server URL."
            isConnected = false
            return
        }
        isTestingConnection = true
        connectionError = nil
        defer { isTestingConnection = false }

        do {
            try await WebDAVClient.testConnection(root: root, credentials: credentials)
            isConnected = true
        } catch {
            isConnected = false
            connectionError = error.localizedDescription
        }
    }
}
