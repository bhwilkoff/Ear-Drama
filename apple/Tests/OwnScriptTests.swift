import Foundation
import Testing

// Own scripts (R4-1, Decision 088.3) in Swift, the port of js/own-core.test.js and OwnScriptTest.kt: every case of the
// three golden files (catalog/tests/golden/own_script_parse.json, own_script_ops.json, ear_cast_lines.json), each file's
// control found wrong, no word lost from any golden text, the caps, and the time budget.
//
// Time: the budget is 100 ms for 400 KB in a Release build on a Mac. This target runs unoptimized (-Onone), several
// times slower, so the test allows 1,500 ms in Debug and 100 ms when compiled with optimization; every hostile shape
// is held to 8 s in Debug and 2 s in Release. The 100 ms figure was measured separately in a Release build (the report
// of the session that added this file says what it was).
//
// Seen to fail, 2026-11-24, each mutation of OwnScript.swift run once then restored (a temporary script, not kept): a
// name printed once counting as a part (`seen >= 1`), mixed names needing four row starts, no established form, no NFC,
// a label with no words not waiting for them, titles read as whole names, COMMON words as parts, a column gap of four,
// a bracket closing mid-row, an exit that does not resume the speech, `_` dropped inside a word, Undo giving letters
// back, letters not following the numbered line, a cut inside an accent, keys not sorted, a shared script editable,
// words not lower-cased, abbreviations ending a sentence, times rounded up, and a left-out line settled as a part.

nonisolated private final class Checks {
    var failures: [String] = []
    func same(_ got: OwnJSON, _ want: OwnJSON, _ msg: String) {
        let g = OwnScript.canonicalLines(got), w = OwnScript.canonicalLines(want)
        if g != w { failures.append("\(msg)\n  want \(w.prefix(400))\n  got  \(g.prefix(400))") }
    }
    func equal<T: Equatable>(_ got: T, _ want: T, _ msg: String) {
        if got != want { failures.append("\(msg): want \(want), got \(got)") }
    }
    /// Unit-for-unit, so a canonically equivalent but different string is a failure.
    func units(_ got: String, _ want: String, _ msg: String) {
        if Array(got.utf16) != Array(want.utf16) { failures.append("\(msg): want \(want.unicodeScalars.map { String($0.value, radix: 16) }), got \(got.unicodeScalars.map { String($0.value, radix: 16) })") }
    }
}

nonisolated private enum OwnGolden {
    static let root: URL = {
        var dir = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("catalog/tests/golden/own_script_parse.json").path) { return dir }
            dir = dir.deletingLastPathComponent()
        }
        return URL(fileURLWithPath: ProcessInfo.processInfo.environment["EAR_DRAMA_ROOT"] ?? FileManager.default.currentDirectoryPath)
    }()

    static func load(_ name: String) -> [String: Any] {
        let data = (try? Data(contentsOf: root.appendingPathComponent("catalog/tests/golden/\(name)"))) ?? Data()
        return ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]
    }

    nonisolated(unsafe) static let parse = load("own_script_parse.json")
    nonisolated(unsafe) static let ops = load("own_script_ops.json")
    nonisolated(unsafe) static let ear = load("ear_cast_lines.json")
}

// MARK: JSON as plain data

nonisolated private func tree(_ v: Any?) -> OwnJSON {
    switch v {
    case nil, is NSNull: return .null
    case let s as String: return .string(s)
    case let a as [Any]: return .array(a.map(tree))
    case let o as [String: Any]: return .object(o.mapValues(tree))
    case let n as NSNumber:
        if String(cString: n.objCType) == "c" { return .bool(n.boolValue) }
        return .int(n.intValue)
    default: return .null
    }
}

