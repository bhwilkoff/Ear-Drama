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

    func detail(for slot: RadioSlot) -> EpisodeDetail? {
        slot.playableEpisode.flatMap { details[$0.id] }
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
    static func load(catalog: CatalogStore, now: Date = Date()) async -> RadioLoad {
        let file: TonightFile?
        do {
            file = try await APIClient.shared.tonight()
        } catch {
            print("[Radio] tonight.json unreachable: \(error.localizedDescription)")
            return .failed
        }
        guard let file, let day = file.day(for: RadioClock.localDate(now)) else { return .nothing }
        await catalog.whenReady()
        var details: [String: EpisodeDetail] = [:]
        for slot in day.slots {
            guard let episode = slot.playableEpisode,
                  let detail = await catalog.episodeDetail(episode.id),
                  detail.defaultRecording != nil else { continue }
            details[episode.id] = detail
        }
        return .evening(RadioEvening(day: day, zone: file.zone, details: details))
    }
}
