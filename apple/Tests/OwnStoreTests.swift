#if os(macOS)
import Foundation
import Testing

// Own scripts on this device (PLAYS-DESIGN §13, iOS-DESIGN §4.21): the port of js/own.test.js over OwnScripts,
// ProductionStore.adopt, OwnPartsModel, OwnFile, OwnBuild and PlaysLibrary. Nothing here touches a network.
//
// Seen to fail, 2026-11-24, each mutation run once through tools/apple_own_mutants.py, which keeps the list.

private let text = """
A LITTLE PLAY

ANNA: Who is there?
BEN: Only me.

Somebody knocks twice.

ANNA: Come in, then. (She opens the door.) Mind the step.
BEN: Thank you.
SOUND: DOOR CLOSES
ANNA: Sit down.
"""

nonisolated private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var t: Double = 1000
    func next() -> Date {
        lock.lock()
        defer { lock.unlock() }
        t += 1
        return Date(timeIntervalSince1970: t)
    }
}

nonisolated private final class Disk: @unchecked Sendable {
    private let lock = NSLock()
    private var isFull = false
    private var delay: TimeInterval = 0
    var full: Bool {
        get { lock.withLock { isFull } }
        set { lock.withLock { isFull = newValue } }
    }
    func slowOnce(_ s: TimeInterval) { lock.withLock { delay = s } }
    func commit(_ files: [String: Data], _ folder: URL) throws {
        let (stop, wait) = lock.withLock { let w = delay; delay = 0; return (isFull, w) }
        if stop { throw CocoaError(.fileWriteOutOfSpace) }
        if wait > 0 { Thread.sleep(forTimeInterval: wait) }
        try OwnScripts.commitFiles(files, folder)
    }
}

@MainActor
private struct Env {
    let root: URL
    let plays: ProductionStore
    let own: OwnScripts
    let disk = Disk()

    init() {
        root = FileManager.default.temporaryDirectory.appending(path: "OwnStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        plays = ProductionStore(root: root.appending(path: "Plays", directoryHint: .isDirectory))
        let clock = Clock(), disk = disk
        own = OwnScripts(root: root.appending(path: "Scripts", directoryHint: .isDirectory), plays: plays,
                         commit: { try disk.commit($0, $1) }, now: { clock.next() })
    }

    func reopened() -> OwnScripts { OwnScripts(root: own.root, plays: plays) }

    func clean() { try? FileManager.default.removeItem(at: root) }

    /// Adds the text and presses Done, as the parts page does.
    func made(_ title: String = "A Little Play", words: String = text) async throws -> OwnRecord {
        var rec = try await own.create(title: title, text: words)
        rec.doc = OwnScript.done(rec.doc)
        rec.done = true
        #expect(try await own.keep(rec) == nil)
        return rec
    }

    @discardableResult
    func record(_ script: PlayScript, _ lineID: String, created: Date = .now) throws -> String {
        var p = try plays.create(script)
        let line = script.lines.first { $0.id == lineID }!
        p.add(Take(id: UUID().uuidString, lineID: lineID, part: line.part, file: "\(lineID)-x.flac", created: created, frames: 10,
                   sampleRate: 48_000, capture: .direct, heard: [:], loudness: nil, peak: 0, bleed: false))
        try plays.save(p)
        return p.id
    }
}

/// One color rule for a part on every surface (B26): the parts page, the casting page, the script's page, the reader and the studio.
///   Broken control: EarModel.hue by the order named (the old rule): BEN, named second and the largest, read teal here and blue there.
@MainActor
struct PartColorRuleTests {
    @Test func aPartHasTheSameColorOnTheCastingPageAndTheScriptsPage() async throws {
        let env = Env()
        defer { env.clean() }
        let rec = try await env.made("Colors", words: "ANNA: One.\nBEN: Two.\nBEN: Three.\nBEN: Four.\nCY: Five.\nCY: Six.\nANNA: Seven.")
        let script = try #require(env.own.script(rec.id))
        // Named in the order ANNA, CY, BEN (the order a person names them while listening); sizes BEN 3, ANNA 2, CY 2.
        let named = [OwnPart(name: "ANNA", lines: 2), OwnPart(name: "CY", lines: 2), OwnPart(name: "BEN", lines: 3)]
        for part in named {
            #expect(EarCore.hue(part.name, in: named) == script.partHue(.role(part.name)), "\(part.name)")
        }
        #expect(EarCore.hue("BEN", in: named) == PlayScript.partHues[0], "the largest is first, however it was named")
        #expect(EarCore.hue("DOT", in: named + [OwnPart(name: "DOT", lines: 0)]) == nil, "no line yet, no color")
        #expect(EarCore.hue(nil, in: named) == nil)
        let ordered = [OwnPart(name: "BEN", lines: 3), OwnPart(name: "ANNA", lines: 2), OwnPart(name: "CY", lines: 2)]
        for part in ordered { #expect(EarCore.hue(part.name, in: ordered) == EarCore.hue(part.name, in: named), "the parts page agrees: \(part.name)") }
    }
}

private func step(_ rec: inout OwnRecord, _ op: OwnOp, _ takes: Set<String> = []) -> OwnRefusal? {
    let r = OwnScript.apply(rec.doc, op, OwnEnv(takes: takes))
    if r.refusal == nil { rec.doc = r.doc }
    return r.refusal
}

private func speech(_ rec: OwnRecord, _ role: String, _ n: Int = 0) -> OwnLine {
    rec.doc.lines.filter { $0.kind == "speech" && $0.role == role }[n]
}

@MainActor @Suite struct OwnStoreTests {
    @Test func addedWithItsPartsProposedNoIDGivenAndNotCastableUntilDone() async throws {
        let env = Env(); defer { env.clean() }
        let rec = try await env.own.create(title: "  A Little Play  ", text: text)
        #expect(OwnScript.isOwnID(rec.id))
        #expect(rec.title == "A Little Play")
        #expect(rec.doc.lines.allSatisfy { $0.id == nil })
        #expect(env.own.script(rec.id) == nil)
        let row = try #require(env.own.rows.first)
        #expect(row.parts == 2 && row.open == 2)
        #expect(!row.done && row.facts == "2 lines have no part")
        let back = try #require(try env.reopened().get(rec.id))
        #expect(back.doc == OwnScript.kept(rec.doc), "the working copy reads back whole")
        #expect(back.original == OwnScript.normalize(text))
        #expect(env.reopened().rows.map(\.id) == [rec.id], "and its row, in a new launch")
    }

