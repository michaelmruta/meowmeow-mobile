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

    /// Seeds `songs` from the on-disk cache immediately, before the first
    /// `scan()` even runs, so a normal reopen renders the library the app
    /// already had instead of a "Loading Library…" flash. `scan()` still
    /// verifies against the filesystem afterward and corrects `songs` if
    /// anything actually changed, but that happens silently in the background.
    init() {
        songs = Self.loadCache().values.map(\.song)
    }

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

    /// Caps how many files load metadata concurrently, so a large library
    /// still benefits from overlap without opening an unbounded number of
    /// `AVURLAsset` loads at once.
    nonisolated private static let maxConcurrentLoads = 8

    /// Metadata (title/artist/album/artwork/duration/bitrate) is the
    /// expensive part of a scan — it means parsing every file's tags via
    /// AVFoundation. Keyed by `Song.id` (path relative to Documents) and
    /// invalidated per-file by size+mod-date, so a rescan (e.g. right after a
    /// sync) only redoes that work for files that are actually new or
    /// changed; everything else is served from the last scan's cache.
    ///
    /// Artwork is deliberately kept OUT of this JSON — embedding every song's
    /// album art as base64 here made the single cache file scale with the
    /// whole library's artwork size, which made loading the "cache" on a
    /// large library slow (and prone to failing to save) in exactly the way
    /// a scan is supposed to avoid. Artwork is written to its own small file
    /// per song instead (see `artworkFileURL`) and reattached after decode.
    private struct CacheEntry: Codable {
        let song: Song
        let fileSize: Int

        private enum CodingKeys: String, CodingKey {
            case song, fileSize
        }

        init(song: Song, fileSize: Int) {
            self.song = song
            self.fileSize = fileSize
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            song = try container.decode(Song.self, forKey: .song)
            fileSize = try container.decode(Int.self, forKey: .fileSize)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            var songWithoutArtwork = song
            songWithoutArtwork.artwork = nil
            try container.encode(songWithoutArtwork, forKey: .song)
            try container.encode(fileSize, forKey: .fileSize)
        }
    }

    nonisolated private static var cacheFileURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LibraryScanCache.json")
    }

    nonisolated private static var artworkCacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LibraryArtworkCache", isDirectory: true)
    }

    nonisolated private static func artworkFileURL(for relativePath: String) -> URL {
        artworkCacheDirectory.appendingPathComponent(relativePath.replacingOccurrences(of: "/", with: "_"))
    }

    nonisolated private static func loadArtwork(for relativePath: String) -> Data? {
        try? Data(contentsOf: artworkFileURL(for: relativePath))
    }

    nonisolated private static func saveArtwork(_ data: Data, for relativePath: String) {
        try? FileManager.default.createDirectory(at: artworkCacheDirectory, withIntermediateDirectories: true)
        try? data.write(to: artworkFileURL(for: relativePath), options: .atomic)
    }

    func scan() async {
        ensureDirectories()
        isScanning = true
        defer { isScanning = false }

        let root = Self.downloadsURL
        let documentsRoot = Self.documentsURL

        // The stat walk, cache comparison, artwork sidecar reads, and any
        // AVFoundation metadata loads all happen off the main actor, so a
        // scan — even one that finds real changes — never blocks the UI.
        songs = await Task.detached(priority: .utility) {
            let scannedFiles = Self.collectScannedFiles(in: root)
            let cache = Self.loadCache()

            var freshCache: [String: CacheEntry] = [:]
            var results: [Song] = []
            var needsLoad: [(url: URL, size: Int)] = []

            for file in scannedFiles {
                let relativePath = Self.relativePath(of: file.url, root: documentsRoot)
                if let cached = cache[relativePath],
                   cached.fileSize == file.size,
                   cached.song.dateAdded == file.modDate {
                    var song = cached.song
                    song.fileURL = file.url
                    song.artwork = Self.loadArtwork(for: relativePath)
                    freshCache[relativePath] = CacheEntry(song: song, fileSize: file.size)
                    results.append(song)
                } else {
                    needsLoad.append((file.url, file.size))
                }
            }

            if !needsLoad.isEmpty {
                await withTaskGroup(of: (String, Song?, Int).self) { group in
                    var iterator = needsLoad.makeIterator()

                    func addNext() {
                        guard let file = iterator.next() else { return }
                        group.addTask {
                            let relativePath = Self.relativePath(of: file.url, root: documentsRoot)
                            let song = await Self.loadSong(at: file.url, documentsRoot: documentsRoot)
                            return (relativePath, song, file.size)
                        }
                    }

                    for _ in 0..<min(Self.maxConcurrentLoads, needsLoad.count) { addNext() }

                    while let (relativePath, song, size) = await group.next() {
                        if let song {
                            if let artwork = song.artwork {
                                Self.saveArtwork(artwork, for: relativePath)
                            }
                            freshCache[relativePath] = CacheEntry(song: song, fileSize: size)
                            results.append(song)
                        }
                        addNext()
                    }
                }
            }

            Self.saveCache(freshCache)
            return results
        }.value
    }

    nonisolated private static func relativePath(of url: URL, root: URL) -> String {
        let normalizedRoot = root.resolvingSymlinksInPath().path
        return url.resolvingSymlinksInPath().path.replacingOccurrences(of: normalizedRoot + "/", with: "")
    }

    nonisolated private static func loadCache() -> [String: CacheEntry] {
        guard let data = try? Data(contentsOf: cacheFileURL),
              let decoded = try? JSONDecoder().decode([String: CacheEntry].self, from: data) else {
            return [:]
        }
        return decoded
    }

    nonisolated private static func saveCache(_ cache: [String: CacheEntry]) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: cacheFileURL, options: .atomic)
    }

    private struct ScannedFile {
        let url: URL
        let size: Int
        let modDate: Date
    }

    nonisolated private static func collectScannedFiles(in root: URL) -> [ScannedFile] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let audioExtensions: Set<String> = ["mp4", "m4a", "mp3", "wav", "aac", "flac"]
        var files: [ScannedFile] = []
        for case let fileURL as URL in enumerator {
            guard audioExtensions.contains(fileURL.pathExtension.lowercased()) else { continue }
            let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            files.append(ScannedFile(
                url: fileURL,
                size: values?.fileSize ?? 0,
                modDate: values?.contentModificationDate ?? .distantPast
            ))
        }
        return files
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
        let relativePath = Self.relativePath(of: url, root: documentsRoot)
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
