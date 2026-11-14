import Foundation

// Record's library (iOS-DESIGN §4.14, Decision 075; the web's js/plays-core.js): a play's voices and
// length from its own record, the three facets and the sort, and Today's play. The same rules, in the
// same words, on every platform; `catalog/tests/golden/todays_play.json` holds the pick.

nonisolated enum VoiceBand: String, CaseIterable, Sendable {
    case oneTwo = "1-2", threeFive = "3-5", sixTen = "6-10", elevenPlus = "11+"

    var title: String {
        switch self {
        case .oneTwo: "1 or 2 voices"
        case .threeFive: "3 to 5 voices"
        case .sixTen: "6 to 10 voices"
        case .elevenPlus: "11 or more voices"
        }
    }

    static func of(_ voices: Int) -> VoiceBand? {
        switch voices {
        case 1...2: .oneTwo
        case 3...5: .threeFive
        case 6...10: .sixTen
        case 11...: .elevenPlus
        default: nil
        }
    }
}

nonisolated enum LengthBand: String, CaseIterable, Sendable {
    case short, mid, long

    var title: String {
        switch self {
        case .short: "Under 30 min"
        case .mid: "30 to 60 min"
        case .long: "Over an hour"
        }
    }

    static func of(_ minutes: Int) -> LengthBand? {
        switch minutes {
        case ...29: .short
        case 30...60: .mid
        case 61...: .long
        default: nil
        }
    }
}

nonisolated enum PlayKindFacet: String, CaseIterable, Sendable {
    case radio, stage
    var title: String { self == .radio ? "Radio play" : "Stage play" }
}

nonisolated enum PlaySort: String, CaseIterable, Sendable {
    case voices, short, name

    var title: String {
        switch self {
        case .voices: "Fewest voices first"
        case .short: "Shortest first"
        case .name: "A to Z"
        }
    }

    /// The chip's label, which has to fit a 375 pt phone beside the other chips.
    var chipTitle: String {
        switch self {
        case .voices: "Fewest voices"
        case .short: "Shortest"
        case .name: "A to Z"
        }
    }
}

nonisolated extension PlayScript {
    /// Words a minute for a play's length: speech read aloud. A length is "About N min", never exact.
    static let wordsPerMinute = 150

    /// Speaking parts.
    var voices: Int {
        roles.isEmpty ? castParts.filter { $0.id.isSpeaking }.count : roles.count
    }

    /// Minutes from the words its parts speak, at least 1.
    var minutes: Int {
        let words = roles.reduce(0) { $0 + $1.words }
        return max(1, Int((Double(words) / Double(Self.wordsPerMinute)).rounded()))
    }

    var voiceBand: VoiceBand? { VoiceBand.of(voices) }
    var lengthBand: LengthBand? { LengthBand.of(minutes) }
    var kindFacet: PlayKindFacet? { PlayKindFacet(rawValue: kind) }

    static func todaysPlay(_ scripts: [PlayScript], dateKey: String) -> PlayScript? {
        PlayBrowse.todaysPlay(scripts, dateKey: dateKey)
    }

    /// "3 voices", "About 30 min": the two facts a play tile says.
    var voicesText: String { voices == 1 ? "1 voice" : "\(voices.formatted()) voices" }
    var minutesText: String { "About \(minutes.formatted()) min" }

    /// The speaking parts the cast window draws: largest first, at most seven, and how many more there are.
    var castWindowBars: (shown: [CastPart], more: Int) {
        let speaking = castParts.filter { $0.id.isSpeaking }
        return (Array(speaking.prefix(7)), max(0, speaking.count - 7))
    }
}

/// A person's choice on Record: the three facets and the order.
nonisolated struct PlayFilter: Equatable, Sendable {
    var voices: VoiceBand?
    var length: LengthBand?
    var kind: PlayKindFacet?
    var sort: PlaySort = .voices

    var isFiltered: Bool { voices != nil || length != nil || kind != nil }
    var cleared: PlayFilter { PlayFilter(sort: sort) }
}

nonisolated enum PlayBrowse {
    enum Facet: Sendable { case voices, length, kind }

    /// Whether a play passes the filter, leaving out `skip`, so a facet's own counts ignore its own choice.
    static func keeps(_ s: PlayScript, _ f: PlayFilter, skip: Facet? = nil) -> Bool {
        (skip == .voices || f.voices == nil || s.voiceBand == f.voices)
            && (skip == .length || f.length == nil || s.lengthBand == f.length)
            && (skip == .kind || f.kind == nil || s.kindFacet == f.kind)
    }

    private static func byName(_ a: PlayScript, _ b: PlayScript) -> Bool {
        let ka = a.sortName ?? a.title, kb = b.sortName ?? b.title
        let c = ka.compare(kb, options: [.caseInsensitive, .diacriticInsensitive], range: nil, locale: Locale(identifier: "en"))
        return c == .orderedSame ? a.id < b.id : c == .orderedAscending
    }

    static func list(_ scripts: [PlayScript], _ f: PlayFilter) -> [PlayScript] {
        let kept = scripts.filter { keeps($0, f) }
        switch f.sort {
        case .voices:
            return kept.sorted { $0.voices != $1.voices ? $0.voices < $1.voices : byName($0, $1) }
        case .short:
            return kept.sorted { $0.minutes != $1.minutes ? $0.minutes < $1.minutes : byName($0, $1) }
        case .name:
            return kept.sorted(by: byName)
        }
    }

    /// How many plays a facet's option would leave, with the other two facets applied.
    static func count(_ scripts: [PlayScript], _ f: PlayFilter, facet: Facet, matching: (PlayScript) -> Bool) -> Int {
        scripts.filter { keeps($0, f, skip: facet) && matching($0) }.count
    }

    static func fnv1a64(_ text: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            h ^= UInt64(byte)
            h = h &* 0x100000001b3
        }
        return h
    }

    /// Today's play (WEB-DESIGN §4.2): the script whose FNV-1a 64 of "play:{YYYY-MM-DD}:{id}" is smallest,
    /// ties by id, on the person's own calendar date. Order-independent, so every platform with the same
    /// library and date picks the same play. Nil for an empty library.
    static func todaysPlay(_ scripts: [PlayScript], dateKey: String) -> PlayScript? {
        var best: PlayScript?
        var bestHash: UInt64 = 0
        for script in scripts {
            let h = fnv1a64("play:\(dateKey):\(script.id)")
            if best == nil || h < bestHash || (h == bestHash && script.id < best!.id) {
                best = script
                bestHash = h
            }
        }
        return best
    }
}

nonisolated extension Production {
    /// Any part still waiting for a performer.
    var hasOpenPart: Bool { parts.values.contains { $0.status == .open } }
}

nonisolated extension PlayBrowse {
    /// Home's Open Parts: this device's productions with a part still open, newest first, at most `limit`.
    static func openProductions(_ productions: [Production], limit: Int = 5) -> [Production] {
        Array(productions.filter { $0.hasOpenPart && !$0.isFinished }.sorted { $0.created > $1.created }.prefix(limit))
    }
}