    @Test func doneGivesEachLineItsIDOnceAndKeepsTheCastableShapeSealed() async throws {
        let env = Env(); defer { env.clean() }
        let rec = try await env.made()
        let s = try #require(env.own.script(rec.id))
        #expect(s.isOwn && s.rights.bucket == "own" && s.source.name == "Added by you" && s.source.url.isEmpty)
        #expect(s.lines.prefix(3).map(\.id) == ["L0001", "L0002", "L0003"])
        let directions: [String] = s.lines.filter { $0.kind == .direction }.compactMap(\.source)
        #expect(directions == ["A LITTLE PLAY", "Somebody knocks twice."])
        #expect(s.castParts.map(\.title) == ["ANNA", "BEN", "Sound effects", "Stage directions"])
        let lines = OwnScript.toScript(rec.doc, rec.meta)["lines"]!
        #expect(s.revision == OwnScript.revisionOf(lines), "the revision is its lines'")
        #expect(env.own.rows.first?.done == true)
        #expect(env.own.rows.first?.facts == "2 parts \u{00B7} 8 lines")
    }

    @Test func linesThatCannotBeAScriptLeaveTheLastThatCould() async throws {
        let env = Env(); defer { env.clean() }
        var rec = try await env.made()
        let before = try #require(env.own.script(rec.id))
        #expect(step(&rec, OwnOp(op: .notPart, part: "ANNA")) == nil)
        #expect(step(&rec, OwnOp(op: .notPart, part: "BEN")) == nil)
        #expect(try await env.own.keep(rec) == .no_parts)
        #expect(env.own.script(rec.id)?.revision == before.revision)
        #expect(try env.own.get(rec.id)?.doc.lines.contains { $0.kind == "speech" } == false, "and the working copy has the change")
    }

    @Test func aFullDiskKeepsNothingOfAChangeAndSaysWhy() async throws {
        let env = Env(); defer { env.clean() }
        var rec = try await env.made()
        let files = { () -> [String: Data] in
            let folder = env.own.folder(rec.id)
            return Dictionary(uniqueKeysWithValues: ["doc.json", "row.json", "script.json"].map { ($0, (try? Data(contentsOf: folder.appending(path: $0))) ?? Data()) })
        }
        let was = files()
        env.disk.full = true
        #expect(step(&rec, OwnOp(op: .words, line: speech(rec, "ANNA").k, text: "Who goes there?")) == nil)
        await #expect(throws: CocoaError.self) { try await env.own.keep(rec) }
        #expect(files() == was, "not one of the three files changed")
        #expect(OwnText.notKept(CocoaError(.fileWriteOutOfSpace)) == "This device is out of space.")
        await #expect(throws: (any Error).self) { _ = try await env.own.create(title: "T", text: text) }
        env.disk.full = false
        #expect(try await env.own.keep(rec) == nil, "Try Again keeps it")
        #expect(env.own.script(rec.id)?.lines.first { $0.role == "ANNA" }?.spokenText == "Who goes there?")
        #expect(FileManager.default.subpaths(atPath: env.own.root.path)?.contains { $0.contains(".staged-") } == false, "no staged folder is left")
    }

