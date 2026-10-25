import CarPlay
import SwiftData
import UIKit

/// Builds the CarPlay template tree (tab bar → list templates → Now Playing)
/// and wires list selection back into the shared `PlayerService`. Kept
/// separate from `CarPlaySceneDelegate` so the delegate stays a thin
/// connect/disconnect shell.
///
/// CarPlay has no `@Query`/`@Environment(\.modelContext)`, so Favorites,
/// Playlists, and Recently Played are read with plain `FetchDescriptor`s
/// against the shared `ModelContainer.mainContext` — the same context the
/// phone UI's `@Query`s read and write, so an edit on either side is visible
/// on the other. This mirrors `FavoritesView`/`PlaylistsView`/
/// `RecentlyPlayedView`, just without SwiftUI's property wrapper.
@MainActor
final class CarPlayTemplateBuilder {
    weak var interfaceController: CPInterfaceController?

    private var env: AppEnvironment { AppEnvironment.shared }

    func makeRootTemplate() -> CPTabBarTemplate {
        let artists = makeArtistsTemplate()
        artists.tabTitle = "Artists"
        artists.tabImage = UIImage(systemName: "music.mic")

        let playlists = makePlaylistsTemplate()
        playlists.tabTitle = "Playlists"
        playlists.tabImage = UIImage(systemName: "music.note.list")

        let favorites = makeSongsTemplate(title: "Favorites", songs: fetchFavoriteSongs())
        favorites.tabTitle = "Favorites"
        favorites.tabImage = UIImage(systemName: "heart.fill")

        let recent = makeSongsTemplate(title: "Recently Played", songs: fetchRecentlyPlayedSongs(), isRecentlyPlayed: true)
        recent.tabTitle = "Recent"
        recent.tabImage = UIImage(systemName: "clock.fill")

        // CarPlay allows up to 5 tabs; 4 keeps it well within that limit.
        return CPTabBarTemplate(templates: [artists, playlists, favorites, recent])
    }

    // MARK: - Artists → Songs

    private func makeArtistsTemplate() -> CPListTemplate {
        let items = env.library.artistsAlphabetical.map { artist -> CPListItem in
            let item = CPListItem(text: artist, detailText: nil)
            item.handler = { [weak self] _, completion in
                guard let self else { completion(); return }
                MainActor.assumeIsolated {
                    let songs = self.env.library.songs(forArtist: artist)
                    let template = self.makeSongsTemplate(title: artist, songs: songs)
                    self.interfaceController?.pushTemplate(template, animated: true, completion: nil)
                }
                completion()
            }
            return item
        }
        return CPListTemplate(title: "Artists", sections: [CPListSection(items: items)])
    }

    // MARK: - Playlists → Songs

    private struct PlaylistSummary {
        let name: String
        let songs: [Song]
    }

    private func makePlaylistsTemplate() -> CPListTemplate {
        let playlists = fetchPlaylists()
        let items = playlists.map { playlist -> CPListItem in
            let count = playlist.songs.count
            let item = CPListItem(text: playlist.name, detailText: "\(count) song\(count == 1 ? "" : "s")")
            item.handler = { [weak self] _, completion in
                guard let self else { completion(); return }
                MainActor.assumeIsolated {
                    let template = self.makeSongsTemplate(title: playlist.name, songs: playlist.songs)
                    self.interfaceController?.pushTemplate(template, animated: true, completion: nil)
                }
                completion()
            }
            return item
        }
        return CPListTemplate(title: "Playlists", sections: [CPListSection(items: items)])
    }

    // MARK: - Song lists & playback

    private func makeSongsTemplate(title: String, songs: [Song], isRecentlyPlayed: Bool = false) -> CPListTemplate {
        // CPListTemplate caps the number of items it will display; favor the
        // naturally small per-artist/per-playlist lists over one giant flat
        // list, and cap defensively for any that are still large.
        let capped = Array(songs.prefix(CPListTemplate.maximumItemCount))
        let items = capped.map { song in
            makeSongItem(song: song, queue: capped, isRecentlyPlayed: isRecentlyPlayed)
        }
        return CPListTemplate(title: title, sections: [CPListSection(items: items)])
    }

    private func makeSongItem(song: Song, queue: [Song], isRecentlyPlayed: Bool) -> CPListItem {
        let item = CPListItem(text: song.title, detailText: song.artist)
        if let data = song.artwork, let image = UIImage(data: data) {
            item.setImage(image)
        }
        item.handler = { [weak self] _, completion in
            guard let self else { completion(); return }
            MainActor.assumeIsolated {
                self.env.player.play(song: song, in: queue, isRecentlyPlayed: isRecentlyPlayed)
                self.interfaceController?.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
            }
            completion()
        }
        return item
    }

    // MARK: - SwiftData fetches (no @Query available in CarPlay)

    private func fetchFavoriteSongs() -> [Song] {
        let descriptor = FetchDescriptor<FavoriteRecord>(sortBy: [SortDescriptor(\.dateFavorited, order: .reverse)])
        let records = (try? env.modelContainer.mainContext.fetch(descriptor)) ?? []
        return env.library.songs(forIDs: records.map(\.songPath))
    }

    private func fetchRecentlyPlayedSongs() -> [Song] {
        let descriptor = FetchDescriptor<RecentlyPlayedRecord>(sortBy: [SortDescriptor(\.lastPlayedDate, order: .reverse)])
        let records = (try? env.modelContainer.mainContext.fetch(descriptor)) ?? []
        return env.library.songs(forIDs: records.map(\.songPath))
    }

    private func fetchPlaylists() -> [PlaylistSummary] {
        let descriptor = FetchDescriptor<PlaylistEntity>(sortBy: [SortDescriptor(\.sortIndex)])
        let entities = (try? env.modelContainer.mainContext.fetch(descriptor)) ?? []
        // Map to Song structs immediately so no @Model object escapes this fetch.
        return entities.map { entity in
            let orderedIDs = entity.songs
                .sorted { $0.sortIndex < $1.sortIndex }
                .map(\.songPath)
            return PlaylistSummary(name: entity.name, songs: env.library.songs(forIDs: orderedIDs))
        }
    }
}
