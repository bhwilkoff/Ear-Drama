#if os(iOS)
import SwiftUI

/// iPhone and iPad: one TabView whose style adapts (a tab bar on iPhone, a
/// sidebar on iPad), one NavigationStack per tab, and the shared destination
/// registry on every stack. iOS-DESIGN §3.1 (Decision 068): iPhone's five tabs
/// are Archive Watch's verbs; Surprise is a push from Home's toolbar, and only
/// at regular width does the sidebar list it.
struct ContentView_iOS: View {
    @Environment(AppStore.self) private var store
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        @Bindable var store = store
        TabView(selection: $store.selectedTab) {
            Tab(AppTab.home.title, systemImage: AppTab.home.symbol, value: AppTab.home) {
                stack(.home) { ListenScreen() }
            }
            Tab(AppTab.browse.title, systemImage: AppTab.browse.symbol, value: AppTab.browse) {
                stack(.browse) { SeriesBrowseScreen() }
            }
            Tab(AppTab.stations.title, systemImage: AppTab.stations.symbol, value: AppTab.stations) {
                stack(.stations) { RadioScreen() }
            }
            Tab(AppTab.search.title, systemImage: AppTab.search.symbol, value: AppTab.search, role: .search) {
                stack(.search) { SearchScreen_iOS() }
            }
            Tab(AppTab.library.title, systemImage: AppTab.library.symbol, value: AppTab.library) {
                stack(.library) { LibraryScreen() }
            }
            // Hidden "for: .tabBar" alone it would still count toward the phone's
            // bar and grow a More tab (Archive Watch, seen on the iPhone 12).
            if hSize == .regular {
                Tab(AppTab.surprise.title, systemImage: AppTab.surprise.symbol, value: AppTab.surprise) {
                    stack(.surprise) { SurpriseScreen() }
                }
                .defaultVisibility(.hidden, for: .tabBar)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        // At compact width Surprise is Home's push, never a tab: a door, or a
        // window narrowed while it was selected, hands it to Home.
        .onChange(of: [store.selectedTab == .surprise, hSize == .regular], initial: true) {
            guard store.selectedTab == .surprise, hSize != .regular else { return }
            store.selectedTab = .home
            store.push(Route.surprise)
        }
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
/// when playback starts and reset every tab's stack.) The offline line sits
/// above it (iOS-DESIGN §7.2).
private struct MiniPlayerInset: ViewModifier {
    @Environment(AudioPlayer.self) private var player
    @Environment(CatalogStore.self) private var catalog

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if player.item != nil || !catalog.isOnline {
                VStack(spacing: 0) {
                    OfflineLine()
                    if player.item != nil {
                        MiniPlayer_iOS()
                            .padding(.vertical, Spacing.s2)
                    }
                }
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
    @Environment(AppStore.self) private var store
    @State private var query = ""

    var body: some View {
        SearchResultsList(query: query)
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Titles, people, spoken words")
            .onChange(of: store.pendingSearch, initial: true) { _, q in
                guard let q else { return }
                query = q
                store.pendingSearch = nil
            }
    }
}
#endif
