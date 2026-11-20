import Foundation

// The label (Decision 081, WEB-DESIGN 6.4r): the drawn art of anything without a picture, as a pure
// spec with no views, the web's `LabelCore.labelSpec` (js/label-core.js) with the same golden cases
// (catalog/tests/golden/label_spec.json). Every mark is a fact the item's published fields hold;
// nothing is hashed or random, and an undated show draws no arc. The geometry is design-tokens.json
// `art.label` (LabelTokens.swift is generated). Angles are degrees, 0 at three o'clock,
// counterclockwise positive; the dial runs clockwise, so an arc's `from` is larger than its `to`.
// Colors are token references (board.mystery, brand.text) that LabelView resolves.

nonisolated struct LabelItem: Sendable, Equatable {
    enum Kind: String, Sendable { case series, episode, station, drama, person, play }
    struct Part: Sendable, Equatable {
        var lines: Int
        var hue: String?
    }

    var kind: Kind = .series
    var name: String?
    var genre: String?
    var first: String?
    var last: String?
    var network: String?
    var tickYear: String?
    var date: String?
    var num: String?
    var parts: [Part] = []
    var finished: String?
    var voices: Int = 0
    var opening = false
    var cast: [Int] = []
}

nonisolated struct LabelSpec: Encodable, Equatable, Sendable {
    struct Disc: Encodable, Equatable, Sendable { var r: Double; var opacity: Double }
    struct Grooves: Encodable, Equatable, Sendable { var radii: [Double]; var width: Double; var opacity: Double }
    struct Ticks: Encodable, Equatable, Sendable { var r0, r1, width, opacity: Double; var deg: [Double] }
    struct Arc: Encodable, Equatable, Sendable {
        var r, width, from, to: Double
        var capFrom, capTo: String
    }
    struct Evening: Encodable, Equatable, Sendable { var deg, r0, r1, width: Double }
    struct Segment: Encodable, Equatable, Sendable { var from, to: Double; var color: String }
    struct Backing: Encodable, Equatable, Sendable { var color: String; var width: Double }
    struct Parts: Encodable, Equatable, Sendable { var r, width: Double; var backing: Backing; var segments: [Segment] }
    struct Ring: Encodable, Equatable, Sendable { var r, width, opacity: Double }
    struct Dot: Encodable, Equatable, Sendable { var r: Double }
    struct Text: Encodable, Equatable, Sendable {
        var s, face: String
        var size, x, y: Double
        var anchor, fill: String
    }
    struct Rim: Encodable, Equatable, Sendable {
        var text: String
        var r, size, tracking, opacity, centerDeg: Double
    }
    struct Rules: Encodable, Equatable, Sendable {
        var count: Int
        var x0, y, len, gap, width, opacity, foot: Double
    }
    struct Bar: Encodable, Equatable, Sendable { var x, y, w, h: Double }
    struct Cast: Encodable, Equatable, Sendable { var bars: [Bar] }

    var kind, shape, tier: String
    var viewBox: Double
    var ground, on: String
    var disc: Disc?
    var grooves: Grooves?
    var ticks: Ticks?
    var arc: Arc?
    var evening: Evening?
    var parts: Parts?
    var ring: Ring?
    var label: Dot?
    var text: [Text] = []
    var rim: Rim?
    var rules: Rules?
    var cast: Cast?

    /// A run arc or a part segment drawn all the way round.
    static func isFull(from: Double, to: Double) -> Bool { from - to >= 359.99 }
}

// MARK: - The spec

extension LabelSpec {
    private struct Node {
        let v: Any
        subscript(_ k: String) -> Node { Node(v: (v as? [String: Any])?[k] ?? 0) }
        func d(_ tier: String? = nil) -> Double {
            if let m = v as? [String: Any] { return (tier.flatMap { m[$0] } as? NSNumber)?.doubleValue ?? 0 }
            return (v as? NSNumber)?.doubleValue ?? 0
        }
        var s: String { v as? String ?? "" }
        var list: [Node] { (v as? [Any] ?? []).map { Node(v: $0) } }
        func glyph(_ ch: String) -> Double {
            let m = v as? [String: Any]
            return ((m?[ch] ?? m?["default"]) as? NSNumber)?.doubleValue ?? 0
        }
    }

    private static let T: Node = {
        let data = Data(LabelTokens.json.utf8)
        return Node(v: (try? JSONSerialization.jsonObject(with: data)) ?? [:])
    }()

