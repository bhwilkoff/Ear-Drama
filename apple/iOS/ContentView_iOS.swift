#if os(iOS)
import SwiftUI

/// iPhone and iPad: one TabView whose style adapts (a tab bar on iPhone, a
/// sidebar on iPad), one NavigationStack per tab, and the shared destination
/// registry on every stack. iOS-DESIGN §3.1 (Decision 075): five tabs at every
/// width, Home, Browse, Record, Search, Library; Stations and Surprise are
/// pushes from Home, never tabs, so the Duo's strip shows nothing twice.
struct ContentView_iOS: View {
    @Environment(AppStore.self) private var store
    @Environment(PlaysLibrary.self) private var plays

    var body: some View {
        @Bindable var store = store
        TabView(selection: $store.selectedTab) {
            Tab(AppTab.home.title, systemImage: AppTab.home.symbol, value: AppTab.home) {
                stack(.home) { ListenScreen() }
            }
            Tab(AppTab.browse.title, systemImage: AppTab.browse.symbol, value: AppTab.browse) {
                stack(.browse) { SeriesBrowseScreen() }
            }
            Tab(AppTab.record.title, systemImage: AppTab.record.symbol, value: AppTab.record) {
                stack(.record) { RecordScreen() }
            }
            Tab(AppTab.search.title, systemImage: AppTab.search.symbol, value: AppTab.search, role: .search) {
                stack(.search) { SearchScreen_iOS() }
            }
            Tab(AppTab.library.title, systemImage: AppTab.library.symbol, value: AppTab.library) {
                stack(.library) { LibraryScreen() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .modifier(HapticFeedback_iOS())
        .sheet(isPresented: $store.isPlayerPresented) {
            PlayerSheet_iOS()
                .presentationDragIndicator(.visible)
        }
        .task(id: store.productionDoor) {
            guard let id = store.productionDoor else { return }
            store.productionDoor = nil
            guard let script = try? await plays.script(id: id), let made = try? plays.store.create(script) else { return }
            store.selectedTab = .record
            store.push(PlayRoute.production(made.id))
        }
        .fullScreenCover(item: $store.reading) { target in
            NavigationStack { ScriptReaderView(scriptID: target.scriptID, startLine: target.line, studio: target.studio) }
        }
        #if DEBUG
        .onAppear { ScrollDoor.openIfAsked() }
        #endif
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
