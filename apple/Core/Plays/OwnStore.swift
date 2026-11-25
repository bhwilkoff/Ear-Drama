import Foundation

// The person's own scripts on this device (PLAYS-DESIGN §13, iOS-DESIGN §4.21; Decision 088.3): the port of the web's
// js/own-store.js. Nothing here leaves the device and nothing asks for an account.
//
// `Application Support/Scripts/` (never compiled for the TV, whose Application Support refuses a write):
//   <id>/doc.json     the working copy OwnScript corrects, with the title, the text as pasted (normalized), and the
//                     parts named but not yet given a line (the web's shape)
//   <id>/script.json  the castable shape, once Done: what the reader and the recorder read
//   <id>/row.json     what Record's Your Scripts draws without opening either
//   draft.json        the text being added, before Next
// A script cast by ear also carries `episode` and `ear`. A script's three files are written in a staged folder and
// swapped in together, so a full disk never leaves half of one. A file this build does not know how to read is left
// as it is, never overwritten and never deleted.

// MARK: - A doc as it is kept

nonisolated extension OwnWho: Codable {
    private enum Keys: String, CodingKey { case role, out }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        if let role = try c.decodeIfPresent(String.self, forKey: .role) { self = .role(role) } else { self = .out }
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case let .role(role): try c.encode(role, forKey: .role)
        case .out: try c.encode(true, forKey: .out)
        }
    }
}

nonisolated extension OwnSpan: Codable {
    init(from decoder: any Decoder) throws {
        var c = try decoder.unkeyedContainer()
        self.init(start: try c.decode(Int64.self), end: try c.decode(Int64.self))
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(start)
        try c.encode(end)
    }
}

/// Why a script could not be kept or read back: its files are unreadable, or it was shared and is frozen.
nonisolated enum OwnKeepFailure: Error { case unreadable, shared }

/// A script being corrected.
nonisolated struct OwnRecord: Codable, Equatable, Sendable, Identifiable {
    struct Episode: Codable, Equatable, Sendable {
        var id: String
        var url: String
    }

    /// A casting by ear: the transcript it was made from, the copy it was heard on, and the place it was left (ms).
    struct Ear: Codable, Equatable, Sendable {
        var sig: String
        var copy: String
        var place: Int64
    }

    static let formatNow = 1

    var format = OwnRecord.formatNow
    var id: String
    var title: String
    var original: String
    var doc: OwnDoc
    var extras: [String] = []
    var created: Date
    var updated: Date
    var done = false
    var episode: Episode?
    var ear: Ear?
    /// When it was first shared: from then on it is what people were sent, and only a copy can change (§13 item 12).
    var shared: Date?

    static func newID() -> String { "own-" + UUID().uuidString.lowercased() }

    var meta: OwnMeta { OwnMeta(id: id, title: title, episodeId: episode?.id, episodeUrl: episode?.url) }
}

/// A script as Record's Your Scripts draws it.
nonisolated struct OwnRow: Codable, Equatable, Sendable, Identifiable {
    struct Ear: Codable, Equatable, Sendable {
        var cast: Int
        var lines: Int
    }

    let id: String
    let title: String
    let parts: Int
    let lines: Int
    let open: Int
    let done: Bool
    /// Each part's lines, largest first.
    let cast: [Int]
    let voices: Int
    let created: Date
    let updated: Date
    var episode: String?
    var ear: Ear?
    var shared: Date?

    var halfCast: Bool { ear.map { $0.cast < $0.lines } ?? false }

    /// "37 of 149 lines cast", "2 lines have no part", or "9 parts · 297 lines".
    var facts: String {
        if halfCast, let ear { return OwnText.castLine(ear.cast, ear.lines) }
        return !done && open > 0 ? OwnText.noPart(open) : OwnText.partsAndLines(parts, lines)
    }
}

// MARK: - The words every page shares

