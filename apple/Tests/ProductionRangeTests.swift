import Foundation
import Testing

// A scene's range (B31 §3.4, PLAYS-DESIGN §2.12) held to catalog/tests/golden/production_range.json, the file the web's
// js/plays.test.js and Android's ProductionRangeTest run too. `RangeCore` is the seam each answer is read through, so a
// mutant swaps one closure and the golden must notice; the real core is the default.
//
// Mutants, each seen to fail the golden (the second test): a scope that ignores the range; Done over the whole play;
// a mix that keeps cues outside the range; a range not dropped on drift; a migration that rewrites the takes; a title
// without the scene's heading.

nonisolated private enum RangeGolden {
    static let root: URL = {
        var dir = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("catalog/tests/golden/production_range.json").path) { return dir }
            dir = dir.deletingLastPathComponent()
        }
        return URL(fileURLWithPath: ProcessInfo.processInfo.environment["EAR_DRAMA_ROOT"] ?? FileManager.default.currentDirectoryPath)
    }()

    nonisolated(unsafe) static let json: [String: Any] = {
        let data = (try? Data(contentsOf: root.appendingPathComponent("catalog/tests/golden/production_range.json"))) ?? Data()
        return ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]
    }()

    static func data(_ object: Any?) -> Data { (try? JSONSerialization.data(withJSONObject: object ?? [:])) ?? Data() }
    static func decode<T: Decodable>(_ type: T.Type, _ object: Any?) throws -> T { try JSONDecoder().decode(type, from: data(object)) }

    static var scriptObject: [String: Any] { json["script"] as? [String: Any] ?? [:] }
    static var script: PlayScript { get throws { try decode(PlayScript.self, scriptObject) } }
    static var range: ProductionRange { get throws { try decode(ProductionRange.self, json["range"]) } }
    static var heading: String { json["heading"] as? String ?? "" }
    static var expect: [String: Any] { json["expect"] as? [String: Any] ?? [:] }

    static func strings(_ any: Any?) -> [String] { any as? [String] ?? [] }
    static func pairs(_ any: Any?) -> [String] { (any as? [[Any]] ?? []).map { "\($0[0])|\($0[1])" } }
    static func counted(_ parts: [CastPart]) -> [String] { parts.map { "\($0.id.rawValue)|\($0.lineCount)" } }

    static func production(_ core: RangeCore, chosen: [String: String], sound: Bool = false) throws -> Production {
        var p = core.make(try script, try range, heading)
        p.takes = (json["takes"] as? [[String: Any]] ?? []).map { t in
            var take = Take(id: t["id"] as? String ?? "", lineID: t["lineID"] as? String ?? "", part: PartID(rawValue: t["part"] as? String ?? ""),
                            file: "\(t["id"] as? String ?? "").flac", created: Date(timeIntervalSince1970: 0), frames: (t["frames"] as? Int) ?? 0,
                            sampleRate: 48_000, capture: .direct, heard: [:], loudness: (t["loudness"] as? NSNumber)?.doubleValue,
                            peak: Float((t["peak"] as? NSNumber)?.doubleValue ?? 0), bleed: false)
            take.cue = t["cue"] as? String
            return take
        }
        p.chosen = chosen
        if sound { p.sound = try decode(SoundBlock.self, json["sound"]) }
        return p
    }
}

nonisolated private struct RangeCore {
    var make: (PlayScript, ProductionRange, String) -> Production = { Production(script: $0, range: $1, heading: $2) }
    var scope: (Production, PlayScript) -> PlayScript = { $1.scoped(for: $0) }
    var castParts: (PlayScript, ProductionRange) -> [CastPart] = { $0.castParts(for: $1) }
    var isComplete: (Production, PlayScript) -> Bool = { Relay.isComplete($0, $1) }
    var timeline: (PlayScript, Production) throws -> MixTimeline = { try MixTimeline.build(script: $0, production: $1) }
    var drifted: (Production, PlayScript) -> Bool = { $1.rangeDrifted($0) }
    var migrate: (Production) -> Production = { $0.migrated }

    static func unranged(_ p: Production, _ whole: PlayScript) -> Production {
        var q = Production(script: whole)
        q.takes = p.takes
        q.chosen = p.chosen
        q.sound = p.sound
        return q
    }

    static var mutants: [(String, RangeCore)] { [
        ("a scope that ignores the range", { var c = RangeCore(); c.scope = { $1.whole }; c.castParts = { s, _ in s.whole.castParts }; return c }()),
        ("Done over the whole play", { var c = RangeCore(); c.isComplete = { p, s in Relay.isComplete(unranged(p, s.whole), s.whole) }; return c }()),
        ("a mix that keeps cues outside the range", { var c = RangeCore(); c.timeline = { s, p in try MixTimeline.build(script: s.whole, production: unranged(p, s.whole)) }; return c }()),
        ("no drift drop", { var c = RangeCore(); c.drifted = { _, _ in false }; return c }()),
        ("a migration that rewrites the takes", { var c = RangeCore(); c.migrate = { var p = $0.migrated; p.chosen = [:]; return p }; return c }()),
        ("a title without the heading", { var c = RangeCore(); c.make = { s, r, _ in Production(script: s, range: r, heading: nil) }; return c }()),
    ] }
}

