import Foundation

// The rows the served projection carries (docs/CATALOG-CONTRACT.md §3). Every
// value here is a pipeline output; nothing is computed on the client except
// display formatting (§5.5).

/// A served image (contract §3.3a, Decision 069): a Commons file with its
/// evidence. `url` takes a width; `credit` is set only where the license asks.
nonisolated struct Artwork: Hashable, Sendable {
    let url: URL
    var width: Int? = nil
    var height: Int? = nil
    var credit: String? = nil
    var evidence: URL? = nil
    /// Where a small crop centers (contract §3.3a), computed once in the pipeline.
    var face: FaceBox? = nil
    /// The picture's published levels (uniform-imagery-design §2); nil until the projection carries `art.grade`.
    var grade: Grade? = nil

    /// The linear levels `k * v + o` a picture takes after the monochrome, in sRGB.
    struct Grade: Hashable, Sendable {
        var k: Double
        var o: Double
        static let identity = Grade(k: 1, o: 0)
    }

    /// A face box normalized to the image, origin at its top left: "x,y,w,h" in the projection.
    struct FaceBox: Hashable, Sendable {
        let x, y, w, h: Double

        init(x: Double, y: Double, w: Double, h: Double) {
            (self.x, self.y, self.w, self.h) = (x, y, w, h)
        }

        init?(_ text: String?) {
            let v = (text ?? "").split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard v.count == 4, v[2] > 0, v[3] > 0 else { return nil }
            self.init(x: v[0], y: v[1], w: v[2], h: v[3])
        }
    }

    /// A crop square normalized to the image: origin at its top left, `w` and `h` its share
    /// of the image's width and height.
    struct CropRect: Hashable, Sendable {
        let x, y, w, h: Double
    }

    /// The square a small slot (a row tile, a cast face) shows (iOS-DESIGN R11a, contract
    /// §3.3a, the web's `API.cropRect` with the same golden cases): around the published
    /// face, the face about half the square and at most `maxZoom` times the largest square;
    /// without a face the largest square at 50 % across and 20 % down; nil when the picture
    /// is wide with no face (not cropped) or its size is unknown (the plain fill crop).
    func cropRect(maxZoom: Double = 4) -> CropRect? {
        guard let a = aspectRatio, face != nil || !isWide else { return nil }
        let full = min(a, 1)
        func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, v)) }
        var (s, left, top) = (full, 0.5 * (a - full), 0.2 * (1 - full))
        if let f = face {
            s = clamp(2 * max(f.w * a, f.h), full / maxZoom, full)
            left = clamp((f.x + f.w / 2) * a - s / 2, 0, a - s)
            top = clamp(f.y + f.h / 2 - s / 2, 0, 1 - s)
        }
        return CropRect(x: left / a, y: top, w: s / a, h: s)
    }

    /// The square, in pixels, a lock screen is handed from a decoded `width` x `height` copy
    /// of this picture: the largest square, moved onto the face (no zoom: the system shows it
    /// large), or nil to hand over the whole.
    func squareCrop(width: Int, height: Int) -> (x: Int, y: Int, side: Int)? {
        guard width > 0, height > 0, width != height else { return nil }
        var sized = self
        (sized.width, sized.height) = (width, height)
        guard let r = sized.cropRect(maxZoom: 1) else { return nil }
        return (Int((r.x * Double(width)).rounded()), Int((r.y * Double(height)).rounded()), min(width, height))
    }

    /// Commons' standard thumbnail steps; any other width is refused upstream.
    static let steps = [120, 330, 500, 960]

    /// The one image helper: the smallest standard width covering `pixels`.
    func url(pixels: Double) -> URL {
        let width = Self.steps.first { Double($0) >= pixels } ?? Self.steps[Self.steps.count - 1]
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        parts?.queryItems = [URLQueryItem(name: "width", value: String(width))]
        return parts?.url ?? url
    }

    /// Past this width over height a picture is wide; anything else is upright, a square
    /// included (iOS-DESIGN R11a, the same number as WEB-DESIGN §6.4a and ANDROID-DESIGN).
    static let wideAspect = 1.15

    /// Width over height from the projection, or nil when the size was never read.
    var aspectRatio: Double? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return Double(width) / Double(height)
    }

    /// The print beside a heading, or the plate above it. An unknown size is upright.
    var isWide: Bool { (aspectRatio ?? 0) > Self.wideAspect }
}

/// The first letter or digit of a name, skipping a leading article.
nonisolated enum ArtInitial {
    static func of(_ name: String) -> String {
        var rest = Substring(name).drop { !$0.isLetter && !$0.isNumber }
        for article in ["The ", "A ", "An "] where rest.lowercased().hasPrefix(article.lowercased()) {
            rest = rest.dropFirst(article.count)
            break
        }
        return rest.first { $0.isLetter || $0.isNumber }.map { String($0).uppercased() } ?? ""
    }
}

