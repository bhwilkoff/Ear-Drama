import Foundation

// The rows the served projection carries (docs/CATALOG-CONTRACT.md §3). Every
// value here is a pipeline output; nothing is computed on the client except
// display formatting (§5.5).

nonisolated struct SeriesRow: Hashable, Sendable, Identifiable {
    let key: String
    let name: String
    let genre: String?
    let firstDate: String?
    let lastDate: String?
    let networks: [String]
    let episodeCount: Int

    var id: String { key }

    var yearSpan: String? {
        let first = firstDate.map { String($0.prefix(4)) }
        let last = lastDate.map { String($0.prefix(4)) }
        switch (first, last) {
        case let (f?, l?) where f == l: return f
        case let (f?, l?): return "\(f)–\(l)"
        case let (f?, nil): return f
        default: return nil
        }
    }

    /// `CBS · 1942–1962 · 1,098 episodes`: the one meta line a series card carries.
    var metaLine: String {
        var parts: [String] = []
        if let network = networks.first { parts.append(network) }
        if let span = yearSpan { parts.append(span) }
        parts.append(episodeCount == 1 ? "1 episode" : "\(episodeCount.formatted()) episodes")
        return parts.joined(separator: " · ")
    }
}

nonisolated struct EpisodeRow: Hashable, Sendable, Identifiable {
    let id: String
    let seriesKey: String
    let seriesName: String
    let airDate: String?
    let season: String?
    let number: Int?
    let title: String?
    let lengthSeconds: Double?
    let rights: String
    let rightsBasis: String?
    let network: String?
    /// The default copy's integrated loudness (LUFS) and true peak (dBTP),
    /// contract §3.1; nil until measured. Read only by `episodeDetail`.
    var loudnessI: Double? = nil
    var loudnessTP: Double? = nil
    /// archive.org's automatic transcript, set only where the quality gate
    /// passed (contract §3.1, `has_transcript = 1`); fetched on demand, never
    /// bundled. Read only by `episodeDetail`.
    var transcriptURL: URL? = nil

    /// The episode's display title. A row the pipeline left untitled shows its
    /// log number, then its date, and only then the series name.
    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        if let number { return "No. \(number)" }
        if let airDate { return airDate }
        return seriesName
    }

    var durationText: String? { lengthSeconds.map(Self.clock) }

    static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

nonisolated struct Recording: Hashable, Sendable, Identifiable {
    let rank: Int
    let archiveID: String
    let url: URL
    let format: String?
    let kbps: Int?
    let lengthSeconds: Double?
    let variant: String?
    let partial: Bool

    var id: Int { rank }

    /// §5.5 display vocabulary; a recording with nothing to say says nothing.
    var notes: [String] {
        var out: [String] = []
        if let variant, variant == "AFRS" || variant == "AFRTS" { out.append("Armed Forces Radio rebroadcast") }
        if partial { out.append("Incomplete copy") }
        return out
    }
}

nonisolated struct Credit: Hashable, Sendable, Identifiable {
    let personID: String
    let name: String
    let role: String?
    let character: String?

    var id: String { "\(personID)|\(role ?? "")|\(character ?? "")" }
}

nonisolated struct EpisodeDetail: Hashable, Sendable {
    let episode: EpisodeRow
    let sponsor: String?
    let credits: [Credit]
    let recordings: [Recording]
    /// The published rights words (contract §5.5); nil shows no line.
    let rightsLine: String?
    var defaultRecording: Recording? { recordings.first }
}

nonisolated struct SeasonGroup: Hashable, Sendable, Identifiable {
    /// The broadcast season (`1949-50`), or nil for the undated episodes.
    let season: String?
    let episodes: [EpisodeRow]
    var id: String { season ?? "undated" }
}

nonisolated struct SeriesPage: Hashable, Sendable {
    let series: SeriesRow
    let seasons: [SeasonGroup]
    var episodes: [EpisodeRow] { seasons.flatMap(\.episodes) }
}

