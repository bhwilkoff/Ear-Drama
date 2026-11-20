import Foundation

/// Test "doors": launch env vars that open a screen directly, so a harness
/// (`simctl launch`, `devicectl ... --environment-variables`, a Mac exec) can
/// reach any surface without pressing blind. Names match tools/app_config.py
/// (HOOK_START_TAB, HOOK_START_ITEM, HOOK_AUTOPLAY, HOOK_MUTE,
/// HOOK_DOOR_SECONDS, HOOK_SLEEP_MENU).
///
/// - APP_START_TAB: home | browse | record | search | library (Decision 075); stations and
///   surprise open Home and then push that screen; the older listen | series | radio | plays
///   still open (plays is Record). The TV has no Record: it opens Home.
/// - APP_START_ITEM: a series key or an episode id, pushed on that tab
/// - APP_AUTOPLAY=1: play APP_START_ITEM and show the player
/// - APP_SLEEP_MENU=1: open the sleep timer's choices on the player
/// - APP_MUTE=1 (or the `-APP_MUTE` launch argument): the player is muted
/// - APP_FORCE_OFFLINE=1: the offline state, for a screenshot (fakes the
///   state, never the network)
/// - APP_READER_RESET_MARKS=1: erases the opened play's marks first (R2-marks-port-brief frames).
/// - APP_RESET_USER_STATE=1: the listening history, queue and followed shows are erased before the
///   stores open, so a UI test starts from a new listener's lists, not an earlier run's (the tap tier
///   sets it on every launch)
/// - APP_RESET_PRODUCTIONS=1: this device's productions (Record, Yours) are deleted before the stores open
///   (the App Review recording starts from none)
/// - APP_EMPTY_LIBRARY=1: Library drawn as a new listener's, for its empty
///   state (fakes the lists, never clears them)
///
/// - APP_READER=<script id>: open the script reader on that play (iOS and macOS); APP_READER_LINE a line id to open at,
///   APP_READER_PART a part ("role:HAMLET") to play, APP_READER_HIDE=1 to hide its lines, APP_READER_SHEET
///   contents | search | text, APP_READER_PAGE a page to turn to, APP_READER_PREFS the settings as JSON,
///   APP_READER_STUDIO=1 presses Record (the studio, PLAYS-DESIGN §2.9); APP_STUDIO_STUB=1 records and plays nothing
///   (no microphone) and APP_STUDIO_PHASE=listening | takes shows a take recording or the take list (StudioDoor)
///
/// - APP_PRODUCTION=<script id>: open a production's cast sheet on that play (made if none exists; iOS and macOS);
///   APP_PICKER=role:NAME opens that part's voice picker, APP_READER_HEAR=1 starts Hear the Cast in the reader
///
/// - APP_SCENE=try | hear: presses Today's Scene's Try a Line or Hear It once (iOS and macOS; read by `SceneDoor`)
///
/// - APP_START_ALONG=<production id>: open that finished ear drama's page and press Listen, so its read-along panel
///   follows the files (the Apple TV's panel; muted with APP_MUTE=1). `rehearsal` or `rehearsal:<script id>` needs no
///   finished drama (none is published yet): the page opens over a bundled script and the panel steps through its
///   lines on a timer, playing nothing (DEBUG, tvOS)
///
/// - APP_START_READ_ROOM=<CODE>: open that read room (Decision 082; the `eardrama://read/CODE` twin). APP_START_SEAT=
///   <class code>:<seat id or label> takes that seat of a class room first (a debug stand-in for picking a name);
///   APP_START_SCREEN=1 opens the room as the shared screen (the Apple TV's only mode). APP_READ_DIAG=1 prints the
///   transport, the cursor delay and the clock offset, and `rec <line>` for each line this device opens its microphone on.
///   APP_START_READ_PART=<role name or role:NAME> claims that part once the reader is in the room, and APP_START_READ_RECORD=1
///   then arms Record (use APP_STUDIO_STUB=1: no microphone, nothing heard)
///
/// - APP_SCROLL_Y=<points> (iOS): scrolls the page on screen that far down APP_SCROLL_DELAY seconds after launch
///   (default 6), for frames of the open iPhone Duo below the first screen (ScrollDoor_iOS)
///
/// - APP_DOOR_FILE (Mac): commands read from a file while the app runs (DoorFile_macOS)
///
/// DEBUG-only: in a Release build `current` is always empty, so every door is a
/// no-op in production. Doors never touch the router directly; they are posted
/// to the AppStore inbox and consumed by RootView like any other deep link.
struct LaunchDoors: Sendable, Equatable {
    var startTab: String?
    var startItem: String?
    var autoplay = false
    var sleepMenu = false
    var mute = false
    var doorSeconds: Int?
    var forceOffline = false
    var emptyLibrary = false
    var resetUserState = false
    var resetProductions = false
    var reader: String?
    var readerDoor = ReaderDoor()
    var production: String?
    var picker: String?
    var along: String?
    var readRoom: String?
    var readSeat: String?
    var readScreen = false
    var readPart: String?
    var readRecord = false