nonisolated private func rangeAnswers(_ core: RangeCore) throws -> [String] {
    typealias G = RangeGolden
    var bad: [String] = []
    func want<T: Equatable>(_ got: T, _ exp: T, _ name: String) { if got != exp { bad.append("\(name): got \(got), want \(exp)") } }
    let script = try G.script, range = try G.range, e = G.expect
    let p0 = core.make(script, range, G.heading)
    want(p0.title, e["title"] as? String ?? "", "title")
    want(p0.format, e["format"] as? Int, "format")
    want(p0.range, range, "range stored")
    want(p0.parts.keys.map(\.rawValue).sorted(), G.strings(e["parts"]).sorted(), "parts of the range only")
    let s = core.scope(p0, script)
    want(s.lines.map(\.id), G.strings(e["lineIDs"]), "line ids")
    want(G.counted(core.castParts(script, range)), G.pairs(e["cast"]), "castParts(for: range)")
    want(G.counted(s.castParts), G.pairs(e["cast"]), "cast of the scoped script")
    want(G.counted(script.castParts), G.pairs(e["wholeCast"]), "whole cast unchanged")
    want([s.voices, s.minutes], [e["voices"] as? Int ?? -1, e["minutes"] as? Int ?? -1], "voices and minutes are the range's")
    want(Relay.listenPlan(p0, script).map(\.lineID), G.strings(e["listenBeforeAnyTake"]), "listen before any take")

    let done = G.json["done"] as? [String: Any] ?? [:]
    for k in ["before", "after"] {
        let d = done[k] as? [String: Any] ?? [:]
        let p = try G.production(core, chosen: d["chosen"] as? [String: String] ?? [:])
        want(core.isComplete(p, script), d["complete"] as? Bool ?? false, "\(k): Done")
        want(Relay.missingSpeech(p, script), G.strings(d["missing"]), "\(k): missing")
        for (part, ids) in d["partMissing"] as? [String: Any] ?? [:] {
            want(Relay.missingLines(PartID(rawValue: part), in: p, script: script), G.strings(ids), "\(k): \(part) missing")
        }
        if let whole = d["wholeMissing"] {
            want(Relay.missingSpeech(RangeCore.unranged(p, script), script), G.strings(whole), "\(k): the whole play is not done")
        }
    }
    let after = (done["after"] as? [String: Any])?["chosen"] as? [String: String] ?? [:]
    let finished = try G.production(core, chosen: after, sound: true)
    want(Relay.listenPlan(finished, script).map { "\($0.lineID)|\($0.isDeviceVoice ? "voice" : "take")" },
         (G.json["listenAfter"] as? [[String]] ?? []).map { "\($0[0])|\($0[1])" }, "listen through after")
    do {
        let t = try core.timeline(script, finished)
        let export = G.json["export"] as? [String: Any] ?? [:]
        want(t.placements.map(\.lineID), G.strings(export["voice"]), "export voice lines")
        want(t.sounds.map(\.soundID), G.strings(export["sounds"]), "export sounds")
        want(t.sounds.map(\.lineID), G.strings(export["soundLines"]), "export sound lines")
        want(t.left, [], "a cue outside the range is out of the mix, never missing")
    } catch { bad.append("export threw \(error)") }

    do {
        let recording = try Relay.take(.role("DEMEA"), performer: nil, in: try G.production(core, chosen: after), script: script)
        let through = try Relay.finish(.role("DEMEA"), in: recording, script: script)
        want(through.state(of: .role("DEMEA")).status, .done, "finish in range")
    } catch { bad.append("a part of the range could not be taken and finished: \(error)") }
    do {
        _ = try Relay.take(.role("SYRUS"), performer: nil, in: p0, script: script)
        bad.append("a part outside the range was taken")
    } catch { want(error, .notOpen, "a part outside the range") }

    for c in G.json["drift"] as? [[String: Any]] ?? [] {
        var object = G.scriptObject
        let removed = Set(G.strings(c["remove"]))
        object["revision"] = "r2"
        object["lines"] = (object["lines"] as? [[String: Any]] ?? []).filter { !removed.contains($0["id"] as? String ?? "") }
        let revised = try G.decode(PlayScript.self, object)
        var record = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(p0)) as? [String: Any])
        if let other = c["range"] { record["range"] = other }
        let moved = try JSONDecoder().decode(Production.self, from: G.data(record))
        want(core.drifted(moved, revised), c["drifted"] as? Bool ?? false, c["name"] as? String ?? "drift")
    }
    let dropped = p0.droppingRange(whole: s)
    let droppedWant = G.json["dropped"] as? [String: Any] ?? [:]
    want([dropped.title, "\(dropped.range == nil)", "\(dropped.listenedThrough)", dropped.parts.keys.map(\.rawValue).sorted().joined(separator: ",")],
         [droppedWant["title"] as? String ?? "", "true", "\(droppedWant["listenedThrough"] as? Bool ?? true)", G.strings(droppedWant["parts"]).joined(separator: ",")],
         "dropped range")

    let old = (G.json["old"] as? [String: Any]) ?? [:]
    let record = try G.decode(Production.self, old["record"])
    let migrated = core.migrate(record)
    let fingerprint = old["fingerprint"] as? String ?? ""
    want([record.chosenFingerprint, migrated.chosenFingerprint, "\(migrated.format ?? 0)", "\(migrated.isFinished)"],
         [fingerprint, fingerprint, "2", "true"], "old record migrated, fingerprint unchanged")
    want(G.counted(core.scope(migrated, script).castParts), G.pairs(old["cast"]), "an old production is the whole play")
    want(Relay.listenPlan(migrated, script).count, script.lines.filter { $0.kind == .speech }.count, "an old production listens through the whole play")
    var newer = old["record"] as? [String: Any] ?? [:]
    newer["format"] = (G.json["tooNew"] as? [String: Any])?["format"]
    want(try G.decode(Production.self, newer).isTooNew, true, "a newer format is refused")
    want(migrated.isTooNew, false, "control: the current format is read")
    return bad
}

