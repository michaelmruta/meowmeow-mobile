import Foundation

/// Looks up album artwork via the (keyless, public) iTunes Search API.
enum ArtworkFetchService {
    enum FetchError: LocalizedError {
        case noResults
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .noResults: return "No artwork found for this song."
            case .invalidResponse: return "The artwork lookup returned an unexpected response."
            }
        }
    }

    private struct SearchResponse: Decodable {
        let results: [Result]
    }

    private struct Result: Decodable {
        let artworkUrl100: String?
    }

    static func fetchArtwork(artist: String, album: String, title: String) async throws -> Data {
        let term = [artist, album.isEmpty || album == artist ? title : album]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !term.isEmpty else { throw FetchError.noResults }

        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "5"),
        ]
        guard let searchURL = components.url else { throw FetchError.invalidResponse }

        let (data, _) = try await URLSession.shared.data(from: searchURL)
        let response = try JSONDecoder().decode(SearchResponse.self, from: data)
        guard let artworkURLString = response.results.compactMap(\.artworkUrl100).first else {
            throw FetchError.noResults
        }

        // The search API only returns 100x100 thumbnails; iTunes serves the
        // same asset at higher resolutions if you swap the size in the path.
        let highResURLString = artworkURLString.replacingOccurrences(of: "100x100bb", with: "600x600bb")
        guard let artworkURL = URL(string: highResURLString) else { throw FetchError.invalidResponse }

        let (imageData, _) = try await URLSession.shared.data(from: artworkURL)
        return imageData
    }
}