    /// The swap itself: a failure part way through writing the staged folder leaves the script's own untouched.
    @Test func aStagedFolderThatFailsIsNeverSwappedIn() async throws {
        let env = Env(); defer { env.clean() }
        let rec = try await env.made()
        let folder = env.own.folder(rec.id)
        let was = try Data(contentsOf: folder.appending(path: "doc.json"))
        #expect(throws: (any Error).self) {
            try OwnScripts.commitFiles(["doc.json": Data("{}".utf8), "no/such/place.json": Data()], folder)
        }
        #expect(try Data(contentsOf: folder.appending(path: "doc.json")) == was)
    }

    @Test func twoChangesKeptCloseTogetherEndAsTheSecond() async throws {
        let env = Env(); defer { env.clean() }
        var rec = try await env.made()
        env.disk.slowOnce(0.06)
        _ = step(&rec, OwnOp(op: .words, line: speech(rec, "ANNA").k, text: "One?"))
        let one = rec
        _ = step(&rec, OwnOp(op: .words, line: speech(rec, "ANNA").k, text: "Two?"))
        let two = rec, own = env.own
        let a = Task { try await own.keep(one) }
        let b = Task { try await own.keep(two) }
        _ = try await (a.value, b.value)
        #expect(try env.own.get(rec.id)?.doc.lines.first { $0.role == "ANNA" }?.text == "Two?")
    }

