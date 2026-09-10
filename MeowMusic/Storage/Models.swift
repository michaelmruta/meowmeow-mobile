import Foundation
import SwiftData

/// A song is favorited by its stable relative path under Documents/Downloads.
/// `dateFavorited` drives the "most recent on top" ordering in the Favorites tab.
@Model
final class FavoriteRecord {
    @Attribute(.unique) var songPath: String
    var dateFavorited: Date

    init(songPath: String, dateFavorited: Date = .now) {
        self.songPath = songPath
        self.dateFavorited = dateFavorited
    }
}

/// Tracks recently played songs (up to 200). Last played appears at the top.
/// A song is only added if at least 33% of its duration was played.
@Model
final class RecentlyPlayedRecord {
    @Attribute(.unique) var songPath: String
    var lastPlayedDate: Date

    init(songPath: String, lastPlayedDate: Date = .now) {
        self.songPath = songPath
        self.lastPlayedDate = lastPlayedDate
    }
}

@Model
final class PlaylistEntity {
    @Attribute(.unique) var id: UUID
    var name: String
    var sortIndex: Int
    var createdDate: Date

    @Relationship(deleteRule: .cascade, inverse: \PlaylistSongEntity.playlist)
    var songs: [PlaylistSongEntity] = []

    init(id: UUID = UUID(), name: String, sortIndex: Int, createdDate: Date = .now) {
        self.id = id
        self.name = name
        self.sortIndex = sortIndex
        self.createdDate = createdDate
    }
}

@Model
final class PlaylistSongEntity {
    var songPath: String
    var sortIndex: Int
    var playlist: PlaylistEntity?

    init(songPath: String, sortIndex: Int, playlist: PlaylistEntity? = nil) {
        self.songPath = songPath
        self.sortIndex = sortIndex
        self.playlist = playlist
    }
}
