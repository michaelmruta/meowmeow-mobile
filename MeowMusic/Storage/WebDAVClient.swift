import Foundation

struct WebDAVCredentials: Sendable {
    var username: String
    var password: String
}

struct WebDAVEntry: Sendable {
    let url: URL
    let isDirectory: Bool
    let size: Int
    let modDate: Date
}

enum WebDAVError: LocalizedError {
    case invalidServerURL
    case invalidResponse
    case http(Int)
    case malformedListing

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "Enter a valid WebDAV server URL, starting with http:// or https://."
        case .invalidResponse:
            return "The server sent an unexpected response."
        case .http(401), .http(403):
            return "The server rejected the username or password."
        case .http(404):
            return "That folder wasn't found on the server."
        case .http(let code):
            return "Server returned an error (HTTP \(code))."
        case .malformedListing:
            return "Couldn't parse the server's file listing."
        }
    }
}

/// Talks to a WebDAV server using PROPFIND (directory listing) and GET (file
/// download). No shell/rsync equivalent is available in the iOS sandbox, so
/// this is a small hand-rolled client rather than a wrapped CLI tool.
enum WebDAVClient {
    /// Caps how many PROPFIND/GET requests run at once, so a deep folder
    /// tree or a large batch of downloads doesn't open more simultaneous
    /// connections than a self-hosted server (Synology, small Nextcloud
    /// instances) is willing to accept.
    static let maxConcurrentRequests = 4

    /// Lists every file under `root` — the whole tree, size and last-modified
    /// included, in one request via `Depth: infinity` where the server
    /// supports it (confirmed working against WsgiDAV). Some servers
    /// (Nextcloud, Apache mod_dav) disable Depth: infinity for load reasons
    /// and reject it, so on failure this falls back to walking directories
    /// one level at a time, `maxConcurrentRequests` siblings at once.
    static func listFiles(root: URL, credentials: WebDAVCredentials) async throws -> [WebDAVEntry] {
        if let entries = try? await propfind(url: root, depth: "infinity", credentials: credentials) {
            return entries.filter { !$0.isDirectory && !isSameResource($0.url, root) }
        }
        return try await listFilesShallow(root: root, credentials: credentials)
    }

    private static func listFilesShallow(root: URL, credentials: WebDAVCredentials) async throws -> [WebDAVEntry] {
        let entries = try await propfind(url: root, depth: "1", credentials: credentials)
        let directories = entries.filter { $0.isDirectory && !isSameResource($0.url, root) }
        let files = entries.filter { !$0.isDirectory && !isSameResource($0.url, root) }

        guard !directories.isEmpty else { return files }

        let nested = try await withThrowingTaskGroup(of: [WebDAVEntry].self) { group -> [[WebDAVEntry]] in
            var iterator = directories.makeIterator()
            var results: [[WebDAVEntry]] = []

            func addNext() {
                guard let directory = iterator.next() else { return }
                group.addTask {
                    try await listFilesShallow(root: directory.url, credentials: credentials)
                }
            }

            for _ in 0..<min(maxConcurrentRequests, directories.count) { addNext() }
            while let result = try await group.next() {
                results.append(result)
                addNext()
            }
            return results
        }

        return files + nested.flatMap { $0 }
    }

    static func testConnection(root: URL, credentials: WebDAVCredentials) async throws {
        _ = try await propfind(url: root, depth: "0", credentials: credentials)
    }

    /// Downloads `url` to `destinationURL` and stamps the local file's
    /// modification date with `modificationDate` (the server's Last-Modified
    /// value) so later syncs can trust a local-vs-remote mod-date comparison
    /// instead of comparing against whenever the download happened to run.
    static func download(from url: URL, to destinationURL: URL, modificationDate: Date, credentials: WebDAVCredentials) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(basicAuthHeader(credentials), forHTTPHeaderField: "Authorization")

        let (tempURL, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse else { throw WebDAVError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw WebDAVError.http(http.statusCode) }

        let fm = FileManager.default
        try? fm.removeItem(at: destinationURL)
        try fm.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: tempURL, to: destinationURL)
        try? fm.setAttributes([.modificationDate: modificationDate], ofItemAtPath: destinationURL.path)
    }

    private static func propfind(url: URL, depth: String, credentials: WebDAVCredentials) async throws -> [WebDAVEntry] {
        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue(depth, forHTTPHeaderField: "Depth")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(basicAuthHeader(credentials), forHTTPHeaderField: "Authorization")
        request.httpBody = Data("""
        <?xml version="1.0" encoding="utf-8" ?>
        <D:propfind xmlns:D="DAV:">
          <D:prop>
            <D:resourcetype/>
            <D:getcontentlength/>
            <D:getlastmodified/>
          </D:prop>
        </D:propfind>
        """.utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw WebDAVError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw WebDAVError.http(http.statusCode) }

        guard let rawEntries = WebDAVPropfindParser.parse(data: data) else {
            throw WebDAVError.malformedListing
        }

        return rawEntries.compactMap { raw in
            guard let href = raw.href,
                  let resolvedURL = URL(string: href, relativeTo: url)?.absoluteURL else { return nil }
            return WebDAVEntry(
                url: resolvedURL,
                isDirectory: raw.isCollection,
                size: raw.contentLength ?? 0,
                modDate: raw.lastModified ?? .distantPast
            )
        }
    }

    private static func basicAuthHeader(_ credentials: WebDAVCredentials) -> String {
        let raw = "\(credentials.username):\(credentials.password)"
        return "Basic \(Data(raw.utf8).base64EncodedString())"
    }

    private static func isSameResource(_ a: URL, _ b: URL) -> Bool {
        normalizedPath(a) == normalizedPath(b)
    }

    private static func normalizedPath(_ url: URL) -> String {
        var path = url.path
        if path.hasSuffix("/") { path.removeLast() }
        return path
    }
}

/// Parses a PROPFIND multistatus XML response. Namespace processing is
/// enabled so element names come through without their server-chosen prefix
/// (`D:`, `d:`, `lp1:`, ...), since that varies across WebDAV implementations.
private final class WebDAVPropfindParser: NSObject, XMLParserDelegate {
    struct RawEntry {
        var href: String?
        var isCollection = false
        var contentLength: Int?
        var lastModified: Date?
    }

    private static let httpDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        formatter.timeZone = TimeZone(identifier: "GMT")
        return formatter
    }()

    private var entries: [RawEntry] = []
    private var current: RawEntry?
    private var textBuffer = ""

    static func parse(data: Data) -> [RawEntry]? {
        let parser = XMLParser(data: data)
        let delegate = WebDAVPropfindParser()
        parser.delegate = delegate
        parser.shouldProcessNamespaces = true
        guard parser.parse() else { return nil }
        return delegate.entries
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        textBuffer = ""
        switch elementName {
        case "response":
            current = RawEntry()
        case "collection":
            current?.isCollection = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let trimmed = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "href":
            current?.href = trimmed
        case "getcontentlength":
            current?.contentLength = Int(trimmed)
        case "getlastmodified":
            current?.lastModified = Self.httpDateFormatter.date(from: trimmed)
        case "response":
            if let current { entries.append(current) }
            current = nil
        default:
            break
        }
        textBuffer = ""
    }
}
