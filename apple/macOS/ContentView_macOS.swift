#if os(macOS)
import SwiftUI

// MARK: - Root View (macOS)
//
// Read the `macos-platform-patterns` skill before building on this. macOS is
// a full-parity platform sharing the same Core/ as iOS + tvOS — the FEATURE
// set is identical; the IDIOM is a pointer + keyboard + menu-bar + resizable
// multi-window Mac app, NOT the iOS app resized.
//
// The load-bearing macOS rules (all cost real iteration to learn):
//   1. Shell = NavigationSplitView (sidebar Section enum + ONE NavigationPath
//      feeding a single detail column) — NOT the iOS per-tab stack.
//   2. The PLAYER REPLACES the split view as the window root while playing —
//      never an .overlay/cover on the split view (its toolbar + sidebar
//      toggle + previous title bleed through over the player).
//   3. A resizable-window hero is full-width 16:9 aspect-FIT with NO maxHeight
//      cap (a fixed height crops as the window widens; a cap insets/centers).
//   4. macOS AVPlayerItem has NO externalMetadata — show the title via the
//      window title bar, never an AVMutableComposition metadata override
//      (it BLANKS video over a resilient custom-scheme asset).
//   5. Never bare AsyncImage for browse art — route through an ImagePipeline
//      (decoded NSCache + one capped URLSession), and decode non-RGB → sRGB
//      once (Image(nsImage:)'s Metal path renders grayscale as a white box).
//   6. Structured concurrency (.task(id:)), never Combine Timer.publish, for
//      hero rotation / debounce (a timer can fire into a torn-down view).
//   7. Companion-app deep links via NSWorkspace.urlForApplication(toOpen:) /
//      open (the AppKit analog of UIApplication.canOpenURL/open) — NO
//      LSApplicationQueriesSchemes entry needed on macOS.

struct ContentView_macOS: View {
    @Environment(AppStore.self) private var store

    /// The sidebar selection IS the store's selectedTab, so the inbox (deep
    /// links, APP_START_TAB) can select a section without touching this view.
    private var section: Binding<SidebarSection?> {
        Binding(
            get: { store.selectedTab.flatMap(SidebarSection.init(rawValue:)) ?? .home },
            set: { store.selectedTab = $0?.rawValue; store.navigationPath = NavigationPath() }
        )
    }

    var body: some View {
        @Bindable var bindableStore = store
        NavigationSplitView {
            List(SidebarSection.allCases, selection: section) { item in
                Label(item.title, systemImage: item.symbol)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            // ONE NavigationPath feeds the single detail column. Every
            // pushable destination is a Hashable route resolved by a single
            // .navigationDestination — never a per-view destination.
            NavigationStack(path: $bindableStore.navigationPath) {
                Group {
                    switch section.wrappedValue ?? .home {
                    case .home:     HomeView_macOS()
                    case .browse:   Text("Browse")   // FILL IN
                    case .search:   Text("Search")   // FILL IN
                    case .library:  Text("Library")  // FILL IN
                    }
                }
                .navigationDestination(for: String.self) { destination in
                    Text(destination)  // FILL IN: your item route
                }
            }
        }
        // Menu-bar commands are wired at the App level via .commands { }
        // (keyboard-first is a Mac expectation). With a WindowGroup first +
        // a DocumentGroup, re-point ⌘N with CommandGroup(replacing: .newItem).
    }
}

/// Sidebar sections = the top-level verbs (the macOS analog of the iOS tab bar
/// / tvOS sidebar). Settings rides the app menu (⌘,), never a sidebar row.
enum SidebarSection: String, CaseIterable, Identifiable {
    case home, browse, search, library
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: "Home"; case .browse: "Browse"
        case .search: "Search"; case .library: "Library"
        }
    }
    var symbol: String {
        switch self {
        case .home: "house"; case .browse: "square.grid.2x2"
        case .search: "magnifyingglass"; case .library: "books.vertical"
        }
    }
}

// MARK: - Home (starter shape)

struct HomeView_macOS: View {
    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 32) {
                // Full-width hero: aspect-FIT 16:9, NO maxHeight cap. The image
                // rides .background so a fill-mode image can't inflate layout.
                RoundedRectangle(cornerRadius: 14)
                    .fill(.quaternary)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)

                // Shelves: LazyVGrid is fine for small counts; migrate a large
                // reusable grid to an NSCollectionView (reuse/prefetch/hover).
                ForEach(0..<3, id: \.self) { shelf in
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Shelf \(shelf + 1)").font(.title3.bold())
                        ScrollView(.horizontal) {
                            LazyHStack(spacing: 16) {
                                ForEach(0..<8, id: \.self) { _ in
                                    Button {
                                        // FILL IN: path.append(route)
                                    } label: {
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(.quaternary)
                                            .frame(width: 180, height: 101)
                                    }
                                    .buttonStyle(.plain)  // correct on macOS
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Home")
    }
}
#endif
