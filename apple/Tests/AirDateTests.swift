import Foundation
import Testing

// R1: an air date is shown at the precision the catalog has, in the system's long form.

struct AirDateTests {
    private let us = Locale(identifier: "en_US")

    @Test func aFullDateIsTheLongLocalizedForm() {
        #expect(AirDate.display("1947-10-12", locale: us) == "Sunday, October 12, 1947")
        #expect(AirDate.display("1947-10-12", locale: Locale(identifier: "de_DE")) == "Sonntag, 12. Oktober 1947")
    }

    @Test func aYearOrMonthStaysThatPrecise() {
        #expect(AirDate.display("1947", locale: us) == "1947")
        #expect(AirDate.display("1947-10", locale: us) == "October 1947")
    }

    @Test func noDateAndNoSenseAreHonest() {
        #expect(AirDate.display(nil, locale: us) == "Undated")
        #expect(AirDate.display("", locale: us) == "Undated")
        #expect(AirDate.display("1947-13-40", locale: us) == "1947-13-40", "control: a date that is no day is shown as stored, never invented")
        #expect(AirDate.display("circa 1940", locale: us) == "circa 1940")
    }

    @Test func theMediumFormIsAbbreviatedAndKeepsPrecision() {
        #expect(AirDate.medium("1949-09-17", locale: us) == "Sep 17, 1949")
        #expect(AirDate.medium("1949-09", locale: us) == "Sep 1949")
        #expect(AirDate.medium("1949", locale: us) == "1949")
        #expect(AirDate.medium(nil, locale: us) == "Undated")
    }

    /// Everything a row, event line or title draws from an air date: no ISO shape. The control
    /// proves the pattern would catch the raw stored string.
    @Test func noIsoDateReachesTheScreen() {
        let iso = /\d{4}-\d{2}(-\d{2})?/
        #expect("1949-09-17".contains(iso), "control: the pattern catches a raw date")
        #expect(AirDate.spellingDates(in: "Abbott & Costello (1947-04-14)", locale: us) == "Abbott & Costello (Apr 14, 1947)")
        for date in ["1949-09-17", "1949-09", "1949", "1931-01-01"] {
            let episode = EpisodeRow(id: "e", seriesKey: "s", seriesName: "Show", airDate: date, season: nil, number: nil,
                                     title: nil, lengthSeconds: nil, rights: "unclaimed", rightsBasis: nil, network: nil)
            var drawn = [AirDate.medium(date), AirDate.display(date), episode.displayTitle]
            let block = Grammar.dateBlock(date: date, number: nil)
            drawn += [block.small, block.big]
            for text in drawn { #expect(!text.contains(iso), "\(text) is an ISO date") }
        }
    }

    @Test func recordingsAreNamedByPositionNeverByIdentifier() {
        func copy(_ rank: Int, id: String, label: String? = nil) -> Recording {
            Recording(rank: rank, archiveID: id, url: URL(string: "https://archive.org/download/\(id)/a.mp3")!, format: nil,
                      kbps: 128, lengthSeconds: 1790, variant: nil, partial: false, label: label)
        }
        let ids = ["OTRR_Suspense_Singles", "Suspense420617TheBurningCourt", "AnthonyBerkeleyThePoisonedChocolatesCaseBBCSNT198"]
        for id in ids { #expect(RecordingLabel.looksLikeIdentifier(id), "control: \(id) is identifier-shaped") }
        for (index, id) in ids.enumerated() {
            let recording = copy(index, id: id, label: index == 0 ? id : nil)
            let drawn = RecordingLabel.title(recording, position: index + 1) + " " + RecordingLabel.facts(recording, isBest: index == 0)
            #expect(!RecordingLabel.looksLikeIdentifier(drawn), "\(drawn)")
            #expect(!drawn.contains(id))
        }
        // Unlabeled, a copy is named by its facts, never "Recording 1" (owner, 2026-11-09).
        #expect(RecordingLabel.title(copy(0, id: "x"), position: 1) == "128 kbps \u{00B7} 29:50")
        #expect(RecordingLabel.facts(copy(0, id: "x"), isBest: true) == "Best copy")
        #expect(RecordingLabel.facts(copy(0, id: "x", label: "Old Time Radio Researchers"), isBest: true)
                == "Best copy \u{00B7} 128 kbps \u{00B7} 29:50")
        #expect(RecordingLabel.title(copy(1, id: "x", label: "Old Time Radio Researchers"), position: 2) == "Old Time Radio Researchers")
    }
}
