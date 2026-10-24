import Foundation
import Testing

/// Genre stations (contract §8, R10, Decision 068): the published schedule
/// decodes, and the client only looks up what is on now and where in it.
/// The cases are js/api.test.js "onNow" and Android's StationsTest.
struct StationsTests {
    private static func t(_ iso: String) -> Date { try! Date(iso, strategy: .iso8601) }

    private static let file = Data("""
    {"schemaVersion": 1, "generatedAt": "2026-10-24T18:20:00Z", "stations": [
      {"genre": "mystery", "name": "Mystery", "slots": [
        {"utc_start": "2026-10-24T18:00:00Z", "utc_end": "2026-10-24T18:29:51Z", "length_s": 1791,
         "episode": {"id": "suspense|1947-10-16", "series": "Suspense", "title": "Self Defense"}},
        {"utc_start": "2026-10-24T18:29:51Z", "utc_end": "2026-10-24T18:44:51Z", "length_s": 900, "withheld": true},
        {"utc_start": "2026-10-24T18:44:51Z", "utc_end": "2026-10-24T19:14:51Z", "length_s": 1800,
         "episode": {"id": "whistler|1947-10-20", "series": "The Whistler"}}
      ]},
      {"genre": "western", "name": "Western", "slots": []}
    ]}
    """.utf8)

    private static var mystery: Station { try! StationsFile.decode(file).stations[0] }

    @Test func theFileDecodesTheContractShape() throws {
        let file = try StationsFile.decode(Self.file)
        #expect(file.stations.map(\.name) == ["Mystery", "Western"])
        let slots = Self.mystery.slots
        #expect(slots.count == 3)
        #expect(slots[0].playableEpisode?.series == "Suspense")
        #expect(slots[0].playableEpisode?.title == "Self Defense")
        #expect(slots[0].playableEpisode?.lengthS == 1791)
        #expect(slots[0].utcEnd == Self.t("2026-10-24T18:29:51Z"))
        #expect(slots[1].playableEpisode == nil && slots[1].withheld)
        #expect(RadioClock.gapNote(slots[1]) == "Not in the catalog")
        #expect(slots[2].playableEpisode?.title == nil)
    }

    @Test func onNowIsTheSlotWhoseInstantsHoldAndWhereInIt() {
        let slots = Self.mystery.slots
        let at = { (iso: String) in StationClock.onNow(slots, at: Self.t(iso)) }
        #expect(at("2026-10-24T17:59:59Z") == nil)
        #expect(at("2026-10-24T18:00:00Z")?.index == 0)
        #expect(at("2026-10-24T18:10:00Z")?.offset == 600)
        #expect(at("2026-10-24T18:29:50Z")?.index == 0)
        // A boundary belongs to the slot that starts.
        #expect(at("2026-10-24T18:29:51Z")?.index == 1)
        #expect(at("2026-10-24T18:44:51Z").map { [$0.index, Int($0.offset)] } == [2, 0])
        #expect(at("2026-10-24T19:14:50Z")?.index == 2)
        #expect(at("2026-10-24T19:14:51Z") == nil, "after the last slot nothing is on")
        #expect(StationClock.onNow([], at: Self.t("2026-10-24T18:10:00Z")) == nil)
    }

    @Test func aheadIsTheSlotOnNowAndThoseStartingWithinTheSpan() {
        let slots = Self.mystery.slots
        #expect(StationClock.ahead(slots, from: Self.t("2026-10-24T18:10:00Z"), span: 600).count == 1)
        #expect(StationClock.ahead(slots, from: Self.t("2026-10-24T18:10:00Z"), span: 3600).count == 3)
        #expect(StationClock.ahead(slots, from: Self.t("2026-10-24T18:30:00Z")).first?.utcStart
                == Self.t("2026-10-24T18:29:51Z"))
        #expect(StationClock.ahead(slots, from: Self.t("2026-10-24T20:00:00Z")).isEmpty)
    }

    /// A station plays through the one LiveListening: join where the clock
    /// stands, a withheld slot plays nothing, the next starts at its own time.
    @Test func listeningLiveToAStationJoinsWaitsAndPlaysOn() {
        let slots = Self.mystery.slots
        var live = LiveListening(slots: slots, lengths: ["suspense|1947-10-16": 1791, "whistler|1947-10-20": 1800])
        #expect(live.tick(now: Self.t("2026-10-24T18:10:00Z")) == .play(episodeID: "suspense|1947-10-16", at: 600))
        #expect(live.handle(.ended) == .none)
        #expect(live.tick(now: Self.t("2026-10-24T18:35:00Z")) == .none)
        #expect(live.tick(now: Self.t("2026-10-24T18:44:51Z")) == .play(episodeID: "whistler|1947-10-20", at: 0))
        _ = live.handle(.ended)
        #expect(live.tick(now: Self.t("2026-10-24T19:14:51Z")) == .stop)
    }
}