nonisolated private func obj(_ v: Any?) -> [String: Any] { v as? [String: Any] ?? [:] }
nonisolated private func arr(_ v: Any?) -> [Any] { v as? [Any] ?? [] }
nonisolated private func str(_ v: Any?) -> String { v as? String ?? "" }
nonisolated private func opt(_ o: [String: Any], _ k: String) -> Any? { o[k] is NSNull ? nil : o[k] }
nonisolated private func int(_ v: Any?) -> Int { (v as? NSNumber)?.intValue ?? 0 }
nonisolated private func i64(_ v: Any?) -> Int64 { (v as? NSNumber)?.int64Value ?? 0 }
nonisolated private func bool(_ v: Any?) -> Bool { (v as? NSNumber)?.boolValue ?? false }

nonisolated private func spanIn(_ v: Any?) -> OwnSpan? {
    guard let a = v as? [Any], a.count == 2 else { return nil }
    return OwnSpan(start: i64(a[0]), end: i64(a[1]))
}

nonisolated private func spanOut(_ s: OwnSpan?) -> OwnJSON { s.map { .array([.int(Int($0.start)), .int(Int($0.end))]) } ?? .null }

nonisolated private func lineIn(_ o: [String: Any]) -> OwnLine {
    OwnLine(kind: str(o["kind"]), role: opt(o, "role") as? String, text: str(o["text"]), label: opt(o, "label") as? String, at: spanIn(opt(o, "at")))
}

nonisolated private func opIn(_ o: [String: Any]) -> OwnOp {
    let name = str(o["op"])
    var to: OwnTarget?
    if let t = opt(o, "to") {
        if let d = t as? [String: Any] { to = .role(str(d["role"])) } else { to = .kind(str(t)) }
    }
    return OwnOp(
        op: OwnOpKind(rawValue: name) ?? .unknown, line: opt(o, "line").map(int), at: opt(o, "at").map(int), text: str(opt(o, "text")),
        to: to, after: opt(o, "after").map(int), kind: str(opt(o, "kind")), role: str(opt(o, "role")), part: str(opt(o, "part")),
        rename: name == "rename" ? str(opt(o, "to")) : "")
}

nonisolated private func envIn(_ o: [String: Any]) -> OwnEnv {
    guard let e = opt(o, "env") as? [String: Any] else { return OwnEnv() }
    return OwnEnv(takes: Set(arr(e["takes"]).map { str($0) }), shared: bool(e["shared"]))
}

nonisolated private func lineOut(_ l: OwnLine, withKey: Bool = false) -> OwnJSON {
    var m: [String: OwnJSON] = ["kind": .string(l.kind), "text": .string(l.text)]
    if withKey { m["k"] = .int(l.k); m["id"] = l.id.map { .string($0) } ?? .null }
    if let r = l.role, !r.isEmpty { m["role"] = .string(r) }
    if let b = l.label, !b.isEmpty { m["label"] = .string(b) }
    return .object(m)
}

nonisolated private func refusalOut(_ r: OwnRefusal?) -> OwnJSON { r.map { .string($0.rawValue) } ?? .null }

// MARK: The golden runners

nonisolated private func runParseCase(_ c: [String: Any], _ k: Checks) {
    let r = OwnScript.parse(str(c["raw"]))
    k.same(
        .object(["lines": .array(r.lines.map { lineOut($0) }), "parts": .array(r.parts.map { .object(["name": .string($0.name), "lines": .int($0.lines)]) })]),
        tree(c["want"]), "\(str(c["layout"])): \(str(c["name"]))")
}

nonisolated private func runParse(_ k: Checks) {
    let g = OwnGolden.parse
    for c in arr(g["normalize"]) {
        let o = obj(c)
        k.units(OwnScript.normalize(str(o["raw"])), str(o["want"]), "normalize \(str(o["name"]))")
    }
    for c in arr(g["names"]) {
        let o = obj(c)
        let n = OwnScript.partName(str(o["raw"]))
        k.units(n, str(o["name"]), "name \(str(o["raw"]))")
        k.equal(OwnScript.partNameRefusal(n)?.rawValue, opt(o, "refusal") as? String, "name refusal \(str(o["raw"]))")
    }
    for c in arr(g["pieces"]) {
        let o = obj(c)
        let got = OwnScript.pieces(str(o["text"])).map { p -> OwnJSON in
            switch p {
            case .say(let t): return .object(["say": .string(t)])
            case .direction(let t): return .object(["direction": .string(t)])
            }
        }
        k.same(.array(got), tree(o["parts"]), "pieces of \(str(o["text"]))")
    }
    for c in arr(g["cases"]) { runParseCase(obj(c), k) }
}

