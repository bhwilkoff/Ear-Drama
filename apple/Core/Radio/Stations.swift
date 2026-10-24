import Foundation

// Genre stations (docs/CATALOG-CONTRACT.md §8, R10, Decision 068): each
// station's schedule is published back to back on the one clock; the client
// only looks up what is on now and where in it. Mirrors js/api.js
// (`onNow`, `ahead`) and Android's `StationClock`.

/// `stations.json`: one station per genre, Tonight's neighbors on Stations.
nonisolated struct StationsFile: Decodable, Sendable {
    let stations: [Station]

    static func decode(_ data: Data) throws -> StationsFile {
        try JSONDecoder().decode(StationsFile.self, from: data)
    }
}

/// A genre station. Its slots are `RadioSlot`s, so the one `LiveListening`
/// plays a station exactly as it plays an evening.
nonisolated struct Station: Decodable, Hashable, Sendable, Identifiable {
    let genre: String
    /// The genre's name, from the data (genres.py), never written here.
    let name: String
    let slots: [RadioSlot]

    var id: String { genre }

    init(genre: String, name: String, slots: [RadioSlot]) {
        self.genre = genre
        self.name = name
        self.slots = slots
    }

    private enum CodingKeys: String, CodingKey { case genre, name, slots }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        genre = try c.decode(String.self, forKey: .genre)
        name = try c.decode(String.self, forKey: .name)
        slots = try c.decode([StationSlot].self, forKey: .slots).map(\.radioSlot)
    }
}

/// One published slot: `utc_start`, `utc_end`, `length_s`, and its episode, or
/// `withheld` (an episode no longer served keeps its time; nothing plays).
private nonisolated struct StationSlot: Decodable {
    let utcStart: String
    let utcEnd: String
    let lengthS: Int
    let episode: Episode?
    let withheld: Bool?

    struct Episode: Decodable {
        let id: String
        let series: String
        let title: String?
    }

    enum CodingKeys: String, CodingKey {
        case utcStart = "utc_start", utcEnd = "utc_end", lengthS = "length_s"
        case episode, withheld
    }

    var radioSlot: RadioSlot {
        let start = (try? Date(utcStart, strategy: .iso8601)) ?? .distantPast
        let end = (try? Date(utcEnd, strategy: .iso8601)) ?? start.addingTimeInterval(Double(lengthS))
        return RadioSlot(etStart: "", etEnd: "", lengthMin: (lengthS + 59) / 60, utcStart: start, utcEnd: end,
                         episode: episode.map { .init(id: $0.id, series: $0.series, title: $0.title,
                                                      lengthS: Double(lengthS)) },
                         gap: episode == nil, withheld: withheld ?? (episode == nil))
    }
}

/// What a station has on at an instant.
nonisolated enum StationClock {
    struct OnNow: Equatable, Sendable {
        let index: Int
        let slot: RadioSlot
        /// Seconds since the slot started.
        let offset: TimeInterval
    }

    /// The slot whose instants hold `now`, found by halving (the slots are
    /// back to back and in order), or nil before the first or after the last.
    static func onNow(_ slots: [RadioSlot], at now: Date) -> OnNow? {
        var lo = 0, hi = slots.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let s = slots[mid]
            if now < s.utcStart { hi = mid - 1 } else if now >= s.utcEnd { lo = mid + 1 } else {
                return OnNow(index: mid, slot: s, offset: now.timeIntervalSince(s.utcStart))
            }
        }
        return nil
    }

    /// The slot on now and every slot starting within `span` of now: what one
    /// tune-in may play. Listening ends after the last (R14), so a tune-in
    /// lasts at most `span` past now.
    static func ahead(_ slots: [RadioSlot], from now: Date, span: TimeInterval = 12 * 3600) -> [RadioSlot] {
        guard let on = onNow(slots, at: now) else { return [] }
        let horizon = now.addingTimeInterval(span)
        return Array(slots[on.index...].prefix { $0.utcStart < horizon })
    }
}
