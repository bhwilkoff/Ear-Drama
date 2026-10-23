import Foundation
import Testing

/// Tonight in 19xx (contract §8; WEB-DESIGN §4.9; R9, R10, R14): the one
/// clock, the listener's own date, gaps that never play, and listening live.
struct RadioTests {
    /// ICU writes a narrow no-break space before "PM".
    private static func plain(_ s: String) -> String { s.replacingOccurrences(of: "\u{202F}", with: " ") }

    private static func t(_ iso: String) -> Date { try! Date(iso, strategy: .iso8601) }

    private static func slot(_ start: String, _ end: String, episode: String? = nil, length: Double? = nil,
                             gap: Bool = false, withheld: Bool = false) -> RadioSlot {
        RadioSlot(etStart: "19:00", etEnd: "19:30", lengthMin: Int(t(end).timeIntervalSince(t(start)) / 60),
                  utcStart: t(start), utcEnd: t(end),
                  episode: episode.map { .init(id: $0, series: "Series", title: nil, lengthS: length) },
                  gap: gap || episode == nil, withheld: withheld)
    }

    /// js/api.test.js "onAir reads the one clock from the published instants".
    private static let golden = [
        slot("2026-10-22T23:00:00Z", "2026-10-22T23:30:00Z"),
        slot("2026-10-22T23:30:00Z", "2026-10-23T00:00:00Z"),
        slot("2026-10-23T00:00:00Z", "2026-10-23T00:30:00Z"),
    ]

    // MARK: - onAir, golden against the web

    @Test func onAirMatchesTheWebsCases() {
        let at = { (iso: String) in RadioClock.onAir(Self.golden, at: Self.t(iso)) }
        #expect(at("2026-10-22T22:59:59Z") == .init(phase: .before, index: nil))
        #expect(at("2026-10-22T23:00:00Z") == .init(phase: .during, index: 0))
        #expect(at("2026-10-22T23:45:00Z") == .init(phase: .during, index: 1))
        #expect(at("2026-10-23T00:29:59Z") == .init(phase: .during, index: 2))
        #expect(at("2026-10-23T00:30:00Z") == .init(phase: .after, index: nil))
        #expect(RadioClock.onAir([], at: Date()) == .init(phase: .after, index: nil))
    }

    @Test func aSlotBoundaryBelongsToTheSlotThatStarts() {
        let at = { (iso: String) in RadioClock.onAir(Self.golden, at: Self.t(iso)) }
        #expect(at("2026-10-22T23:29:59Z").index == 0)
        #expect(at("2026-10-22T23:30:00Z").index == 1)
        #expect(at("2026-10-23T00:00:00Z").index == 2)
    }

    // MARK: - The listener's own date

    @Test func localDateIsTheDevicesOwnDateNotUTC() {
        var denver = Calendar(identifier: .gregorian)
        denver.timeZone = TimeZone(identifier: "America/Denver")!
        // 03:30 UTC on the 23rd is 9:30 PM on the 22nd in Denver.
        #expect(RadioClock.localDate(Self.t("2026-10-23T03:30:00Z"), calendar: denver) == "2026-10-22")
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        #expect(RadioClock.localDate(Self.t("2026-10-22T20:00:00Z"), calendar: tokyo) == "2026-10-23")
        // control: padding
        #expect(RadioClock.localDate(Self.t("2026-01-05T12:05:00Z"), calendar: denver) == "2026-01-05")
    }

    // MARK: - The file