nonisolated enum OwnText {
    static func number(_ n: Int) -> String { n.formatted(.number.locale(Locale(identifier: "en_US"))) }
    static func count(_ n: Int, _ one: String, _ many: String) -> String { n == 1 ? "1 \(one)" : "\(number(n)) \(many)" }
    static func partsAndLines(_ parts: Int, _ lines: Int) -> String {
        "\(count(parts, "part", "parts")) \u{00B7} \(count(lines, "line", "lines"))"
    }
    static func noPart(_ n: Int) -> String { n == 1 ? "1 line has no part" : "\(number(n)) lines have no part" }
    static func castLine(_ cast: Int, _ lines: Int) -> String { "\(number(cast)) of \(number(lines)) lines cast" }

    /// Why something was refused, in essential words.
    static func say(_ refusal: OwnRefusal) -> String {
        switch refusal {
        case .too_long, .too_many_lines: "That text is too long."
        case .empty: "There are no words."
        case .bad_name, .bad_part: "That name does not work."
        case .line_has_take: "This line has a take."
        case .lines_have_take: "A line there has a take."
        case .part_has_take: "A line of this part has a take."
        case .no_parts: "No line has a part."
        case .no_lines: "No lines."
        case .no_title: "Add a title."
        case .title_too_long: "That title is too long."
        case .no_such_line: "No line is lit."
        default: "That did not work."
        }
    }

    static func name(_ refusal: OwnRefusal) -> String {
        switch refusal {
        case .too_long: "That name is too long."
        case .empty: "Add a name."
        default: say(refusal)
        }
    }

    static let kept = "Kept on this device"
    static let addedByYou = "Added by you"
    static let cannotPublish = "This script can\u{2019}t be published."
    static let wordsChanged = "Words changed"

    static let shared = "This script is shared."

    static func notKept(_ error: any Error) -> String {
        if let failure = error as? OwnKeepFailure, failure == .shared { return shared }
        return (error as? CocoaError)?.code == .fileWriteOutOfSpace ? "This device is out of space." : "This device could not save it."
    }
}

// MARK: - A file's bytes as text

nonisolated enum OwnFile {
    enum Refusal: String, Error, Equatable, Sendable {
        case too_long, not_text
        var words: String { self == .too_long ? "That file is too long." : "That is not a text file." }
    }

    /// What a file may hold before anything reads it.
    static let maxBytes = 2 * OwnScript.maxBytes + 2

    /// Windows-1252's 0x80 to 0x9F (old .txt files), as the Encoding Standard maps them.
    private static let high: [UInt32] = [
        0x20AC, 0x81, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x8D, 0x017D, 0x8F,
        0x90, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, 0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x9D, 0x017E, 0x0178,
    ]

    /// UTF-8, UTF-16 with its mark, else Windows-1252. Bytes are counted before anything reads them.
    static func decode(_ data: Data) throws -> String {
        if data.count > maxBytes { throw Refusal.too_long }
        let b = [UInt8](data)
        func starts(_ x: UInt8...) -> Bool { b.starts(with: x) }
        if starts(0x25, 0x50, 0x44, 0x46) || starts(0x7b, 0x5c, 0x72, 0x74, 0x66) || starts(0x50, 0x4b, 3, 4) { throw Refusal.not_text }
        let text: String
        if starts(0xff, 0xfe) || starts(0xfe, 0xff) {
            let little = b[0] == 0xff
            var units: [UInt16] = []
            units.reserveCapacity(b.count / 2)
            var i = 2
            while i + 1 < b.count {
                units.append(little ? UInt16(b[i]) | UInt16(b[i + 1]) << 8 : UInt16(b[i]) << 8 | UInt16(b[i + 1]))
                i += 2
            }
            text = String(decoding: units, as: UTF16.self)
        } else {
            if b.contains(0) { throw Refusal.not_text }
            let body = starts(0xef, 0xbb, 0xbf) ? Data(b.dropFirst(3)) : data
            if let utf8 = String(data: body, encoding: .utf8) {
                text = utf8
            } else {
                let controls = b.reduce(0) { $1 < 32 && $1 != 9 && $1 != 10 && $1 != 12 && $1 != 13 ? $0 + 1 : $0 }
                if controls > b.count / 500 { throw Refusal.not_text }
                var s = String.UnicodeScalarView()
                for x in b { s.append(Unicode.Scalar(x >= 0x80 && x < 0xa0 ? high[Int(x) - 0x80] : UInt32(x)) ?? "\u{FFFD}") }
                text = String(s)
            }
        }
        if OwnScript.textRefusal(text) == .too_long { throw Refusal.too_long }
        return text
    }

    /// A file on disk, its size asked before it is read; and the title its name gives it.
    static func read(_ url: URL) throws -> (title: String, text: String) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maxBytes { throw Refusal.too_long }
        guard let data = try? Data(contentsOf: url) else { throw Refusal.not_text }
        return (String(url.deletingPathExtension().lastPathComponent.prefix(OwnScript.maxTitle)), try decode(data))
    }
}

