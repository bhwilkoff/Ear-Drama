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
        /// The sound board's block (B32 §5.1), nil when the production places none.
        var sound: SoundBlock? = nil
        /// The scene this production records (PLAYS-DESIGN §2.12), nil for the whole play.
        var range: ProductionRange? = nil
    }

    /// One script mark (docs/EXPORT.md `marks[]`): offsets in UTF-16 units into the line's printed words.
    struct MarkRow: Sendable, Equatable {
        var script: String
        var title: String?
        var revision: String?
        var line: String
        var start: Int
        var end: Int
        var kind: String
        var text: String
        var hue: String?
        var label: String?
        var note: String?
        var created: Date
        var updated: Date
    }

    /// One line's Pencil ink (docs/EXPORT.md `ink[]`): the stroke count and the `PKDrawing` data, base64, in the
    /// line block's own units (`width` points of text column).
    struct InkRow: Sendable, Equatable {
        var script: String
        var title: String?
        var revision: String?
        var line: String
        var strokes: Int
        var width: Double
        var updated: Date
        var drawing: String
    }

    /// One of the person's own scripts (docs/EXPORT.md `scripts[]`): its lines as they stand, Done or not.
    struct Script: Sendable, Equatable {
        var id: String
        var title: String
        var source: String
        var episode: String?
        var created: Date
        var done: Bool
        var lines: [ScriptLineRow]
    }

    struct ScriptLineRow: Sendable, Equatable {
        var id: String?
        var kind: String
        var role: String?
        var parts: [LinePart]?
        var source: String?

        var object: [String: Any] {
            var out: [String: Any] = ["kind": kind]
            if let id { out["id"] = id }
            if let role { out["role"] = role }
            if let source { out["source"] = source }
            if let parts { out["parts"] = parts.map { [$0.isSaid ? "say" : "direction": $0.text] } }
            return out
        }
    }

    /// One of the person's own sounds (docs/EXPORT.md `ownSounds[]`, B32 §3.4 item 4): the sound itself as a base64
    /// 16-bit 48 kHz mono WAV, so the export is a whole copy of the person's own work.
    struct OwnSoundRow: Sendable, Equatable {
        var id: String
        var name: String
        var created: Date
        var from: String
        var seconds: Double
        var bytes: Int
        var wav: String
    }

    var exportedAt: Date
    var history: [History]
    var following: [Follow]
    var queue: [Queued]
    var takes: [Production]
    var marks: [MarkRow] = []
    var ink: [InkRow] = []
    var scripts: [Script] = []
    var ownSounds: [OwnSoundRow] = []

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
                var o = drop([("production", p.id), ("title", p.title), ("created", Self.iso(p.created)),
                      ("takes", p.takes.map { t in
                          drop([("id", t.id), ("lineID", t.line), ("part", t.part), ("created", Self.iso(t.created)),
                                ("seconds", t.seconds), ("chosen", t.chosen)])
                      })])
                if let sound = p.sound,
                   let data = try? JSONEncoder().encode(sound),
                   let object = try? JSONSerialization.jsonObject(with: data) {
                    o["sound"] = object
                }
                if let range = p.range { o["range"] = ["from": range.from, "to": range.to] }
                return o
            },
            "marks": marks.map { m in
                drop([("script", m.script), ("title", m.title), ("revision", m.revision), ("line", m.line), ("start", m.start),
                      ("end", m.end), ("kind", m.kind), ("text", m.text), ("hue", m.hue), ("label", m.label), ("note", m.note),
                      ("created", Self.iso(m.created)), ("updated", Self.iso(m.updated))])
            },
            "ink": ink.map { i in
                drop([("script", i.script), ("title", i.title), ("revision", i.revision), ("line", i.line), ("strokes", i.strokes),
                      ("width", i.width), ("updated", Self.iso(i.updated)), ("drawing", i.drawing)])
            },
            "scripts": scripts.map { s in
                var o = drop([("id", s.id), ("title", s.title), ("source", s.source), ("created", Self.iso(s.created)), ("done", s.done),
                              ("lines", s.lines.map(\.object))])
                if let episode = s.episode { o["episode"] = episode }
                return o
            },
            "ownSounds": ownSounds.map { o in
                drop([("id", o.id), ("name", o.name), ("created", Self.iso(o.created)), ("from", o.from), ("seconds", o.seconds),
                      ("bytes", o.bytes), ("wav", o.wav)])
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
