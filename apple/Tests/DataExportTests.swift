import Foundation
import Testing

/// Export (Human-Shaped principle 11): the JSON holds history, follows, queue and takes; the CSV
/// quotes what needs it. Same keys as js/export.js.
struct DataExportTests {
    private let sample = DataExport(
        exportedAt: Date(timeIntervalSince1970: 1_793_361_600),
        history: [
            .init(episode: "a|1", title: "One, with a comma", seriesName: "The \"Quoted\" Show", airDate: "1949-02-03",
                  listenedAt: Date(timeIntervalSince1970: 1_793_300_000), positionSeconds: 600, durationSeconds: 1800),
            .init(episode: "a|2", title: nil, seriesName: nil, airDate: nil, listenedAt: nil, positionSeconds: nil,
                  durationSeconds: nil),
        ],
        following: [.init(series: "a", name: "A Show")],
        queue: [.init(episode: "a|3", title: "Three", seriesName: "A Show", airDate: nil)],
        takes: [.init(id: "p1", title: "Play", created: Date(timeIntervalSince1970: 1_793_000_000), takes: [
            .init(id: "t1", line: "l1", part: "role:A", created: Date(timeIntervalSince1970: 1_793_000_100), seconds: 2.5, chosen: true),
        ])])

    @Test func jsonCarriesEverythingUnderTheWebsKeys() throws {
        let object = try #require(try JSONSerialization.jsonObject(with: sample.json()) as? [String: Any])
        #expect(object["app"] as? String == "Ear Drama")
        #expect((object["history"] as? [[String: Any]])?.first?["episode"] as? String == "a|1")
        #expect((object["history"] as? [[String: Any]])?.first?["positionSeconds"] as? Double == 600)
        #expect((object["following"] as? [[String: Any]])?.first?["series"] as? String == "a")
        #expect((object["queue"] as? [[String: Any]])?.first?["position"] as? Int == 1)
        let production = try #require((object["takes"] as? [[String: Any]])?.first)
        #expect(production["production"] as? String == "p1")
        #expect((production["takes"] as? [[String: Any]])?.first?["chosen"] as? Bool == true)
    }

    @Test func csvQuotesCommasAndQuotesAndLeavesGapsEmpty() {
        let lines = sample.historyCSV().components(separatedBy: "\r\n")
        #expect(lines[0] == DataExport.historyColumns.joined(separator: ","))
        #expect(lines[1].hasPrefix("a|1,\"One, with a comma\",\"The \"\"Quoted\"\" Show\",1949-02-03,"))
        #expect(lines[1].hasSuffix(",600,1800"))
        #expect(lines[2] == "a|2,,,,,,")
        #expect(lines.count == 4)
    }

    @Test func nothingHeldExportsAnEmptyFileNotAnError() throws {
        let empty = DataExport(exportedAt: .now, history: [], following: [], queue: [], takes: [])
        let object = try #require(try JSONSerialization.jsonObject(with: empty.json()) as? [String: Any])
        #expect((object["history"] as? [Any])?.isEmpty == true)
        #expect(empty.historyCSV() == DataExport.historyColumns.joined(separator: ",") + "\r\n")
    }
}
