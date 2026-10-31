import Foundation

// Export (Human-Shaped principle 11): a person's own listening history, follows, queue, and takes
// list as a JSON file, and the history as CSV. Built on the device from what it holds and handed to
// the system's share or save sheet; nothing is uploaded. Same keys as js/export.js (docs/EXPORT.md).

nonisolated struct DataExport: Sendable, Equatable {
    struct History: Sendable, Equatable {
        var episode: String
        var title: String?
        var seriesName: String?
        var airDate: String?
        var listenedAt: Date?
        var positionSeconds: Double?
        var durationSeconds: Double?
    }

    struct Follow: Sendable, Equatable {
        var series: String
        var name: String?
    }

    struct Queued: Sendable, Equatable {
        var episode: String
        var title: String?
        var seriesName: String?
        var airDate: String?
    }

    struct Take: Sendable, Equatable {
        var id: String
        var line: String
        var part: String
        var created: Date
        var seconds: Double
        var chosen: Bool
    }

    struct Production: Sendable, Equatable {
        var id: String
        var title: String
        var created: Date
        var takes: [Take]
    }

    var exportedAt: Date
    var history: [History]
    var following: [Follow]
    var queue: [Queued]
    var takes: [Production]

    static let historyColumns = ["episode", "title", "seriesName", "airDate", "listenedAt", "positionSeconds", "durationSeconds"]

    private static func iso(_ date: Date) -> String { date.formatted(.iso8601) }

    func json() throws -> Data {
        func drop(_ pairs: [(String, Any?)]) -> [String: Any] {
            var out: [String: Any] = [:]
            for (key, value) in pairs { out[key] = value ?? NSNull() }
            return out
        }
        let object: [String: Any] = [
            "app": "Ear Drama",
            "format": 1,
            "exportedAt": Self.iso(exportedAt),
            "history": history.map {
                drop([("episode", $0.episode), ("title", $0.title), ("seriesName", $0.seriesName), ("airDate", $0.airDate),
                      ("listenedAt", $0.listenedAt.map(Self.iso)), ("positionSeconds", $0.positionSeconds),
                      ("durationSeconds", $0.durationSeconds)])
            },
            "following": following.map { drop([("series", $0.series), ("name", $0.name)]) },
            "queue": queue.enumerated().map { index, q in
                drop([("position", index + 1), ("episode", q.episode), ("title", q.title), ("seriesName", q.seriesName),
                      ("airDate", q.airDate)])
            },
            "takes": takes.map { p in
                drop([("production", p.id), ("title", p.title), ("created", Self.iso(p.created)),
                      ("takes", p.takes.map { t in
                          drop([("id", t.id), ("lineID", t.line), ("part", t.part), ("created", Self.iso(t.created)),
                                ("seconds", t.seconds), ("chosen", t.chosen)])
                      })])
            },
        ]
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    static func cell(_ value: String?) -> String {
        let text = value ?? ""
        guard text.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    func historyCSV() -> String {
        func number(_ value: Double?) -> String? { value.map { String(Int($0)) } }
        var lines = [Self.historyColumns.joined(separator: ",")]
        for h in history {
            let row: [String?] = [h.episode, h.title, h.seriesName, h.airDate, h.listenedAt.map(Self.iso),
                                  number(h.positionSeconds), number(h.durationSeconds)]
            lines.append(row.map(Self.cell).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }
}