// MARK: - What is made of a record

nonisolated enum OwnBuild {
    static func row(_ rec: OwnRecord) -> OwnRow {
        let settled = OwnScript.settle(rec.doc).lines
        let parts = OwnScript.partsOf(settled).map(\.lines).sorted(by: >)
        let n = OwnScript.castCount(rec.doc)
        return OwnRow(id: rec.id, title: rec.title, parts: parts.count, lines: settled.count,
                      open: settled.filter { $0.kind == "open" }.count, done: rec.done, cast: parts,
                      voices: parts.filter { $0 >= 1 }.count, created: rec.created, updated: rec.updated,
                      episode: rec.episode?.id, ear: rec.ear == nil ? nil : OwnRow.Ear(cast: n.cast, lines: n.lines), shared: rec.shared)
    }

    /// The castable shape of a Done record. A transcript half cast keeps its lines open: the script's are directions
    /// until they are somebody's.
    private static func shape(_ rec: OwnRecord) -> OwnJSON { OwnScript.toScript(OwnScript.done(rec.doc, keepOpen: rec.ear != nil), rec.meta) }

    static func refusal(_ rec: OwnRecord) -> OwnRefusal? { OwnScript.refusalOf(shape(rec)) }

    static func script(_ rec: OwnRecord, was: PlayScript?, taken: Set<String>, at: Date) -> (script: PlayScript?, refusal: OwnRefusal?) {
        let built = shape(rec)
        if let refusal = OwnScript.refusalOf(built) { return (nil, refusal) }
        guard var made = try? JSONDecoder().decode(PlayScript.self, from: Data(OwnScript.canonicalBytes(OwnScript.seal(built)))) else {
            return (nil, .bad_line)
        }
        made.edits = edits(was, made, taken, at)
        return (made, nil)
    }

    static func text(_ line: ScriptLine) -> String {
        guard line.kind == .speech else { return line.source ?? "" }
        return OwnScript.textOf((line.parts ?? []).map { $0.isSaid ? .say($0.text) : .direction($0.text) })
    }

    /// What a line with a take said before its words changed, and until when, oldest first.
    private static func edits(_ was: PlayScript?, _ now: PlayScript, _ taken: Set<String>, _ at: Date) -> [String: [PlayScript.LineEdit]]? {
        guard let was else { return nil }
        var out = was.edits ?? [:]
        let before = Dictionary(was.lines.map { ($0.id, text($0)) }, uniquingKeysWith: { a, _ in a })
        for line in now.lines {
            guard taken.contains(line.id), let old = before[line.id], old != text(line) else { continue }
            out[line.id, default: []].append(PlayScript.LineEdit(until: at, text: old))
        }
        return out.isEmpty ? nil : out
    }

    /// Whether the words of `take`'s line changed, more than punctuation, since it was recorded (§13 item 4).
    static func wordsChanged(_ script: PlayScript, _ take: Take) -> Bool {
        guard let said = script.edits?[take.lineID]?.first(where: { take.created < $0.until }),
              let line = script.lines.first(where: { $0.id == take.lineID }) else { return false }
        return OwnScript.wordsChanged(said.text, text(line))
    }

    /// The script as plain text, readable as Fountain and by Add a Script: a name alone in capitals over its words (an
    /// `@` before one with no capital letter to show), directions as paragraphs.
    static func asText(_ script: PlayScript) -> String {
        script.lines.map { line in
            guard line.kind == .speech, let role = line.role else { return line.source ?? "" }
            let capital = role.unicodeScalars.contains { $0.value >= 65 && $0.value <= 90 }
            return "\(capital ? "" : "@")\(role)\n\(text(line))"
        }
        .joined(separator: "\n\n") + "\n"
    }

    static func fileName(_ title: String) -> String {
        let bad = Set<Character>("\\/:*?\"<>|")
        let stem = String(title.filter { !bad.contains($0) }).trimmingCharacters(in: .whitespacesAndNewlines)
        return (stem.isEmpty ? "Script" : stem) + ".txt"
    }

    /// Each line with no part's two nearest speakers, as `OwnScript.nearestParts` answers, for every line in two passes.
    static func nearest(_ lines: [OwnLine]) -> [Int: [String]] {
        struct Seen { let role: String; let i: Int }
        func sweep(_ order: [Int]) -> [[Seen]] {
            var out = [[Seen]](repeating: [], count: lines.count)
            var two: [Seen] = []
            for i in order {
                out[i] = two
                guard lines[i].kind == "speech", let role = lines[i].role else { continue }
                two = Array(([Seen(role: role, i: i)] + two.filter { $0.role != role }).prefix(2))
            }
            return out
        }
        let indexes = Array(lines.indices)
        let above = sweep(indexes), below = sweep(indexes.reversed())
        var out: [Int: [String]] = [:]
        for (i, l) in lines.enumerated() where l.kind == "open" {
            let near = (above[i].map { (role: $0.role, d: i - $0.i, up: 0) } + below[i].map { (role: $0.role, d: $0.i - i, up: 1) })
                .sorted { $0.d != $1.d ? $0.d < $1.d : $0.up < $1.up }
            var names: [String] = []
            for n in near where !names.contains(n.role) { names.append(n.role) }
            out[l.k] = Array(names.prefix(2))
        }
        return out
    }
}

