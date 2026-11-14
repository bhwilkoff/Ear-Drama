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
/// - APP_RESET_USER_STATE=1: the listening history, queue and followed shows are erased before the
///   stores open, so a UI test starts from a new listener's lists, not an earlier run's (the tap tier
///   sets it on every launch)
/// - APP_EMPTY_LIBRARY=1: Library drawn as a new listener's, for its empty
///   state (fakes the lists, never clears them)
///
/// - APP_READER=<script id>: open the script reader on that play (iOS and macOS); APP_READER_LINE a line id to open at,
///   APP_READER_PART a part ("role:HAMLET") to play, APP_READER_HIDE=1 to hide its lines, APP_READER_SHEET
///   contents | search | text, APP_READER_PAGE a page to turn to, APP_READER_PREFS the settings as JSON
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
    var reader: String?
    var readerDoor = ReaderDoor()

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
            reader: environment["APP_READER"],
            readerDoor: ReaderDoor(line: environment["APP_READER_LINE"], part: environment["APP_READER_PART"],
                                   hide: environment["APP_READER_HIDE"] == "1", sheet: environment["APP_READER_SHEET"],
                                   page: environment["APP_READER_PAGE"].flatMap { Int($0) },
                                   prefs: environment["APP_READER_PREFS"])
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
}
