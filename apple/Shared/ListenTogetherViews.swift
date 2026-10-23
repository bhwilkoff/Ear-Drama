import GroupActivities
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Listen Together's one control on the player (iOS-DESIGN §5.8): SharePlay
/// with the system's own sheet and call, and Leave once a room is live. The
/// TV cannot place a call, so it shows the control only inside one.
struct ListenTogetherButton: View {
    @Environment(SharePlayRoom.self) private var room
    @Environment(AudioPlayer.self) private var player

    var body: some View {
        if room.isActive {
            Menu {
                Button("Leave SharePlay", systemImage: "xmark") { room.leave() }
            } label: {
                Label("SharePlay", systemImage: "shareplay")
            }
            .accessibilityLabel("SharePlay")
            .accessibilityValue("\(room.memberCount) listening")
        } else if canStart {
            Button {
                Task { await ListenTogetherStarter.start(room) }
            } label: {
                Label("SharePlay", systemImage: "shareplay")
            }
            .disabled(player.item == nil)
            .accessibilityLabel("SharePlay")
            .help("SharePlay")
        }
    }

    private var canStart: Bool {
        #if os(tvOS)
        room.isEligible
        #else
        true
        #endif
    }
}

/// The refusal a following member sees where the controls went quiet.
struct FollowingHostNotice: View {
    @Environment(AudioPlayer.self) private var player

    var body: some View {
        if player.isFollowing {
            Label("The host has the controls.", systemImage: "shareplay")
                .font(TypeRamp.caption)
                .foregroundStyle(Color.brandTextMuted)
        }
    }
}

/// Starts SharePlay: directly in a live call, otherwise through the system's
/// sharing sheet, which picks people and places the call. Never plays alone.
enum ListenTogetherStarter {
    static func start(_ room: SharePlayRoom) async {
        guard await room.share() == .needsCall else { return }
        #if os(iOS)
        guard let activity = room.activityForSheet() else { return }
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard var top = scene?.keyWindow?.rootViewController,
              let controller = try? GroupActivitySharingController(activity) else {
            room.sheetDidNotShare()
            return
        }
        while let presented = top.presentedViewController { top = presented }
        top.present(controller, animated: true)
        #elseif os(macOS)
        guard let activity = room.activityForSheet() else { return }
        guard let host = NSApp.keyWindow?.contentViewController,
              let controller = try? GroupActivitySharingController(activity) else {
            room.sheetDidNotShare()
            return
        }
        host.presentAsSheet(controller)
        if await controller.result != .success { room.sheetDidNotShare() }
        #endif
    }
}
