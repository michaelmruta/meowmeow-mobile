import SwiftUI
import UIKit

/// Shared song row used by Favorites, Playlist, and Browse. `isPlaying`
/// drives the orange "now playing" highlight everywhere consistently.
struct SongRow: View {
    let song: Song
    var isPlaying: Bool
    var showArtist: Bool = true
    var showArtwork: Bool = true

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