#if os(iOS) || os(macOS)
// MARK: - The store

@Observable
final class OwnScripts {
    nonisolated struct Draft: Codable, Equatable, Sendable {
        var title = ""
        var text = ""
        var isEmpty: Bool { title.isEmpty && text.isEmpty }
    }

    typealias Failure = OwnKeepFailure

    /// A script's files staged and swapped in together; a seam so a test can fill the disk.
    typealias Commit = @Sendable (_ files: [String: Data], _ folder: URL) throws -> Void

    let root: URL
    /// Your scripts, the last one changed first.
    private(set) var rows: [OwnRow] = []
    @ObservationIgnored weak var plays: ProductionStore?
    @ObservationIgnored private let commit: Commit
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var tail: Task<Void, Never>?

    init(root: URL? = nil, plays: ProductionStore? = nil, commit: @escaping Commit = OwnScripts.commitFiles,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.root = root ?? Self.defaultRoot
        self.plays = plays
        self.commit = commit
        self.now = now
        load()
    }

    static var defaultRoot: URL {
        (LaunchDoors.scratchRoot ?? URL.applicationSupportDirectory).appending(path: "Scripts", directoryHint: .isDirectory)
    }

    func folder(_ id: String) -> URL { root.appending(path: id, directoryHint: .isDirectory) }

    func load() {
        let found = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        var out: [OwnRow] = []
        for url in found.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = url.lastPathComponent
            // A staged folder a crash left: it was never anyone's script.
            if name.hasPrefix(Self.staged) {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            guard let data = try? Data(contentsOf: url.appending(path: "row.json")),
                  let row = try? JSONDecoder().decode(OwnRow.self, from: data), row.id == name, OwnScript.isOwnID(row.id) else { continue }
            out.append(row)
        }
        rows = Self.sorted(out)
    }

    private static func sorted(_ rows: [OwnRow]) -> [OwnRow] {
        rows.sorted { $0.updated != $1.updated ? $0.updated > $1.updated : $0.id < $1.id }
    }

    func row(_ id: String) -> OwnRow? { rows.first { $0.id == id } }

    /// The script being cast from an episode, by the id it has now or one it had when the casting began.
    func row(ofEpisode id: String, forwarding: IDForwarding = IDForwarding()) -> OwnRow? {
        rows.first { $0.episode == id } ?? rows.first { $0.episode.map(forwarding.resolve) == id }
    }