    private static func r2(_ v: Double) -> Double { (v * 100 + 0.5).rounded(.down) / 100 }
    private static func tierOf(_ size: Double) -> String {
        size >= T["tiers"]["L"].d() ? "L" : size >= T["tiers"]["M"].d() ? "M" : "S"
    }
    private static func yearOf(_ d: String?) -> Int? {
        guard let d, d.count >= 4, d.prefix(4).allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(d.prefix(4))
    }
    private static func known(_ g: String?) -> Bool { g.map { LabelTokens.genres.contains($0) } ?? false }
    private static func groundOf(_ g: String?) -> String { known(g) ? "board.\(g!)" : T["colors"]["groundNone"].s }
    private static func onOf(_ g: String?) -> String { known(g) ? "onBoard.\(g!)" : T["colors"]["onNone"].s }

    // The dial: a year is one slot of sweepDeg / (to - from + 1) degrees, clockwise from startDeg.
    static var slot: Double { T["dial"]["sweepDeg"].d() / (T["dial"]["to"].d() - T["dial"]["from"].d() + 1) }
    static func yearDeg(_ y: Double) -> Double { T["dial"]["startDeg"].d() - (y - T["dial"]["from"].d()) * slot }
    private static func clampYear(_ y: Int) -> Double { min(T["dial"]["to"].d(), max(T["dial"]["from"].d(), Double(y))) }
    private static func offDial(_ y: Int) -> Bool { Double(y) < T["dial"]["from"].d() || Double(y) > T["dial"]["to"].d() }

    private static func runArc(_ first: String?, _ last: String?, r: Double, width: Double) -> Arc? {
        guard let a = yearOf(first) else { return nil }
        var b = yearOf(last) ?? a
        if b < a { b = a }
        return Arc(r: r, width: width, from: r2(yearDeg(clampYear(a))), to: r2(yearDeg(clampYear(b) + 1)),
                   capFrom: offDial(a) ? "butt" : "round", capTo: offDial(b) ? "butt" : "round")
    }

    // Text: a line's width from the glyph table, so every stack fits the same size.
    private static func em(_ s: String, _ face: String) -> Double {
        s.unicodeScalars.reduce(0.0) { $0 + T["glyphs"][face].glyph(String($1)) + T["glyphs"]["tracking"].d() }
    }
    private static func fit(_ s: String, _ face: String, _ maxW: Double, _ maxCap: Double) -> Double {
        min(maxCap / T["glyphs"][face]["cap"].d(), maxW / max(em(s, face), 0.01))
    }

    private struct Line { var s: String; var face: String }

    private static func centered(_ lines: [Line], boxW: Double, boxH: Double, fill: String) -> [Text] {
        let ls = lines.filter { !$0.s.isEmpty }
        let capOf = { (f: String) in T["glyphs"][f]["cap"].d() }
        if ls.isEmpty { return [] }
        if ls.count == 1 {
            let l = ls[0]
            let size = fit(l.s, l.face, boxW, boxH)
            return [Text(s: l.s, face: l.face, size: r2(size), x: 50, y: r2(50 + size * capOf(l.face) / 2), anchor: "middle", fill: fill)]
        }
        let sm = ls[0], bg = ls[1]
        let sSize = min(boxH * T["label"]["small"].d(), boxW / max(em(sm.s, sm.face), 0.01))
        let hs = sSize * capOf(sm.face), gap = hs * T["label"]["lead"].d()
        let bSize = fit(bg.s, bg.face, boxW, boxH - hs - gap)
        let hb = bSize * capOf(bg.face)
        let top = 50 - (hs + gap + hb) / 2
        return [Text(s: sm.s, face: sm.face, size: r2(sSize), x: 50, y: r2(top + hs), anchor: "middle", fill: fill),
                Text(s: bg.s, face: bg.face, size: r2(bSize), x: 50, y: r2(top + hs + gap + hb), anchor: "middle", fill: fill)]
    }