    var isEmpty: Bool { self == LaunchDoors() }

    static let current: LaunchDoors = {
        #if DEBUG
        return from(environment: ProcessInfo.processInfo.environment,
                    arguments: ProcessInfo.processInfo.arguments)
        #else
        return LaunchDoors()
        #endif
    }()

    static func from(environment: [String: String], arguments: [String]) -> LaunchDoors {
        LaunchDoors(
            startTab: environment["APP_START_TAB"],
            startItem: environment["APP_START_ITEM"],
            autoplay: environment["APP_AUTOPLAY"] == "1",
            sleepMenu: environment["APP_SLEEP_MENU"] == "1",
            mute: environment["APP_MUTE"] == "1" || arguments.contains("-APP_MUTE"),
            doorSeconds: environment["APP_DOOR_SECONDS"].flatMap { Int($0) },
            forceOffline: environment["APP_FORCE_OFFLINE"] == "1",
            emptyLibrary: environment["APP_EMPTY_LIBRARY"] == "1",
            resetUserState: environment["APP_RESET_USER_STATE"] == "1",
            resetProductions: environment["APP_RESET_PRODUCTIONS"] == "1",
            reader: environment["APP_READER"],
            readerDoor: ReaderDoor(line: environment["APP_READER_LINE"], part: environment["APP_READER_PART"],
                                   hide: environment["APP_READER_HIDE"] == "1", sheet: environment["APP_READER_SHEET"],
                                   page: environment["APP_READER_PAGE"].flatMap { Int($0) },
                                   prefs: environment["APP_READER_PREFS"],
                                   hear: environment["APP_READER_HEAR"] == "1",
                                   studio: environment["APP_READER_STUDIO"] == "1",
                                   resetMarks: environment["APP_READER_RESET_MARKS"] == "1",
                                   ink: environment["APP_READER_INK"] == "1",
                                   inkFinger: environment["APP_READER_INK_FINGER"] == "1",
                                   inkDemo: environment["APP_READER_INK_DEMO"] == "1"),
            production: environment["APP_PRODUCTION"],
            picker: environment["APP_PICKER"],
            along: environment["APP_START_ALONG"].flatMap { $0.isEmpty ? nil : $0 },
            readRoom: environment["APP_START_READ_ROOM"].flatMap { $0.isEmpty ? nil : $0 },
            readSeat: environment["APP_START_SEAT"].flatMap { $0.isEmpty ? nil : $0 },
            readScreen: environment["APP_START_SCREEN"] == "1",
            readPart: environment["APP_START_READ_PART"].flatMap { $0.isEmpty ? nil : $0 },
            readRecord: environment["APP_START_READ_RECORD"] == "1"
        )
    }

    /// The keys of the lists a person builds by listening, on this device.
    static let userStatePrefixes = ["listeningHistory.", "listeningQueue.", "followedSeries."]

    /// Erases those lists from `defaults` when the door is open. Called before any store is made.
    @discardableResult
    static func resetUserStateIfAsked(_ doors: LaunchDoors = .current, defaults: UserDefaults = .standard) -> Bool {
        guard doors.resetUserState else { return false }
        for key in defaults.dictionaryRepresentation().keys where userStatePrefixes.contains(where: key.hasPrefix) {
            defaults.removeObject(forKey: key)
        }
        return true
    }

    #if os(iOS) || os(macOS)
    @discardableResult
    static func resetProductionsIfAsked(_ doors: LaunchDoors = .current) -> Bool {
        guard doors.resetProductions else { return false }
        try? FileManager.default.removeItem(at: ProductionStore.defaultRoot)
        return true
    }
    #endif
}
