import Foundation
import Testing

// WEB-DESIGN §4.2r rule 5: the same cases as js/api.test.js "homeShows" and "uploadTagged".

struct HomeShowsTests {
    private func ep(_ id: Int, _ series: String) -> EpisodeRow {
        EpisodeRow(id: "\(series)|\(id)", seriesKey: series, seriesName: series, airDate: nil, season: nil, number: nil,
                   title: nil, lengthSeconds: nil, rights: "unclaimed", rightsBasis: nil, network: nil)
    }

    @Test func aShowAppearsAtMostOncePerHome() {
        var seen: Set<String> = ["gunsmoke"]
        let start = HomeShows.keep([ep(1, "gunsmoke"), ep(2, "dragnet"), ep(3, "dragnet"), ep(4, "suspense")], seen: &seen)
        #expect(start.map(\.id) == ["dragnet|2", "suspense|4"], "above is skipped, a repeat in the row is skipped")
        let length = HomeShows.keep([ep(5, "dragnet"), ep(6, "suspense"), ep(7, "xminusone"), ep(8, "gunsmoke")], seen: &seen)
        #expect(length.map(\.id) == ["xminusone|7"], "By length never opens on Start a show's shows")
        #expect(seen == ["gunsmoke", "dragnet", "suspense", "xminusone"])
    }

    @Test func chipsSkipOnlyWhatIsAboveAndTheFirstFeedsTheRowsBelow() {
        let a = HomeChip(id: "a", title: "A", episodes: [ep(1, "x"), ep(2, "y")])
        let b = HomeChip(id: "b", title: "B", episodes: [ep(3, "x")])
        let c = HomeChip(id: "c", title: "C", episodes: [ep(4, "hero")])
        let out = HomeShows.chips([c, a, b], above: ["hero"])
        #expect(out.chips.map(\.id) == ["a", "b"], "a chip left empty is dropped")
        #expect(out.chips[1].episodes.map(\.id) == ["x|3"], "a later chip is not filtered by the first chip's shows")
        #expect(out.seen == ["hero", "x", "y"])
    }

    @Test func theDialNamesWhatEachStationHasOnNow() {
        func slot(_ id: String?, withheld: Bool = false) -> RadioSlot {
            RadioSlot(etStart: "8:00", etEnd: "8:30", lengthMin: 30, utcStart: Date(timeIntervalSince1970: 0),
                      utcEnd: Date(timeIntervalSince1970: 1000),
                      episode: id.map { RadioSlot.Episode(id: "\($0)|1942-05-25", series: $0.uppercased(), title: "Ep", lengthS: 1800) },
                      withheld: withheld)
        }
        let stations = [Station(genre: "mystery", name: "Mystery", slots: [slot("m")]),
                        Station(genre: "news", name: "News", slots: [slot("n", withheld: true)])]
        let dial = DialEntry.entries(stations, now: Date(timeIntervalSince1970: 500))
        #expect(dial.map(\.show) == ["M", nil], "a withheld slot is nothing on")
        #expect(dial[0].year == 1942)
        #expect(dial[1].on == nil, "control: nothing playable, nothing to tune")
    }

    @Test func anUploadTagOrIdentifierIsRawText() {
        #expect(HomeShows.uploadTagged("AbyM #026 The Girl on Shipwreck Island Pt 03 More About Gracie"))
        #expect(HomeShows.uploadTagged("OTRR_Suspense_420622"))
        for title in ["The Telltale Bottle", "Sorry, Wrong Number", "The Case of the 13 Keys", ""] {
            #expect(!HomeShows.uploadTagged(title), "\(title) is a title")
        }
    }

    @Test func aRawTitleGivesWayToTheBroadcastDate() {
        #expect(HomeShows.heroTitle("The Telltale Bottle", id: "ellery|1939-04-02") == "The Telltale Bottle")
        let raw = HomeShows.heroTitle("AbyM #026 Gracie", id: "abym|1946-03-04")
        #expect(raw == AirDate.medium("1946-03-04"), "composed from the record's date")
        #expect(HomeShows.heroTitle("AbyM #026 Gracie", id: "abym|") == nil, "control: no date, no line")
    }
}
