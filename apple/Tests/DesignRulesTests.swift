import Foundation
import SwiftUI
import Testing

/// The rules the binding design docs settled on 2026-10-23, held in Core.
/// Broken controls, 2026-10-23, each seen to fail before the fix was kept:
///   PlayerNumbers.speeds with 0.8 first: the Decision 062 test fails.
///   SleepTimer.fadeSeconds back to a literal 20: the fade-default test fails.
///   Haptic.success mapped to .selection: the mapping test fails.
///   SiteLinks.component using .urlPathAllowed: the encodeURIComponent golden fails.
///   AppStore.goBack removing the whole path: the Back test fails.
struct PlayerNumbersTests {
    @Test func numbersAreDecision062s() {
        #expect(PlayerNumbers.sleepFadeSeconds == 10)
        #expect(PlayerNumbers.speeds == [0.75, 1, 1.25, 1.5, 2])
        #expect(PlayerNumbers.saveEverySeconds == 5)
        #expect(PlayerNumbers.interruptionRewindSeconds == 3)
    }

    @Test func playerAndTimerReadTheNumbers() {
        #expect(AudioPlayer.speeds == PlayerNumbers.speeds)
        #expect(SleepTimer().fadeSeconds == PlayerNumbers.sleepFadeSeconds)
        var timer = SleepTimer()
        timer.set(.endOfEpisode, now: Date())
        var before = timer, inside = timer
        #expect(before.tick(now: Date(), remainingInEpisode: PlayerNumbers.sleepFadeSeconds).volume == 1)
        let fading = inside.tick(now: Date(), remainingInEpisode: PlayerNumbers.sleepFadeSeconds - 1).volume
        #expect(fading < 1 && fading > 0)
    }

    @Test func saveIsDueEveryFiveSeconds() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        #expect(!PlayerNumbers.isSaveDue(lastSaved: t0, now: t0.addingTimeInterval(4.9)))
        #expect(PlayerNumbers.isSaveDue(lastSaved: t0, now: t0.addingTimeInterval(5)))
    }
}

struct HapticTests {
    @Test func everyKindMapsToItsSystemFeedback() {
        #expect(Haptic.selection.feedback == .selection)
        #expect(Haptic.light.feedback == .impact(weight: .light))
        #expect(Haptic.medium.feedback == .impact(weight: .medium))
        #expect(Haptic.heavy.feedback == .impact(weight: .heavy))
        #expect(Haptic.success.feedback == .success)
        #expect(Haptic.warning.feedback == .warning)
        #expect(Haptic.error.feedback == .error)
    }

    @Test func downloadsSpeakOnlyWhenARecordChanges() {
        #expect(Haptic.forDownloads(from: [:], to: ["a": .downloaded]) == nil)
        #expect(Haptic.forDownloads(from: ["a": .downloading], to: ["a": .downloaded]) == .success)
        #expect(Haptic.forDownloads(from: ["a": .downloading], to: ["a": .failed]) == .error)
        #expect(Haptic.forDownloads(from: ["a": .downloaded], to: ["a": .downloaded]) == nil)
        #expect(Haptic.forDownloads(from: ["a": .downloaded], to: [:]) == nil)
    }

    @Test func errorOnlyWhenALineAppears() {
        #expect(Haptic.forError(from: nil, to: "This recording would not play.") == .error)
        #expect(Haptic.forError(from: "x", to: "y") == nil)
        #expect(Haptic.forError(from: "x", to: nil) == nil)
    }
}

struct SiteLinksTests {
    /// Golden from node: encodeURIComponent("lux-radio|1943-05-25 Café & 'x'(1)!~*/?#").
    @Test func componentMatchesEncodeURIComponent() {
        #expect(SiteLinks.component("lux-radio|1943-05-25 Café & 'x'(1)!~*/?#")
                == "lux-radio%7C1943-05-25%20Caf%C3%A9%20%26%20'x'(1)!~*%2F%3F%23")
    }

    @Test func episodeShareIsTheHttpsTwin() {
        #expect(SiteLinks.episode("lux-radio|1943-05-25").absoluteString
                == "https://eardrama.org/episode/lux-radio%7C1943-05-25")
        #expect(SiteLinks.series("lux-radio").absoluteString == "https://eardrama.org/series/lux-radio")
    }
}

struct AppStoreNavigationTests {
    @Test func backPopsOneScreenAndStopsAtTheRoot() {
        let store = AppStore()
        store.selectedTab = .series
        #expect(!store.canGoBack)
        store.push(Route.series("a"))
        store.push(Route.episode("a|1"))
        store.goBack()
        #expect(store.paths[.series]?.count == 1)
        store.goBack()
        #expect(!store.canGoBack)
        store.goBack()
        #expect(store.paths[.series]?.count == 0)
    }

    @Test func searchOpensTheSectionAndAsksForFocus() {
        let store = AppStore()
        store.openSearch()
        #expect(store.selectedTab == .search)
        #expect(store.wantsSearchFocus)
    }
}
