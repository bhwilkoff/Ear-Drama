import Foundation

/// The Sound part without a view (B32 §3; iOS-DESIGN §4.15 "The sound board", macOS-DESIGN §4.7; Decision 091 on the
/// mix), the mirror of js/sound-core.js function for function: the slots a script offers (its cue rows, and any line a
/// person adds a sound to), the edits the board makes to the production's `sound` block, the pack manifest reader with
/// its rights gate, search, the cast sheet's words, and the cue schedule the live listen plays. Nothing here fills a
/// slot: a slot opens empty, and only the person's act puts a sound in it (§3.1 item 4). Tests: SoundBoardTests.
nonisolated enum SoundBoard {
    static let placements = SoundMix.placements
    static let fadesMs: [Double] = [0, 200, 500, 1000, 2000]
    static let bedFadeInMs = 1500.0
    static let bedFadeOutMs = 2000.0
    static let startStepMs = 100.0
    /// The rights gate (B32 §5.2): the only licenses a pack row may carry, and the hosts never taken from.
    static let licenses: [String: String] = ["CC0-1.0": "CC0", "PDM-1.0": "Public domain", "US-pre-1926": "Public domain"]
    static let refusedHosts = ["freesound.org", "sonniss.com", "bbcrewind.co.uk", "sound-effects.bbcrewind.co.uk"]
    /// Own sounds (§3.4): a recorded one up to 30 s; a brought file up to 10 minutes and 50 MB.
    static let ownRecordMaxSeconds = 30.0
    static let ownFileMaxSeconds = 600.0
    static let ownFileMaxBytes = 50 * 1024 * 1024

    /// `Math.round`: halves toward positive infinity, as js/sound-core.js rounds.
    static func jsRound(_ v: Double) -> Double { (v + 0.5).rounded(.down) }

    static func placementLabel(_ at: String) -> String {
        ["before": "Before", "under": "Under", "after": "After", "bed": "Bed"][at] ?? ""
    }

    // MARK: Slots

    /// One slot as the Sound part shows it: a cue row (with its record slot once touched) or an added slot.
    struct Slot: Equatable, Sendable, Identifiable {
        /// The record id when there is one, else the cue row's place ("L0180:1").
        let key: String
        let recordID: String?
        let line: String
        let piece: Int?
        let added: Bool
        let text: String
        let silent: Bool
        let sounds: [SoundCue]
        var id: String { key }
    }

    private static func lineIndex(_ script: PlayScript) -> [String: Int] {
        Dictionary(script.lines.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    static func recordSlots(_ p: Production) -> [SoundSlot] { p.sound?.slots ?? [] }

    private static func pieceText(_ line: ScriptLine, _ piece: Int?) -> String {
        guard let piece, let parts = line.parts, piece >= 0, piece < parts.count else { return "" }
        return parts[piece].text
    }

    private static func view(_ line: String, _ piece: Int?, _ added: Bool, _ text: String, _ s: SoundSlot?) -> Slot {
        Slot(key: s?.id ?? "\(line):\(piece.map(String.init) ?? "")", recordID: s?.id, line: line, piece: piece, added: added,
             text: text, silent: s?.silent ?? false, sounds: s?.sounds ?? [])
    }

    /// Every slot the Sound part shows, in script order: each cue row and every added slot.
    static func slots(_ script: PlayScript, _ p: Production) -> [Slot] {
        let at = lineIndex(script)
        let rec = recordSlots(p)
        var used = Set<String>()
        var out: [Slot] = []
        for row in script.cueRows {
            let s = rec.first { !$0.added && $0.line == row.line && $0.piece == row.piece }
            if let s { used.insert(s.id) }
            out.append(view(row.line, row.piece, false, row.text, s))
        }
        for s in rec where !used.contains(s.id) {
            guard let k = at[s.line] else { continue }
            out.append(view(s.line, s.piece, s.added, pieceText(script.lines[k], s.piece), s))
        }
        func order(_ x: Slot) -> Int { x.added ? 1_000_000_000 : (x.piece ?? -1) }
        return out.enumerated().sorted { a, b in
            let la = at[a.element.line] ?? 0, lb = at[b.element.line] ?? 0
            if la != lb { return la < lb }
            if order(a.element) != order(b.element) { return order(a.element) < order(b.element) }
            return a.offset < b.offset
        }.map(\.element)
    }

    static func emptyBlock() -> SoundBlock {
        SoundBlock(v: SoundMix.version, lanes: SoundLanes(effects: SoundLane(duckDb: SoundMix.effectsDuckDb),
                                                          music: SoundLane(duckDb: SoundMix.musicDuckDb)), slots: [])
    }

    /// The production with the slot in its record. A cue row's slot is written on first touch.
    static func ensure(_ p: Production, _ slot: Slot) -> (production: Production, id: String) {
        if let id = slot.recordID, recordSlots(p).contains(where: { $0.id == id }) { return (p, id) }
        var n = p
        if n.sound == nil { n.sound = emptyBlock() }
        let id = UUID().uuidString
        n.sound?.slots.append(SoundSlot(id: id, line: slot.line, piece: slot.piece, added: slot.added))
        return (n, id)
    }

    /// Add a sound here (§3.1 item 3): a slot at the line's end, or the one already there.
    static func addSlot(_ p: Production, line: String) -> (production: Production, id: String) {
        if let there = recordSlots(p).first(where: { $0.added && $0.line == line }) { return (p, there.id) }
        return ensure(p, Slot(key: "", recordID: nil, line: line, piece: nil, added: true, text: "", silent: false, sounds: []))
    }

    private static func edit(_ p: Production, _ slotID: String, _ body: (inout SoundSlot) -> Void) -> Production {
        guard let i = recordSlots(p).firstIndex(where: { $0.id == slotID }) else { return p }
        var n = p
        body(&n.sound!.slots[i])
        n.listenedThrough = false
        return n
    }

    /// Leave silent marks an empty slot done (§3.1 item 4); a slot holding a sound is never silent.
    static func setSilent(_ p: Production, _ slotID: String, _ on: Bool) -> Production {
        edit(p, slotID) { s in if !on || s.sounds.isEmpty { s.silent = on } }
    }

    /// Where a sound in a cue inside a speech starts by default (§3.3): Before a cue printed ahead of every said word,
    /// After one printed behind them all, else Under, at the share of the said words before it.
    static func defaultPlacement(_ script: PlayScript, line: String, piece: Int?, added: Bool) -> (at: String, share: Double) {
        guard let l = script.lines.first(where: { $0.id == line }), l.kind == .speech, let piece, !added, let parts = l.parts else {
            return ("after", 0)
        }
        func words(_ pc: LinePart) -> Int { pc.isSaid ? pc.text.split(whereSeparator: \.isWhitespace).count : 0 }
        let total = parts.reduce(0) { $0 + words($1) }
        let before = parts.prefix(max(0, min(piece, parts.count))).reduce(0) { $0 + words($1) }
        if total == 0 || before == 0 { return ("before", 0) }
        if before >= total { return ("after", 1) }
        return ("under", Double(before) / Double(total))
    }

    /// Adds a sound to a slot as the person chose it. `kind` is what the source says of itself; `take` the anchor line's
    /// chosen take when there is one (an Under start is its share of the take's length).
    static func addSound(_ p: Production, _ script: PlayScript, slotID: String, src: SoundSource, kind: String = "effect",
                         take: Take? = nil) -> (production: Production, id: String?) {
        guard let slot = recordSlots(p).first(where: { $0.id == slotID }) else { return (p, nil) }
        let id = UUID().uuidString
        let bed = kind == "music" || kind == "ambience"
        let def = defaultPlacement(script, line: slot.line, piece: slot.piece, added: slot.added)
        let at = bed && def.at != "under" ? "bed" : def.at
        var startMs = 0.0
        if at == "under", let take, take.sampleRate > 0 {
            startMs = jsRound(def.share * Double(take.frames) * 1000 / take.sampleRate / startStepMs) * startStepMs
        }
        var sound = SoundCue(id: id, src: src, at: at, startMs: startMs)
        if at == "bed" {
            sound.until = slot.line
            sound.fadeInMs = bedFadeInMs
            sound.fadeOutMs = bedFadeOutMs
            sound.loop = true
        }
        return (edit(p, slotID) { s in s.silent = false; s.sounds.append(sound) }, id)
    }

    /// The changes a board makes to one sound; nil leaves a field as it is (`duckDb` set to `.some(nil)` is the lane's).
    struct Patch: Sendable {
        var at: String?
        var startMs: Double?
        var gainDb: Double?
        var fadeInMs: Double?
        var fadeOutMs: Double?
        var loop: Bool?
        var duckDb: Double??
        var until: String?

        init(at: String? = nil, startMs: Double? = nil, gainDb: Double? = nil, fadeInMs: Double? = nil, fadeOutMs: Double? = nil,
             loop: Bool? = nil, duckDb: Double?? = nil, until: String? = nil) {
            self.at = at
            self.startMs = startMs
            self.gainDb = gainDb
            self.fadeInMs = fadeInMs
            self.fadeOutMs = fadeOutMs
            self.loop = loop
            self.duckDb = duckDb
            self.until = until
        }
    }

    private static func nearest(_ v: Double, _ list: [Double]) -> Double {
        list.reduce(list[0]) { abs($1 - v) < abs($0 - v) ? $1 : $0 }
    }

    /// One sound's settings changed, each held to what the board offers (§3.2 item 2).
    static func updateSound(_ p: Production, slotID: String, soundID: String, _ patch: Patch) -> Production {
        edit(p, slotID) { s in
            guard let i = s.sounds.firstIndex(where: { $0.id == soundID }) else { return }
            var x = s.sounds[i]
            if let at = patch.at, placements.contains(at), at != x.at {
                let was = x.at
                x.at = at
                if at == "bed" {
                    x.until = x.until ?? s.line
                    x.loop = true
                    x.fadeInMs = bedFadeInMs
                    x.fadeOutMs = bedFadeOutMs
                } else {
                    x.until = nil
                    if was == "bed" { x.loop = false; x.fadeInMs = 0; x.fadeOutMs = 0 }
                    if at != "under" { x.loop = false }
                }
            }
            if let v = patch.startMs { x.startMs = max(SoundMix.startMinMs, jsRound(v / startStepMs) * startStepMs) }
            if let v = patch.gainDb { x.gainDb = min(SoundMix.gainMaxDb, max(SoundMix.gainMinDb, jsRound(v))) }
            if let v = patch.fadeInMs { x.fadeInMs = nearest(v, x.at == "bed" ? fadesMs + [bedFadeInMs] : fadesMs) }
            if let v = patch.fadeOutMs { x.fadeOutMs = nearest(v, fadesMs) }
            if let v = patch.loop, x.at == "under" || x.at == "bed" { x.loop = v }
            if let d = patch.duckDb { x.duckDb = d.map { min(0, max(-60, jsRound($0))) } }
            if let u = patch.until, x.at == "bed" { x.until = u }
            s.sounds[i] = x
        }
    }

    static func removeSound(_ p: Production, slotID: String, soundID: String) -> Production {
        edit(p, slotID) { s in s.sounds.removeAll { $0.id == soundID } }
    }

    /// Record slots that hold nothing are dropped (an added slot is removed when left empty, §3.1 item 3); `keep` stays.
    static func prune(_ p: Production, keep: String? = nil) -> Production {
        let rec = recordSlots(p)
        let gone = Set(rec.filter { $0.id != keep && !$0.silent && $0.sounds.isEmpty }.map(\.id))
        guard !gone.isEmpty else { return p }
        var n = p
        n.sound?.slots = rec.filter { !gone.contains($0.id) }
        if n.sound?.slots.isEmpty == true { n.sound = nil }
        return n
    }

    /// A performed cue joins the production (B32 §3.1 item 6, round 3: a take like any line): kept as a take on the
    /// slot's line with `cue` naming the slot, never a line's chosen take, and placed in the slot.
    static func addPerformed(_ p: Production, _ script: PlayScript, slotID: String, take: Take) -> Production {
        var n = p
        var t = take
        t = Take(id: t.id, lineID: t.lineID, part: .sound, file: t.file, created: t.created, frames: t.frames,
                 sampleRate: t.sampleRate, capture: t.capture, heard: t.heard, loudness: t.loudness, peak: t.peak,
                 bleed: t.bleed, cue: slotID)
        n.takes.append(t)
        return addSound(n, script, slotID: slotID, src: .take(t.id)).production
    }

    // MARK: What the cast sheet and the dock say

    struct Summary: Equatable, Sendable {
        let cues: Int
        let chosen: Int
        let silent: Int
        let added: Int
        let beds: Int
        let sounds: Int
    }

    static func summary(_ script: PlayScript, _ p: Production) -> Summary {
        let all = slots(script, p)
        let cues = all.filter { !$0.added }
        let sounds = all.flatMap(\.sounds)
        return Summary(cues: cues.count, chosen: cues.filter { !$0.sounds.isEmpty }.count, silent: cues.filter(\.silent).count,
                       added: all.filter { $0.added && !$0.sounds.isEmpty }.count, beds: sounds.filter { $0.at == "bed" }.count,
                       sounds: sounds.count)
    }

    private static func count(_ n: Int, _ one: String, _ many: String) -> String {
        n == 1 ? "1 \(one)" : "\(n.formatted()) \(many)"
    }

    /// The Sound part's length on the cast sheet (§3.1 item 1): its cue rows, or Add sounds when the script prints none.
    static func cuesLength(_ n: Int) -> String { n == 0 ? "Add sounds" : count(n, "cue", "cues") }

    /// The Sound row's words on the cast sheet (§3.1 item 1): "9 of 12 cues · 2 beds".
    static func partLine(_ script: PlayScript, _ p: Production, taken: Bool) -> String {
        let m = summary(script, p)
        let beds = m.beds > 0 ? " · \(count(m.beds, "bed", "beds"))" : ""
        if m.cues == 0 { return m.sounds > 0 ? count(m.sounds, "sound", "sounds") + beds : "Add sounds" }
        let cues = count(m.cues, "cue", "cues")
        if !taken && m.sounds == 0 { return "\(cues) · none chosen" }
        return "\(m.chosen.formatted()) of \(cues)\(beds)"
    }

    /// Stage directions read by a person (§2 item 3): "6 of 22 recorded · the rest silent".
    static func directionsLine(_ script: PlayScript, _ p: Production) -> String {
        let lines = script.lines(for: .directions)
        let kept = lines.filter { p.usableTake(for: $0.id) != nil }.count
        let of = "\(kept.formatted()) of \(lines.count.formatted()) recorded"
        return kept < lines.count ? "\(of) · the rest silent" : of
    }

    /// "after the line · +0.0 s", the sound's place in words (§3.2 item 2).
    static func placeLine(_ x: SoundCue, untilLabel: String? = nil) -> String {
        if x.at == "bed" { return untilLabel.map { "bed to \($0)" } ?? "bed" }
        let start = "\(x.startMs < 0 ? "\u{2212}" : "+")\(String(format: "%.1f", abs(x.startMs) / 1000)) s"
        let words = ["before": "before the line", "under": "under the line", "after": "after the line"][x.at] ?? ""
        return "\(words) · \(start)"
    }

    static func clock(_ ms: Double) -> String {
        let s = Int(jsRound(ms / 1000))
        return "\(s / 60):\(String(format: "%02d", s % 60))"
    }

    /// The refusal for sounds this device lacks (B32 §7): "2 sounds are on another device: Owl at night, Gate creak."
    static func missingLine(_ names: [String]) -> String {
        let n = names.count
        return "\(n == 1 ? "1 sound is" : "\(n.formatted()) sounds are") on another device: \(names.joined(separator: ", "))."
    }

    // MARK: The pack (B32 §5.2)

    struct Category: Equatable, Sendable, Identifiable {
        let id: String
        let title: String
        let bytes: Int
    }

    struct PackCue: Equatable, Sendable, Identifiable {
        struct Source: Equatable, Sendable { let name: String; let page: String; let file: String?; let maker: String? }
        struct License: Equatable, Sendable { let id: String; let url: String?; let evidence: String; let checked: String }
        let id: String
        let title: String
        let category: String
        let tags: [String]
        let kind: String
        let ms: Double
        let loop: Bool
        let file: String
        let bytes: Int
        let sha256: String
        let lufs: Double?
        let peak: Double?
        let source: Source
        let license: License
    }

    struct Manifest: Equatable, Sendable {
        let pack: String
        let built: String?
        let categories: [Category]
        let cues: [PackCue]
        let refused: [(id: String?, why: String)]

        static func == (a: Manifest, b: Manifest) -> Bool {
            a.pack == b.pack && a.built == b.built && a.categories == b.categories && a.cues == b.cues
                && a.refused.map(\.why) == b.refused.map(\.why)
        }
    }

    enum ManifestError: Error, Equatable { case notAnObject, format(Int?), noPack }

    private static func host(_ s: String?) -> String {
        guard let s, let u = URL(string: s), let h = u.host else { return "" }
        return h.lowercased()
    }

    private static func httpURL(_ s: Any?) -> Bool {
        guard let s = s as? String, s.range(of: "^https?://", options: [.regularExpression, .caseInsensitive]) != nil else { return false }
        return !host(s).isEmpty
    }

    private static func refusedHost(_ s: String?) -> Bool {
        let h = host(s)
        return !h.isEmpty && refusedHosts.contains { h == $0 || h.hasSuffix("." + $0) }
    }

    private static func number(_ v: Any?) -> Double? {
        guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        return n.doubleValue
    }

    /// Reads `sounds.json`: the categories and every cue that passes the rights gate. A row whose license is not CC0-1.0,
    /// PDM-1.0 or US-pre-1926, that lacks an evidence URL or a checked date, comes from a refused host, or lacks its
    /// file, length or checksum, is never listed; `refused` names each with why. Throws on a format this client does
    /// not read.
    static func readManifest(_ data: Data) throws -> Manifest {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ManifestError.notAnObject }
        guard number(json["format"]) == 1 else { throw ManifestError.format(number(json["format"]).map { Int($0) }) }
        guard let pack = json["pack"] as? String, !pack.isEmpty else { throw ManifestError.noPack }
        let categories: [Category] = ((json["categories"] as? [Any]) ?? []).compactMap { c in
            guard let c = c as? [String: Any], let id = c["id"] as? String, let title = c["title"] as? String else { return nil }
            return Category(id: id, title: title, bytes: Int(number(c["bytes"]) ?? 0))
        }
        let cats = Set(categories.map(\.id))
        var cues: [PackCue] = []
        var refused: [(id: String?, why: String)] = []
        var seen = Set<String>()
        for raw in (json["cues"] as? [Any]) ?? [] {
            let c = raw as? [String: Any]
            if let why = refusal(c, cats, seen) {
                refused.append(((c?["id"] as? String).flatMap { $0.isEmpty ? nil : $0 }, why))
                continue
            }
            guard let c else { continue }
            let id = c["id"] as! String
            seen.insert(id)
            let src = c["source"] as! [String: Any]
            let lic = c["license"] as! [String: Any]
            let kind = c["kind"] as? String
            cues.append(PackCue(
                id: id, title: c["title"] as! String, category: c["category"] as! String,
                tags: ((c["tags"] as? [Any]) ?? []).map { String(describing: $0).lowercased() },
                kind: ["effect", "ambience", "music"].contains(kind ?? "") ? kind! : "effect", ms: number(c["ms"])!,
                loop: (c["loop"] as? Bool) ?? false, file: c["file"] as! String, bytes: Int(number(c["bytes"]) ?? 0),
                sha256: (c["sha256"] as! String).lowercased(), lufs: number(c["lufs"]), peak: number(c["peak"]),
                source: .init(name: src["name"] as! String, page: src["page"] as! String, file: src["file"] as? String,
                              maker: src["maker"] as? String),
                license: .init(id: lic["id"] as! String, url: lic["url"] as? String, evidence: lic["evidence"] as! String,
                               checked: lic["checked"] as! String)))
        }
        return Manifest(pack: pack, built: json["built"] as? String, categories: categories.filter { c in cues.contains { $0.category == c.id } },
                        cues: cues, refused: refused)
    }

    private static func refusal(_ c: [String: Any]?, _ cats: Set<String>, _ seen: Set<String>) -> String? {
        guard let c, let id = c["id"] as? String, !id.isEmpty else { return "no id" }
        if seen.contains(id) { return "a second row with this id" }
        guard let title = c["title"] as? String, !title.trimmingCharacters(in: .whitespaces).isEmpty else { return "no title" }
        guard let cat = c["category"] as? String, cats.contains(cat) else { return "no such category" }
        let lic = (c["license"] as? [String: Any]) ?? [:]
        guard let licID = lic["id"] as? String, licenses[licID] != nil else { return "license \((lic["id"] as? String) ?? "none")" }
        guard httpURL(lic["evidence"]) else { return "no evidence" }
        guard let checked = lic["checked"] as? String, checked.range(of: "^\\d{4}-\\d{2}-\\d{2}", options: .regularExpression) != nil else {
            return "no checked date"
        }
        let src = (c["source"] as? [String: Any]) ?? [:]
        guard let name = src["name"] as? String, !name.isEmpty, httpURL(src["page"]) else { return "no source page" }
        if [src["page"] as? String, src["file"] as? String, lic["evidence"] as? String].contains(where: { $0 != nil && refusedHost($0) }) {
            return "refused host \(host(src["page"] as? String))"
        }
        guard let file = c["file"] as? String, !file.isEmpty, !file.hasPrefix("/"), !file.contains("..") else { return "no file" }
        guard let sha = c["sha256"] as? String, sha.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil else {
            return "no checksum"
        }
        guard let ms = number(c["ms"]), ms > 0 else { return "no length" }
        return nil
    }

    static func licenseLabel(_ cue: PackCue) -> String { licenses[cue.license.id] ?? "" }

    /// "0:06 · OpenGameArt · CC0", or "0:38 loop · ..." (§3.2 item 5).
    static func cueLine(_ cue: PackCue) -> String {
        "\(clock(cue.ms))\(cue.loop ? " loop" : "") · \(cue.source.name) · \(licenseLabel(cue))"
    }

    static func megabytes(_ bytes: Int) -> String { String(format: "%.1f MB", Double(bytes) / 1_048_576) }

    private static func words(_ s: String) -> [String] {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX")).lowercased()
        var out: [String] = []
        var cur = ""
        for ch in folded.unicodeScalars {
            if ("a"..."z").contains(ch) || ("0"..."9").contains(ch) { cur.unicodeScalars.append(ch) } else if !cur.isEmpty { out.append(cur); cur = "" }
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    /// The search field's first words (§3.2 item 3): the first word of the cue that is a tag in the pack, else empty.
    static func seedQuery(_ text: String, cues: [PackCue]) -> String {
        let tags = Set(cues.flatMap(\.tags))
        for w in words(text) {
            if tags.contains(w) { return w }
            var one = w
            if one.hasSuffix("es") { one.removeLast(2) } else if one.hasSuffix("s") { one.removeLast() }
            if one != w && tags.contains(one) { return one }
            if w.hasSuffix("s"), tags.contains(String(w.dropLast())) { return String(w.dropLast()) }
        }
        return ""
    }

    /// Cues whose title or tags hold every word of the query (a word's start), in the pack's order; in one category when given.
    static func search(_ cues: [PackCue], _ query: String, category: String? = nil) -> [PackCue] {
        let q = words(query)
        return cues.filter { c in
            guard category == nil || c.category == category else { return false }
            let have = words(c.title) + c.tags.flatMap(words)
            return q.allSatisfy { w in have.contains { $0.hasPrefix(w) || (w.count > 3 && w.hasSuffix("s") && $0.hasPrefix(String(w.dropLast()))) } }
        }
    }

    /// Own sounds by name, the same way.
    static func searchMine(_ names: [(id: String, name: String)], _ query: String) -> [String] {
        let q = words(query)
        return names.filter { m in q.allSatisfy { w in words(m.name).contains { $0.hasPrefix(w) } } }.map(\.id)
    }

    /// The sources a block names, by kind.
    static func sources(_ p: Production) -> (pack: [String], own: [String], take: [String]) {
        var out: (pack: [String], own: [String], take: [String]) = ([], [], [])
        for s in recordSlots(p) {
            for x in s.sounds {
                switch x.src {
                case let .pack(_, cue): out.pack.append(cue)
                case let .own(id, _): out.own.append(id)
                case let .take(id): out.take.append(id)
                }
            }
        }
        return out
    }

    /// The block a published play may carry (§3.4 item 3): own sounds removed, slots left empty dropped.
    static func withoutOwn(_ block: SoundBlock?) -> SoundBlock? {
        guard var n = block else { return nil }
        n.slots = n.slots.map { s in
            var s = s
            s.sounds.removeAll { if case .own = $0.src { true } else { false } }
            return s
        }.filter { $0.silent || !$0.sounds.isEmpty }
        return n
    }

    // MARK: The live listen (§4.4: close, not sample-exact)

    struct LiveCue: Equatable, Sendable {
        let slot: SoundSlot
        let sound: SoundCue
    }

    struct EntryCues: Equatable, Sendable {
        var before: [LiveCue] = []
        var under: [LiveCue] = []
        var after: [LiveCue] = []
        /// The beds that end with this entry (their sound ids).
        var stop: [String] = []
        var isEmpty: Bool { before.isEmpty && under.isEmpty && after.isEmpty && stop.isEmpty }
    }

    /// For a listen plan, which sounds play at each entry: `before` its words (the line waits for them), `under` and
    /// `bed` from its start, `after` it (the next entry waits), and the beds that end with it (`stop`). A slot on a line
    /// the plan skips (a silent direction) plays with the next entry.
    static func listenCues(_ script: PlayScript, _ p: Production, plan: [ListenEntry]) -> [EntryCues] {
        let at = lineIndex(script)
        var out = plan.map { _ in EntryCues() }
        guard !plan.isEmpty else { return out }
        let entryAt = plan.map { at[$0.lineID] ?? -1 }
        func entryFor(_ line: String) -> Int {
            guard let k = at[line] else { return -1 }
            return entryAt.firstIndex { $0 >= k } ?? -1
        }
        func lastFor(_ line: String) -> Int {
            guard let k = at[line] else { return -1 }
            var j = -1
            for (i, x) in entryAt.enumerated() where x <= k { j = i }
            return j
        }
        guard let readable = try? SoundMix.readSound(p.sound) else { return out }
        for slot in readable.slots {
            guard at[slot.line] != nil else { continue }
            let i = entryFor(slot.line)
            let exact = i >= 0 && plan[i].lineID == slot.line
            for x in slot.sounds where placements.contains(x.at) {
                let cue = LiveCue(slot: slot, sound: x)
                if i < 0 { out[plan.count - 1].after.append(cue); continue }
                if !exact && (x.at == "after" || x.at == "under") { out[i].before.append(cue); continue }
                switch x.at {
                case "before": out[i].before.append(cue)
                case "after": out[i].after.append(cue)
                default: out[i].under.append(cue)
                }
                if x.at == "bed" {
                    let j = max(i, lastFor(x.until ?? slot.line))
                    out[j].stop.append(x.id)
                }
            }
        }
        return out
    }

    /// The plan entries Hear it in place plays (§3.2 item 2): from the entry before the slot's line to the one after it.
    static func inPlace(_ script: PlayScript, plan: [ListenEntry], line: String) -> ClosedRange<Int>? {
        guard !plan.isEmpty else { return nil }
        let at = lineIndex(script)
        let k = at[line] ?? 0
        var i = plan.firstIndex { (at[$0.lineID] ?? 0) >= k } ?? plan.count
        let exact = i < plan.count && plan[i].lineID == line
        let from = max(0, i - 1)
        if i >= plan.count { i = plan.count }
        let to = min(plan.count - 1, exact ? i + 1 : i)
        return from...max(from, to)
    }
}