    private static let file = Data("""
    {"schemaVersion": 1, "zone": "America/New_York", "floor": 0.25, "days": {
      "2026-10-22": {"evening": "1942-10-22", "picked": "anniversary", "network": "CBS", "station": "WJSV",
        "coverage": 0.3, "witness": {"paper": "Washington Post", "url": "https://example.org/log.pdf",
          "via": "JJ's Newspaper Radio Logs (jjonz.us)"},
        "slots": [
          {"et_start": "19:00", "et_end": "19:15", "length_min": 15, "printed": "Amos W Andy", "gap": true,
           "known_series": "Amos 'n' Andy", "utc_start": "2026-10-22T23:00:00Z", "utc_end": "2026-10-22T23:15:00Z"},
          {"et_start": "19:15", "et_end": "19:45", "length_min": 30, "printed": "Suspense",
           "episode": {"id": "suspense|1942-10-22", "series": "Suspense", "title": "The Hitchhiker", "rights": "unclaimed",
                       "length_s": 1770, "match": 0.9},
           "utc_start": "2026-10-22T23:15:00Z", "utc_end": "2026-10-22T23:45:00Z"},
          {"et_start": "19:45", "et_end": "20:00", "length_min": 15, "printed": "Lux", "gap": true, "withheld": true,
           "known_series": "Lux Radio Theatre", "utc_start": "2026-10-22T23:45:00Z", "utc_end": "2026-10-23T00:00:00Z"}
        ]}}}
    """.utf8)

    @Test func theFileDecodesTheContractShape() throws {
        let tonight = try TonightFile.decode(Self.file)
        #expect(tonight.zone == "America/New_York")
        #expect(tonight.day(for: "2026-10-23") == nil)
        let day = try #require(tonight.day(for: "2026-10-22"))
        #expect(day.year == "1942")
        #expect(day.stationLine == "CBS · WJSV")
        #expect(day.witnessLine == "Washington Post, via JJ's Newspaper Radio Logs")
        #expect(day.slots.count == 3)
        #expect(day.slots[0].gap && day.slots[0].knownSeries == "Amos 'n' Andy")
        #expect(day.slots[1].playableEpisode?.id == "suspense|1942-10-22")
        #expect(day.slots[1].playableEpisode?.lengthS == 1770)
        #expect(day.slots[1].utcEnd == Self.t("2026-10-22T23:45:00Z"))
    }

    @Test func withheldAndGapSlotsNeverPlay() throws {
        let day = try #require(try TonightFile.decode(Self.file).day(for: "2026-10-22"))
        #expect(day.slots[0].playableEpisode == nil)
        #expect(day.slots[2].playableEpisode == nil)
        #expect(RadioClock.gapNote(day.slots[0]) == "Not surviving")
        #expect(RadioClock.gapNote(day.slots[2]) == "Not in the catalog")
        // A withheld slot that still names its episode is refused too.
        let named = Self.slot("2026-10-22T23:00:00Z", "2026-10-22T23:30:00Z", episode: "x|1", withheld: true)
        #expect(named.playableEpisode == nil)
        var live = LiveListening(slots: [named], lengths: ["x|1": 1800])
        #expect(live.tick(now: Self.t("2026-10-22T23:05:00Z")) == .none)
    }

    @Test func eachSlotReadsLocalTimeWithEasternBeside() throws {
        let day = try #require(try TonightFile.decode(Self.file).day(for: "2026-10-22"))
        let en = Locale(identifier: "en_US")
        let ny = RadioClock.timeLabel(day.slots[0], zone: "America/New_York",
                                      timeZone: TimeZone(identifier: "America/New_York")!, locale: en)
        #expect(Self.plain(ny.local) == "7:00 PM ET" && ny.eastern == nil)
        let denver = RadioClock.timeLabel(day.slots[0], zone: "America/New_York",
                                          timeZone: TimeZone(identifier: "America/Denver")!, locale: en)
        #expect(Self.plain(denver.local) == "5:00 PM" && denver.eastern.map(Self.plain) == "7:00 PM ET")
    }

    // MARK: - Listening live

    private static let evening = [
        slot("2026-10-22T23:00:00Z", "2026-10-22T23:30:00Z", episode: "a|1"),
        slot("2026-10-22T23:30:00Z", "2026-10-22T23:45:00Z"),
        slot("2026-10-22T23:45:00Z", "2026-10-23T00:15:00Z", episode: "b|1"),
    ]

