import Foundation
import Testing

/// The label's Swift port held to the web's own cases: catalog/tests/golden/label_spec.json is the
/// contract every stack reads straight from the repo (js/label.test.js, LabelSpecTest.kt). Numbers
/// match within the file's tolerance; strings, nulls and array lengths exactly; an absent key and a
/// null are the same.
///
/// Negative control, 2026-11-19: art.label.arc.width.L 3.5 -> 3.6 in LabelTokens.swift failed
/// "series, long run, rim at L (Suspense)" and "episode ..." cases; `theComparatorSeesADifference` fails
/// when the comparator stops looking.
struct LabelSpecTests {
    private static let golden: [String: Any] = {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("catalog/tests/golden/label_spec.json")
        let data = (try? Data(contentsOf: url)) ?? Data()
        return ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]
    }()

    private static var cases: [[String: Any]] { golden["cases"] as? [[String: Any]] ?? [] }
    /// B31 2.1's play page label, every tier, the twelve frame plays (js/label.test.js runs the same).
    private static var pageCases: [[String: Any]] { (golden["playPage"] as? [String: Any])?["cases"] as? [[String: Any]] ?? [] }
    private static var tolerance: Double { (golden["tolerance"] as? NSNumber)?.doubleValue ?? 0.01 }

    private static func string(_ v: Any?) -> String? {
        switch v {
        case let s as String: s
        case let n as NSNumber: n.stringValue
        default: nil
        }
    }

    private static func item(_ o: [String: Any]) -> LabelItem {
        var it = LabelItem()
        it.kind = LabelItem.Kind(rawValue: o["kind"] as? String ?? "series") ?? .series
        it.name = o["name"] as? String
        it.genre = o["genre"] as? String
        it.first = string(o["first"])
        it.last = string(o["last"])
        it.network = o["network"] as? String
        it.tickYear = string(o["tickYear"])
        it.date = string(o["date"])
        it.num = string(o["num"])
        it.finished = o["finished"] as? String
        it.voices = (o["voices"] as? NSNumber)?.intValue ?? 0
        it.opening = o["opening"] as? Bool ?? false
        it.cast = (o["cast"] as? [NSNumber])?.map(\.intValue) ?? []
        it.parts = (o["parts"] as? [[String: Any]] ?? []).map {
            LabelItem.Part(lines: ($0["lines"] as? NSNumber)?.intValue ?? 0, hue: $0["hue"] as? String)
        }
        it.author = o["author"] as? String
        it.hue = o["hue"] as? String
        it.era = o["era"] as? String
        if let life = o["life"] as? [String: Any] {
            it.life = LabelItem.Life(born: (life["born"] as? NSNumber)?.intValue, died: (life["died"] as? NSNumber)?.intValue)
        }
        return it
    }

    private static func json(_ spec: LabelSpec) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(spec))
    }

    /// The first difference between `got` and `want`, as a path and the two values; nil when equal.
    static func difference(_ got: Any?, _ want: Any?, _ path: String = "$", tolerance: Double) -> String? {
        let g = got is NSNull ? nil : got, w = want is NSNull ? nil : want
        switch (g, w) {
        case (nil, nil): return nil
        case let (g as [String: Any], w as [String: Any]):
            for key in Set(g.keys).union(w.keys).sorted() {
                if let d = difference(g[key], w[key], "\(path).\(key)", tolerance: tolerance) { return d }
            }
            return nil
        case let (g as [Any], w as [Any]):
            if g.count != w.count { return "\(path): \(g.count) items, wanted \(w.count)" }
            for (i, pair) in zip(g, w).enumerated() {
                if let d = difference(pair.0, pair.1, "\(path)[\(i)]", tolerance: tolerance) { return d }
            }
            return nil
        case let (g as String, w as String): return g == w ? nil : "\(path): \(g), wanted \(w)"
        case let (g as NSNumber, w as NSNumber):
            return abs(g.doubleValue - w.doubleValue) <= tolerance ? nil : "\(path): \(g), wanted \(w)"
        default: return "\(path): \(String(describing: g)), wanted \(String(describing: w))"
        }
    }

    @Test func goldenFileIsThere() {
        #expect(Self.cases.count >= 36, "label_spec.json was not read from the repo")
    }

    @Test func everyGoldenCaseMatches() throws {
        for c in Self.cases {
            let name = c["name"] as? String ?? "?"
            let spec = LabelSpec.make(Self.item(c["item"] as? [String: Any] ?? [:]), size: (c["size"] as? NSNumber)?.doubleValue ?? 0)
            let miss = Self.difference(try Self.json(spec), c["want"], tolerance: Self.tolerance)
            #expect(miss == nil, "\(name): \(miss ?? "")")
        }
    }

    private static func pageMisses(_ make: (LabelItem, Double) -> LabelSpec = { LabelSpec.make($0, size: $1) }) throws -> [String] {
        try pageCases.compactMap { c in
            let spec = make(item(c["item"] as? [String: Any] ?? [:]), (c["size"] as? NSNumber)?.doubleValue ?? 0)
            return difference(try json(spec), c["want"], tolerance: tolerance).map { "\(c["name"] as? String ?? "?"): \($0)" }
        }
    }

    @Test func everyPlayPageCaseMatches() throws {
        #expect(Self.pageCases.count >= 20, "the playPage cases were not read")
        let misses = try Self.pageMisses()
        #expect(misses.isEmpty, "\(misses.prefix(3).joined(separator: "\n"))")
        let tiers = Set(Self.pageCases.compactMap { ($0["want"] as? [String: Any])?["tier"] as? String })
        #expect(tiers == ["S", "M", "L"])
    }

    /// Negative controls: a page with no rest column, and one whose ruler forgets the era, fail the goldens.
    @Test func thePlayPageGoldensSeeAMutant() throws {
        let noRest = try Self.pageMisses { item, size in
            var spec = LabelSpec.make(item, size: size)
            if let cols = spec.cols { spec.cols?.bars = cols.bars.map { var b = $0; b.rest = false; return b } }
            return spec
        }
        #expect(!noRest.isEmpty, "a page with no rest column passed every golden")
        let unlit = try Self.pageMisses { item, size in
            var spec = LabelSpec.make(item, size: size)
            spec.ruler?.lit = -1
            return spec
        }
        #expect(!unlit.isEmpty, "a ruler with no lit cell passed every golden")
    }

    @Test func thePlayPageKeepsItsColumnsOnThePage() {
        for (size, most) in [(56.0, 6), (128.0, 10), (360.0, 12)] {
            for n in [1, 2, most, most + 1, 67] {
                let cast = (0..<n).map { 100 - $0 }
                let bars = LabelSpec.make(LabelItem(kind: .play, name: "Peter Pan", cast: cast), size: size).cols?.bars ?? []
                #expect(bars.count == min(n, most), "\(n) parts at \(size)")
                #expect(bars.filter(\.rest).count == (n > most ? 1 : 0), "\(n) parts at \(size): the rest column")
                #expect((bars.last.map { $0.x + $0.w } ?? 0) <= 91.01, "\(n) parts at \(size): a column past the page")
            }
        }
        #expect(LabelSpec.surnameOf("Lucius Annaeus Seneca Jr.") == "SENECA")
        #expect(LabelSpec.lifeOf(.init(born: -447, died: -386)) == "447-386 BCE")
        #expect(LabelSpec.make(LabelItem(kind: .play, name: "X", hue: "comedy"), size: 128).ground == "board.comedy")
        #expect(LabelSpec.make(LabelItem(kind: .play, name: "X"), size: 128).ground == "brand.surfaceAlt")
    }

    @Test func theComparatorSeesADifference() throws {
        let c = try #require(Self.cases.first)
        let spec = LabelSpec.make(Self.item(c["item"] as? [String: Any] ?? [:]), size: 360)
        var drifted = spec
        drifted.arc?.width += 0.5
        #expect(Self.difference(try Self.json(drifted), c["want"], tolerance: Self.tolerance) != nil)
        var rimless = spec
        rimless.rim = nil
        #expect(Self.difference(try Self.json(rimless), c["want"], tolerance: Self.tolerance) != nil)
    }

    /// js/label.test.js's twin: a play's "+N" never stands on its bars, and the bars keep their shares.
    ///   Broken control: the room ignored (`more > 99`): the 58-part cast's bars ran under its "+51".
    @Test func aPlaysMoreNeverStandsOnItsBars() throws {
        let casts: [[Int]] = [Array(repeating: 8, count: 58), Array(repeating: 3, count: 120), [40, 38, 36, 30, 28, 27, 26, 25, 1], [9, 9, 9, 9, 9, 9, 9, 1]]
        for cast in casts {
            let spec = LabelSpec.make(LabelItem(kind: .play, voices: cast.count, cast: cast), size: 48)
            let t = try #require(spec.text.first), bars = try #require(spec.cast?.bars), last = try #require(bars.last)
            let left = t.x - t.size * LabelSpec.em(t.s, "body")
            #expect(last.x + last.w <= left + 0.01, "+\(cast.count - 7) on its bars")
            for (i, b) in bars.enumerated() {
                let want = (100 * Double(cast[i]) / Double(cast[0])).rounded() / 100
                #expect(abs(b.w / bars[0].w - want) < 0.01, "bar \(i)'s share")
            }
        }
        let fits = LabelSpec.make(LabelItem(kind: .play, voices: 3, cast: [30, 20, 10]), size: 48)
        #expect(fits.cast?.bars.first?.w == 76, "a cast that fits draws full width")
    }

    @Test func tiersFollowTheWindow() {
        #expect(LabelSpec.make(LabelItem(name: "A"), size: 95).tier == "S")
        #expect(LabelSpec.make(LabelItem(name: "A"), size: 96).tier == "M")
        #expect(LabelSpec.make(LabelItem(name: "A"), size: 320).tier == "L")
    }
}