    @Test func aTakeFixesItsLinesPartAndBoundariesInEveryProduction() async throws {
        let env = Env(); defer { env.clean() }
        var rec = try await env.made()
        let s = try #require(env.own.script(rec.id))
        let anna = s.lines.first { $0.role == "ANNA" }!.id
        let ben = s.lines.filter { $0.role == "BEN" }[1].id
        try env.record(s, anna)
        try env.record(s, ben)
        let other = try await env.made("Another")
        #expect(env.own.takes(rec.id) == [anna, ben], "both productions' takes lock")
        #expect(env.own.takes(other.id).isEmpty, "another script's are free")
        let takes = env.own.takes(rec.id)
        let k = speech(rec, "ANNA").k
        #expect(step(&rec, OwnOp(op: .assign, line: k, to: .role("BEN")), takes) == .line_has_take)
        #expect(step(&rec, OwnOp(op: .split, line: k, at: 4), takes) == .line_has_take)
        #expect(step(&rec, OwnOp(op: .leaveOut, line: k), takes) == .line_has_take)
        #expect(step(&rec, OwnOp(op: .rename, part: "ANNA", rename: "ANN"), takes) == .part_has_take)
        #expect(step(&rec, OwnOp(op: .words, line: k, text: "Who is it?"), takes) == nil, "its words may change")
        // An unchosen take locks too.
        var p = env.plays.productions(of: rec.id)[0]
        p.chosen = [:]
        try env.plays.save(p)
        #expect(env.own.takes(rec.id).count == 2)
        let model = OwnPartsModel(try #require(try env.own.get(rec.id)), store: env.own)
        #expect(model.isLocked(model.lines.first { $0.role == "ANNA" }!))
        #expect(model.hasTake(part: "ANNA") && model.change(OwnOp(op: .leaveOut, line: k)) == .line_has_take)
    }

    @Test func aChangeReachesItsProductionsAndWordsChangedReadsTrueOnlyForAnOlderTake() async throws {
        let env = Env(); defer { env.clean() }
        var rec = try await env.made()
        let s = try #require(env.own.script(rec.id))
        let annas = s.lines.filter { $0.role == "ANNA" }.map(\.id)
        let pid = try env.record(s, annas[0], created: Date(timeIntervalSinceNow: -60))
        var p = env.plays.production(pid)!
        p.listenedThrough = true
        p.mixedFrom = "x"
        try env.plays.save(p)
        let old = p.takes[0]
        _ = step(&rec, OwnOp(op: .words, line: speech(rec, "ANNA").k, text: "Who goes there?"), [annas[0]])
        rec.title = "Renamed"
        try await env.own.keep(rec)
        p = env.plays.production(pid)!
        var ps = try #require(env.plays.script(for: p))
        let now = try #require(env.own.script(rec.id))
        #expect(p.title == "Renamed" && p.scriptRevision == now.revision && ps.revision == now.revision && now.revision != s.revision)
        #expect(ps.lines.first { $0.id == annas[0] }?.spokenText == "Who goes there?")
        #expect(p.takes == [old], "the take stays")
        #expect(p.listenedThrough && p.mixedFrom == "x", "words alone leave a finished play finished")
        func take(_ line: String, _ at: Date) -> Take {
            Take(id: "t", lineID: line, part: .role("ANNA"), file: "f", created: at, frames: 1, sampleRate: 48_000, capture: .direct, heard: [:],
                 loudness: nil, peak: 0, bleed: false)
        }
        #expect(OwnBuild.wordsChanged(ps, old))
        #expect(!OwnBuild.wordsChanged(ps, take(annas[0], Date(timeIntervalSinceNow: 60))), "a take of the new words does not")
        #expect(!OwnBuild.wordsChanged(ps, take(annas[1], old.created)), "nor one on another line")
        // Changed back, but for punctuation: no words changed.
        _ = step(&rec, OwnOp(op: .words, line: speech(rec, "ANNA").k, text: "Who is there."), [annas[0]])
        try await env.own.keep(rec)
        #expect(!OwnBuild.wordsChanged(env.own.script(rec.id)!, old))
        // A part renamed and a line split: parts follow, and the play is no longer finished.
        #expect(step(&rec, OwnOp(op: .rename, part: "BEN", rename: "BENJAMIN"), [annas[0]]) == nil)
        let second = speech(rec, "ANNA", 1)
        #expect(step(&rec, OwnOp(op: .split, line: second.k, at: 13), [annas[0]]) == nil)
        try await env.own.keep(rec)
        p = env.plays.production(pid)!
        ps = env.plays.script(for: p)!
        #expect(p.parts.keys.filter(\.isSpeaking).map(\.rawValue).sorted() == ["role:ANNA", "role:BENJAMIN"])
        #expect(ps.lines.contains { $0.id == "\(second.id!)a" }, "the split line takes a letter")
        #expect(!p.listenedThrough && p.mixedFrom == nil && p.takes.count == 1)
        #expect(ProductionStore(root: env.plays.root).production(pid)?.scriptRevision == ps.revision, "and it is kept, not only in memory")
    }

    @Test func aSharedProductionKeepsItsOwnText() async throws {
        let env = Env(); defer { env.clean() }
        var rec = try await env.made()
        let s = try #require(env.own.script(rec.id))
        let pid = try env.record(s, s.lines.first { $0.role == "ANNA" }!.id)
        let share = try JSONDecoder().decode(ProductionShare.self, from: Data(Self.share.utf8))
        try env.plays.setShare(pid, share)
        _ = step(&rec, OwnOp(op: .words, line: speech(rec, "BEN").k, text: "Nobody."))
        try await env.own.keep(rec)
        #expect(env.plays.production(pid)?.scriptRevision == s.revision)
        #expect(env.plays.script(for: env.plays.production(pid)!)?.revision == s.revision)
        #expect(env.own.script(rec.id)?.revision != s.revision)
    }

    private static let share: String = {
        let made = ProductionShare(pid: "w1")
        return String(decoding: (try? JSONEncoder().encode(made)) ?? Data(), as: UTF8.self)
    }()

    @Test func deletingAScriptLeavesItsProductionsTheirCopy() async throws {
        let env = Env(); defer { env.clean() }
        let rec = try await env.made()
        let s = try #require(env.own.script(rec.id))
        let pid = try env.record(s, s.lines.first { $0.role == "ANNA" }!.id)
        let keep = try await env.made("Kept")
        #expect(env.own.productions(rec.id).map(\.id) == [pid])
        try await env.own.remove(rec.id)
        #expect(try env.own.get(rec.id) == nil && env.own.script(rec.id) == nil)
        #expect(env.own.rows.map(\.id) == [keep.id])
        #expect(env.plays.script(for: env.plays.production(pid)!)?.id == s.id, "the production reads its own copy")
    }

    @Test func theTextBeingAddedIsKeptAndGoesWhenItIsEmpty() throws {
        let env = Env(); defer { env.clean() }
        #expect(env.own.draft() == nil)
        try env.own.setDraft(.init(title: "T", text: "ANNA: Hello"))
        #expect(env.reopened().draft() == .init(title: "T", text: "ANNA: Hello"))
        #expect(env.reopened().rows.isEmpty, "and it is no script")
        try env.own.setDraft(.init(title: "", text: ""))
        #expect(env.own.draft() == nil)
    }

    @Test func exportCarriesEveryOwnScriptDoneOrNot() async throws {
        let env = Env(); defer { env.clean() }
        let rec = try await env.made()
        _ = try await env.own.create(title: "Not yet", text: text)
        let export = DataExport(exportedAt: .now, history: [], following: [], queue: [], takes: [], scripts: env.own.exportRows())
        let object = try #require(try JSONSerialization.jsonObject(with: export.json()) as? [String: Any])
        let scripts = try #require(object["scripts"] as? [[String: Any]])
        #expect(scripts.map { $0["title"] as? String } == ["Not yet", "A Little Play"])
        #expect(scripts.map { $0["done"] as? Bool } == [false, true] && scripts.allSatisfy { $0["source"] as? String == "Added by you" })
        let lines = try #require(scripts[1]["lines"] as? [[String: Any]])
        #expect(lines.count == rec.doc.lines.count && lines[2]["id"] as? String == "L0003")
        #expect((lines[1]["parts"] as? [[String: String]])?.first?["say"] == "Who is there?")
        let open = try #require(scripts[0]["lines"] as? [[String: Any]]).filter { $0["kind"] as? String == "open" }
        #expect(open.map { $0["source"] as? String } == ["A LITTLE PLAY", "Somebody knocks twice."])
        let none = DataExport(exportedAt: .now, history: [], following: [], queue: [], takes: [])
        #expect((try JSONSerialization.jsonObject(with: none.json()) as? [String: Any])?["scripts"] as? [String] == [])
    }

    @Test func saveAsTextReadsBackAsTheSameSpeeches() async throws {
        let env = Env(); defer { env.clean() }
        let rec = try await env.made()
        let s = try #require(env.own.script(rec.id))
        let out = OwnBuild.asText(s)
        #expect(out.contains("\n\nANNA\nWho is there?\n\n"), "a name in capitals over its words (Fountain)")
        let again = OwnScript.parse(out).lines
        #expect(again.filter { $0.kind == "speech" }.map(\.text) == s.lines.filter { $0.kind == .speech }.map(OwnBuild.text))
        #expect(again.filter { $0.kind == "sound" }.map(\.text) == ["SOUND: DOOR CLOSES"])
        #expect(OwnBuild.fileName("A/B: \"C\"?") == "AB C.txt" && OwnBuild.fileName("///") == "Script.txt")
    }

    @Test func aFileIsTextOrRefusedCountedBeforeItIsRead() throws {
        func why(_ d: Data) -> OwnFile.Refusal? { do { _ = try OwnFile.decode(d); return nil } catch { return error as? OwnFile.Refusal } }
        #expect(try OwnFile.decode(Data("ANNA: Café".utf8)) == "ANNA: Café")
        #expect(try OwnFile.decode(Data([0xef, 0xbb, 0xbf, 0x41])) == "A")
        #expect(try OwnFile.decode(Data([0xff, 0xfe, 0x41, 0, 0xe9, 0])) == "Aé")
        #expect(try OwnFile.decode(Data([0xfe, 0xff, 0, 0x41])) == "A")
        #expect(try OwnFile.decode(Data([0x43, 0x61, 0x66, 0xe9, 0x92])) == "Café\u{2019}", "an old Windows file")
        for bytes in [Data("%PDF-1.4".utf8), Data("{\\rtf1".utf8), Data([0x50, 0x4b, 3, 4, 0]), Data([0x41, 0, 0x42]),
                      Data([0xff, 0xd8, 0xff, 1, 2, 3, 4, 5])] { #expect(why(bytes) == .not_text) }
        #expect(why(Data(count: OwnFile.maxBytes + 1)) == .too_long, "too many bytes, unread")
        #expect(why(Data(String(repeating: "é", count: OwnScript.maxBytes / 2 + 1).utf8)) == .too_long)
        #expect(try OwnFile.decode(Data(String(repeating: "a", count: OwnScript.maxBytes).utf8)).utf8.count == OwnScript.maxBytes)
        let dir = FileManager.default.temporaryDirectory.appending(path: "OwnFile-\(UUID().uuidString)/Inbox", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        let big = dir.appending(path: "big.txt"), ok = dir.appending(path: "My Play.txt")
        FileManager.default.createFile(atPath: big.path, contents: nil)
        let handle = try FileHandle(forWritingTo: big)
        try handle.truncate(atOffset: 5_000_000_000)
        try handle.close()
        // Unreadable as well as long: only its size can say why.
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: big.path)
        #expect(OwnIncoming(big).read() == .failure(.too_long), "five gigabytes are refused by their size, unread")
        try Data("ANNA: Hello".utf8).write(to: ok)
        #expect(OwnIncoming(ok).read() == .success(.init(title: "My Play", text: "ANNA: Hello")))
        #expect(!FileManager.default.fileExists(atPath: ok.path), "the system's copy does not stay")
    }

    @Test func theNearestSpeakersOfEveryLineAnswerAsTheCoreDoes() {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            let lines = (0..<Int.random(in: 1...30, using: &rng)).map { i -> OwnLine in
                switch Int.random(in: 0..<10, using: &rng) {
                case 0..<4: OwnLine(k: i + 1, kind: "speech", role: ["A", "B", "C", "D"].randomElement(using: &rng), text: "x")
                case 4..<6: OwnLine(k: i + 1, kind: "direction", text: "x")
                default: OwnLine(k: i + 1, kind: "open", text: "x")
                }
            }
            let all = OwnBuild.nearest(lines)
            for (i, l) in lines.enumerated() where l.kind == "open" { #expect(all[l.k] == OwnScript.nearestParts(lines, i)) }
        }
    }

    // MARK: Migration

    /// What is on a device from before own scripts, and from a build after this one: productions and their scripts read
    /// as they did, a script this build cannot read is left alone, and a folder a crash left half staged is not a script.
    @Test func whatIsOnTheDeviceAlreadyReadsAsItDidAndWhatCannotBeReadIsLeftAlone() async throws {
        let env = Env(); defer { env.clean() }
        let lib = try #require(Self.library())
        let play = lib.scripts[0]
        let pid = try env.record(play, play.lines.first { $0.kind == .speech }!.id)
        // A script.json as 1.0.137 wrote it has none of the new keys.
        let url = env.plays.folder(pid).appending(path: "script.json")
        var old = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        old["episode"] = nil
        old["edits"] = nil
        try JSONSerialization.data(withJSONObject: old).write(to: url)
        let again = ProductionStore(root: env.plays.root)
        #expect(again.production(pid).flatMap { again.script(for: $0) }?.lines.count == play.lines.count)
        #expect(try JSONDecoder().decode(PlayScript.self, from: Data(contentsOf: url)).lines.count == play.lines.count)
        let rec = try await env.made()
        let doc = env.own.folder(rec.id).appending(path: "doc.json")
        var newer = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: doc)) as? [String: Any])
        newer["format"] = OwnRecord.formatNow + 1
        let data = try JSONSerialization.data(withJSONObject: newer)
        try data.write(to: doc)
        try FileManager.default.createDirectory(at: env.own.root.appending(path: ".staged-dead"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: env.own.root.appending(path: "own-not-an-id"), withIntermediateDirectories: true)
        let opened = env.reopened()
        #expect(opened.rows.map(\.id) == [rec.id], "still listed")
        #expect(throws: OwnScripts.Failure.self) { _ = try opened.get(rec.id) }
        #expect(try Data(contentsOf: doc) == data, "never overwritten")
        #expect(!FileManager.default.fileExists(atPath: env.own.root.appending(path: ".staged-dead").path))
        #expect(FileManager.default.fileExists(atPath: env.own.root.appending(path: "own-not-an-id").path), "never deleted")
        #expect(opened.script(rec.id)?.title == "A Little Play", "what was Done is still read and recorded")
    }

