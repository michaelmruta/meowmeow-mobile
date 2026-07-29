import Foundation
import Observation
import UIKit
import GoogleSignIn

/// Persists the configured Drive folder (UserDefaults) and tracks Google
/// sign-in / connection state. Unlike `WebDAVAccountStore`, no
/// username/password is stored here — the GoogleSignIn SDK owns the OAuth
/// tokens in its own Keychain storage and hands back a fresh access token on
/// request via `accessToken()`.
@MainActor
@Observable
final class GoogleDriveAccountStore {
    /// Read-only scope: this app only ever downloads from Drive, never
    /// writes back, so the least-privilege scope is sufficient.
    private static let driveScope = "https://www.googleapis.com/auth/drive.readonly"

    private let folderKey = "googledrive.folderID"

    var folderIDInput: String {
        didSet { UserDefaults.standard.set(folderIDInput, forKey: folderKey) }
    }

    private(set) var currentUserEmail: String?
    private(set) var isSigningIn = false
    private(set) var isConnected = false
    private(set) var isTestingConnection = false
    private(set) var connectionError: String?

    init() {
        folderIDInput = UserDefaults.standard.string(forKey: folderKey) ?? ""
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
    }

    /// The Drive folder to sync from: accepts a raw folder ID, a full
    /// `.../folders/<id>` share link, or blank (Drive's `root` alias for the
    /// signed-in user's My Drive root).
    var resolvedFolderID: String {
        let trimmed = folderIDInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "root" }

        if let range = trimmed.range(of: "/folders/") {
            let id = trimmed[range.upperBound...].prefix { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
            if !id.isEmpty { return String(id) }
        }
        return trimmed
    }

    /// Fetches a fresh access token, silently refreshing it if it's expired.
    /// Passed around as a closure (rather than a `GIDGoogleUser` value)
    /// so `GoogleDriveClient`/`GoogleDriveSyncEngine` stay decoupled from
    /// the GoogleSignIn SDK's types.
    nonisolated func accessToken() async throws -> String {
        guard let user = await GIDSignIn.sharedInstance.currentUser else { throw GoogleDriveError.notSignedIn }
        return try await withCheckedThrowingContinuation { continuation in
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
    }

    func testConnection() async {
        guard isConfigured else {
            connectionError = "Sign in with Google to continue."
            isConnected = false
            return
        }
        isTestingConnection = true
        connectionError = nil
        defer { isTestingConnection = false }

        do {
            try await GoogleDriveClient.testConnection(folderID: resolvedFolderID, accessToken: accessToken)
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
