import Foundation
import AVFoundation
import Observation

/// Scans Documents/Downloads/<Artist>/<file> and keeps an in-memory library.
/// The filesystem (managed by the user via Finder, or mirrored in by Sync) is
/// the source of truth for which songs exist; SwiftData only stores
/// favorites/playlists on top of it. Storage is always the app's local,
/// on-device Documents directory — deliberately not iCloud, since that
/// container's availability is resolved asynchronously and can differ
/// between launches, which made the library appear to go empty at random.
@MainActor
@Observable
final class LibraryStore {
    private static let seedFileName = "Add Music Here.txt"

    private(set) var songs: [Song] = []
    private(set) var isScanning = false

    static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var downloadsURL: URL {
        documentsURL.appendingPathComponent("Downloads", isDirectory: true)
    }

    static var playlistsURL: URL {
        documentsURL.appendingPathComponent("Playlists", isDirectory: true)
    }

    var artistsAlphabetical: [String] {
        Array(Set(songs.map(\.artist))).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    func songs(forArtist artist: String) -> [Song] {
        songs
            .filter { $0.artist == artist }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    struct AlbumGroup: Identifiable {
        var id: String { album }
        var album: String
        var artwork: Data?
        var songs: [Song]
    }

    func albums(forArtist artist: String) -> [AlbumGroup] {
        let grouped = Dictionary(grouping: songs(forArtist: artist), by: \.album)
        return grouped.keys
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { album in
                let albumSongs = grouped[album] ?? []
                let art = albumSongs.first(where: { $0.artwork != nil })?.artwork
                return AlbumGroup(album: album, artwork: art, songs: albumSongs)
            }
    }

    func song(withID id: String) -> Song? {
        songs.first { $0.id == id }
    }

    func ensureDirectories() {
        let fm = FileManager.default
        try? fm.createDirectory(at: Self.downloadsURL, withIntermediateDirectories: true)
        try? fm.createDirectory(at: Self.playlistsURL, withIntermediateDirectories: true)
        Self.ensureSeedFile()
    }

    func scan() async {
        ensureDirectories()
        isScanning = true
        defer { isScanning = false }

        let root = Self.downloadsURL
        let documentsRoot = Self.documentsURL
        let fileURLs = Self.collectAudioFileURLs(in: root)

        var results: [Song] = []
        for fileURL in fileURLs {
            if let song = await Self.loadSong(at: fileURL, documentsRoot: documentsRoot) {
                results.append(song)
            }
        }
        songs = results
    }

    nonisolated private static func collectAudioFileURLs(in root: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let audioExtensions: Set<String> = ["mp4", "m4a", "mp3", "wav", "aac", "flac"]
        var fileURLs: [URL] = []
        for case let fileURL as URL in enumerator {
            guard audioExtensions.contains(fileURL.pathExtension.lowercased()) else { continue }
            fileURLs.append(fileURL)
        }
        return fileURLs
    }

    private static func ensureSeedFile() {
        let fileURL = documentsURL.appendingPathComponent(seedFileName)
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return }

        let text = """
        Add your music files to the Downloads folder.

        Suggested layout:
        Downloads/Artist Name/Song Title.mp3
        """
        try? text.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private static func loadSong(at url: URL, documentsRoot: URL) async -> Song? {
        let relativePath = url.path.replacingOccurrences(of: documentsRoot.path + "/", with: "")
        let artistFolder = url.deletingLastPathComponent().lastPathComponent
        let fallbackTitle = url.deletingPathExtension().lastPathComponent
        let resourceValues = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .totalFileSizeKey])
        let dateAdded = resourceValues?.contentModificationDate ?? .now
        let fileSize = resourceValues?.totalFileSize ?? resourceValues?.fileSize

        var title = fallbackTitle
        var artist = artistFolder
        var album = artistFolder
        var artwork: Data?
        var duration: TimeInterval = 0
        var bitrateKbps: Int?

        let asset = AVURLAsset(url: url)
        if let metadata = try? await asset.load(.commonMetadata) {
            for item in metadata {
                guard let key = item.commonKey else { continue }
                switch key {
                case .commonKeyTitle:
                    if let v = try? await item.load(.stringValue), !v.isEmpty { title = v }
                case .commonKeyArtist:
                    if let v = try? await item.load(.stringValue), !v.isEmpty { artist = v }
                case .commonKeyAlbumName:
                    if let v = try? await item.load(.stringValue), !v.isEmpty { album = v }
                case .commonKeyArtwork:
                    if let v = try? await item.load(.dataValue) { artwork = v }
                default:
                    break
                }
            }
        }
        if let seconds = try? await asset.load(.duration).seconds, seconds.isFinite {
            duration = seconds
        }
        if let audioTracks = try? await asset.loadTracks(withMediaType: .audio) {
            var totalBitrate: Float = 0
            for track in audioTracks {
                if let estimatedDataRate = try? await track.load(.estimatedDataRate), estimatedDataRate > 0 {
                    totalBitrate += estimatedDataRate
                }
            }
            if totalBitrate > 0 {
                bitrateKbps = Int((totalBitrate / 1000).rounded())
            }
        }
        if bitrateKbps == nil, let fileSize, duration > 0 {
            bitrateKbps = Int(((Double(fileSize) * 8) / duration / 1000).rounded())
        }

        return Song(
            id: relativePath,
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            bitrateKbps: bitrateKbps,
            artwork: artwork,
            fileURL: url,
            dateAdded: dateAdded
        )
    }
}
