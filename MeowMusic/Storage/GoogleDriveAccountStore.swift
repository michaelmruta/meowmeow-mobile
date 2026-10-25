import Foundation
import Observation
import UIKit
import GoogleSignIn

/// Persists the configured Drive folder (UserDefaults) and tracks Google
/// sign-in / connection state. Unlike `WebDAVAccountStore`, no
/// username/password is stored here — the GoogleSignIn SDK owns the OAuth
/// tokens in its own Keychain storage and hands back a fresh access token on
/// request via `credentials()`.
@MainActor
@Observable
final class GoogleDriveAccountStore {
    /// Per-file scope: the app only ever sees folders the user explicitly
    /// grants through the Google Picker (and files it created). Unlike the
    /// broad `drive.readonly`, this is a non-restricted scope, so it doesn't
    /// require Google's paid CASA security assessment to ship publicly.
    private static let driveScope = "https://www.googleapis.com/auth/drive.file"

    private let folderIDKey = "googledrive.folderID"
    private let folderNameKey = "googledrive.folderName"

    /// The folder the user picked via the Google Picker. Under `drive.file`
    /// there is no free-text folder entry — access is only ever granted by
    /// selecting a folder in Google's own UI.
    private(set) var selectedFolderID: String {
        didSet { UserDefaults.standard.set(selectedFolderID, forKey: folderIDKey) }
    }
    private(set) var selectedFolderName: String {
        didSet { UserDefaults.standard.set(selectedFolderName, forKey: folderNameKey) }
    }

    private(set) var currentUserEmail: String?
    private(set) var isSigningIn = false
    private(set) var isConnected = false
    private(set) var isTestingConnection = false
    private(set) var connectionError: String?

    init() {
        selectedFolderID = UserDefaults.standard.string(forKey: folderIDKey) ?? ""
        selectedFolderName = UserDefaults.standard.string(forKey: folderNameKey) ?? ""
        currentUserEmail = GIDSignIn.sharedInstance.currentUser?.profile?.email
    }

    var isConfigured: Bool {
        GIDSignIn.sharedInstance.currentUser != nil
    }

    /// Restores a previous Google sign-in from the Keychain, if one exists,
    /// without presenting any UI. Called once at app launch.
    func restorePreviousSignIn() async {
        guard GIDSignIn.sharedInstance.hasPreviousSignIn() else { return }
        do {
            let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
            currentUserEmail = user.profile?.email
        } catch {
            currentUserEmail = nil
        }
    }

    func signIn(presenting viewController: UIViewController) async {
        isSigningIn = true
        connectionError = nil
        defer { isSigningIn = false }

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: viewController,
                hint: nil,
                additionalScopes: [Self.driveScope]
            )
            currentUserEmail = result.user.profile?.email
        } catch {
            connectionError = error.localizedDescription
        }
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        currentUserEmail = nil
        isConnected = false
        connectionError = nil
        // The folder grant is tied to the account and scope, so drop it when
        // signing out — a fresh sign-in must pick a folder again.
        selectedFolderID = ""
        selectedFolderName = ""
    }

    /// Records the folder the user chose in the Google Picker. Selecting it is
    /// what grants the `drive.file`-scoped app access to that folder's contents.
    func setPickedFolder(_ folder: GoogleDrivePickedFolder) {
        selectedFolderID = folder.id
        selectedFolderName = folder.name
        isConnected = false
        connectionError = nil
    }

    var hasSelectedFolder: Bool { !selectedFolderID.isEmpty }

    /// Surfaces a picker/folder problem in the same place as connection errors.
    func reportFolderError(_ message: String) {
        connectionError = message
        isConnected = false
    }

    /// The Drive folder to sync from — the id captured from the Picker. Empty
    /// until the user picks one; sync/test guard against that.
    var resolvedFolderID: String { selectedFolderID }

    /// Assembles what `GoogleDrivePickerView` needs: a fresh access token plus
    /// the browser API key and project number read from `GoogleService-Info`.
    /// Throws a readable error if the app hasn't been configured with a Picker
    /// API key yet.
    func pickerConfig() async throws -> GoogleDrivePickerConfig {
        let credentials = try await credentials()

        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path) else {
            throw GoogleDriveError.pickerNotConfigured
        }
        guard let apiKey = (plist["API_KEY"] as? String), !apiKey.isEmpty else {
            throw GoogleDriveError.pickerNotConfigured
        }
        // The project number that the Picker wants as its "app ID" is the
        // leading numeric segment of the OAuth client ID.
        guard let clientID = plist["CLIENT_ID"] as? String,
              let appId = clientID.split(separator: "-").first.map(String.init) else {
            throw GoogleDriveError.pickerNotConfigured
        }

        return GoogleDrivePickerConfig(accessToken: credentials.accessToken, apiKey: apiKey, appId: appId)
    }

    /// Fetches a fresh access token, silently refreshing it if it's expired,
    /// and wraps it in a plain `Sendable` value. `GoogleDriveClient` and
    /// `GoogleDriveSyncEngine` take that value rather than a live
    /// token-fetching closure or a `GIDGoogleUser` reference, so it can be
    /// captured safely inside concurrent task-group closures during a sync.
    func credentials() async throws -> GoogleDriveCredentials {
        guard let user = GIDSignIn.sharedInstance.currentUser else { throw GoogleDriveError.notSignedIn }
        let token = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            user.refreshTokensIfNeeded { refreshedUser, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let token = refreshedUser?.accessToken.tokenString else {
                    continuation.resume(throwing: GoogleDriveError.notSignedIn)
                    return
                }
                continuation.resume(returning: token)
            }
        }
        return GoogleDriveCredentials(accessToken: token)
    }

    func testConnection() async {
        guard isConfigured else {
            connectionError = "Sign in with Google to continue."
            isConnected = false
            return
        }
        guard hasSelectedFolder else {
            connectionError = "Choose a Drive folder to sync from."
            isConnected = false
            return
        }
        isTestingConnection = true
        connectionError = nil
        defer { isTestingConnection = false }

        do {
            let credentials = try await credentials()
            try await GoogleDriveClient.testConnection(folderID: resolvedFolderID, credentials: credentials)
            isConnected = true
        } catch {
            isConnected = false
            connectionError = error.localizedDescription
        }
    }
}

extension UIApplication {
    var foregroundRootViewController: UIViewController? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    }
}
