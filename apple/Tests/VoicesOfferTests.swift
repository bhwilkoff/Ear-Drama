import Foundation
import Testing

/// PLAYS-DESIGN §2.8 rule 13: the Better Voices step at first launch, once more at the first read, never after.
@Suite struct VoicesOfferTests {
    private func fresh() -> UserDefaults {
        let name = "voices-offer-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func firstLaunchShowsOnce() {
        let offer = VoicesOffer(defaults: fresh())
        #expect(offer.atLaunch(eligible: true))
        #expect(!offer.atLaunch(eligible: true))
        #expect(offer.stage == 1)
    }

    @Test func skipIsRememberedThenOfferedOnceAtFirstRead() {
        let d = fresh()
        #expect(VoicesOffer(defaults: d).atLaunch(eligible: true))
        // A new launch: the skip is kept, no step at launch.
        let next = VoicesOffer(defaults: d)
        #expect(!next.atLaunch(eligible: true))
        #expect(next.atFirstUse(eligible: true))
        #expect(!next.atFirstUse(eligible: true))
        #expect(!VoicesOffer(defaults: d).atLaunch(eligible: true))
        #expect(next.stage == 2)
    }

    @Test func neverAfterADownload() {
        let d = fresh()
        let offer = VoicesOffer(defaults: d)
        offer.downloadBegan()
        #expect(!offer.atLaunch(eligible: true))
        #expect(!offer.atFirstUse(eligible: true))
    }

    @Test func downloadFromTheLaunchStepEndsTheOffers() {
        let offer = VoicesOffer(defaults: fresh())
        #expect(offer.atLaunch(eligible: true))
        offer.downloadBegan()
        #expect(!offer.atFirstUse(eligible: true))
    }

    @Test func nothingToOfferMeansNoStepAndNoRecord() {
        let offer = VoicesOffer(defaults: fresh())
        #expect(!offer.atLaunch(eligible: false))
        #expect(offer.stage == 0)
        // Offered at the first read if the device can run them by then.
        #expect(!offer.atFirstUse(eligible: false))
        #expect(offer.stage == 0)
        #expect(offer.atFirstUse(eligible: true))
    }

    @Test func forcedDoorShowsWithoutReadingOrWriting() {
        let d = fresh()
        d.set(2, forKey: VoicesOffer.key)
        let forced = VoicesOffer(defaults: d, forced: true)
        #expect(forced.atLaunch(eligible: true))
        #expect(forced.atLaunch(eligible: true))
        #expect(!forced.atFirstUse(eligible: true))
        forced.downloadBegan()
        #expect(d.integer(forKey: VoicesOffer.key) == 2)
        let empty = fresh()
        let door = VoicesOffer(defaults: empty, forced: true)
        #expect(door.atLaunch(eligible: true))
        door.downloadBegan()
        #expect(empty.object(forKey: VoicesOffer.key) == nil)
    }

    @Test func skipDoorKeepsItAwayAndWritesNothing() {
        let d = fresh()
        let skip = VoicesOffer(defaults: d, skip: true)
        #expect(!skip.atLaunch(eligible: true))
        #expect(!skip.atFirstUse(eligible: true))
        #expect(d.object(forKey: VoicesOffer.key) == nil)
    }

    @Test func launchDoorsParseTheTwoDoors() {
        let doors = LaunchDoors.from(environment: ["APP_SKIP_ONBOARD": "1", "APP_VOICES_STEP": "1"], arguments: [])
        #expect(doors.skipOnboard)
        #expect(doors.voicesStep)
        #expect(!LaunchDoors.from(environment: [:], arguments: []).voicesStep)
    }

    @Test func lowStorageRefusesUnderSizePlusAFifth() {
        #expect(VoicesSpace.short(free: 200_000_000, size: 184_759_454))
        #expect(!VoicesSpace.short(free: 250_000_000, size: 184_759_454))
        #expect(!VoicesSpace.short(free: nil, size: 184_759_454))
        #expect(VoicesSpace.warning(free: 310_000_000) == "Not enough space: 310 MB free.")
    }
}