    private static func library() -> CastableLibrary? {
        var dir = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<6 {
            let file = dir.appending(path: "catalog/plays/castable-scripts.json")
            if let data = try? Data(contentsOf: file) { return try? JSONDecoder().decode(CastableLibrary.self, from: data) }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }

    // MARK: The seam

    @Test func theLibraryReadsAnOwnIDFromThisDeviceAndNeverAsksTheNetwork() async throws {
        let env = Env(); defer { env.clean() }
        let rec = try await env.made()
        let asked = Asked()
        let library = PlaysLibrary(store: env.plays, fetch: { _ in await asked.count(); return nil }, cache: env.root, bundled: { nil }, own: env.own)
        #expect(try await library.script(id: rec.id)?.title == "A Little Play")
        #expect(try await library.script(id: "own-00000000-0000-0000-0000-000000000000") == nil)
        #expect(library.has(rec.id) && !library.has("own-00000000-0000-0000-0000-000000000000"))
        #expect(await asked.n == 0)
        _ = try await library.script(id: "gut-1")
        #expect(await asked.n > 0, "control: a catalog id is")
        let reader = KokoroReader(phonemes: { _ in await asked.count(); return nil })
        let before = await asked.n
        #expect(await reader.prepare(rec.id) == false)
        #expect(await asked.n == before, "no phonemes are asked for")
        let s = try #require(env.own.script(rec.id))
        #expect(VoiceCast.script(s).downloadedVoices().isEmpty && VoiceCast.production("p", script: s).downloadedVoices().isEmpty)
    }

    private actor Asked {
        var n = 0
        func count() { n += 1 }
    }

    @Test func nothingLeavesTheDeviceAndNoDeadButtonStands() throws {
        let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
        func source(_ path: String) throws -> String {
            try String(contentsOf: root.appending(path: path), encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
        }
        func leaks(_ s: String) -> [String] { ["URLSession", "workerResponse", "PlaysWorker", "WorkerOpenPlays", "AccountStore", "SharedPlays"].filter(s.contains) }
        for f in ["Core/Plays/OwnScript.swift", "Core/Plays/OwnStore.swift", "Core/Plays/OwnPartsModel.swift", "Core/Plays/EarModel.swift",
                  "Shared/OwnScreens.swift", "Shared/OwnPartsScreen.swift", "Shared/EarScreen.swift"] { #expect(try leaks(source(f)).isEmpty, "\(f)") }
        #expect(leaks("AccountStore URLSession").count == 2, "control")
        for word in ["AVAudioEngine", "installTap", "SFSpeech", "AVPlayer(", "AVAudioPlayer("] {
            for f in ["Core/Plays/EarCore.swift", "Core/Plays/EarModel.swift", "Shared/EarScreen.swift"] { #expect(try !source(f).contains(word), "\(f) \(word)") }
        }
        let plays = try source("Shared/PlaysScreens.swift")
        #expect(plays.contains("if !script.isOwn { ReadStartButton(script: script) }"), "no Read Together on its page")
        // Sharing arrived with R4-5: Share is the production's, and Publish is absent for it, with its reason (OwnShareViews).
        #expect(plays.contains("SharedProductionSection(production: production, script: script)") && !plays.contains("if !script.isOwn {\n                SharedProductionSection("), "Share on a production of one")
        #expect(try source("Shared/SharedPlaysViews.swift").contains("if script.isOwn { OwnShareRows("), "and its own rows: readers, Try Again, Report Script")
        #expect(try source("Shared/PlaysGrammar.swift").contains("script.kind == \"own\" ? \"Your script\""), "its kicker is its own")
    }

    @Test func aRealPlayPastedIsCorrectedKeptAndReadByTheRecorder() async throws {
        let env = Env(); defer { env.clean() }
        let play = try #require(Self.library()).scripts.max { $0.lines.count < $1.lines.count }!
        let rec = try await env.made(play.title, words: OwnBuild.asText(play))
        #expect(rec.doc.lines.count > 200)
        let s = try #require(env.own.script(rec.id))
        let p = try env.plays.create(s)
        #expect(Relay.next(p, s) != nil)
        #expect(s.speechLineIDs.count == s.lines.filter { $0.kind == .speech }.count)
    }

    // MARK: The layout

    /// `layoutOf`'s twin of the web's `emphasis: false`: a bracket in a person's own script is theirs.
    @Test func anOwnScriptsBracketsAreDirectionsNeverSaid() {
        let line = ScriptLine(id: "L1", kind: .speech, role: "A", parts: [.say("I was"), .direction("laughing"), .say("so sure")])
        func said(_ lay: PageLine) -> [Bool] { lay.speeches[0].rows.flatMap(\.runs).map(\.said) }
        #expect(said(PlayPage.layoutOf(line, roles: [], emphasis: false)) == [true, false, true])
        #expect(said(PlayPage.layoutOf(line, roles: [])) == [true, true, true], "control: a catalog script's is the parser's emphasis")
    }
}

// MARK: - The parts page

@MainActor @Suite struct OwnPartsModelTests {
    private func model(_ env: Env) async throws -> OwnPartsModel { OwnPartsModel(try await env.own.create(title: "T", text: text), store: env.own) }

    @Test func nextGoesToEachLineWithNoPartAndAround() async throws {
        let env = Env(); defer { env.clean() }
        let m = try await model(env)
        #expect(m.open == 2)
        let first = m.nextOpen(), second = m.nextOpen()
        #expect(first == m.lines[0].k && second == m.lines[3].k)
        #expect(m.nextOpen() == first, "around the end")
        m.give(first!, .kind("direction"))
        m.give(second!, .role("BEN"))
        #expect(m.open == 0 && m.nextOpen() == nil)
        #expect(m.parts.map(\.name) == ["ANNA", "BEN"] && m.parts.map(\.lines) == [3, 3])
    }

    @Test func undoTakesBackAStepThroughTheSystemsOwnUndo() async throws {
        let env = Env(); defer { env.clean() }
        let m = try await model(env)
        let undo = UndoManager()
        undo.groupsByEvent = false
        m.undoManager = undo
        let before = m.lines
        func step(_ op: OwnOp) { undo.beginUndoGrouping(); #expect(m.change(op) == nil); undo.endUndoGrouping() }
        step(OwnOp(op: .assign, line: before[0].k, to: .kind("direction")))
        step(OwnOp(op: .split, line: before[4].k, at: 13))
        #expect(m.lines.count == before.count + 1)
        undo.undo()
        #expect(m.lines.count == before.count && m.canUndo)
        m.undo()
        #expect(m.lines == before && !m.canUndo && !undo.canUndo, "the toolbar's Undo and shake take back the same steps")
    }

    @Test func leaveOutEverythingAboveIsOneStep() async throws {
        let env = Env(); defer { env.clean() }
        let m = try await model(env)
        let k = m.lines[4].k
        #expect(m.change(OwnOp(op: .leaveOutAbove, line: k)) == nil && m.lines[0].k == k)
        m.undo()
        #expect(m.lines.count == 8)
        #expect(m.change(OwnOp(op: .leaveOutBelow, line: k)) == nil && m.lines.last?.k == k)
    }

    @Test func aPartNamedWaitsUntilALineIsItsAndOneWithNoneCanGo() async throws {
        let env = Env(); defer { env.clean() }
        let m = try await model(env)
        #expect(m.addPart(" carol: ").name == "CAROL" && m.parts.last == OwnPart(name: "CAROL", lines: 0))
        #expect(m.addPart("").refusal == .empty && m.addPart(String(repeating: "x", count: 41)).refusal == .too_long)
        #expect(m.partCount == 2 && m.hue("CAROL") == nil && m.hue("ANNA") == PlayScript.partHues[0])
        m.dropPart("CAROL")
        #expect(!m.parts.contains { $0.name == "CAROL" })
    }

    @Test func doneMakesItAScriptOrSaysWhyNotAndKeepsTheWork() async throws {
        let env = Env(); defer { env.clean() }
        let m = try await model(env)
        #expect(m.change(OwnOp(op: .notPart, part: "ANNA")) == nil && m.change(OwnOp(op: .notPart, part: "BEN")) == nil)
        #expect(await m.finish() == false)
        #expect(m.problem == "No line has a part." && !m.rec.done)
        m.undo(); m.undo()
        env.disk.full = true
        #expect(await m.finish() == false)
        #expect(m.problem == "This device is out of space." && !m.rec.done && m.lines[0].kind == "open", "the page keeps the work")
        env.disk.full = false
        #expect(await m.finish())
        #expect(env.own.script(m.rec.id)?.lines.count == 8 && m.problem == nil)
    }

    @Test func everyStepIsKeptAsItIsMade() async throws {
        let env = Env(); defer { env.clean() }
        var page: OwnPartsModel? = try await model(env)
        let first = page!.lines[0].k, fourth = page!.lines[3].k
        page!.give(first, .kind("direction"))
        for _ in 0..<100 where env.own.rows.first?.open != 1 { try await Task.sleep(for: .milliseconds(20)) }
        #expect(env.own.rows.first?.open == 1)
        page!.give(fourth, .kind("sound"))
        page!.leave()
        page = nil
        for _ in 0..<50 where env.own.rows.first?.open != 0 { try await Task.sleep(for: .milliseconds(20)) }
        #expect(env.own.rows.first?.open == 0, "and what was waiting when the page closed, its model already gone")
    }
}

// MARK: - The doors

@Suite struct OwnDoorTests {
    @MainActor @Test func aDoorNeverReadsOrWritesThePersonsOwn() {
        for env in [["APP_START_OWN": "parts"], ["APP_START_CAST": "x|y"], ["APP_SCRATCH": "1"]] {
            #expect(LaunchDoors.from(environment: env, arguments: []).scratch == "1")
        }
        #expect(LaunchDoors.from(environment: ["APP_SCRATCH": "keep"], arguments: []).scratch == "keep")
        #expect(LaunchDoors.from(environment: ["APP_START_PLAY": "gut-1"], arguments: []).scratch == nil)
        #expect(LaunchDoors.from(environment: ["APP_START_OWN": "nonsense"], arguments: []).own == nil)
    }

    @MainActor @Test func aTextFileHandedToTheAppWaitsInTheInboxForAddAScript() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "Handed-\(UUID().uuidString).txt")
        try Data("ANNA: Hello".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let store = AppStore()
        store.post(.script(file))
        #expect(store.incomingScript == nil && !store.wantsAddScript, "nothing is read before the root takes it")
        #expect(store.drainInbox().isEmpty)
        #expect(store.wantsAddScript && store.incomingScript?.read() == .success(.init(title: file.deletingPathExtension().lastPathComponent, text: "ANNA: Hello")))
        #expect(FileManager.default.fileExists(atPath: file.path), "a file that is not the system's copy is left where it is")
    }

    /// Open In never makes Ear Drama what a text file opens with, and the TV opens none.
    @Test func theDocumentTypeIsAnAlternateAndTheTVHasNone() throws {
        let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
        func plist(_ name: String) throws -> [String: Any] {
            try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: root.appending(path: "Resources/\(name)")), format: nil) as? [String: Any])
        }
        var phone = try plist("EarDrama-Info.plist")
        let tv = try plist("EarDrama-tvOS-Info.plist")
        let types = try #require(phone["CFBundleDocumentTypes"] as? [[String: Any]])
        #expect(types.count == 1 && types[0]["LSHandlerRank"] as? String == "Alternate")
        #expect(types[0]["LSItemContentTypes"] as? [String] == ["public.plain-text"])
        phone["CFBundleDocumentTypes"] = nil
        #expect(NSDictionary(dictionary: phone).isEqual(to: tv), "the two plists differ only by it")
    }
}
#endif
