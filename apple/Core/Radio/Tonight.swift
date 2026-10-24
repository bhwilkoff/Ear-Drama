import Foundation

// Tonight in 19xx (docs/CATALOG-CONTRACT.md §8): the evenings are published;
// the client only reads the clock. Mirrors js/api.js (localDate, tonight,
// onAir) so every platform puts the same slot on the air at the same instant.

/// `tonight.json`: evenings keyed by the listener's own calendar date.
nonisolated struct TonightFile: Decodable, Sendable {
    let zone: String
    let days: [String: TonightDay]

    /// The evening published for `date` (YYYY-MM-DD, the person's own), or nil.
    func day(for date: String) -> TonightDay? { days[date] }
}

nonisolated struct TonightDay: Decodable, Hashable, Sendable {
    /// The broadcast evening, YYYY-MM-DD.
    let evening: String
    let network: String?
    let station: String?
    let witness: Witness?
    let slots: [RadioSlot]
    /// Decision 067: the same date's other published years, each a whole
    /// evening on tonight's clock (contract §8). Absent in an older file.
    private let otherYears: [TonightDay]?

    enum CodingKeys: String, CodingKey {
        case evening, network, station, witness, slots
        case otherYears = "years"
    }

    init(evening: String, network: String?, station: String?, witness: Witness?, slots: [RadioSlot],
         years: [TonightDay] = []) {
        self.evening = evening
        self.network = network
        self.station = station
        self.witness = witness
        self.slots = slots
        self.otherYears = years
    }

    var years: [TonightDay] { otherYears ?? [] }

    /// This evening and the date's other published years, oldest first: what a
    /// listener may pick between.
    var choices: [TonightDay] { ([self] + years).sorted { $0.evening < $1.evening } }

    nonisolated struct Witness: Decodable, Hashable, Sendable {
        let paper: String?
        let url: URL?
        let via: String?
    }

    /// "1942" from the evening's date.
    var year: String { String(evening.prefix(4)) }

    /// "CBS · WJSV".
    var stationLine: String? {
        let parts = [network, station].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "Washington Post, via JJ's Newspaper Radio Logs": the credit for the
    /// listing, without the parenthesized host the web also drops.
    var witnessLine: String? {
        guard let witness, witness.url != nil else { return nil }
        let paper = witness.paper ?? "newspaper listing"
        guard let via = witness.via, !via.isEmpty else { return paper }
        let bare = via.replacingOccurrences(of: #"\s*\(.*\)$"#, with: "", options: .regularExpression)
        return "\(paper), via \(bare)"
    }
}

/// One slot of the evening: an episode the catalog serves, or a gap stated as
/// a gap (R9): its time and, when the listing matched a series, that series'
/// name. The newspaper's printed text is never drawn (Decision 067); the file
/// no longer carries it, and this type never decoded it.
nonisolated struct RadioSlot: Decodable, Hashable, Sendable, Identifiable {
    let etStart: String
    let etEnd: String
    let lengthMin: Int
    let utcStart: Date
    let utcEnd: Date
    let episode: Episode?
    let gap: Bool
    let knownSeries: String?
    let withheld: Bool

    nonisolated struct Episode: Decodable, Hashable, Sendable {
        let id: String
        let series: String
        let title: String?
        let lengthS: Double?

        enum CodingKeys: String, CodingKey {
            case id, series, title
            case lengthS = "length_s"
        }
    }

    var id: Date { utcStart }

    /// The episode this slot may play: never a gap, never a withheld slot.
    var playableEpisode: Episode? { gap || withheld ? nil : episode }

    enum CodingKeys: String, CodingKey {
        case etStart = "et_start", etEnd = "et_end", lengthMin = "length_min"
        case utcStart = "utc_start", utcEnd = "utc_end"
        case episode, gap, withheld
        case knownSeries = "known_series"
    }

    init(etStart: String, etEnd: String, lengthMin: Int, utcStart: Date, utcEnd: Date,
         episode: Episode? = nil, gap: Bool = false, knownSeries: String? = nil, withheld: Bool = false) {
        self.etStart = etStart
        self.etEnd = etEnd
        self.lengthMin = lengthMin
        self.utcStart = utcStart
        self.utcEnd = utcEnd
        self.episode = episode
        self.gap = gap
        self.knownSeries = knownSeries
        self.withheld = withheld
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        etStart = try c.decode(String.self, forKey: .etStart)
        etEnd = try c.decode(String.self, forKey: .etEnd)
        lengthMin = try c.decode(Int.self, forKey: .lengthMin)
        utcStart = try Self.instant(c.decode(String.self, forKey: .utcStart), c, .utcStart)
        utcEnd = try Self.instant(c.decode(String.self, forKey: .utcEnd), c, .utcEnd)
        episode = try c.decodeIfPresent(Episode.self, forKey: .episode)
        gap = try c.decodeIfPresent(Bool.self, forKey: .gap) ?? false
        knownSeries = try c.decodeIfPresent(String.self, forKey: .knownSeries)
        withheld = try c.decodeIfPresent(Bool.self, forKey: .withheld) ?? false
    }

    private static func instant(_ text: String, _ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> Date {
        guard let date = try? Date(text, strategy: .iso8601) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "not an ISO 8601 instant: \(text)")
        }
        return date
    }
}

/// The one clock (R10, R14): where an evening stands at an instant.
nonisolated enum RadioClock {
    enum Phase: Equatable, Sendable { case before, during, after }

    struct OnAir: Equatable, Sendable {
        let phase: Phase
        /// The slot whose instants hold now; nil outside the evening.
        let index: Int?
    }

    /// The person's own calendar date, YYYY-MM-DD, in the device's time zone.
    static func localDate(_ date: Date = Date(), calendar: Calendar = .current) -> String {
        let d = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", d.year ?? 0, d.month ?? 0, d.day ?? 0)
    }

    /// js/api.js `onAir`: every instant is the file's own; nothing is computed
    /// from a time zone here.
    static func onAir(_ slots: [RadioSlot], at now: Date) -> OnAir {
        guard let first = slots.first else { return OnAir(phase: .after, index: nil) }
        if now < first.utcStart { return OnAir(phase: .before, index: nil) }
        let end = slots.map(\.utcEnd).max() ?? first.utcEnd
        if now >= end { return OnAir(phase: .after, index: nil) }
        let index = slots.firstIndex { $0.utcStart <= now && now < $0.utcEnd }
        return OnAir(phase: .during, index: index)
    }

    /// The last slot's end: the evening is over then, and nothing plays after.
    static func end(of slots: [RadioSlot]) -> Date? { slots.map(\.utcEnd).max() }

    /// Seconds into the recording where the clock stands, or nil when the
    /// recording already ended inside its slot (within its last 5 seconds).
    static func liveOffset(_ slot: RadioSlot, recordingLength: Double?, at now: Date) -> Double? {
        let at = now.timeIntervalSince(slot.utcStart)
        let length = recordingLength ?? slot.episode?.lengthS ?? Double(slot.lengthMin * 60)
        guard at < length - 5 else { return nil }
        return max(0, at)
    }

    /// Why a slot holds no episode: a recording this catalog does not serve,
    /// or none that survives.
    static func gapNote(_ slot: RadioSlot) -> String {
        slot.withheld || slot.episode != nil ? "Not in the catalog" : "Not surviving"
    }

    /// A slot's time as the listener reads it: local time, with the paper's
    /// Eastern time beside it as a fact, or "7:00 PM ET" alone where the two agree.
    static func timeLabel(_ slot: RadioSlot, zone: String, timeZone: TimeZone = .current,
                          locale: Locale = .current) -> (local: String, eastern: String?) {
        let local = clock(slot.utcStart, in: timeZone, locale: locale)
        let eastern = TimeZone(identifier: zone).map { clock(slot.utcStart, in: $0, locale: locale) }
        if local == eastern { return ("\(local) ET", nil) }
        return (local, "\(printedClock(slot.etStart, locale: locale)) ET")
    }

    /// "7:00 PM" (or "19:00" where the locale says so) at an instant in a zone.
    static func clock(_ date: Date, in timeZone: TimeZone = .current, locale: Locale = .current) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale)
        style.timeZone = timeZone
        return date.formatted(style)
    }

    /// The paper's "19:30" drawn in the listener's clock style.
    static func printedClock(_ hhmm: String, locale: Locale = .current) -> String {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, let utc = TimeZone(identifier: "UTC") else { return hhmm }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let date = calendar.date(from: DateComponents(year: 2000, month: 1, day: 1, hour: parts[0], minute: parts[1]))
        return date.map { clock($0, in: utc, locale: locale) } ?? hhmm
    }

    /// "Wednesday, October 21, 1942" for the evening's date.
    static func longDate(_ evening: String, locale: Locale = .current) -> String {
        guard let utc = TimeZone(identifier: "UTC"),
              let date = try? Date(evening + "T12:00:00Z", strategy: .iso8601) else { return evening }
        var style = Date.FormatStyle(date: .complete, time: .omitted, locale: locale)
        style.timeZone = utc
        return date.formatted(style)
    }
}