/// Whose face a series or episode wears: a person's name and served portrait.
nonisolated struct Face: Hashable, Sendable {
    let name: String
    let art: Artwork
}

/// Browse's orders (iOS-DESIGN §4.2): Popular is the default, then the web's three.
nonisolated enum SeriesSort: String, CaseIterable, Hashable, Sendable {
    case popular, name, episodes, firstAired
    var title: String {
        switch self {
        case .popular: "Popular"
        case .name: "A to Z"
        case .episodes: "Most episodes"
        case .firstAired: "Oldest first"
        }
    }
}

nonisolated struct SeriesRow: Hashable, Sendable, Identifiable {
    let key: String
    let name: String
    let genre: String?
    let firstDate: String?
    let lastDate: String?
    let networks: [String]
    let episodeCount: Int
    /// The series' star and portrait (contract §3.3a), or nil: its art is then the typographic card.
    var face: Face? = nil
    /// The series' own picture (contract §3.3a): its show image, else its star, else the person heard
    /// most; nil on a catalog that predates `series.picture`. `pictureKind` is never said on a tile.
    var picture: Artwork? = nil
    var pictureKind: String? = nil

    var id: String { key }

    /// What the window draws: the published picture, else the star's portrait an older catalog carries.
    var windowArt: Artwork? { picture ?? face?.art }

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
    /// The series' genre and face, so a row that mixes series can draw its tile.
    var seriesGenre: String? = nil
    var seriesFace: Face? = nil
    var seriesPicture: Artwork? = nil
    var seriesWindowArt: Artwork? { seriesPicture ?? seriesFace?.art }

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
    /// The person's served portrait (contract §3.3a), or nil.
    var art: Artwork? = nil

    var id: String { "\(personID)|\(role ?? "")|\(character ?? "")" }
}

nonisolated struct EpisodeDetail: Hashable, Sendable {
    let episode: EpisodeRow
    let sponsor: String?
    let credits: [Credit]
    let recordings: [Recording]
    /// The published rights words (contract §5.5); nil shows no line.
    let rightsLine: String?
    /// The episode's face, a person credited in it (contract §3.3a), or nil.
    var star: String? = nil
    /// A castable script this episode can be recorded from (contract §3.1), or nil.
    var script: String? = nil
    var defaultRecording: Recording? { recordings.first }
    /// The credited star with a portrait, drawn beside the heading.
    var starFace: Face? {
        guard let star, let credit = credits.first(where: { $0.personID == star && $0.art != nil }),
              let art = credit.art else { return nil }
        return Face(name: credit.name, art: art)
    }
    /// What Now Playing and the lock screen show: the episode's face, else the series'.
    var face: Face? { starFace ?? episode.seriesFace }
    /// The portraits whose license asks for a credit, once each, leaving out
    /// the heading's face, which carries its own (Decision 069).
    var owedCredits: [Credit] {
        let headed = starFace == nil ? nil : star
        var seen = Set<String>()
        return credits.filter { credit in
            guard credit.art?.credit != nil, credit.personID != headed, !seen.contains(credit.personID)
            else { return false }
            seen.insert(credit.personID)
            return true
        }
    }
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
    /// `searchPeople(q)` (contract §5): credited people, most episodes first.
    var people: [PersonRow] = []
    /// What aired on the date the query names, or nil when it names none.
    var aired: AiredResults? = nil
    /// Episodes whose shown transcript says the query's words, less those in
    /// `episodes`; each carries its `transcriptURL` (contract §3.4).
    var transcript: [EpisodeRow] = []
    var isEmpty: Bool {
        series.isEmpty && episodes.isEmpty && people.isEmpty && (aired?.episodes.isEmpty ?? true)
            && transcript.isEmpty
    }
}

nonisolated struct AiredResults: Hashable, Sendable {
    /// YYYY, YYYY-MM, or YYYY-MM-DD (`DateQuery`).
    let prefix: String
    let episodes: [EpisodeRow]
    var title: String { "Aired \(DateQuery.label(prefix))" }
}

// MARK: - People (withPerson, contract §5)

