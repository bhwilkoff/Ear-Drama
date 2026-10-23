#if os(iOS)
import SwiftUI

/// iPhone and iPad: one TabView whose style adapts (a tab bar on iPhone, a
/// sidebar on iPad), one NavigationStack per tab, and the shared destination
/// registry on every stack.
struct ContentView_iOS: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        TabView(selection: $store.selectedTab) {
            Tab(AppTab.listen.title, systemImage: AppTab.listen.symbol, value: AppTab.listen) {
                stack(.listen) { ListenScreen() }
            }
            Tab(AppTab.series.title, systemImage: AppTab.series.symbol, value: AppTab.series) {
                stack(.series) { SeriesBrowseScreen() }
            }
            Tab(AppTab.radio.title, systemImage: AppTab.radio.symbol, value: AppTab.radio) {
                stack(.radio) { RadioScreen() }
            }
            Tab(AppTab.plays.title, systemImage: AppTab.plays.symbol, value: AppTab.plays) {
                stack(.plays) { PlaysScreen() }
            }
            Tab(AppTab.library.title, systemImage: AppTab.library.symbol, value: AppTab.library) {
                stack(.library) { LibraryScreen() }
            }
            Tab(AppTab.search.title, systemImage: AppTab.search.symbol, value: AppTab.search, role: .search) {
                stack(.search) { SearchScreen_iOS() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .modifier(HapticFeedback_iOS())
        .sheet(isPresented: $store.isPlayerPresented) {
            PlayerSheet_iOS()
                .presentationDragIndicator(.visible)
        }
    }

    private func stack<Root: View>(_ tab: AppTab, @ViewBuilder root: () -> Root) -> some View {
        NavigationStack(path: store.path(for: tab)) {
            root().routeDestinations()
        }
        .modifier(MiniPlayerInset())
    }
}

/// The mini player sits inside each tab's stack, above the tab bar, on every
/// supported iOS. (The iOS 26 tab accessory would change the TabView's identity
/// when playback starts and reset every tab's stack.)
private struct MiniPlayerInset: ViewModifier {
    @Environment(AudioPlayer.self) private var player

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if player.item != nil {
                MiniPlayer_iOS()
                    .padding(.vertical, Spacing.s2)
                    .background(.regularMaterial)
            }
        }
    }
}

/// The phone's haptics (iOS-DESIGN §6.5), named through `Haptic` only:
/// selection on a tab change, success on a finished download, error with the
/// player's error line or "Download failed".
private struct HapticFeedback_iOS: ViewModifier {
    @Environment(AppStore.self) private var store
    @Environment(AudioPlayer.self) private var player
    @Environment(DownloadStore.self) private var downloads

    func body(content: Content) -> some View {
        content
            .sensoryFeedback(Haptic.selection.feedback, trigger: store.selectedTab)
            .sensoryFeedback(trigger: downloads.records.mapValues(\.state)) { old, new in
                Haptic.forDownloads(from: old, to: new)?.feedback
            }
            .sensoryFeedback(trigger: player.errorMessage) { old, new in
                Haptic.forError(from: old, to: new)?.feedback
            }
    }
}

private struct SearchScreen_iOS: View {
    @State private var query = ""

    var body: some View {
        SearchResultsList(query: query)
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Titles, series, people")
    }
}
#endif
