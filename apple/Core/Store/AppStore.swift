import SwiftUI

/// The top-level verbs: the iPhone tab bar, the Mac sidebar, the TV sidebar.
/// Radio follows Series, as on the web (Tonight in 19xx, contract §8). Plays is
/// on iPhone, iPad, and Mac; the TV records nothing and shows no Plays tab
/// (PLAYS-DESIGN §6).
enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case listen, series, radio, plays, search, library
    var id: String { rawValue }
    var title: String {
        switch self {
        case .listen: "Listen"
        case .series: "Series"
        case .radio: "Radio"
        case .plays: "Plays"
        case .search: "Search"
        case .library: "Library"
        }
    }
    var symbol: String {
        switch self {
        case .listen: "play.circle"
        case .series: "square.stack"
        case .radio: "radio"
        case .plays: "theatermasks"
        case .search: "magnifyingglass"
        case .library: "books.vertical"
        }
    }
}

/// Every pushable screen. ONE destination registry resolves these on every
/// platform, so any surface can push any screen from any tab.
enum Route: Hashable {
    case series(String)
    case episode(String)

    /// Episode ids carry the series key and a `|`; series keys never do.
    init(id: String) {
        self = id.contains("|") ? .episode(id) : .series(id)
    }
}

/// Global app state, injected via @Environment(AppStore.self).
@Observable
final class AppStore {
    var selectedTab: AppTab = .listen
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
    }

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
                if let tab = AppTab(rawValue: raw) {
                    selectedTab = tab
                    paths[tab] = NavigationPath()
                }
            case .item(let id):
                push(Route(id: id))
            case .play(let id):
                toPlay.append(id)
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
