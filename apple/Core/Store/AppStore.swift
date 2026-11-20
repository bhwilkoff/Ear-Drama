import SwiftUI

/// The top-level verbs (Decision 075; iOS-DESIGN §3.1): Home what is on and where to start, Browse
/// every show by facet, Record making an ear drama, Search, Library. Stations and Surprise are pushes
/// from Home (`Route.stations`, `Route.surprise`), never sections. The TV lists four: it records
/// nothing (tvOS-DESIGN §2.1), so `.record` is never selected there.
enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case home, browse, record, search, library
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: "Home"
        case .browse: "Browse"
        case .record: "Record"
        case .search: "Search"
        case .library: "Library"
        }
    }
    var symbol: String {
        switch self {
        case .home: "house"
        case .browse: "square.grid.2x2"
        case .record: "mic"
        case .search: "magnifyingglass"
        case .library: "books.vertical"
        }
    }

    /// A door's or link's name for a section, the older names included: listen is Home, series
    /// Browse, plays Record (Decision 075), and radio, stations and surprise open Home and then push
    /// that screen (`push(forDoor:)`).
    init?(door raw: String) {
        var renamed = ["listen": "home", "series": "browse", "plays": "record",
                       "radio": "home", "stations": "home", "surprise": "home"]
        #if DEBUG
        // A test door only (the App Review recording: drags do not scroll on an open iPhone Duo).
        renamed["account"] = "library"
        #endif
        guard let tab = AppTab(rawValue: renamed[raw.lowercased()] ?? raw.lowercased()) else { return nil }
        self = tab
    }

    /// The screen a door pushes on its section once it is open: the sections that became pushes.
    static func push(forDoor raw: String) -> Route? {
        switch raw.lowercased() {
        case "radio", "stations": .stations
        case "surprise": .surprise
        #if DEBUG
        case "account": .account
        #endif
        default: nil
        }
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
    /// Surprise pushed from Home's toolbar (iOS-DESIGN §4.11).
    case surprise
    /// Stations pushed from Home's On the air and the Listen door (iOS-DESIGN §3.1, Decision 075).
    case stations
    /// A finished ear drama's page (DEEP_LINKS.md `drama/{pid}`).
    case drama(String)
    /// An invite link's page (DEEP_LINKS.md): readable signed out. Never on a TV.
    case invitation(String)
    /// A read room (DEEP_LINKS.md `read/{CODE}`): a reader on iPhone, iPad and Mac; the shared screen on a TV.
    case readRoom(String)
    /// The room's shared screen: a projector window or the Apple TV (PLAYS-DESIGN §12.5).
    case readScreen(String)
    /// The teacher's class page and its casting board (PLAYS-DESIGN §12.4).
    case classPage(String)
    case classCasting(String, String)
    /// A seat's parts at home and each take's state (PLAYS-DESIGN §12.11). Never a deep link.
    case parts

    /// Episode ids carry the series key and a `|`; series keys never do.
    init(id: String) {
        self = id.contains("|") ? .episode(id) : .series(id)
    }
}

/// What a pushed page's loading task is keyed on: the page's own id and the catalog generation, so a
/// view reused for another show reloads instead of keeping the first show's state.
enum PageIdentity {
    static func taskID(_ id: String, load: Int) -> String { "\(id)#\(load)" }
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
    /// The script reader is open on this play (iPhone and iPad, a full-screen cover; the Mac opens a window).
    var reading: ReaderTarget?
    /// A launch door's settings for the reader, taken once when the reader opens.
    var readerDoor: ReaderDoor?
    /// A launch door's play: its cast sheet opens (DEBUG doors only).
    var productionDoor: String?

