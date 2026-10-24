import Foundation
import Testing

/// Decision 067: a following member's Play and Pause are their own hold,
/// handed to the room (SharePlayRoom catches them up on release); skip and
/// seek stay the host's.
@MainActor
struct GuestHoldTests {
    private func player() -> AudioPlayer {
        let defaults = UserDefaults(suiteName: "GuestHoldTests-\(UUID().uuidString)")!
        return AudioPlayer(history: ListeningHistory(defaults: defaults))
    }

    @Test func aFollowersPauseAndPlayAreTheirOwnHold() {
        let p = player()
        var told: [Bool] = []
        p.onGuestHold = { told.append($0) }
        p.setFollowing(true)
        p.pause()
        #expect(p.isHeld)
        p.togglePlayPause()
        #expect(!p.isHeld)
        p.togglePlayPause()
        p.resume()
        #expect(told == [true, false, true, false], "pause and toggle hold; toggle and play release")
        p.seek(to: 500)
        #expect(p.elapsed == 0, "seek is still the host's")
    }

    @Test func leavingTheRoomEndsAHold() {
        let p = player()
        var told: [Bool] = []
        p.onGuestHold = { told.append($0) }
        p.setFollowing(true)
        p.pause()
        p.setFollowing(false)
        #expect(!p.isHeld)
        p.pause()
        #expect(told == [true], "control: out of a room, pause is the player's own")
    }
}