    private static let months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]

    /// "1942-12-22" as its year, month (0 when absent) and day (0 when absent).
    private static func ymd(_ s: String?) -> (y: String, mo: Int, day: Int)? {
        guard let s, yearOf(s) != nil else { return nil }
        let parts = s.split(separator: "-", omittingEmptySubsequences: false)
        func two(_ i: Int) -> Int {
            guard parts.count > i, parts[i].count >= 2, parts[i].prefix(2).allSatisfy({ $0.isASCII && $0.isNumber }) else { return 0 }
            return Int(parts[i].prefix(2)) ?? 0
        }
        let mo = two(1)
        return (String(s.prefix(4)), mo, mo > 0 ? two(2) : 0)
    }

    private static func episodeLines(_ date: String?, _ num: String?, _ tier: String) -> [Line]? {
        let m = ymd(date)
        let yy = m.map { "’" + $0.y.suffix(2) } ?? ""
        let hasNum = !(num ?? "").isEmpty
        if let m {
            if tier == "S" { return [Line(s: yy, face: "display")] }
            if (1...12).contains(m.mo), m.day > 0 { return [Line(s: "\(months[m.mo - 1]) \(yy)", face: "body"), Line(s: String(m.day), face: "display")] }
            if (1...12).contains(m.mo) { return [Line(s: yy, face: "body"), Line(s: months[m.mo - 1], face: "display")] }
            return [Line(s: m.y, face: "display")]
        }
        if hasNum, tier == "S" { return [Line(s: "No.\(num!)", face: "display")] }
        if hasNum { return [Line(s: "No.", face: "body"), Line(s: num!, face: "display")] }
        return nil
    }

    private static func rimOf(_ text: String?) -> Rim? {
        guard let text, !text.isEmpty else { return nil }
        let rim = T["rim"]
        let maxLen = Double.pi * rim["r"].d() * rim["maxSweepDeg"].d() / 180
        let perEm = em(text, "body") + Double(text.unicodeScalars.count) * rim["tracking"].d()
        return Rim(text: text, r: rim["r"].d(), size: r2(min(rim["size"].d(), maxLen / perEm)), tracking: rim["tracking"].d(),
                   opacity: rim["opacity"].d(), centerDeg: 90)
    }

    private static func decadeOf(_ first: String?) -> String? { yearOf(first).map { "\($0 / 10 * 10)s" } }

    private static func grooves(_ tier: String) -> Grooves? {
        if tier == "S" { return nil }
        let g = T["grooves"]
        let to = g["to"].d(tier), step = g["step"].d(tier)
        var radii: [Double] = []
        var i = 0.0
        while g["from"].d() + i * step <= to + 1e-9 { radii.append(r2(g["from"].d() + i * step)); i += 1 }
        return Grooves(radii: radii, width: g["width"].d(), opacity: g["opacity"].d())
    }

    private static func disc(_ it: LabelItem, _ tier: String, _ kind: LabelItem.Kind) -> LabelSpec {
        let g = known(it.genre) ? it.genre! : kind == .drama ? "drama" : ""
        let labelR = T["label"]["r"].d(tier)
        var spec = LabelSpec(kind: kind.rawValue, shape: "square", tier: tier, viewBox: T["viewBox"].d(), ground: groundOf(g), on: onOf(g),
                             disc: Disc(r: T["disc"]["r"].d(), opacity: T["disc"]["opacity"].d()), grooves: grooves(tier),
                             label: Dot(r: labelR))
        let dialed = kind != .drama
        if dialed, tier != "S" {
            let k = T["ticks"]
            spec.ticks = Ticks(r0: k["r0"].d(), r1: k["r1"].d(), width: k["width"].d(), opacity: k["opacity"].d(),
                               deg: T["dial"]["ticks"].list.map { r2(yearDeg($0.d())) })
        }
        if kind == .series || kind == .episode {
            spec.arc = runArc(it.first, it.last, r: T["arc"]["r"].d(tier), width: T["arc"]["width"].d(tier))
        }
        if dialed, let ty = yearOf(it.tickYear) {
            let e = T["evening"]
            spec.evening = Evening(deg: r2(yearDeg(clampYear(ty)) - slot / 2), r0: e["r0"].d(), r1: e["r1"].d(), width: e["width"].d(tier))
        }
        if kind == .drama {
            let ps = it.parts.filter { $0.lines > 0 }
            let total = Double(ps.reduce(0) { $0 + $1.lines })
            if !ps.isEmpty {
                let w = T["parts"]["width"].d(tier), gap = ps.count > 1 ? T["parts"]["gapDeg"].d() : 0
                var a = T["parts"]["startDeg"].d()
                let segs = ps.map { p -> Segment in
                    let d = Double(p.lines) / total * 360
                    let seg = Segment(from: r2(a), to: r2(a - max(d - gap, d / 2)),
                                      color: known(p.hue) ? "genre.\(p.hue!)" : T["colors"]["partNone"].s)
                    a -= d
                    return seg
                }
                spec.parts = Parts(r: T["parts"]["r"].d(tier), width: w,
                                   backing: Backing(color: T["colors"]["partsBacking"].s, width: r2(w + T["parts"]["backing"].d())), segments: segs)
            }
        }
        let box = 2 * labelR
        var lines = kind == .episode ? episodeLines(it.date, it.num, tier) : nil
        if lines == nil { lines = kind == .station && (it.name ?? "").isEmpty ? [] : [Line(s: Grammar.monogram(it.name), face: "display")] }
        spec.text = centered(lines ?? [], boxW: box * T["label"]["fitW"].d(), boxH: box * T["label"]["fitH"].d(), fill: "ground")
        if tier == "L" {
            if kind == .drama {
                if let m = ymd(it.finished), (1...12).contains(m.mo), (it.finished ?? "").count >= 7 {
                    spec.rim = rimOf("RECORDED · \(months[m.mo - 1]) \(m.y)")
                }
            } else if kind != .station {
                let words = [it.network.flatMap { $0.isEmpty ? nil : $0.uppercased() }, decadeOf(it.first)].compactMap { $0 }
                spec.rim = rimOf(words.joined(separator: " · "))
            }
        }
        return spec
    }

    private static func person(_ it: LabelItem, _ tier: String) -> LabelSpec {
        let g = known(it.genre) ? it.genre : nil
        let box = 2 * T["person"]["fitR"].d()
        let ring = T["person"]["ring"]
        return LabelSpec(kind: "person", shape: "circle", tier: tier, viewBox: T["viewBox"].d(), ground: groundOf(g), on: onOf(g),
                         arc: tier == "L" ? runArc(it.first, it.last, r: T["person"]["arc"]["r"].d(), width: T["person"]["arc"]["width"].d()) : nil,
                         ring: Ring(r: ring["r"].d(), width: ring["width"].d(tier), opacity: ring["opacity"].d()),
                         text: centered([Line(s: Grammar.monogram(it.name), face: "display")], boxW: box * T["label"]["fitW"].d(),
                                        boxH: box * T["label"]["fitH"].d(), fill: "on"))
    }

    private static func play(_ it: LabelItem, _ tier: String) -> LabelSpec {
        var base = LabelSpec(kind: "play", shape: "square", tier: tier, viewBox: T["viewBox"].d(), ground: "", on: "")
        let P = T["play"]
        if it.opening {
            let bands = P["bands"].list.map { $0.d() }
            let v = Double(it.voices)
            let count = v <= 0 ? 0 : v <= bands[0] ? 1 : v <= bands[1] ? 2 : v <= bands[2] ? 3 : 4
            let R = P["rule"]
            base.ground = T["colors"]["playGround"].s
            base.on = T["colors"]["playInk"].s
            if count > 0 {
                base.rules = Rules(count: count, x0: R["x0"].d(), y: R["y"].d(), len: R["len"].d(), gap: R["gap"].d(), width: R["width"].d(),
                                   opacity: R["opacity"].d(), foot: R["foot"].d())
            }
            return base
        }
        let C = P["cast"], g = P["board"].s
        let all = it.cast.filter { $0 > 0 }
        let shown = Array(all.prefix(Int(C["max"].d())))
        let most = Double(shown.first ?? 1)
        let total = shown.isEmpty ? 0 : C["hFirst"].d() + Double(shown.count - 1) * (C["h"].d() + C["gap"].d())
        var y = 50 - total / 2
        let bars = shown.enumerated().map { i, n -> Bar in
            let h = i > 0 ? C["h"].d() : C["hFirst"].d()
            let pct = max(C["minW"].d(), ((100 * Double(n)) / most).rounded(.toNearestOrAwayFromZero))
            let bar = Bar(x: C["x"].d(), y: r2(y), w: r2(C["w"].d() * pct / 100), h: h)
            y += h + C["gap"].d()
            return bar
        }
        let more = all.count - shown.count
        base.ground = groundOf(g)
        base.on = onOf(g)
        base.cast = bars.isEmpty ? nil : Cast(bars: bars)
        if more > 0 {
            let m = C["more"]
            base.text = [Text(s: "+\(more)", face: "body", size: m["size"].d(), x: m["x"].d(), y: m["y"].d(), anchor: "end", fill: "on")]
        }
        return base
    }

    /// What the label draws for `item` in a window `size` points on a side (the size picks the tier).
    static func make(_ item: LabelItem, size: Double) -> LabelSpec {
        let tier = tierOf(size)
        switch item.kind {
        case .person: return person(item, tier)
        case .play: return play(item, tier)
        default: return disc(item, tier, item.kind)
        }
    }
}
