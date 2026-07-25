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
