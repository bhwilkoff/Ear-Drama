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
/// - APP_MINI_PLAYER=1: with APP_AUTOPLAY, the item plays under the screen: its page is not pushed and the player
///   stays closed, for frames of the mini player
/// - APP_SLEEP_MENU=1: open the sleep timer's choices on the player
/// - APP_MUTE=1 (or the `-APP_MUTE` launch argument): the player is muted
/// - APP_FORCE_OFFLINE=1: the offline state, for a screenshot (fakes the
///   state, never the network)
/// - APP_READER_RESET_MARKS=1: erases the opened play's marks first (R2-marks-port-brief frames).
/// - APP_RESET_USER_STATE=1: the listening history, queue and followed shows are set aside before the
///   stores open, so a UI test starts from a new listener's lists, not an earlier run's (the tap tier
///   sets it on every launch); the next launch without it puts the person's own lists back
/// - APP_RESET_PRODUCTIONS=1: this device's productions (Record, Yours) are deleted before the stores open
///   (the App Review recording starts from none)
/// - APP_UITEST_SESSION=1: a UI test's launch (every one); the set-aside lists wait for a launch without it.
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
///   APP_PICKER=role:NAME opens that part's voice picker, APP_READER_ALONG=1 then opens its Read Along (iOS),
///   APP_READER_HEAR=1 starts Hear the Cast in the reader
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
/// - APP_START_PLAY=<script id>: open that play's own page on Record (iOS and macOS). It only opens the page: no
///   production is made (APP_PRODUCTION makes one)
/// - APP_LIBRARY_SIDE=making | listening: Library drawn on that side; the side the person last chose is not written
/// - APP_LANDSCAPE=1 (iOS): asks the scene for landscape, for frames of a phone nobody can turn (ScrollDoor_iOS)
///
/// - APP_SCRATCH=1: the person's own scripts and productions are set aside whole: both are read and written in a
///   scratch folder, emptied at each launch (APP_SCRATCH=keep leaves what the last one made, for a relaunch inside a
///   test), and nothing of the owner's is read or changed. The own-script doors below always set it
/// - APP_START_OWN=add | parts | script (iOS and macOS, §4.21): Add a Script, the parts page, or an own script's page,
///   over APP_OWN_FROM=<script id>'s own words (a library or bundled play as text; the first bundled one without it).
///   `keep` adds what the first Done makes: APP_OWN_LINE=<n> goes to the nth line, APP_OWN_SHEET=1 opens its controls
/// - APP_START_CAST=<episode id> (iOS and macOS, §4.22): casting that episode by ear; APP_CAST_STEPS drives it for a
///   frame (EarDoorSteps). Use with APP_MUTE=1
///
/// - APP_SKIP_ONBOARD=1: no Better Voices step at launch or at first use (every UI test sets it; PLAYS-DESIGN §2.8
///   rule 13). APP_VOICES_STEP=1 shows the step at launch without reading or writing its record (iOS and macOS)
///
/// - APP_DOOR_FILE (Mac): commands read from a file while the app runs (DoorFile_macOS)
///
/// - APP_PLAY_QUERY=<words> (iOS and macOS): Record's search field holds those words (B31 §3.3);
///   APP_PLAY_PICKS=form=comedy,voices=1-2 chooses those facet values (B31 §3.1)
/// - APP_BROWSE_SCOPE=plays (tvOS): Browse opens on that scope (B31 §3.7)
///
/// DEBUG-only: in a Release build `current` is always empty, so every door is a
/// no-op in production. Doors never touch the router directly; they are posted
/// to the AppStore inbox and consumed by RootView like any other deep link.
struct LaunchDoors: Sendable, Equatable {
    var startTab: String?
    var startItem: String?
    var autoplay = false
    var miniPlayer = false
    var sleepMenu = false
    var mute = false
    var doorSeconds: Int?
    var forceOffline = false
    var emptyLibrary = false
    var resetUserState = false
    var uitestSession = false
    var resetProductions = false
    var reader: String?
    var readerDoor = ReaderDoor()
    var production: String?
    var play: String?
    var librarySide: String?
    var landscape = false
    var picker: String?
    var along: String?
    var readRoom: String?
    var readSeat: String?
    var readScreen = false
    var readPart: String?
    var readRecord = false
    var scratch: String?
    var own: String?
    var ownFrom: String?
    var ownLine: Int?
    var ownSheet = false
    var cast: String?
    var castSteps: String?
    var skipOnboard = false
    var voicesStep = false
    var playQuery: String?
    var playPicks: [String: String] = [:]
    var browseScope: String?

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
            miniPlayer: environment["APP_MINI_PLAYER"] == "1",
            sleepMenu: environment["APP_SLEEP_MENU"] == "1",
            mute: environment["APP_MUTE"] == "1" || arguments.contains("-APP_MUTE"),
            doorSeconds: environment["APP_DOOR_SECONDS"].flatMap { Int($0) },
            forceOffline: environment["APP_FORCE_OFFLINE"] == "1",
            emptyLibrary: environment["APP_EMPTY_LIBRARY"] == "1",
            resetUserState: environment["APP_RESET_USER_STATE"] == "1",
            uitestSession: environment["APP_UITEST_SESSION"] == "1",
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
            play: environment["APP_START_PLAY"].flatMap { $0.isEmpty ? nil : $0 },
            librarySide: environment["APP_LIBRARY_SIDE"].flatMap { ["making", "listening"].contains($0) ? $0 : nil },
            landscape: environment["APP_LANDSCAPE"] == "1",
            picker: environment["APP_PICKER"],
            along: environment["APP_START_ALONG"].flatMap { $0.isEmpty ? nil : $0 },
            readRoom: environment["APP_START_READ_ROOM"].flatMap { $0.isEmpty ? nil : $0 },
            readSeat: environment["APP_START_SEAT"].flatMap { $0.isEmpty ? nil : $0 },
            readScreen: environment["APP_START_SCREEN"] == "1",
            readPart: environment["APP_START_READ_PART"].flatMap { $0.isEmpty ? nil : $0 },
            readRecord: environment["APP_START_READ_RECORD"] == "1",
            scratch: Self.scratch(environment),
            own: environment["APP_START_OWN"].flatMap { ["add", "parts", "script"].contains($0) ? $0 : nil },
            ownFrom: environment["APP_OWN_FROM"].flatMap { $0.isEmpty ? nil : $0 },
            ownLine: environment["APP_OWN_LINE"].flatMap { Int($0) },
            ownSheet: environment["APP_OWN_SHEET"] == "1",
            cast: environment["APP_START_CAST"].flatMap { $0.isEmpty ? nil : $0 },
            castSteps: environment["APP_CAST_STEPS"],
            skipOnboard: environment["APP_SKIP_ONBOARD"] == "1",
            voicesStep: environment["APP_VOICES_STEP"] == "1",
            playQuery: environment["APP_PLAY_QUERY"].flatMap { $0.isEmpty ? nil : $0 },
            playPicks: Self.picks(environment["APP_PLAY_PICKS"]),
            browseScope: environment["APP_BROWSE_SCOPE"].flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    /// "form=comedy,voices=1-2" as facet picks.
    static func picks(_ text: String?) -> [String: String] {
        var out: [String: String] = [:]
        for pair in (text ?? "").split(separator: ",") {
            let kv = pair.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if kv.count == 2, !kv[0].isEmpty, !kv[1].isEmpty { out[kv[0]] = kv[1] }
        }
        return out
    }

