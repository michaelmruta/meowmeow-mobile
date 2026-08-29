import SwiftUI

/// App root: hosts the tab bar (Now Playing / Favorites / Playlist / Browse /
/// Sync). The tab bar is always present; the metadata editor is reached from
/// the (i) button on the Now Playing tab instead of a separate pane.
///
/// Also hosts the "recently played" sidebar, toggled by pressing Y on a
/// hardware keyboard (iPad/Catalyst) — it lives here rather than in
/// `RootTabView` so it can overlay every tab, not just Now Playing.
struct RootContainerView: View {
    @State private var showingHistory = false
    @FocusState private var isFocused: Bool

    var body: some View {
        RootTabView()
            .background(Theme.background.ignoresSafeArea())
            .focusable()
            .focusEffectDisabled()
            .focused($isFocused)
            .onAppear { isFocused = true }
            .onKeyPress { press in
                guard press.characters.lowercased() == "y" else { return .ignored }
                showingHistory.toggle()
                return .handled
            }
            .overlay {
                if showingHistory {
                    ZStack(alignment: .trailing) {
                        Color.black.opacity(0.35)
                            .ignoresSafeArea()
                            .onTapGesture { showingHistory = false }

                        HistorySidebarView(isPresented: $showingHistory)
                            .frame(maxWidth: 340)
                            .frame(maxHeight: .infinity)
                            .ignoresSafeArea(edges: .vertical)
                            .transition(.move(edge: .trailing))
                    }
                }
            }
            .animation(.easeInOut(duration: 0.25), value: showingHistory)
    }
}