nonisolated private func runSequence(_ c: [String: Any], _ k: Checks) {
    var doc = OwnScript.newDoc(arr(c["lines"]).map { lineIn(obj($0)) })
    var refusals: [OwnJSON] = []
    for st in arr(c["steps"]) {
        let s = obj(st)
        if str(s["op"]) == "done" { doc = OwnScript.done(doc, keepOpen: bool(opt(s, "keepOpen"))); refusals.append(.null); continue }
        let r = OwnScript.apply(doc, opIn(s), envIn(s))
        doc = r.doc
        refusals.append(refusalOut(r.refusal))
    }
    k.same(
        .object([
            "refusals": .array(refusals), "letters": .object(doc.letters.mapValues { .int($0) }), "undo": .int(doc.undo.count),
            "lines": .array(doc.lines.map { lineOut($0, withKey: true) }),
        ]), tree(c["want"]), str(c["name"]))
}

nonisolated private func runOps(_ k: Checks) {
    let g = OwnGolden.ops
    for c in arr(g["sequences"]) { runSequence(obj(c), k) }
    for c in arr(g["cut"]) {
        let o = obj(c)
        k.equal(OwnScript.cutAt(str(o["text"]), int(o["at"])), int(o["want"]), "cut \(str(o["text"])) at \(int(o["at"]))")
    }
    for c in arr(g["wordsChanged"]) {
        let o = obj(c)
        k.equal(OwnScript.wordsChanged(str(o["before"]), str(o["after"])), bool(o["want"]), "words changed \(o)")
    }
    for c in arr(g["nearest"]) {
        let o = obj(c)
        let lines = str(o["roles"]).map { r in r == "." ? OwnLine(kind: "open", text: "x") : OwnLine(kind: "speech", role: String(r), text: "x") }
        k.same(.array(OwnScript.nearestParts(lines, int(o["at"])).map { .string($0) }), tree(o["want"]), "nearest in \(str(o["roles"])) at \(int(o["at"]))")
    }
    let w = obj(g["letters"])
    var doc = OwnScript.done(OwnScript.newDoc([OwnLine(kind: "speech", role: "A", text: str(w["text"]))]))
    for _ in 0..<int(w["splits"]) {
        let t = doc.lines.first { $0.k == 1 }!.text
        let units = Array(t.utf16)
        let at = (units.lastIndex(of: 32) ?? -1) + 1
        doc = OwnScript.apply(doc, OwnOp(op: .split, line: 1, at: at)).doc
    }
    k.same(.array(doc.lines.map { $0.id.map { .string($0) } ?? .null }), tree(w["want"]), "letters past z")
    for c in arr(g["canonical"]) {
        let o = obj(c)
        k.equal(OwnScript.canonicalLines(tree(o["lines"])), str(o["json"]), "canonical JSON")
        k.equal(OwnScript.revisionOf(tree(o["lines"])), str(o["revision"]), "revision")
    }
    for c in arr(g["scripts"]) {
        let o = obj(c)
        var d = OwnScript.newDoc(OwnScript.parse(str(o["raw"])).lines)
        for st in arr(o["steps"]) { d = OwnScript.apply(d, opIn(obj(st))).doc }
        let want = obj(o["want"])
        let s = OwnScript.seal(OwnScript.toScript(OwnScript.done(d), OwnMeta(id: str(want["id"]), title: str(o["title"]))))
        k.same(s, tree(o["want"]), str(o["name"]))
        k.equal(OwnScript.refusalOf(s)?.rawValue, opt(o, "refusal") as? String, "\(str(o["name"])): may be kept")
    }
    for c in arr(g["built"]) {
        let o = obj(c)
        let text = String(repeating: str(o["unit"]), count: int(o["times"]))
        k.equal(OwnScript.textRefusal(text)?.rawValue, nil, "a text that may be read: \(str(o["name"]))")
        k.equal(OwnScript.builtRefusal(OwnScript.parse(text).lines)?.rawValue, opt(o, "want") as? String, "built: \(str(o["name"]))")
    }
    for c in arr(g["refusals"]) {
        let o = obj(c)
        k.equal(OwnScript.refusalOf(tree(o["script"]))?.rawValue, opt(o, "want") as? String, "refusal: \(str(o["name"]))")
    }
}