    /// A script being corrected; nil when it is not here, and an error when it is and cannot be read.
    func get(_ id: String) throws -> OwnRecord? {
        guard OwnScript.isOwnID(id) else { return nil }
        let url = folder(id).appending(path: "doc.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let rec = try JSONDecoder().decode(OwnRecord.self, from: Data(contentsOf: url))
        guard rec.format <= OwnRecord.formatNow, rec.id == id else { throw Failure.unreadable }
        return rec
    }

    /// The castable script, once Done; nil before, and for an id not here.
    func script(_ id: String) -> PlayScript? {
        guard OwnScript.isOwnID(id), let data = try? Data(contentsOf: folder(id).appending(path: "script.json")) else { return nil }
        return try? JSONDecoder().decode(PlayScript.self, from: data)
    }

    /// A new script from a title and a text: its parts proposed, no line id given yet.
    func create(title: String, text: String) async throws -> OwnRecord {
        let at = now()
        let rec = await Task.detached(priority: .userInitiated) {
            OwnRecord(id: OwnRecord.newID(), title: OwnScript.trim(OwnScript.normalize(title)), original: OwnScript.normalize(text),
                      doc: OwnScript.newDoc(OwnScript.parse(text).lines), created: at, updated: at)
        }.value
        try await keep(rec)
        return rec
    }

    /// A script begun by casting an episode's transcript. Not kept until `keep`.
    func begin(title: String, doc: OwnDoc, episode: OwnRecord.Episode, ear: OwnRecord.Ear) -> OwnRecord {
        let at = now()
        return OwnRecord(id: OwnRecord.newID(), title: OwnScript.trim(OwnScript.normalize(title)), original: "", doc: doc,
                         created: at, updated: at, episode: episode, ear: ear)
    }

    /// Keeps `rec` as it stands. A Done script's castable shape is sealed and its productions follow; while its lines
    /// cannot be a script (`no_parts`), the last one that could stays. Answers that refusal or nil. Writes never
    /// overtake each other.
    @discardableResult
    func keep(_ rec: OwnRecord) async throws -> OwnRefusal? {
        var snap = rec
        snap.doc = OwnScript.kept(rec.doc)
        snap.updated = now()
        let before = tail
        let work = Task { [snap] () throws -> OwnRefusal? in
            await before?.value
            return try await self.write(snap)
        }
        tail = Task { _ = try? await work.value }
        return try await work.value
    }

    /// Shared once, a script is frozen: what people were sent is what it stays (§13 item 12).
    func frozen(_ id: String) -> Bool { row(id)?.shared != nil }

    func freeze(_ id: String) async throws {
        guard var rec = try get(id), rec.shared == nil else { return }
        rec.shared = now()
        try await keep(rec)
    }

    /// Edit a Copy (§13 item 12): a new script of `script`'s text, with a new id and its own productions. The kept doc is copied
    /// while it is that text, so a casting can be taken up again; its line ids are kept, and it is not frozen.
    func copy(_ script: PlayScript) async throws -> OwnRecord {
        let was = try get(script.id)
        let same = was != nil && self.script(script.id)?.revision == script.revision
        let at = now()
        var rec: OwnRecord
        if let was, same {
            rec = was
        } else {
            let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(script))
            guard let tree = OwnJSON.parse(try JSONSerialization.data(withJSONObject: json)) else { throw Failure.unreadable }
            rec = OwnRecord(id: script.id, title: script.title, original: "", doc: OwnScript.done(OwnScript.fromScript(tree)), created: at, updated: at,
                            episode: script.episode.map { OwnRecord.Episode(id: $0, url: script.source.url) })
        }
        rec.id = OwnRecord.newID()
        rec.title = Self.copyTitle(script.title)
        rec.created = at
        rec.updated = at
        rec.done = true
        rec.shared = nil
        if let refusal = try await keep(rec) { throw Refused(refusal) }
        return rec
    }

    struct Refused: Error { let refusal: OwnRefusal; init(_ r: OwnRefusal) { refusal = r } }

    nonisolated static func copyTitle(_ title: String) -> String {
        let tail = " (copy)"
        return String(title.prefix(OwnScript.maxTitle - tail.count)) + tail
    }

