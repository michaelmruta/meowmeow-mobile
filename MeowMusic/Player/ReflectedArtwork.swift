import SwiftUI
import UIKit

/// Album art with a soft mirrored reflection fading out beneath it.
struct ReflectedArtwork: View {
    let artwork: Data?
    var size: CGFloat

    var body: some View {
        if let image {
            VStack(spacing: 2) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.55), radius: 24, y: 14)

                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .scaleEffect(x: 1, y: -1)
                    .frame(height: size * 0.32, alignment: .top)
                    .clipped()
                    .mask(
                        LinearGradient(colors: [.white.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom)
                    )
            }
        } else {
            VStack(spacing: 2) {
                placeholderImage
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.55), radius: 24, y: 14)

                placeholderImage
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .scaleEffect(x: 1, y: -1)
                    .frame(height: size * 0.32, alignment: .top)
                    .clipped()
                    .mask(
                        LinearGradient(colors: [.white.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom)
                    )
            }
        }
    }

    private var image: UIImage? {
        artwork.flatMap(UIImage.init(data:))
    }

    private var placeholderImage: some View {
        Image("EmptyArtworkPlaceholder")
            .resizable()
            .aspectRatio(contentMode: .fill)
    }
}