nonisolated private func castOut(_ d: OwnDoc) -> OwnJSON {
    let m = OwnScript.castOf(d)
    return .array(d.lines.map { l -> OwnJSON in
        switch m[l.k] ?? nil {
        case .out?: return .object(["out": .bool(true)])
        case .role(let n)?: return .object(["role": .string(n)])
        case nil: return .null
        }
    })
}

nonisolated private func runCast(_ c: [String: Any], _ k: Checks) {
    var d = OwnScript.fromCues(OwnScript.parseCues(str(OwnGolden.ear["vtt"])))
    var refusals: [OwnJSON] = []
    for st in arr(c["steps"]) {
        let s = obj(st)
        var r = OwnResult(doc: d, refusal: nil)
        if s["hear"] != nil { r = OwnResult(doc: OwnScript.hear(d, int(s["hear"]), from: int(s["from"])), refusal: nil) }
        else if s["tap"] != nil {
            let who: OwnWho = bool(opt(s, "out")) ? .out : .role(str(s["role"]))
            r = OwnScript.tap(d, int(s["tap"]), who, envIn(s))
        } else if s["leaveOut"] != nil { r = OwnScript.leaveOutHeard(d, int(s["leaveOut"]), envIn(s)) }
        else if s["undo"] != nil { r = OwnScript.apply(d, OwnOp(op: .undo)) }
        else if s["done"] != nil { r = OwnResult(doc: OwnScript.done(d, keepOpen: bool(opt(s, "keepOpen"))), refusal: nil) }
        else { r = OwnScript.apply(d, opIn(s), envIn(s)) }
        d = r.doc
        refusals.append(refusalOut(r.refusal))
    }
    let settled: [OwnJSON] = OwnScript.settle(d).lines.map { l in
        var m: [String: OwnJSON] = ["k": .int(l.k), "kind": .string(l.kind), "text": .string(l.text), "at": spanOut(l.at)]
        if let r = l.role, !r.isEmpty { m["role"] = .string(r) }
        return .object(m)
    }
    let count = OwnScript.castCount(d)
    k.same(
        .object(["refusals": .array(refusals), "cast": castOut(d), "count": .object(["cast": .int(count.cast), "lines": .int(count.lines)]), "settled": .array(settled)]),
        tree(c["want"]), str(c["name"]))
}

