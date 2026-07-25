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
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        Text(line.text.isEmpty ? " " : line.text)
                            .font(.title3.weight(index == activeIndex ? .bold : .regular))
                            .foregroundStyle(index == activeIndex ? Theme.orange : Theme.secondaryText)
                            .id(index)
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
