import SwiftUI

/// Centralized orange-on-black theme. Every "now playing" highlight in the app
/// (list rows, lyric lines, filter chips) should route through `Theme.highlight`
/// so the look stays consistent if the palette ever changes.
enum Theme {
    static let orange = Color("AccentColor")
    static let background = Color("AppBlack")
    static let card = Color("CardBlack")

    static let highlight = orange
    static let highlightDim = orange.opacity(0.16)

    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.55)
    static let tertiaryText = Color.white.opacity(0.35)

    static let cornerRadius: CGFloat = 12
    static let smallCornerRadius: CGFloat = 6
}

extension View {
    /// Standard "currently playing" row treatment: orange text + subtle tinted background.
    func nowPlayingHighlight(_ isActive: Bool) -> some View {
        self
            .foregroundStyle(isActive ? Theme.highlight : Theme.primaryText)
            .animation(.easeInOut(duration: 0.2), value: isActive)
    }
}

struct RowHighlightBackground: View {
    var isActive: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.smallCornerRadius, style: .continuous)
            .fill(isActive ? Theme.highlightDim : .clear)
    }
}
