import Foundation

/// Surprise's evening (iOS-DESIGN §4.11): one published evening and the first
/// of its surviving slots the open catalog can play.
nonisolated struct SurpriseEvening: Equatable, Sendable {
    let day: TonightDay
    let first: EpisodeDetail?
}

/// The random draws behind Surprise. Each uses this platform's own random:
/// nothing here needs to match another device (Decision 068).
enum SurprisePicks {
    /// Reads tonight.json through the one API client, never from a view.
    static func evening(catalog: CatalogStore) async -> SurpriseEvening? {
        let file: TonightFile?
        do {
            file = try await APIClient.shared.tonight()
        } catch {
            print("[Surprise] tonight.json unreachable: \(error.localizedDescription)")
            return nil
        }
        guard let day = file?.days.values.randomElement() else { return nil }
        await catalog.whenReady()
        for slot in day.slots {
            guard let episode = slot.playableEpisode,
                  let detail = await catalog.episodeDetail(episode.id),
                  detail.defaultRecording != nil else { continue }
            return SurpriseEvening(day: day, first: detail)
        }
        return SurpriseEvening(day: day, first: nil)
    }
}