nonisolated private func runEar(_ k: Checks) {
    let g = OwnGolden.ear
    for c in arr(g["cues"]) {
        let o = obj(c)
        k.same(.array(OwnScript.parseCues(str(o["raw"])).map { .object(["text": .string($0.text), "at": spanOut($0.at)]) }), tree(o["want"]), "cues: \(str(o["name"]))")
    }
    for c in arr(g["sentences"]) {
        let o = obj(c)
        k.same(.array(OwnScript.fromCues([OwnCue(text: str(o["text"]), at: nil)]).lines.map { .string($0.text) }), tree(o["want"]), "sentences of \(str(o["text"]))")
    }
    for c in arr(g["times"]) {
        let o = obj(c)
        let cue = obj(o["cue"])
        let lines = OwnScript.fromCues([OwnCue(text: str(cue["text"]), at: spanIn(opt(cue, "at")))]).lines
        k.same(.array(lines.map { .object(["text": .string($0.text), "at": spanOut($0.at)]) }), tree(o["want"]), "times: \(str(o["name"]))")
    }
    let d = OwnScript.fromCues(OwnScript.parseCues(str(g["vtt"])))
    k.same(.array(d.lines.map { .object(["k": .int($0.k), "text": .string($0.text), "at": spanOut($0.at)]) }), tree(g["lines"]), "the lines of the transcript")
    for c in arr(g["lineAt"]) {
        let o = obj(c)
        k.equal(OwnScript.lineAt(d, i64(o["ms"])), int(o["want"]), "the line at \(i64(o["ms"]))")
    }
    for c in arr(g["casts"]) { runCast(obj(c), k) }
    var s = OwnScript.hear(OwnScript.tap(d, 1, .role("Dantro")).doc, 3, from: 1)
    s = OwnScript.hear(OwnScript.tap(s, 4, .role("Pat")).doc, 6, from: 4)
    s = OwnScript.done(OwnScript.tap(s, 6, .out).doc, keepOpen: true)
    let script = obj(g["script"])
    let ep = obj(script["episode"])
    let id = str(obj(obj(arr(OwnGolden.ops["scripts"])[0])["want"])["id"])
    k.same(OwnScript.seal(OwnScript.toScript(s, OwnMeta(id: id, title: "The Visit", episodeId: str(ep["id"]), episodeUrl: str(ep["url"])))), tree(script["want"]), "a half-cast transcript as a script")
}

// MARK: Time

nonisolated private func fill(_ unit: String, _ n: Int = OwnScript.maxBytes) -> String {
    let u = Array(unit.utf16)
    var out: [UInt16] = []
    out.reserveCapacity(n + u.count)
    while out.count < n { out.append(contentsOf: u) }
    return String(decoding: out[0..<n], as: UTF16.self)
}

nonisolated private func took(_ block: () -> Void) -> Double {
    let t = DispatchTime.now().uptimeNanoseconds
    block()
    return Double(DispatchTime.now().uptimeNanoseconds - t) / 1e6
}

#if DEBUG
nonisolated private let readBudgetMS = 2500.0
nonisolated private let hostileBudgetMS = 8000.0
#else
nonisolated private let readBudgetMS = 100.0
nonisolated private let hostileBudgetMS = 2000.0
#endif

nonisolated private func bare(_ s: String) -> [Int] {
    var out: [Int] = []
    for sc in s.unicodeScalars {
        switch sc.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter, .decimalNumber, .nonspacingMark, .spacingMark, .enclosingMark:
            out.append(Int(sc.value))
        default: break
        }
    }
    return out
}

struct OwnScriptTests {
    @Test func goldenOwnScriptParseEveryStack() {
        let g = OwnGolden.parse
        #expect(arr(g["cases"]).count >= 40, "40 pasted texts")
        #expect(Set(arr(g["cases"]).map { str(obj($0)["layout"]) }).count >= 8, "eight layouts")
        let k = Checks()
        runParse(k)
        #expect(k.failures.isEmpty, Comment(rawValue: k.failures.prefix(3).joined(separator: "\n")))
    }

    @Test func goldenOwnScriptOpsEveryStack() {
        let k = Checks()
        runOps(k)
        #expect(k.failures.isEmpty, Comment(rawValue: k.failures.prefix(3).joined(separator: "\n")))
    }

    @Test func goldenEarCastLinesEveryStack() {
        let k = Checks()
        runEar(k)
        #expect(k.failures.isEmpty, Comment(rawValue: k.failures.prefix(3).joined(separator: "\n")))
    }