nonisolated struct SearchResults: Hashable, Sendable {
    var series: [SeriesRow] = []
    var episodes: [EpisodeRow] = []
    /// Episodes found only by words in their transcript (contract §3.4), so a
    /// row can say why it matched.
    var transcriptOnly: Set<String> = []
    var isEmpty: Bool { series.isEmpty && episodes.isEmpty }
}

/// The Listen tab's shelves. Each is a RULE over data (R13), never a list
/// someone wrote, and every one applies `recommendAnd` (contract §5).
nonisolated enum ShelfRule: Hashable, Sendable, Identifiable {
    /// Episodes first broadcast on this calendar day in any year.
    case onThisDay(month: Int, day: Int)
    /// The first surviving episode of each series in a genre.
    case genreFirsts(String)

    var id: String {
        switch self {
        case let .onThisDay(m, d): "day-\(m)-\(d)"
        case let .genreFirsts(g): "genre-\(g)"
        }
    }

    var title: String {
        switch self {
        case .onThisDay: "This day in radio"
        case let .genreFirsts(g): GenreDisplay.name(g)
        }
    }
}

/// One entry of `meta.listenShelves` (contract §5.1): the pipeline's list,
/// drawn in order. `onThisDay` is a query by rule on the person's date;
/// `genreFirsts` carries its episode ids, drawn as published.
nonisolated enum PublishedShelf: Hashable, Sendable {
    case onThisDay
    case genreFirsts(genre: String, episodes: [String])

    /// The published list, or nil when the value is not a JSON array (an
    /// older catalog). A rule this build does not know is skipped.
    static func parse(_ json: String) -> [PublishedShelf]? {
        guard let data = json.data(using: .utf8),
              let list = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return nil }
        return list.compactMap { item in
            guard let s = item as? [String: Any] else { return nil }
            switch s["rule"] as? String {
            case "onThisDay": return .onThisDay
            case "genreFirsts":
                guard let g = s["genre"] as? String, let ids = s["episodes"] as? [String] else { return nil }
                return .genreFirsts(genre: g, episodes: ids)
            default: return nil
            }
        }
    }
}

nonisolated struct Shelf: Hashable, Sendable, Identifiable {
    let rule: ShelfRule
    let episodes: [EpisodeRow]
    var id: String { rule.id }
}

/// Contract §5.5. The words are published in `meta.rightsLines`; this table is
/// the contract's same strings for a catalog that predates the key. A basis
/// with no published words shows NO line, never the unclaimed one.
nonisolated enum RightsDisplay {
    static let contract: [String: String] = [
        "unclaimed": "No rights claim known. Removed on request.",
        "rec_gov_work": "Government recording",
        "rec_librivox": "LibriVox recording",
        "rec_pd_published_age": "Published before 1926",
        "rec_cc_corroborated": "Creative Commons recording",
    ]

    static func line(rights: String, basis: String?, lines: [String: String] = contract) -> String? {
        switch rights {
        case "unclaimed": return lines["unclaimed"]
        case "clean": return basis.flatMap { lines[$0] }
        default: return nil
        }
    }
}

/// The eight genres' names (contract §5.5). The pipeline decides the genre
/// (catalog/tools/genres.py, NAMES); a client only spells it. An older catalog
/// carried archive.org subjects (`OTR-Comedy`), shown without the prefix.
nonisolated enum GenreDisplay {
    static let names: [String: String] = [
        "drama": "Drama", "mystery": "Mystery", "scifi": "Science fiction", "western": "Western",
        "comedy": "Comedy", "news": "News", "documentary": "Documentary", "serial": "Serials",
    ]

    static func name(_ genre: String) -> String {
        if let name = names[genre] { return name }
        return genre.hasPrefix("OTR-") ? String(genre.dropFirst(4)) : genre
    }
}

/// Air dates are `YYYY-MM-DD` strings (R1: the date is the identity). Shown
/// as the stored digits so a column of dates aligns in tabular figures.
nonisolated enum AirDate {
    static func display(_ date: String?) -> String { date ?? "Undated" }
}
