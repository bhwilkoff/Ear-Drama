import SwiftUI

/// The top-level verbs, as Archive Watch's (Decision 068; iOS-DESIGN §3.1):
/// sections are actions, never content types. The Mac and TV sidebars list all
/// six; iPhone's tab bar holds five, and Surprise is a push from Home's toolbar
/// (`Route.surprise`), listed in the sidebar only at regular width.
enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case home, browse, stations, surprise, search, library
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: "Home"
        case .browse: "Browse"
        case .stations: "Stations"
        case .surprise: "Surprise"
        case .search: "Search"
        case .library: "Library"
        }
    }
    var symbol: String {
        switch self {
        case .home: "house"
        case .browse: "square.grid.2x2"
        case .stations: "radio"
        case .surprise: "shuffle"
        case .search: "magnifyingglass"
        case .library: "books.vertical"
        }
    }

    /// A door's or link's name for a section, the names before Decision 068
    /// included: listen is Home, series Browse, radio Stations, plays Browse.
    init?(door raw: String) {
        let renamed = ["listen": "home", "series": "browse", "radio": "stations", "plays": "browse"]
        guard let tab = AppTab(rawValue: renamed[raw.lowercased()] ?? raw.lowercased()) else { return nil }
        self = tab
    }
}

/// Every pushable screen. ONE destination registry resolves these on every
/// platform, so any surface can push any screen from any tab.
enum Route: Hashable {
    case series(String)
    case episode(String)
    /// A person's page (`withPerson`), pushed from Detail's credits or Search
    /// (iOS-DESIGN §4.13).
    case person(String)
    /// Library's account row (iOS-DESIGN §4.10). Never a deep link.
    case account
    /// Surprise pushed from Home's toolbar on iPhone (iOS-DESIGN §4.11).
    case surprise

    /// Episode ids carry the series key and a `|`; series keys never do.
    init(id: String) {
        self = id.contains("|") ? .episode(id) : .series(id)
    }
}

/// Global app state, injected via @Environment(AppStore.self).
@Observable
final class AppStore {
    var selectedTab: AppTab = .home
    /// One NavigationPath per tab.
    var paths: [AppTab: NavigationPath] = [:]
    /// The full player is showing (iPhone sheet, TV full screen).
    var isPlayerPresented = false
    /// The sleep timer's choices are showing (a door can open them).
    var isSleepMenuPresented = false

    /// Player-level mute. A door launch sets it (APP_MUTE); the player reads
    /// it, so a harness run is silent unless it opts in.
    var isMuted = false

    /// The intent inbox: deep links and test doors are POSTED here and
    /// consumed by RootView once foregrounded.
    private(set) var inbox: [InboxRequest] = []

    enum InboxRequest: Hashable, Sendable {
        case tab(String)
        case item(String)
        case play(String)
        /// An ear drama invite's token (PLAYS-DESIGN §11.7 rule 3).
        case invite(String)
        /// Deep links (DEEP_LINKS.md): a series key, an episode id, a person id.
        case series(String)
        case episode(String)
        case person(String)
        /// Search with its query filled in.
        case search(String)
    }

    /// A deep link's search query, taken once by the Search screen.
    var pendingSearch: String?

    /// The invite opened this session, shown as Library's Invitation until
    /// joined or dropped ("Not now"). Held in memory only.
    var pendingInvite: String?

    func post(_ request: InboxRequest) { inbox.append(request) }

    func path(for tab: AppTab) -> Binding<NavigationPath> {
        Binding(get: { self.paths[tab] ?? NavigationPath() }, set: { self.paths[tab] = $0 })
    }

    func push(_ route: some Hashable) {
        var path = paths[selectedTab] ?? NavigationPath()
        path.append(route)
        paths[selectedTab] = path
    }

    /// The Mac's Back (⌘[): pops the active section's stack; nothing at its root.
    var canGoBack: Bool { !(paths[selectedTab]?.isEmpty ?? true) }

    func goBack() {
        guard canGoBack else { return }
        paths[selectedTab]?.removeLast()
    }

    /// The Mac's Search (⌘F): opens Search and asks its field for focus; the
    /// Search screen clears the request once it has taken focus.
    var wantsSearchFocus = false

    func openSearch() {
        selectedTab = .search
        wantsSearchFocus = true
    }

    /// Leaving a tab from the TV sidebar resets the stack it leaves behind
    /// (tvOS rule: stale push-state must not greet the next visit).
    func selectResettingPrevious(_ tab: AppTab) {
        if tab != selectedTab { paths[selectedTab] = NavigationPath() }
        selectedTab = tab
    }

    /// Called by the root view only. Returns the episode ids to play.
    func drainInbox() -> [String] {
        let pending = inbox
        inbox.removeAll()
        var toPlay: [String] = []
        for request in pending {
            switch request {
            case .tab(let raw):
                if let tab = AppTab(door: raw) {
                    selectedTab = tab
                    paths[tab] = NavigationPath()
                }
            case .item(let id):
                push(Route(id: id))
            case .play(let id):
                toPlay.append(id)
            case .invite(let token):
                pendingInvite = token
                selectedTab = .library
                paths[.library] = NavigationPath()
            case .series(let key):
                push(Route.series(key))
            case .episode(let id):
                push(Route.episode(id))
            case .person(let id):
                push(Route.person(id))
            case .search(let q):
                selectedTab = .search
                paths[.search] = NavigationPath()
                pendingSearch = q
            }
        }
        return toPlay
    }

    @ObservationIgnored private var doorsOpened = false

    /// Posts the launch doors once per process. Returns false when they were
    /// already opened.
    func openDoorsOnce(_ doors: LaunchDoors) -> Bool {
        guard !doorsOpened else { return false }
        doorsOpened = true
        if doors.mute { isMuted = true }
        if let tab = doors.startTab { post(.tab(tab)) }
        if let item = doors.startItem {
            post(.item(item))
            if doors.autoplay { post(.play(item)) }
        }
        if doors.autoplay { isPlayerPresented = true }
        if doors.sleepMenu { isSleepMenuPresented = true }
        return true
    }

    /// APP_DOOR_SECONDS elapsed: end the door's activity on the app's own clock.
    func endDoor() {
        paths = [:]
        isPlayerPresented = false
        isSleepMenuPresented = false
    }
}
