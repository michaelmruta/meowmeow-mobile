import Foundation

/// Looks up lyrics via the (keyless, public) lrclib.net API, preferring the
/// synced (`.lrc`-style) result so it round-trips through `LyricsService`.
enum LyricsFetchService {
    enum FetchError: LocalizedError {
        case noResults

        var errorDescription: String? {
            "No lyrics found for this song."
        }
    }

    private struct Result: Decodable {
        let syncedLyrics: String?
        let plainLyrics: String?
    }

    static func fetchLyrics(artist: String, title: String) async throws -> String {
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
        ]
        guard let url = components.url else { throw FetchError.noResults }

        let (data, _) = try await URLSession.shared.data(from: url)
        let results = try JSONDecoder().decode([Result].self, from: data)
        guard let best = results.first(where: { ($0.syncedLyrics ?? $0.plainLyrics)?.isEmpty == false }) else {
            throw FetchError.noResults
        }
        return best.syncedLyrics ?? best.plainLyrics ?? ""
    }
}