    @Test func liveOffsetIsWhereTheClockStands() {
        let s = Self.evening[0]
        #expect(RadioClock.liveOffset(s, recordingLength: 1770, at: Self.t("2026-10-22T23:12:30Z")) == 750)
        #expect(RadioClock.liveOffset(s, recordingLength: 1770, at: Self.t("2026-10-22T23:00:00Z")) == 0)
        // The recording ended inside its slot: nothing to join.
        #expect(RadioClock.liveOffset(s, recordingLength: 1500, at: Self.t("2026-10-22T23:26:00Z")) == nil)
        #expect(RadioClock.liveOffset(s, recordingLength: 1500, at: Self.t("2026-10-22T23:24:56Z")) == nil)
        #expect(RadioClock.liveOffset(s, recordingLength: 1500, at: Self.t("2026-10-22T23:24:54Z")) == 1494)
        // No length known: the slot's own minutes.
        #expect(RadioClock.liveOffset(s, recordingLength: nil, at: Self.t("2026-10-22T23:29:00Z")) == 1740)
    }

    @Test func liveJoinsThenWaitsThenPlaysTheNextSurvivingSlotAtItsOwnTime() {
        var live = LiveListening(slots: Self.evening, lengths: ["a|1": 1770, "b|1": 1790])
        #expect(live.tick(now: Self.t("2026-10-22T23:10:00Z")) == .play(episodeID: "a|1", at: 600))
        #expect(live.handle(.loaded("a|1")) == .none)
        #expect(live.tick(now: Self.t("2026-10-22T23:10:01Z")) == .none)
        #expect(live.handle(.ended) == .none)
        // The gap plays nothing.
        #expect(live.tick(now: Self.t("2026-10-22T23:35:00Z")) == .none)
        #expect(live.tick(now: Self.t("2026-10-22T23:45:00Z")) == .play(episodeID: "b|1", at: 0))
    }

    @Test func aRecordingStillPlayingIsNotCutOffByTheNextSlot() {
        var live = LiveListening(slots: Self.evening, lengths: ["a|1": 1770, "b|1": 1790])
        _ = live.tick(now: Self.t("2026-10-22T23:10:00Z"))
        #expect(live.tick(now: Self.t("2026-10-22T23:45:01Z")) == .none)
    }

    @Test func aPauseAnotherEpisodeOrTheSleepTimerEndsListeningLive() {
        for event in [TransportEvent.paused, .loaded("other|1"), .sleepFired, .stopped] {
            var live = LiveListening(slots: Self.evening, lengths: ["a|1": 1770, "b|1": 1790])
            _ = live.tick(now: Self.t("2026-10-22T23:10:00Z"))
            #expect(live.handle(event) == .stop, "\(event)")
            #expect(live.isOver)
            // Nothing plays afterward, even when the next slot's time comes.
            #expect(live.tick(now: Self.t("2026-10-22T23:50:00Z")) == .none, "\(event)")
        }
    }

    @Test func theEveningsEndStopsListeningAndNothingPlaysAfter() {
        var live = LiveListening(slots: Self.evening, lengths: ["a|1": 1770, "b|1": 1790])
        _ = live.tick(now: Self.t("2026-10-22T23:10:00Z"))
        _ = live.handle(.ended)
        _ = live.tick(now: Self.t("2026-10-22T23:45:00Z"))
        _ = live.handle(.ended)
        #expect(live.tick(now: Self.t("2026-10-23T00:15:00Z")) == .stop)
        #expect(live.tick(now: Self.t("2026-10-23T00:30:00Z")) == .none)
        #expect(live.tick(now: Self.t("2026-10-23T23:10:00Z")) == .none)
    }

    @Test func anEpisodeTheCatalogDoesNotHoldNeverPlays() {
        var live = LiveListening(slots: Self.evening, lengths: ["b|1": 1790])
        #expect(live.tick(now: Self.t("2026-10-22T23:10:00Z")) == .none)
        #expect(live.tick(now: Self.t("2026-10-22T23:50:00Z")) == .play(episodeID: "b|1", at: 300))
    }
}