@Suite("A scene's range (PLAYS-DESIGN §2.12)")
struct ProductionRangeTests {
    @Test func theGoldenEveryPlatformRuns() throws {
        let bad = try rangeAnswers(RangeCore())
        #expect(bad.isEmpty, "\(bad.joined(separator: "; "))")
    }

    @Test func eachMutantOfTheCoreBreaksTheGolden() throws {
        for (name, core) in RangeCore.mutants {
            #expect(!(try rangeAnswers(core)).isEmpty, "mutant not caught: \(name)")
        }
    }

    @Test func aRangeProductionRecordsOnlyWhatItHolds() throws {
        let p = Production(script: try RangeGolden.script, range: try RangeGolden.range, heading: "Scene II")
        let data = try JSONEncoder().encode(p)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["format"] as? Int == 2 && (object["range"] as? [String: String]) == ["from": "L0003", "to": "L0006"])
        let whole = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Production(script: try RangeGolden.script))) as? [String: Any]
        #expect(whole?["range"] == nil, "a whole-play production has no range key")
        #expect(p.chosenFingerprint == Production(script: try RangeGolden.script).chosenFingerprint, "the range is never in the fingerprint")
        let unresolved = Production(script: try RangeGolden.script, range: ProductionRange(from: "L0006", to: "L0003"), heading: "x")
        #expect(unresolved.range == nil && unresolved.title == "Adelphi", "a range that does not resolve makes a whole-play production")
    }

    #if os(iOS) || os(macOS)
    @Test func theStoreKeepsANewerRecordUnlistedAndDropsADriftedRange() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "range-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProductionStore(root: root)
        let script = try RangeGolden.script
        var made = try store.create(script, range: try RangeGolden.range, heading: RangeGolden.heading)
        made.add(Take(id: "T3", lineID: "L0003", part: .role("DEMEA"), file: "T3.flac", created: .now, frames: 100, sampleRate: 48_000,
                      capture: .direct, heard: [:], loudness: nil, peak: 0, bleed: false))
        try store.save(made)
        #expect(store.script(for: made)?.lines.count == 4 && store.wholeScript(for: made)?.lines.count == 10)
        #expect(store.newest(of: script.id, range: try RangeGolden.range)?.id == made.id)
        #expect(store.newest(of: script.id, range: nil) == nil, "a whole-play door never reuses a scene's production")

        var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(made)) as? [String: Any])
        object["id"] = "newer"
        object["format"] = 3
        let newer = root.appending(path: "newer", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: newer, withIntermediateDirectories: true)
        let file = newer.appending(path: "production.json")
        let bytes = try JSONSerialization.data(withJSONObject: object)
        try bytes.write(to: file)

        var revised = RangeGolden.scriptObject
        revised["revision"] = "r2"
        revised["lines"] = (revised["lines"] as? [[String: Any]] ?? []).filter { $0["id"] as? String != "L0006" }
        try JSONEncoder().encode(try RangeGolden.decode(PlayScript.self, revised))
            .write(to: root.appending(path: made.id).appending(path: "script.json"))

        let again = ProductionStore(root: root)
        #expect(again.production("newer") == nil, "a newer record is not listed")
        #expect(try Data(contentsOf: file) == bytes, "and is not rewritten")
        let dropped = try #require(again.production(made.id))
        #expect(dropped.range == nil && dropped.title == "Adelphi" && !dropped.listenedThrough, "a drifted range is dropped and saved")
        #expect(again.droppedRanges.contains(made.id))
        again.acknowledgeDroppedRange(made.id)
        #expect(again.droppedRanges.isEmpty, "the cast sheet says so once")
        #expect(dropped.takes.map(\.id) == ["T3"], "its takes stay")
    }
    #endif
}