    @Test func eachGoldenFilesControlIsFoundWrong() {
        let a = Checks(), b = Checks(), c = Checks()
        runParseCase(obj(OwnGolden.parse["control"]), a)
        runSequence(obj(OwnGolden.ops["control"]), b)
        runCast(obj(OwnGolden.ear["control"]), c)
        #expect(!a.failures.isEmpty, "own_script_parse control passed")
        #expect(!b.failures.isEmpty, "own_script_ops control passed")
        #expect(!c.failures.isEmpty, "ear_cast_lines control passed")
    }

    @Test func theHarnessSeesADriftInACanonicalCase() {
        let o = obj(arr(OwnGolden.ops["canonical"])[0])
        let k = Checks()
        k.equal(OwnScript.canonicalLines(tree(o["lines"])), str(o["json"]) + " ", "canonical JSON")
        #expect(!k.failures.isEmpty, "control: a changed byte must fail")
    }

    // MARK: Nothing is lost, nothing is written

    @Test func everyLetterAndDigitOfEveryGoldenTextIsInItsLinesInOrderAndNoOther() {
        for c in arr(OwnGolden.parse["cases"]) {
            let o = obj(c)
            let r = OwnScript.parse(str(o["raw"]))
            #expect(bare(r.text) == bare(r.lines.map { ($0.label ?? "") + $0.text }.joined()), "\(str(o["layout"])): \(str(o["name"]))")
        }
    }

    @Test func everyRowOfALineIsASliceOfTheNormalizedText() {
        for c in arr(OwnGolden.parse["cases"]) {
            let r = OwnScript.parse(str(obj(c)["raw"]))
            let text = Array(r.text.utf16)
            for l in r.lines {
                for row in l.text.split(separator: "\n", omittingEmptySubsequences: false).dropFirst() {
                    let ru = Array(row.utf16)
                    var found = ru.isEmpty
                    var i = 0
                    while !found && i + ru.count <= text.count { if Array(text[i..<(i + ru.count)]) == ru { found = true }; i += 1 }
                    #expect(found, Comment(rawValue: String(row)))
                }
            }
        }
    }

    @Test func aLoneSurrogateIsReplacementAndNothingThrowsOnIt() {
        #expect(OwnScript.normalize(units: [0x61, 0xd800, 0x62, 0xdc00, 0x63, 0xd83d, 0xde00]) == [0x61, 0xfffd, 0x62, 0xfffd, 0x63, 0xd83d, 0xde00])
        #expect(OwnScript.parse(units: Array("A".utf16) + [0xd800] + Array(": x\nB: y\nA".utf16) + [0xd800] + Array(": z\nB: w".utf16)).parts.count == 2)
    }

    @Test func unNormalizedTextIsNormalizedUnitForUnit() {
        let k = Checks()
        k.units(OwnScript.normalize("e\u{0301}"), "\u{00e9}", "NFC composes")
        k.units(OwnScript.normalize("\u{212A}"), "K", "the Kelvin sign is K")
        #expect(k.failures.isEmpty)
        #expect(Array(OwnScript.normalize("e\u{0301}").utf16) != Array("e\u{0301}".utf16), "control: Swift == would call these equal; units do not")
        #expect("e\u{0301}" == "\u{00e9}", "control: the trap itself")
    }

