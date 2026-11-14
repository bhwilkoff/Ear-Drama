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
    /// nil below iOS 27 or before the first report: the size class alone decides.
    @State private var sidebarAvailable: Bool?

    /// The Duo's vertical strip shows every tab, hidden or not, so Surprise is a
    /// tab only where a sidebar can list it (iOS-DESIGN §3.1).
    private var showsSurpriseTab: Bool { hSize == .regular && sidebarAvailable != false }

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
            if showsSurpriseTab {
                Tab(AppTab.surprise.title, systemImage: AppTab.surprise.symbol, value: AppTab.surprise) {
                    stack(.surprise) { SurpriseScreen() }
                }
                .defaultVisibility(.hidden, for: .tabBar)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        // At compact width Surprise is Home's push, never a tab: a door, or a
        // window narrowed while it was selected, hands it to Home.
        .onChange(of: [store.selectedTab == .surprise, showsSurpriseTab], initial: true) {
            guard store.selectedTab == .surprise, !showsSurpriseTab else { return }
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
        .background { SidebarAvailabilityProbe(available: $sidebarAvailable) }
    }
}

/// Reports whether the tab view can show a sidebar (iOS 27; the environment value
/// is only meaningful inside a tab's content). Below 27 it reports nothing.
private struct SidebarAvailabilityProbe: View {
    @Binding var available: Bool?
    var body: some View {
        #if compiler(>=6.4)
        if #available(iOS 27, *) { Probe27(available: $available) } else { Color.clear }
        #else
        Color.clear
        #endif
    }

    // The iOS 27 SDK (Swift 6.4) has the value; the App Store workflow still builds
    // with Xcode 26.6 until its runner moves (IPHONE-DUO.md §7 Q1).
    #if compiler(>=6.4)
    @available(iOS 27, *)
    private struct Probe27: View {
        @Binding var available: Bool?
        @Environment(\.isTabViewSidebarAvailable) private var sidebar
        var body: some View {
            Color.clear.onChange(of: sidebar, initial: true) { _, a in
                if available != a { available = a }
            }
        }
    }
    #endif
}

/// The mini player sits inside each tab's stack, above the tab bar, on every
/// supported iOS. (The iOS 26 tab accessory would change the TabView's identity
/// when playback starts and reset every tab's stack.) The offline line sits
/// above it (iOS-DESIGN §7.2).
private struct MiniPlayerInset: ViewModifier {
    @Environment(AudioPlayer.self) private var player
    @Environment(CatalogStore.self) private var catalog

    @State private var barHeight: CGFloat = 0

    /// The inset alone left the last rows of every list under the bar (iPhone 12, 2026-10-31: Library's
    /// Take-down row and Stations' schedule line could not be scrolled into view), so the bar's measured
    /// height is also the scroll views' bottom margin.
    func body(content: Content) -> some View {
        content
            .contentMargins(.bottom, MiniPlayerInsetRule.scrollMargin(barHeight: barHeight), for: .scrollContent)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if player.item != nil || !catalog.isOnline {
                    VStack(spacing: 0) {
                        OfflineLine()
                        if player.item != nil {
                            MiniPlayer_iOS()
                                .padding(.vertical, Spacing.s2)
                        }
                    }
                    .background(.regularMaterial)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { barHeight = $0 }
                } else {
                    Color.clear.frame(height: 0)
                        .onAppear { barHeight = 0 }
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
