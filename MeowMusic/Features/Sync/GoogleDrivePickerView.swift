import SwiftUI
import UIKit
import WebKit

/// The one folder the user chose in the Google Picker.
struct GoogleDrivePickedFolder: Sendable {
    let id: String
    let name: String
}

/// Configuration the Picker JS needs, assembled by `GoogleDriveAccountStore`.
/// `Identifiable` so it can drive a SwiftUI `.sheet(item:)`; the access token is
/// unique enough per presentation to serve as the id.
struct GoogleDrivePickerConfig: Sendable, Identifiable {
    /// Fresh OAuth access token from GoogleSignIn.
    let accessToken: String
    /// Browser API key created in Google Cloud Console (Picker API enabled).
    let apiKey: String
    /// The GCP project number — the leading digits of the OAuth client ID.
    let appId: String

    var id: String { accessToken }
}

/// Hosts the Google Drive Picker inside a `WKWebView`. Google ships no native
/// iOS picker — it's a JavaScript widget loaded from `apis.google.com`. We feed
/// it the signed-in user's OAuth token so it renders that user's Drive, let
/// them pick a single folder, and bridge the chosen folder's id/name back to
/// Swift via a `WKScriptMessageHandler`. With the `drive.file` scope, selecting
/// a folder here is what grants the app recursive read access to its contents;
/// there is no other way to reference a folder under that scope.
struct GoogleDrivePickerView: UIViewControllerRepresentable {
    let config: GoogleDrivePickerConfig
    let onPick: (GoogleDrivePickedFolder) -> Void
    let onCancel: () -> Void
    let onError: (String) -> Void

    /// `setOrigin` for the Picker must match the web view's own origin, so we
    /// load the bootstrap HTML with this as its base URL. It also needs to be
    /// allow-listed on the browser API key (or the key left unrestricted).
    static let origin = "https://meowmusic.app"

    func makeUIViewController(context: Context) -> GoogleDrivePickerController {
        GoogleDrivePickerController(
            config: config,
            onPick: onPick,
            onCancel: onCancel,
            onError: onError
        )
    }

    func updateUIViewController(_ uiViewController: GoogleDrivePickerController, context: Context) {}
}

final class GoogleDrivePickerController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate {
    private let config: GoogleDrivePickerConfig
    private let onPick: (GoogleDrivePickedFolder) -> Void
    private let onCancel: () -> Void
    private let onError: (String) -> Void
    private var webView: WKWebView!
    /// Guards against the callback firing more than once (PICKED then CANCEL,
    /// or a late message after we've already dismissed).
    private var didFinish = false

    init(
        config: GoogleDrivePickerConfig,
        onPick: @escaping (GoogleDrivePickedFolder) -> Void,
        onCancel: @escaping () -> Void,
        onError: @escaping (String) -> Void
    ) {
        self.config = config
        self.onPick = onPick
        self.onCancel = onCancel
        self.onError = onError
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let contentController = WKUserContentController()
        contentController.add(self, name: "picker")

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .clear
        view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        webView.loadHTMLString(pickerHTML, baseURL: URL(string: GoogleDrivePickerView.origin))
    }

    // MARK: - Selection bridge

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard !didFinish, let body = message.body as? [String: Any] else { return }

        if let errorMessage = body["error"] as? String {
            finish { self.onError(errorMessage) }
            return
        }
        if body["cancelled"] as? Bool == true {
            finish { self.onCancel() }
            return
        }
        if let id = body["id"] as? String, let name = body["name"] as? String {
            finish { self.onPick(GoogleDrivePickedFolder(id: id, name: name)) }
        }
    }

    private func finish(_ action: @escaping () -> Void) {
        didFinish = true
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "picker")
        action()
    }

    // MARK: - HTML

    private var pickerHTML: String {
        """
        <!DOCTYPE html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
          <style>
            html, body { margin: 0; height: 100%; background: transparent; }
            .status { font: -apple-system-body; color: #888; text-align: center; margin-top: 40vh; }
          </style>
        </head>
        <body>
          <div class="status">Loading Google Drive…</div>
          <script src="https://apis.google.com/js/api.js"></script>
          <script>
            const OAUTH_TOKEN = "\(escapeForJS(config.accessToken))";
            const API_KEY = "\(escapeForJS(config.apiKey))";
            const APP_ID = "\(escapeForJS(config.appId))";
            const ORIGIN = "\(escapeForJS(GoogleDrivePickerView.origin))";

            function post(payload) {
              try { window.webkit.messageHandlers.picker.postMessage(payload); } catch (e) {}
            }

            function onApiLoad() {
              gapi.load('picker', { callback: createPicker, onerror: onLoadError });
            }

            function onLoadError() {
              post({ error: "Couldn't load the Google Picker. Check your network connection." });
            }

            function createPicker() {
              try {
                const foldersView = new google.picker.DocsView(google.picker.ViewId.FOLDERS)
                  .setSelectFolderEnabled(true)
                  .setIncludeFolders(true)
                  .setMimeTypes('application/vnd.google-apps.folder');

                const sharedView = new google.picker.DocsView(google.picker.ViewId.FOLDERS)
                  .setSelectFolderEnabled(true)
                  .setIncludeFolders(true)
                  .setOwnedByMe(false)
                  .setMimeTypes('application/vnd.google-apps.folder');

                const picker = new google.picker.PickerBuilder()
                  .setAppId(APP_ID)
                  .setOAuthToken(OAUTH_TOKEN)
                  .setDeveloperKey(API_KEY)
                  .setOrigin(ORIGIN)
                  .addView(foldersView)
                  .addView(sharedView)
                  .setTitle('Choose your music folder')
                  .setCallback(pickerCallback)
                  .build();
                picker.setVisible(true);
              } catch (e) {
                post({ error: "Couldn't open the picker: " + (e && e.message ? e.message : e) });
              }
            }

            function pickerCallback(data) {
              const action = data[google.picker.Response.ACTION];
              if (action === google.picker.Action.PICKED) {
                const doc = data[google.picker.Response.DOCUMENTS][0];
                post({ id: doc[google.picker.Document.ID], name: doc[google.picker.Document.NAME] });
              } else if (action === google.picker.Action.CANCEL) {
                post({ cancelled: true });
              }
            }

            onApiLoad();
          </script>
        </body>
        </html>
        """
    }

    private func escapeForJS(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
