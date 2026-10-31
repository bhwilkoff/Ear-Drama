import Foundation

extension TonightFile {
    nonisolated static func decode(_ data: Data) throws -> TonightFile {
        try JSONDecoder().decode(TonightFile.self, from: data)
    }
}

/// The Radio tab's evening, resolved against the open catalog.
nonisolated struct RadioEvening: Equatable, Sendable {
    let day: TonightDay
    let zone: String
    /// The surviving slots' episodes the catalog holds; a slot absent here
    /// is drawn as a gap ("Not in the catalog") and never plays.
    let details: [String: EpisodeDetail]
    /// The evenings a listener may pick for this date (Decision 067), oldest
    /// first, `day` among them; one entry when the date offers no other year.
    var choices: [String] = []

    func detail(for slot: RadioSlot) -> EpisodeDetail? {
        slot.playableEpisode.flatMap { details[$0.id] }
    }

    /// The first slot of the evening that plays: what "Listen from the start" opens once the evening has ended.
    var firstPlayable: EpisodeDetail? { day.slots.lazy.compactMap { detail(for: $0) }.first }
}

/// The genre stations, read through the one API client. A station's episodes
/// are resolved only when someone tunes in (`details`).
enum StationsLoad: Equatable {
    case loading
    case stations([Station])
    /// None is published, or the file could not be fetched: Stations shows
    /// Tonight alone, as before any station existed.
    case none

    var stations: [Station] {
        if case let .stations(s) = self { return s }
        return []
    }

    static func load() async -> StationsLoad {
        do {
            guard let file = try await APIClient.shared.stations(), !file.stations.isEmpty else { return .none }
            return .stations(file.stations)
        } catch {
            print("[Radio] stations.json unreachable: \(error.localizedDescription)")
            return .none
        }
    }

    /// The episodes one tune-in may play, resolved against the open catalog;
    /// a slot absent here never plays.
    static func details(_ slots: [RadioSlot], catalog: CatalogStore) async -> [String: EpisodeDetail] {
        await catalog.whenReady()
        var out: [String: EpisodeDetail] = [:]
        for slot in slots {
            guard let episode = slot.playableEpisode,
                  let detail = await catalog.episodeDetail(episode.id),
                  detail.defaultRecording != nil else { continue }
            out[episode.id] = detail
        }
        return out
    }
}

enum RadioLoad: Equatable {
    case loading
    /// No file is published, or it holds no evening for today.
    case nothing
    case evening(RadioEvening)
    /// The file could not be fetched (offline, or the host failed).
    case failed

    /// Reads the file through the one API client and resolves each surviving
    /// slot in the catalog. Views never fetch it themselves.
    static func load(catalog: CatalogStore, now: Date = Date(), evening picked: String? = nil) async -> RadioLoad {
        let file: TonightFile?
        do {
            file = try await APIClient.shared.tonight()
        } catch {
            print("[Radio] tonight.json unreachable: \(error.localizedDescription)")
            return .failed
        }
        guard let file, let published = file.day(for: RadioClock.localDate(now)) else { return .nothing }
        let day = picked.flatMap { e in published.choices.first { $0.evening == e } } ?? published
        await catalog.whenReady()
        var details: [String: EpisodeDetail] = [:]
        for slot in day.slots {
            guard let episode = slot.playableEpisode,
                  let detail = await catalog.episodeDetail(episode.id),
                  detail.defaultRecording != nil else { continue }
            details[episode.id] = detail
        }
        return .evening(RadioEvening(day: day, zone: file.zone, details: details,
                                     choices: published.choices.map(\.evening)))
    }
}
