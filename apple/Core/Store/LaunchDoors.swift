import Foundation

/// Test "doors": launch env vars that open a screen directly, so a harness
/// (`simctl launch`, `devicectl ... --environment-variables`, a Mac exec) can
/// reach any surface without pressing blind. Names match tools/app_config.py
/// (HOOK_START_TAB, HOOK_START_ITEM, HOOK_AUTOPLAY, HOOK_MUTE,
/// HOOK_DOOR_SECONDS, HOOK_SLEEP_MENU).
///
/// - APP_START_TAB: home | browse | stations | surprise | search | library (the
///   names before Decision 068, listen | series | radio | plays, still open)
/// - APP_START_ITEM: a series key or an episode id, pushed on that tab
/// - APP_AUTOPLAY=1: play APP_START_ITEM and show the player
/// - APP_SLEEP_MENU=1: open the sleep timer's choices on the player
/// - APP_MUTE=1 (or the `-APP_MUTE` launch argument): the player is muted
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

    var isEmpty: Bool { self == LaunchDoors() }

    static let current: LaunchDoors = {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        let arguments = ProcessInfo.processInfo.arguments
        return LaunchDoors(
            startTab: environment["APP_START_TAB"],
            startItem: environment["APP_START_ITEM"],
            autoplay: environment["APP_AUTOPLAY"] == "1",
            sleepMenu: environment["APP_SLEEP_MENU"] == "1",
            mute: environment["APP_MUTE"] == "1" || arguments.contains("-APP_MUTE"),
            doorSeconds: environment["APP_DOOR_SECONDS"].flatMap { Int($0) }
        )
        #else
        return LaunchDoors()
        #endif
    }()
}
