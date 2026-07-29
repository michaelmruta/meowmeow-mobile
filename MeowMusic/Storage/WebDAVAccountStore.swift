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
    /// Public servers must use HTTPS. Plain HTTP is accepted only for local
    /// network hosts, where users commonly run self-hosted WebDAV services.
    var rootURL: URL? {
        let trimmedServer = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedServer.isEmpty,
              let parsed = URL(string: trimmedServer),
              let scheme = parsed.scheme,
              ["http", "https"].contains(scheme.lowercased()),
              let host = parsed.host,
              scheme.lowercased() == "https" || Self.isLocalHost(host) else { return nil }

        var absoluteString = parsed.absoluteString
        if !absoluteString.hasSuffix("/") { absoluteString += "/" }
        guard let serverRoot = URL(string: absoluteString) else { return nil }

        let trimmedPath = remotePath.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "/")))
        guard !trimmedPath.isEmpty else { return serverRoot }
        return serverRoot.appendingPathComponent(trimmedPath, isDirectory: true)
    }

    private static func isLocalHost(_ host: String) -> Bool {
        let lowercased = host.lowercased()
        if lowercased == "localhost" || lowercased.hasSuffix(".local") {
            return true
        }

        if lowercased.contains(":") {
            return lowercased == "::1" || lowercased.hasPrefix("fe80:")
        }

        let octets = lowercased.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else {
            return false
        }

        return octets[0] == 10
            || octets[0] == 127
            || (octets[0] == 169 && octets[1] == 254)
            || (octets[0] == 172 && (16...31).contains(octets[1]))
            || (octets[0] == 192 && octets[1] == 168)
    }

    func testConnection() async {
        guard let root = rootURL else {
            connectionError = "Enter an HTTPS URL, or a local-network HTTP URL."
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