    private func write(_ snap: OwnRecord) async throws -> OwnRefusal? {
        // Shared from another page since this one opened it: what people were sent stands.
        if row(snap.id)?.shared != nil, snap.shared == nil { throw Failure.shared }
        let taken = plays?.takenLines(of: snap.id) ?? []
        let folder = folder(snap.id), commit = commit
        let made = try await Task.detached(priority: .userInitiated) {
            let was = (try? Data(contentsOf: folder.appending(path: "script.json"))).flatMap { try? JSONDecoder().decode(PlayScript.self, from: $0) }
            let built: (script: PlayScript?, refusal: OwnRefusal?) =
                snap.done ? OwnBuild.script(snap, was: was, taken: taken, at: Date()) : (nil, nil)
            let row = OwnBuild.row(snap)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            var files = ["doc.json": try encoder.encode(snap), "row.json": try encoder.encode(row)]
            if let script = built.script { files["script.json"] = try encoder.encode(script) }
            try commit(files, folder)
            return (row: row, script: built.script, refusal: built.refusal)
        }.value
        rows = Self.sorted(rows.filter { $0.id != snap.id } + [made.row])
        if let script = made.script { try plays?.adopt(script) }
        return made.refusal
    }

    func remove(_ id: String) async throws {
        await tail?.value
        guard OwnScript.isOwnID(id) else { return }
        if FileManager.default.fileExists(atPath: folder(id).path) { try FileManager.default.removeItem(at: folder(id)) }
        rows.removeAll { $0.id == id }
    }

    /// The lines of `id` with a take in any of its productions: what may not move (§13 item 4).
    func takes(_ id: String) -> Set<String> { plays?.takenLines(of: id) ?? [] }
    func productions(_ id: String) -> [Production] { plays?.productions(of: id) ?? [] }

    // MARK: The text being added

    private var draftURL: URL { root.appending(path: "draft.json") }

    func draft() -> Draft? {
        (try? Data(contentsOf: draftURL)).flatMap { try? JSONDecoder().decode(Draft.self, from: $0) }
    }

    func setDraft(_ draft: Draft?) throws {
        let fm = FileManager.default
        guard let draft, !draft.isEmpty else {
            if fm.fileExists(atPath: draftURL.path) { try fm.removeItem(at: draftURL) }
            return
        }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(draft).write(to: draftURL, options: .atomic)
    }

    // MARK: Export my data

    /// Export my data's `scripts`: each one's lines as they stand, Done or not.
    func exportRows() -> [DataExport.Script] {
        rows.compactMap { row in
            guard let rec = try? get(row.id) else { return nil }
            let made = rec.done ? script(row.id) : nil
            let lines: [DataExport.ScriptLineRow]
            if let made {
                lines = made.lines.map {
                    DataExport.ScriptLineRow(id: $0.id, kind: $0.kind.rawValue, role: $0.role, parts: $0.kind == .speech ? $0.parts : nil, source: $0.source)
                }
            } else {
                lines = OwnScript.settle(rec.doc).lines.map { l in
                    guard l.kind == "speech" else { return DataExport.ScriptLineRow(id: nil, kind: l.kind, role: nil, parts: nil, source: l.text) }
                    let parts: [LinePart] = OwnScript.pieces(l.text).map { p in
                        switch p {
                        case let .say(t): .say(t)
                        case let .direction(t): .direction(t)
                        }
                    }
                    return DataExport.ScriptLineRow(id: nil, kind: l.kind, role: l.role, parts: parts, source: nil)
                }
            }
            return DataExport.Script(id: rec.id, title: rec.title, source: rec.episode == nil ? OwnText.addedByYou : Transcript.label,
                                     episode: rec.episode?.id, created: rec.created, done: rec.done, lines: lines)
        }
    }

    // MARK: Files

    nonisolated static let staged = ".staged-"

    /// Writes `files` beside what the folder already holds, then swaps the whole folder in: all of them or none.
    nonisolated static func commitFiles(_ files: [String: Data], _ folder: URL) throws {
        let fm = FileManager.default
        let root = folder.deletingLastPathComponent()
        let stage = root.appending(path: staged + UUID().uuidString, directoryHint: .isDirectory)
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: stage) }
        for (name, data) in files { try data.write(to: stage.appending(path: name)) }
        if fm.fileExists(atPath: folder.path) {
            for name in try fm.contentsOfDirectory(atPath: folder.path) where files[name] == nil {
                try fm.copyItem(at: folder.appending(path: name), to: stage.appending(path: name))
            }
            _ = try fm.replaceItemAt(folder, withItemAt: stage)
        } else {
            try fm.moveItem(at: stage, to: folder)
        }
    }
}
#endif