    @Test func piecesAndTextOfAreInverseOver20000MadeUpTexts() {
        let al = ["a", "B", " ", "(", ")", "[", "]", ".", "\n", "\u{00e9}"]
        var seed: UInt64 = 7
        func next(_ n: Int) -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int((seed >> 33) % UInt64(n)) }
        for _ in 0..<20000 {
            var s = ""
            for _ in 0..<(1 + next(14)) { s += al[next(al.count)] }
            s = OwnScript.trim(s)
            if !s.isEmpty {
                let p = OwnScript.pieces(s)
                #expect(p == OwnScript.pieces(OwnScript.textOf(p)), Comment(rawValue: s))
            }
        }
    }

    @Test func aKeptDocAndACopyOfAScriptGoOnWhereTheyWere() {
        var d = OwnScript.done(OwnScript.newDoc(OwnScript.parse("ANNA: One two.\nBEN: Three.\nANNA: Four.\nBEN: Five.").lines))
        d = OwnScript.apply(d, OwnOp(op: .split, line: 1, at: 4)).doc
        let again = OwnScript.kept(d)
        #expect(OwnScript.apply(again, OwnOp(op: .split, line: 2, at: 1)).refusal == nil)
        #expect(OwnScript.apply(again, OwnOp(op: .undo)).refusal == .nothing_to_undo)
        #expect(OwnScript.apply(again, OwnOp(op: .add, text: "x", after: 1, kind: "sound")).doc.lines[1].id == "L0001b")
        let id = "own-3f2b8c1e-5a7d-4e90-8b21-0c9d7e6f5a43"
        let s = OwnScript.toScript(d, OwnMeta(id: id, title: "T"))
        let copy = OwnScript.fromScript(s)
        #expect(OwnScript.apply(copy, OwnOp(op: .add, text: "x", after: 1, kind: "sound")).doc.lines[1].id == "L0001b")
        #expect(OwnScript.canonicalLines(s) == OwnScript.canonicalLines(OwnScript.toScript(copy, OwnMeta(id: id, title: "T"))))
    }

    @Test func undoKeepsReferencesNotCopies() {
        var d = OwnScript.newDoc(Array(repeating: OwnLine(kind: "speech", role: "A", text: "x y"), count: 3000))
        for _ in 0..<30 { d = OwnScript.apply(d, OwnOp(op: .words, line: 1, text: "q\(d.undo.count)")).doc }
        #expect(d.undo.count == 30)
        let ms = took { for _ in 0..<30 { d = OwnScript.apply(d, OwnOp(op: .undo)).doc } }
        #expect(d.undo.isEmpty)
        #expect(ms < hostileBudgetMS)
    }

    // MARK: Caps

    @Test func tooMuchIsRefusedTextLinesCanonicalBytes() {
        let max = OwnScript.maxBytes
        #expect(OwnScript.textRefusal(String(repeating: "a", count: max)) == nil)
        #expect(OwnScript.textRefusal(String(repeating: "a", count: max + 1)) == .too_long)
        #expect(OwnScript.textRefusal(String(repeating: "\u{00e9}", count: 200_001)) == .too_long)
        #expect(OwnScript.textRefusal(String(repeating: "\u{4e2d}", count: 133_333)) == nil)
        #expect(OwnScript.textRefusal(" \u{feff}\n\t") == .empty)
        #expect(OwnScript.utf8Length("a\u{00e9}\u{4e2d}\u{1F600}") == 10)
        let id = "own-3f2b8c1e-5a7d-4e90-8b21-0c9d7e6f5a43"
        func of(_ n: Int, _ text: String) -> OwnJSON {
            OwnScript.toScript(OwnScript.done(OwnScript.newDoc(Array(repeating: OwnLine(kind: "speech", role: "A", text: text), count: n))), OwnMeta(id: id, title: "T"))
        }
        #expect(OwnScript.refusalOf(of(6001, "x")) == .too_many_lines)
        #expect(OwnScript.refusalOf(of(1, String(repeating: "x", count: 399_900))) == nil)
        #expect(OwnScript.refusalOf(of(1, String(repeating: "x", count: 400_000))) == .too_long)
        let full = OwnScript.newDoc(Array(repeating: OwnLine(kind: "speech", role: "A", text: "x y"), count: 6000))
        #expect(OwnScript.apply(full, OwnOp(op: .split, line: 1, at: 1)).refusal == .too_many_lines)
        #expect(OwnScript.apply(full, OwnOp(op: .add, text: "x", after: 1, kind: "sound")).refusal == .too_many_lines)
        #expect(OwnScript.maxLines == 6000)
        #expect(OwnScript.maxPartName == 40)
        #expect(OwnScript.maxTitle == 300)
        let most = OwnScript.toScript(OwnScript.done(OwnScript.newDoc((0..<6000).map { OwnLine(kind: "speech", role: String(repeating: "A", count: 40), text: "w\($0)") })), OwnMeta(id: id, title: "T"))
        if case .array(let ls)? = most["lines"] { #expect(ls[5999]["id"] == .string("L6000")) } else { Issue.record("no lines") }
        #expect(OwnScript.refusalOf(most) == .too_long)
        #expect(OwnScript.partNameRefusal(String(repeating: "A", count: 41)) == .too_long)
        #expect(OwnScript.partNameRefusal(String(repeating: "A", count: 40)) == nil)
        #expect(OwnScript.refusalOf(.object(["id": .string(id), "title": .string(String(repeating: "t", count: 301)), "lines": .array([])])) == .title_too_long)
    }

    @Test func aGermanSharpSIsUppercasedWithNoLocaleAndCappedAfter() {
        #expect(OwnScript.partName("stra\u{00df}e") == "STRASSE")
        #expect(OwnScript.partName("i") == "I", "no Turkish dotted capital")
        #expect(OwnScript.partNameRefusal(OwnScript.partName(String(repeating: "\u{00df}", count: 21))) == .too_long, "grows past 40 after uppercasing")
    }

    // MARK: Hostile shapes and time

    @Test func fourHundredKBOfScriptIsReadInTime() {
        let text = fill("ANNA: The lamp has gone out again, and there is no oil (she looks for it).\n\nBEN. We could light the candle\nfrom the stove.\n\nIt would be a small light, but a light.\n\nANNA\nSo be it.\n\n")
        for _ in 0..<2 { _ = OwnScript.parse(text) }
        let best = (1...5).map { _ in took { _ = OwnScript.parse(text) } }.min()!
        print("OwnScript 400 KB parse best of 5: \(best) ms (budget \(readBudgetMS))")
        #expect(best < readBudgetMS, "\(best) ms")
    }

    @Test func noTextMakesItSlow400KBOfEachHostileShapeEachInTime() {
        let shapes = [
            "(", "[", "(a\n", "(a\n\n", "[a\n", "([", "((a", "A" + String(repeating: " ", count: 5000) + "x", "A ", "A. ", "A:", "A: ", ":", ".", "_", "*", "**a", "-",
            "A (b [c ", "MR. ", "ABCDE FGHI\n", "A\t", "A   b\n", "@A:\n", "\r", "e\u{0301}\u{0301}", "\u{1F469}\u{200D}", "Aaa. Bbb\n",
            "Exit\n", "SOUND ", "ACT ", "END OF ", "A(", "A,(", "A.(", "A.B.",
        ]
        for s in shapes {
            let text = fill(s)
            let ms = took { _ = OwnScript.parse(text); _ = OwnScript.pieces(text); _ = OwnScript.cutAt(text, 200_000); _ = OwnScript.wordsChanged(text, text) }
            #expect(ms < hostileBudgetMS, Comment(rawValue: "\(s.prefix(12)): \(ms) ms"))
        }
        for s in ["<", "-->\n", "<a", "&amp;", "00:01.000 --> 00:02.000\nHi. There.\n\n", "Mr. A. B? \"C\" ", "1:"] {
            let ms = took { _ = OwnScript.fromCues(OwnScript.parseCues(fill(s))) }
            #expect(ms < hostileBudgetMS, Comment(rawValue: "cues \(s.prefix(12)): \(ms) ms"))
        }
    }

    @Test func aLoneSurrogateShapeIsReadInTime() {
        let unit: [UInt16] = [0xd800]
        let ms = took { _ = OwnScript.parse(units: Array(repeating: unit[0], count: OwnScript.maxBytes)) }
        #expect(ms < hostileBudgetMS)
    }
}