    /// APP_START_ALONG: the finished drama whose page presses Listen once it has loaded; the page clears it.
    var alongDoor: String?

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
        /// A finished ear drama, by its production id.
        case drama(String)
        /// A read room by code; `screen` opens it as the shared screen.
        case readRoom(String, screen: Bool)
    }

    /// A deep link's search query, taken once by the Search screen.
    var pendingSearch: String?

    /// A genre the series page asked Browse to filter to, taken once by Browse.
    var pendingBrowseGenre: String?

    /// Browse's Ear dramas scope, asked for by Home's All; taken once by Browse.
    var pendingBrowseDramas = false

    /// Browse's Voices scope, asked for by Home's All; taken once by Browse.
    var pendingBrowseVoices = false

    func openBrowseVoices() {
        paths[.browse] = NavigationPath()
        pendingBrowseVoices = true
        selectedTab = .browse
    }

    func openBrowseDramas() {
        paths[.browse] = NavigationPath()
        pendingBrowseDramas = true
        selectedTab = .browse
    }

    /// Opens Browse filtered to a genre, at its root.
    func openBrowse(genre: String) {
        paths[.browse] = NavigationPath()
        pendingBrowseGenre = genre
        selectedTab = .browse
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
                if let found = AppTab(door: raw) {
                    #if os(tvOS)
                    let tab: AppTab = found == .record ? .home : found
                    #else
                    let tab = found
                    #endif
                    selectedTab = tab
                    paths[tab] = NavigationPath()
                    if let route = AppTab.push(forDoor: raw) { push(route) }
                }
            case .item(let id):
                push(Route(id: id))
            case .play(let id):
                toPlay.append(id)
            case .invite(let token):
                #if !os(tvOS)
                // The Invitation is its own page on Home, readable signed out; the token rides the route.
                selectedTab = .home
                var path = NavigationPath()
                path.append(Route.invitation(token))
                paths[.home] = path
                #endif
            case .drama(let pid):
                push(Route.drama(pid))
            case .readRoom(let code, let screen):
                push(screen ? Route.readScreen(code) : Route.readRoom(code))
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
        productionDoor = doors.production
        if let room = doors.readRoom, let code = ReadCore.normalizeCode(room) {
            post(.readRoom(code, screen: doors.readScreen))
        }
        if let along = doors.along {
            let pid = along.hasPrefix("rehearsal") ? "door-along:" + (along.split(separator: ":", maxSplits: 1).dropFirst().first.map(String.init) ?? "auto") : along
            alongDoor = pid
            post(.drama(pid))
        }
        if let script = doors.reader {
            readerDoor = doors.readerDoor
            reading = ReaderTarget(scriptID: script, line: doors.readerDoor.line)
        }
        return true
    }

    /// APP_DOOR_SECONDS elapsed: end the door's activity on the app's own clock.
    func endDoor() {
        paths = [:]
        isPlayerPresented = false
        isSleepMenuPresented = false
        reading = nil
    }
}

/// A play the reader is open on, and the line to open at when asked.
nonisolated struct ReaderTarget: Identifiable, Hashable, Sendable {
    let scriptID: String
    var line: String?
    /// The studio attached (PLAYS-DESIGN §2.9): the reader opens on the production's own script with the part.
    var studio: StudioTarget?
    var id: String { scriptID + (studio.map { "|" + $0.production + "|" + $0.part } ?? "") }
}

/// A production and one of its parts: the studio's one seam (`open(scriptID, at:, studio:)`).
nonisolated struct StudioTarget: Codable, Hashable, Sendable {
    let production: String
    /// The part's raw id ("role:MOLLY").
    let part: String
    /// A finished drama's read-along (PLAYS-DESIGN 2.11 rule 6): `production` is the finished production's id and this
    /// the script it follows; nothing local backs it.
    var dramaScriptID: String? = nil
    var partID: PartID { PartID(rawValue: part) }
    /// A read-along (PLAYS-DESIGN §2.11): the production's script followed by its listen-through; no part, no recording.
    static func along(_ production: String) -> StudioTarget { StudioTarget(production: production, part: "") }
    static func drama(_ production: String, scriptID: String) -> StudioTarget {
        StudioTarget(production: production, part: "", dramaScriptID: scriptID)
    }
    var isDrama: Bool { dramaScriptID != nil }
    var isAlong: Bool { part.isEmpty }
}

/// What a launch door sets in the reader (DEBUG only; `LaunchDoors`).
nonisolated struct ReaderDoor: Equatable, Sendable {
    var line: String?
    var part: String?
    var hide = false
    var sheet: String?
    var page: Int?
    var prefs: String?
    var hear = false
    /// APP_READER_STUDIO=1: with APP_READER_PART, press the reader's Record (the studio opens).
    var studio = false
    /// APP_READER_RESET_MARKS=1: the play's marks on this device are erased before the reader opens.
    var resetMarks = false
    /// APP_READER_INK=1: Ink mode is on when the reader opens (iPad); APP_READER_INK_FINGER=1 also lets a finger draw,
    /// since a Pencil cannot be driven by a test.
    var ink = false
    var inkFinger = false
    /// APP_READER_INK_DEMO=1: three synthetic strokes are stored on the lines from the first one shown (a device whose
    /// UI automation is not enabled cannot draw them); they are the same stored ink a Pencil makes.
    var inkDemo = false
}
