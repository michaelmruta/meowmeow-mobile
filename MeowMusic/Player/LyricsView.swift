import SwiftUI

/// Scrollable lyrics. When timed, the current line is highlighted in white
/// and auto-scrolled into view; manual scrolling always works (times are
/// never shown) and temporarily suspends auto-scroll while the user drags.
struct LyricsView: View {
    let lines: [LyricLine]
    let currentTime: TimeInterval

    @State private var userScrollOverride = false
    @State private var overrideResetTask: Task<Void, Never>?

    private var isTimed: Bool { LyricsService.isTimed(lines) }

    private var activeIndex: Int? {
        guard isTimed else { return nil }
        var result: Int?
        for (index, line) in lines.enumerated() {
            guard let time = line.time else { continue }
            if time <= currentTime { result = index } else { break }
        }
        return result
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .center, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        // Skip rendering blank lines - their spacing is added to the previous line
                        if !line.text.isEmpty {
                            Text(line.text)
                                .font(.title3.weight(index == activeIndex ? .bold : .regular))
                                .foregroundStyle(index == activeIndex ? Theme.orange : Theme.secondaryText)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .id(index)
                                .padding(.bottom, lineSpacing(at: index))
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: activeIndex)
                .padding(.horizontal, 16)
                .padding(.vertical, 64)
            }
            .simultaneousGesture(
                DragGesture().onChanged { _ in markUserScrolling() }
            )
            .mask(fadeMask)
            .onChange(of: activeIndex) { _, newValue in
                guard let newValue, !userScrollOverride else { return }
                withAnimation(.easeInOut(duration: 0.4)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    private func markUserScrolling() {
        userScrollOverride = true
        overrideResetTask?.cancel()
        overrideResetTask = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { userScrollOverride = false }
        }
    }

    private func lineSpacing(at index: Int) -> CGFloat {
        let currentLine = lines[index]
        
        // If this is the last line, no spacing needed
        guard index < lines.count - 1 else { return 0 }
        
        // Don't add spacing to blank lines (they're not rendered)
        if currentLine.text.isEmpty {
            return 0
        }
        
        // Check if next line(s) are blank - add extra spacing for each blank line
        var spacing: CGFloat = 8  // Normal spacing
        var nextIndex = index + 1
        
        while nextIndex < lines.count && lines[nextIndex].text.isEmpty {
            spacing += 24  // Add spacing for each blank line
            nextIndex += 1
        }
        
        return spacing
    }

    private var fadeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.14),
                .init(color: .black, location: 0.86),
                .init(color: .clear, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
