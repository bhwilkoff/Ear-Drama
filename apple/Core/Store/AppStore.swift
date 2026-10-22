import SwiftUI

/// Global app state — injected via @Environment(AppStore.self).
/// Uses @Observable (iOS 17+) for automatic SwiftUI updates.
@Observable
final class AppStore {
    var navigationPath = NavigationPath()
    var selectedTab: String? = "home"

    /// Player-level mute. A door launch sets it (APP_MUTE); every player reads
    /// it, so a harness run on someone's TV is silent unless it opts in.
    var isMuted = false

    /// The intent inbox: deep links, widget/Top Shelf URLs, intents, and test
    /// doors are POSTED here and consumed by RootView once foregrounded —
    /// external entry points never mutate the router directly.
    private(set) var inbox: [InboxRequest] = []

    enum InboxRequest: Hashable, Sendable {
        case tab(String)
        case item(String)
    }

    func post(_ request: InboxRequest) { inbox.append(request) }

    /// Called by the root view only.
    func drainInbox() {
        let pending = inbox
        inbox.removeAll()
        for request in pending {
            switch request {
            case .tab(let tab):
                selectedTab = tab
                navigationPath = NavigationPath()
            case .item(let id):
                // FILL IN: map the id to your item route type.
                navigationPath.append(id)
            }
        }
    }

    @ObservationIgnored private var doorsOpened = false

    /// Posts the launch doors once per process (a second macOS window must not
    /// re-open them). Returns false when they were already opened.
    func openDoorsOnce(_ doors: LaunchDoors) -> Bool {
        guard !doorsOpened else { return false }
        doorsOpened = true
        if doors.mute { isMuted = true }
        if let tab = doors.startTab { post(.tab(tab)) }
        if let item = doors.startItem { post(.item(item)) }
        return true
    }

    /// APP_DOOR_SECONDS elapsed: end the door's activity on the app's own
    /// clock (stop playback, leave the room) so a crashed harness cannot leave
    /// it running. FILL IN: stop your player / leave any session here too.
    func endDoor() {
        navigationPath = NavigationPath()
    }

    // FILL IN: Add app-wide state here
    // Examples:
    // var unreadCount = 0
    // var currentUserAvatar: String?
}
