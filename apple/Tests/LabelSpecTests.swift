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

    @Test func tiersFollowTheWindow() {
        #expect(LabelSpec.make(LabelItem(name: "A"), size: 95).tier == "S")
        #expect(LabelSpec.make(LabelItem(name: "A"), size: 96).tier == "M")
        #expect(LabelSpec.make(LabelItem(name: "A"), size: 320).tier == "L")
    }
}