    private static func scratch(_ environment: [String: String]) -> String? {
        if let asked = environment["APP_SCRATCH"], ["1", "keep"].contains(asked) { return asked }
        return environment["APP_START_OWN"] != nil || environment["APP_START_CAST"] != nil ? "1" : nil
    }

    /// Where this launch keeps own scripts and productions when the person's are set aside; nil for their own.
    static let scratchRoot: URL? = {
        guard let scratch = current.scratch else { return nil }
        let root = URL.temporaryDirectory.appending(path: "EarDramaScratch", directoryHint: .isDirectory)
        if scratch != "keep" { try? FileManager.default.removeItem(at: root) }
        return root
    }()

    /// The keys of the lists a person builds by listening, on this device.
    static let userStatePrefixes = ["listeningHistory.", "listeningQueue.", "followedSeries."]

    /// Where the reset door sets a person's own lists aside. Test devices are also the owner's phones: on
    /// 2026-11-23 this door erased the owner's history, queue and follows on two of them.
    static let setAsidePrefix = "launchDoors.setAside."
    static let setAsideTaken = "launchDoors.setAside.taken"

    /// Clears those lists from `defaults` when the door is open, setting the first copy aside rather than
    /// erasing it (later test launches never overwrite it). Called before any store is made.
    @discardableResult
    static func resetUserStateIfAsked(_ doors: LaunchDoors = .current, defaults: UserDefaults = .standard) -> Bool {
        guard doors.resetUserState else { return false }
        let first = !defaults.bool(forKey: setAsideTaken)
        for (key, value) in defaults.dictionaryRepresentation() where userStatePrefixes.contains(where: key.hasPrefix) {
            if first { defaults.set(value, forKey: setAsidePrefix + key) }
            defaults.removeObject(forKey: key)
        }
        defaults.set(true, forKey: setAsideTaken)
        return true
    }

    /// The first launch outside a UI test puts the set-aside lists back and drops what the tests left. A test's
    /// own relaunch (APP_UITEST_SESSION, set on every test launch) keeps the test's lists, since tests check that
    /// a follow or a queue survives a relaunch. Runs in every build, so a Release build installed over a test run
    /// restores them too.
    @discardableResult
    static func restoreUserStateIfSetAside(_ doors: LaunchDoors = .current, defaults: UserDefaults = .standard) -> Bool {
        guard !doors.resetUserState, !doors.uitestSession, defaults.bool(forKey: setAsideTaken) else { return false }
        let all = defaults.dictionaryRepresentation()
        for key in all.keys where userStatePrefixes.contains(where: key.hasPrefix) { defaults.removeObject(forKey: key) }
        for (key, value) in all where key.hasPrefix(setAsidePrefix) && key != setAsideTaken {
            defaults.set(value, forKey: String(key.dropFirst(setAsidePrefix.count)))
            defaults.removeObject(forKey: key)
        }
        defaults.removeObject(forKey: setAsideTaken)
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
