import Foundation

/// Mirrors each `PlaylistEntity` to a standard extended M3U file under
/// Documents/Playlists so playlists are visible/portable via Finder.
@MainActor
enum PlaylistFileManager {
    struct PlaylistFile {
        var name: String
        var songPaths: [String]
        var url: URL
    }

    static func sanitizedFileName(for name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Playlist" : cleaned
    }

    static func fileURL(for name: String) -> URL {
        LibraryStore.playlistsURL
            .appendingPathComponent(sanitizedFileName(for: name))
            .appendingPathExtension("m3u")
    }

    static func write(name: String, songPaths: [String], library: LibraryStore) {
        var lines = ["#EXTM3U", "#PLAYLIST:\(name)"]
        for path in songPaths {
            if let song = library.song(withID: path) {
                let seconds = song.duration.isFinite ? Int(song.duration.rounded()) : -1
                lines.append("#EXTINF:\(seconds),\(song.artist) - \(song.title)")
            }
            lines.append(m3uPathLine(for: path))
        }
        let content = lines.joined(separator: "\n") + "\n"
        try? FileManager.default.createDirectory(at: LibraryStore.playlistsURL, withIntermediateDirectories: true)
        try? content.write(to: fileURL(for: name), atomically: true, encoding: .utf8)
    }

    static func rename(oldName: String, newName: String) {
        let fm = FileManager.default
        let oldURL = fileURL(for: oldName)
        let newURL = fileURL(for: newName)
        try? fm.moveItem(at: oldURL, to: newURL)
    }

    static func delete(name: String) {
        try? FileManager.default.removeItem(at: fileURL(for: name))
    }

    static func readPlaylist(from url: URL, library: LibraryStore) -> PlaylistFile? {
        guard let content = readString(from: url) else { return nil }

        var playlistName = url.deletingPathExtension().lastPathComponent
        var songPaths: [String] = []

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("#PLAYLIST:") {
                let name = line.dropFirst("#PLAYLIST:".count).trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    playlistName = name
                }
                continue
            }

            guard !line.hasPrefix("#") else { continue }

            if let songPath = normalizedSongPath(from: line, playlistURL: url, library: library) {
                songPaths.append(songPath)
            }
        }

        return PlaylistFile(name: playlistName, songPaths: songPaths, url: url)
    }

    static func readExistingPlaylists(library: LibraryStore) -> [PlaylistFile] {
        existingPlaylistFiles().compactMap { readPlaylist(from: $0, library: library) }
    }

    private static func existingPlaylistFiles() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: LibraryStore.playlistsURL,
            includingPropertiesForKeys: nil
        )) ?? []

        return urls
            .filter { ["m3u", "m3u8"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    private static func readString(from url: URL) -> String? {
        if let content = try? String(contentsOf: url, encoding: .utf8) {
            return content
        }
        return try? String(contentsOf: url, encoding: .isoLatin1)
    }

    private static func m3uPathLine(for songPath: String) -> String {
        "../\(songPath)"
    }

    private static func normalizedSongPath(from line: String, playlistURL: URL, library: LibraryStore) -> String? {
        let rawPath = (line.removingPercentEncoding ?? line)
            .replacingOccurrences(of: "\\", with: "/")

        if let url = URL(string: rawPath), let scheme = url.scheme, scheme != "file" {
            return nil
        }

        let path: String
        if rawPath.hasPrefix("file://"), let url = URL(string: rawPath) {
            path = url.path
        } else {
            path = rawPath
        }

        if path.hasPrefix("/") {
            return documentsRelativePath(fromAbsolutePath: path, library: library)
        }

        if library.song(withID: path) != nil || path.hasPrefix("Downloads/") {
            return path
        }

        let resolvedURL = playlistURL
            .deletingLastPathComponent()
            .appendingPathComponent(path)
            .standardizedFileURL
        return documentsRelativePath(fromAbsolutePath: resolvedURL.path, library: library)
    }

    private static func documentsRelativePath(fromAbsolutePath path: String, library: LibraryStore) -> String? {
        let documentsPath = LibraryStore.documentsURL.standardizedFileURL.path
        let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path

        if standardizedPath.hasPrefix(documentsPath + "/") {
            return String(standardizedPath.dropFirst(documentsPath.count + 1))
        }

        return library.songs.first { $0.fileURL.standardizedFileURL.path == standardizedPath }?.id
    }
}
