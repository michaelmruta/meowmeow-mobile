import Foundation

struct GoogleDriveCredentials: Sendable {
    var accessToken: String
}

struct GoogleDriveEntry: Sendable {
    let id: String
    let relativePath: String
    let size: Int
    let modDate: Date
}

enum GoogleDriveError: LocalizedError {
    case notSignedIn
    case invalidResponse
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Sign in with Google to continue."
        case .invalidResponse:
            return "Google Drive sent an unexpected response."
        case .http(401), .http(403):
            return "Google rejected the request. Try signing in again."
        case .http(404):
            return "That folder wasn't found in Drive."
        case .http(let code):
            return "Google Drive returned an error (HTTP \(code))."
        }
    }
}

/// Talks to the Google Drive REST v3 API using `files.list` (directory
/// listing, walked recursively since Drive has no native "list a whole tree"
/// call) and `files.get?alt=media` (file download). No shell/rsync
/// equivalent is available in the iOS sandbox, so this is a small
/// hand-rolled client rather than a wrapped CLI tool — mirrors the approach
/// taken for `WebDAVClient`, including taking a plain `Sendable` credentials
/// value rather than a live token-fetching closure, so it crosses into
/// concurrent task-group closures cleanly.
enum GoogleDriveClient {
    /// Caps how many `files.list`/download requests run at once, matching
    /// `WebDAVClient.maxConcurrentRequests`.
    static let maxConcurrentRequests = 4

    private static let folderMimeType = "application/vnd.google-apps.folder"
    private static let filesURL = URL(string: "https://www.googleapis.com/drive/v3/files")!

    static func testConnection(folderID: String, credentials: GoogleDriveCredentials) async throws {
        _ = try await children(ofFolder: folderID, credentials: credentials)
    }

    /// Lists every file under `rootFolderID`, walking subfolders recursively
    /// with bounded concurrency (`maxConcurrentRequests` siblings at once),
    /// building each entry's path relative to the root as it goes — Drive
    /// has no native concept of a hierarchical path, only parent-folder IDs.
    static func listFiles(rootFolderID: String, credentials: GoogleDriveCredentials) async throws -> [GoogleDriveEntry] {
        try await listFiles(folderID: rootFolderID, relativePrefix: "", credentials: credentials)
    }

    private static func listFiles(folderID: String, relativePrefix: String, credentials: GoogleDriveCredentials) async throws -> [GoogleDriveEntry] {
        let items = try await children(ofFolder: folderID, credentials: credentials)
        let folders = items.filter { $0.mimeType == folderMimeType }
        let files = items.filter { $0.mimeType != folderMimeType }.compactMap { file -> GoogleDriveEntry? in
            guard let modDate = parseDate(file.modifiedTime) else { return nil }
            return GoogleDriveEntry(
                id: file.id,
                relativePath: relativePrefix + file.name,
                size: Int(file.size ?? "0") ?? 0,
                modDate: modDate
            )
        }

        guard !folders.isEmpty else { return files }

        let nested = try await withThrowingTaskGroup(of: [GoogleDriveEntry].self) { group -> [[GoogleDriveEntry]] in
            var iterator = folders.makeIterator()
            var results: [[GoogleDriveEntry]] = []

            func addNext() {
                guard let folder = iterator.next() else { return }
                group.addTask {
                    try await listFiles(folderID: folder.id, relativePrefix: relativePrefix + folder.name + "/", credentials: credentials)
                }
            }

            for _ in 0..<min(maxConcurrentRequests, folders.count) { addNext() }
            while let result = try await group.next() {
                results.append(result)
                addNext()
            }
            return results
        }

        return files + nested.flatMap { $0 }
    }

    /// Downloads `fileID` to `destinationURL` and stamps the local file's
    /// modification date with `modificationDate` (Drive's `modifiedTime`)
    /// so later syncs can trust a local-vs-remote mod-date comparison
    /// instead of comparing against whenever the download happened to run.
    static func download(fileID: String, to destinationURL: URL, modificationDate: Date, credentials: GoogleDriveCredentials) async throws {
        var components = URLComponents(url: filesURL.appendingPathComponent(fileID), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "alt", value: "media"),
            URLQueryItem(name: "supportsAllDrives", value: "true")
        ]

        var request = URLRequest(url: components.url!)
        request.setValue(bearerAuthHeader(credentials), forHTTPHeaderField: "Authorization")

        let (tempURL, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse else { throw GoogleDriveError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw GoogleDriveError.http(http.statusCode) }

        let fm = FileManager.default
        try? fm.removeItem(at: destinationURL)
        try fm.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: tempURL, to: destinationURL)
        try? fm.setAttributes([.modificationDate: modificationDate], ofItemAtPath: destinationURL.path)
    }

    private static func children(ofFolder folderID: String, credentials: GoogleDriveCredentials) async throws -> [DriveFile] {
        var allFiles: [DriveFile] = []
        var pageToken: String?

        repeat {
            var components = URLComponents(url: filesURL, resolvingAgainstBaseURL: false)!
            var queryItems = [
                URLQueryItem(name: "q", value: "'\(folderID)' in parents and trashed = false"),
                URLQueryItem(name: "fields", value: "files(id,name,mimeType,size,modifiedTime),nextPageToken"),
                URLQueryItem(name: "pageSize", value: "1000"),
                URLQueryItem(name: "supportsAllDrives", value: "true"),
                URLQueryItem(name: "includeItemsFromAllDrives", value: "true")
            ]
            if let pageToken { queryItems.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            components.queryItems = queryItems

            var request = URLRequest(url: components.url!)
            request.setValue(bearerAuthHeader(credentials), forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw GoogleDriveError.invalidResponse }
            guard (200...299).contains(http.statusCode) else { throw GoogleDriveError.http(http.statusCode) }

            let decoded = try JSONDecoder().decode(DriveFileListResponse.self, from: data)
            allFiles.append(contentsOf: decoded.files)
            pageToken = decoded.nextPageToken
        } while pageToken != nil

        return allFiles
    }

    private static func bearerAuthHeader(_ credentials: GoogleDriveCredentials) -> String {
        "Bearer \(credentials.accessToken)"
    }

    /// Drive's `modifiedTime` is RFC 3339 and usually includes fractional
    /// seconds, but not always, so both variants are tried.
    private static func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        let withFractionalSeconds = ISO8601DateFormatter()
        withFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractionalSeconds.date(from: string) {
            return date
        }

        let withoutFractionalSeconds = ISO8601DateFormatter()
        withoutFractionalSeconds.formatOptions = [.withInternetDateTime]
        return withoutFractionalSeconds.date(from: string)
    }
}

private struct DriveFileListResponse: Decodable {
    let files: [DriveFile]
    let nextPageToken: String?
}

private struct DriveFile: Decodable {
    let id: String
    let name: String
    let mimeType: String
    let size: String?
    let modifiedTime: String?
}
