import Foundation
import Testing

/// The car's Stations: the app's one clock and one live listening, tuned at the clock's position
/// (the cases of Android's CarStationsTest).
struct CarStationsTests {
    private static let now = try! Date("2026-11-24T20:10:00Z", strategy: .iso8601)

    private static let stationsJSON = Data("""
    {"stations": [
      {"genre": "mystery", "name": "Mystery", "slots": [
        {"utc_start": "2026-11-24T19:30:00Z", "utc_end": "2026-11-24T20:00:00Z", "length_s": 1800,
         "episode": {"id": "suspense|1943-05-25", "series": "Suspense"}},
        {"utc_start": "2026-11-24T20:00:00Z", "utc_end": "2026-11-24T20:30:00Z", "length_s": 1800,
         "episode": {"id": "suspense|1942-10-20", "series": "Suspense"}},
        {"utc_start": "2026-11-24T20:30:00Z", "utc_end": "2026-11-24T21:00:00Z", "length_s": 1800,
         "episode": {"id": "suspense|1942-06-17", "series": "Suspense"}}]},
      {"genre": "comedy", "name": "Comedy", "slots": [
        {"utc_start": "2026-11-24T20:00:00Z", "utc_end": "2026-11-24T20:30:00Z", "length_s": 1800, "withheld": true}]},
      {"genre": "news", "name": "News", "slots": [
        {"utc_start": "2026-11-24T20:00:00Z", "utc_end": "2026-11-24T20:30:00Z", "length_s": 1800,
         "episode": {"id": "not-in-this-catalog|1950-01-01", "series": "Elsewhere"}}]}
    ]}
    """.utf8)

    private static func tonight(startingAt start: String) -> Data {
        Data("""
        {"zone": "America/New_York", "days": {"\(RadioClock.localDate(now))": {"evening": "1942-10-22", "network": "CBS",
          "slots": [{"et_start": "19:00", "et_end": "19:30", "length_min": 30, "printed": "Suspense",
                     "episode": {"id": "suspense|1942-06-17", "series": "Suspense", "title": "The Burning Court", "length_s": 1770},
                     "utc_start": "\(start)", "utc_end": "2026-11-24T21:00:00Z"}]}}}
        """.utf8)
    }

    nonisolated private final class Started: @unchecked Sendable {
        nonisolated(unsafe) var tunes: [CarTune] = []
    }

    private func stations(
        catalog: CatalogStore,
        tonight: @escaping () async throws -> TonightFile? = { nil },
        file: @escaping () async throws -> StationsFile? = { try StationsFile.decode(CarStationsTests.stationsJSON) },
        started: Started = Started()
    ) -> CarStations {
        CarStations(catalog: catalog, tonight: tonight, stations: file, start: { started.tunes.append($0) }, now: { Self.now })
    }

    private func catalog() throws -> CatalogStore { CatalogStore(path: try Fixture.make().path) }

    @Test func onlyAStationWithARecordingOnTheAirIsOfferedWithWhatIsOn() async throws {
        let list = try await stations(catalog: try catalog()).list()
        #expect(list.map(\.id) == ["station:mystery"], "a gap and a broadcast the catalog lacks are not offered")
        #expect(list[0].name == "Mystery")
        #expect(list[0].line == "Suspense \u{00B7} The Hitch-Hiker")
        #expect(list[0].artEpisodeID == "suspense|1942-10-20")
    }

    @Test func tonightsEveningIsOfferedFirstOnceItIsUnderWay() async throws {
        let file = try TonightFile.decode(Self.tonight(startingAt: "2026-11-24T20:00:00Z"))
        let list = try await stations(catalog: try catalog(), tonight: { file }).list()
        #expect(list.map(\.id) == [CarStations.tonight, "station:mystery"])
        #expect(list[0].name == "Tonight in 1942")
        #expect(list[0].line == "Suspense \u{00B7} The Burning Court")
        let early = try TonightFile.decode(Self.tonight(startingAt: "2026-11-24T20:30:00Z"))
        #expect(try await stations(catalog: try catalog(), tonight: { early }).list().map(\.id) == ["station:mystery"],
                "an evening that has not begun is not on the air")
    }

    @Test func tuningInStartsTheSlotOnTheAirAtTheClocksPositionThroughTheLiveListening() async throws {
        let started = Started()
        let tuned = await stations(catalog: try catalog(), started: started).tune("station:mystery")
        #expect(tuned == CarStations.Tuned(episodeID: "suspense|1942-10-20", startSeconds: 600))
        guard case let .station(station, slots, details)? = started.tunes.first else { Issue.record("no station tune"); return }
        #expect(station.genre == "mystery" && details.keys.contains("suspense|1942-10-20"))
        #expect(slots.first?.playableEpisode?.id == "suspense|1942-10-20", "the slot on now leads, the earlier one is past")
        #expect(started.tunes.count == 1, "one tune-in, handed to the app's one LiveRadio")
    }

    @Test func tuningInTonightHandsOverTheEvening() async throws {
        let started = Started()
        let file = try TonightFile.decode(Self.tonight(startingAt: "2026-11-24T20:00:00Z"))
        let tuned = await stations(catalog: try catalog(), tonight: { file }, started: started).tune(CarStations.tonight)
        #expect(tuned?.episodeID == "suspense|1942-06-17")
        #expect(tuned?.startSeconds == 600)
        guard case let .evening(day, _)? = started.tunes.first else { Issue.record("no evening tune"); return }
        #expect(day.year == "1942")
    }

    @Test func anUnknownStationOrAGapOnTheAirTunesNothing() async throws {
        let started = Started()
        let car = stations(catalog: try catalog(), started: started)
        #expect(await car.tune("station:nowhere") == nil)
        #expect(await car.tune("station:comedy") == nil)
        #expect(await car.tune("station:news") == nil, "a broadcast this catalog lacks never plays")
        #expect(started.tunes.isEmpty, "nothing was started")
    }

    @Test func offlineWithNoStationsAndNoEveningThrowsSoTheCarSaysSo() async throws {
        let car = stations(catalog: try catalog(), tonight: { throw URLError(.notConnectedToInternet) },
                           file: { throw URLError(.notConnectedToInternet) })
        await #expect(throws: URLError.self) { try await car.list() }
        let oneFile = stations(catalog: try catalog(), tonight: { throw URLError(.notConnectedToInternet) })
        #expect(try await oneFile.list().map(\.id) == ["station:mystery"], "one file alone failing still lists the other")
    }
}
