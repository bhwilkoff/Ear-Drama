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

private struct SearchScreen_iOS: View {
    @State private var query = ""

    var body: some View {
        SearchResultsList(query: query)
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Titles, series, people")
    }
}
#endif
