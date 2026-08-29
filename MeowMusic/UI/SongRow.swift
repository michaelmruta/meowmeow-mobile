import SwiftUI
import SwiftData
import UIKit

/// Shared song row used by Favorites, Playlist, and Browse. `isPlaying`
/// drives the orange "now playing" highlight everywhere consistently.
struct SongRow: View {
    let song: Song
    var isPlaying: Bool
    var showArtist: Bool = true
    var showArtwork: Bool = true
    var showRating: Bool = true

    @Environment(\.modelContext) private var modelContext
    @Query private var ratingRecords: [SongRatingRecord]

    init(song: Song, isPlaying: Bool, showArtist: Bool = true, showArtwork: Bool = true, showRating: Bool = true) {
        self.song = song
        self.isPlaying = isPlaying
        self.showArtist = showArtist
        self.showArtwork = showArtwork
        self.showRating = showRating
        let songPath = song.id
        _ratingRecords = Query(filter: #Predicate<SongRatingRecord> { $0.songPath == songPath })
    }

    private var rating: Int { ratingRecords.first?.rating ?? 0 }

    var body: some View {
        HStack(spacing: 12) {
            if showArtwork {
                artworkThumbnail
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.body.weight(isPlaying ? .semibold : .regular))
                    .foregroundStyle(isPlaying ? Theme.orange : Theme.primaryText)
                    .lineLimit(1)
                if showArtist {
                    Text(song.artist)
                        .font(.subheadline)
                        .foregroundStyle(isPlaying ? Theme.orange.opacity(0.8) : Theme.secondaryText)
                        .lineLimit(1)
                }
                if showRating {
                    StarRatingView(rating: rating, onSet: setRating)
                }
            }
            Spacer()
            if isPlaying {
                Image(systemName: "waveform")
                    .foregroundStyle(Theme.orange)
                    .imageScale(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private func setRating(_ value: Int) {
        if let existing = ratingRecords.first {
            existing.rating = value
        } else {
            modelContext.insert(SongRatingRecord(songPath: song.id, rating: value))
        }
    }

    @ViewBuilder
    private var artworkThumbnail: some View {
        if let data = song.artwork, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous)
                .fill(Theme.card)
                .frame(width: 46, height: 46)
                .overlay { EighthNotePairIcon().padding(10) }
        }
    }
}

/// Plain tap-to-set 1-5 stars. Deliberately "dumb": tapping star N sets the
/// rating to N, no drag gesture, no tap-to-clear — matches every other
/// lightweight control in the song list rows.
struct StarRatingView: View {
    var rating: Int
    var onSet: (Int) -> Void

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    onSet(star)
                } label: {
                    Image(systemName: star <= rating ? "star.fill" : "star")
                        .font(.caption2)
                        .foregroundStyle(star <= rating ? Theme.orange : Theme.tertiaryText)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
