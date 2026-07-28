import Foundation

/// A single playable track, derived from a file under Documents/Downloads/<Artist>/.
/// `id` is the path relative to Documents so it stays stable across app relaunches
/// and can be persisted in `FavoriteRecord`/`PlaylistSongEntity`.
struct Song: Identifiable, Equatable, Hashable, Codable {
    let id: String
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var bitrateKbps: Int?
    var artwork: Data?
    var fileURL: URL
    var dateAdded: Date

    static func == (lhs: Song, rhs: Song) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
