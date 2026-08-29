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

/// One row per song, keyed by its stable relative path. `playedAt` is
/// updated (not duplicated) on every replay, so the history reads as
/// "most recently played songs" rather than a full play log.
@Model
final class PlayHistoryRecord {
    @Attribute(.unique) var songPath: String
    var playedAt: Date

    init(songPath: String, playedAt: Date = .now) {
        self.songPath = songPath
        self.playedAt = playedAt
    }
}

/// 1-5 star rating, one per song. Absence of a record means unrated.
@Model
final class SongRatingRecord {
    @Attribute(.unique) var songPath: String
    var rating: Int

    init(songPath: String, rating: Int) {
        self.songPath = songPath
        self.rating = rating
    }
}

/// Incremented in `PlayerService` once a song has played past the
/// "counts as played" threshold, not on every tap of play.
@Model
final class SongPlayCountRecord {
    @Attribute(.unique) var songPath: String
    var playCount: Int

    init(songPath: String, playCount: Int = 0) {
        self.songPath = songPath
        self.playCount = playCount
    }
}