/// A credited person: facts from the `people` row only, never a written bio.
nonisolated struct Person: Hashable, Sendable, Identifiable {
    let id: String
    let name: String
    let birth: String?
    let death: String?
    /// The person's served portrait (contract §3.3a), or nil.
    var art: Artwork? = nil

    var face: Face? { art.map { Face(name: name, art: $0) } }
    var years: String? { Self.years(birth: birth, death: death) }

    /// The years as every platform writes them (`API.lifeYears` on the web).
    static func years(birth: String?, death: String?) -> String? {
        let b = birth.map { String($0.prefix(4)) }.flatMap { $0.isEmpty ? nil : $0 }
        let d = death.map { String($0.prefix(4)) }.flatMap { $0.isEmpty ? nil : $0 }
        switch (b, d) {
        case let (b?, d?): return "\(b)–\(d)"
        case let (b?, nil): return "Born \(b)"
        case let (nil, d?): return "Died \(d)"
        case (nil, nil): return nil
        }
    }
}

/// A people search row.
nonisolated struct PersonRow: Hashable, Sendable, Identifiable {
    let person: Person
    /// Distinct served episodes crediting the person.
    let episodes: Int
    var id: String { person.id }
}

/// One of a person's credits on an episode: the role and, for cast, whom they played.
nonisolated struct PersonRole: Hashable, Sendable {
    let role: String?
    let character: String?

    /// A role as a heading word, on Detail's credits and a person's rows.
    static func title(_ role: String) -> String {
        switch role.lowercased() {
        case "cast": "Cast"
        case "m. c.", "emcee": "Emcee"
        default: role.prefix(1).uppercased() + role.dropFirst()
        }
    }
}

/// One episode on a person's page, with every role it credits them in.
nonisolated struct PersonEpisode: Hashable, Sendable, Identifiable {
    let episode: EpisodeRow
    var roles: [PersonRole]
    var id: String { episode.id }

    /// "Cast as Mrs. Stevenson, Narrator": every role this episode credits the person in.
    var rolesLine: String {
        roles.map { r in
            let title = PersonRole.title(r.role ?? "cast")
            return r.character.map { "\(title) as \($0)" } ?? title
        }.joined(separator: ", ")
    }
}

nonisolated struct PersonSeriesGroup: Hashable, Sendable, Identifiable {
    let seriesKey: String
    let seriesName: String
    let episodes: [PersonEpisode]
    var id: String { seriesKey }
}

nonisolated struct PersonPage: Hashable, Sendable {
    let person: Person
    /// Every served episode crediting the person, oldest first (R1).
    let episodes: [PersonEpisode]

    /// By series, oldest or newest first, undated last either way; a series
    /// sits where its first episode in that order does (`API.personGroups`).
    func groups(newestFirst: Bool) -> [PersonSeriesGroup] {
        let ordered = newestFirst
            ? episodes.filter { $0.episode.airDate != nil }.reversed() + episodes.filter { $0.episode.airDate == nil }
            : episodes
        var order: [String] = []
        var byKey: [String: [PersonEpisode]] = [:]
        for item in ordered {
            let key = item.episode.seriesKey
            if byKey[key] == nil { order.append(key) }
            byKey[key, default: []].append(item)
        }
        return order.map { key in
            PersonSeriesGroup(seriesKey: key, seriesName: byKey[key]?.first?.episode.seriesName ?? key,
                              episodes: byKey[key] ?? [])
        }
    }
}

/// The Listen tab's shelves. Each is a RULE over data (R13), never a list
/// someone wrote, and every one applies `recommendAnd` (contract §5).
nonisolated enum ShelfRule: Hashable, Sendable, Identifiable {
    /// Episodes first broadcast on this calendar day in any year.
    case onThisDay(month: Int, day: Int)
    /// The first surviving episode of each series in a genre.
    case genreFirsts(String)
    /// Decision 067: the series archive.org's listeners downloaded most, each
    /// by its first surviving episode. Only ever published; never run here.
    case mostDownloaded

    var id: String {
        switch self {
        case let .onThisDay(m, d): "day-\(m)-\(d)"
        case let .genreFirsts(g): "genre-\(g)"
        case .mostDownloaded: "most-downloaded"
        }
    }

    var title: String {
        switch self {
        case .onThisDay: "This day in radio"
        case let .genreFirsts(g): GenreDisplay.name(g)
        case .mostDownloaded: "Most downloaded"
        }
    }
}

/// One entry of `meta.listenShelves` (contract §5.1): the pipeline's list,
/// drawn in order. `onThisDay` is a query by rule on the person's date;
/// `genreFirsts` carries its episode ids, drawn as published.
nonisolated enum PublishedShelf: Hashable, Sendable {
    case onThisDay
    case genreFirsts(genre: String, episodes: [String])
    case mostDownloaded(episodes: [String])

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
            case "mostDownloaded":
                guard let ids = s["episodes"] as? [String] else { return nil }
                return .mostDownloaded(episodes: ids)
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
