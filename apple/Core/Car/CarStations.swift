import Foundation

/// What a tune-in starts: the live listener's own tune-in, handed to the one `LiveRadio`.
nonisolated enum CarTune: Sendable {
    case evening(TonightDay, details: [String: EpisodeDetail])
    case station(Station, slots: [RadioSlot], details: [String: EpisodeDetail])
}

/// The Stations tab's rows for the car (the twin of Android's `CarStations`): tonight's evening and the
/// genre stations that have something on the air now, each tuned at the clock's own position by the
/// app's one `LiveRadio`. No second clock and no day switcher; a station with a gap on the air, or an
/// evening not under way, is not offered.
final class CarStations {
    /// Where a tune-in starts: the episode and how far into it (seconds) the clock stands.
    struct Tuned: Equatable, Sendable {
        let episodeID: String
        let startSeconds: Double
    }

    static let tonight = CarLibrary.stationPrefix + "tonight"

    private let catalog: CatalogStore
    private let tonightFile: () async throws -> TonightFile?
    private let stationsFile: () async throws -> StationsFile?
    private let start: (CarTune) -> Void
    private let now: () -> Date

    init(catalog: CatalogStore,
         tonight: (() async throws -> TonightFile?)? = nil,
         stations: (() async throws -> StationsFile?)? = nil,
         start: @escaping (CarTune) -> Void,
         now: @escaping () -> Date = Date.init) {
        self.catalog = catalog
        tonightFile = tonight ?? { try await APIClient.shared.tonight() }
        stationsFile = stations ?? { try await APIClient.shared.stations() }
        self.start = start
        self.now = now
    }

    /// Throws when neither file can be read (offline).
    func list() async throws -> [CarStation] {
        let at = now()
        var failure: Error?
        var evening: TonightDay?
        do { evening = try await tonightFile()?.day(for: RadioClock.localDate(at)) } catch { failure = error }
        var genre: [Station] = []
        do { genre = try await stationsFile()?.stations ?? [] } catch where failure == nil { failure = error } catch {}
        if let failure, evening == nil, genre.isEmpty { throw failure }
        await catalog.whenReady()
        var out: [CarStation] = []
        if let evening, let on = RadioClock.onAir(evening.slots, at: at).index,
           let detail = await playable(evening.slots[on]) {
            out.append(CarStation(id: Self.tonight, name: "Tonight in \(evening.year)", line: Self.line(detail.episode),
                                  artEpisodeID: detail.episode.id))
        }
        for station in genre {
            guard let slot = StationClock.onNow(station.slots, at: at)?.slot, let detail = await playable(slot) else { continue }
            out.append(CarStation(id: CarLibrary.stationPrefix + station.genre, name: station.name,
                                  line: Self.line(detail.episode), artEpisodeID: detail.episode.id))
        }
        return out
    }

    /// Tunes `id` in the app's live listening and says what the player will start with; nil when nothing is on.
    func tune(_ id: String) async -> Tuned? {
        let at = now()
        let slots: [RadioSlot]
        let details: [String: EpisodeDetail]
        let tune: CarTune
        if id == Self.tonight {
            guard let day = (try? await tonightFile())?.day(for: RadioClock.localDate(at)) else { return nil }
            slots = day.slots
            details = await StationsLoad.details(slots, catalog: catalog)
            tune = .evening(day, details: details)
        } else {
            guard let station = (try? await stationsFile())?.stations.first(where: { CarLibrary.stationPrefix + $0.genre == id })
            else { return nil }
            slots = StationClock.ahead(station.slots, from: at)
            details = await StationsLoad.details(slots, catalog: catalog)
            tune = .station(station, slots: slots, details: details)
        }
        // What `LiveRadio` will play first, from the same pure state machine, before it plays it.
        var preview = LiveListening(slots: slots, lengths: details.mapValues {
            $0.defaultRecording?.lengthSeconds ?? $0.episode.lengthSeconds
        })
        guard case let .play(episodeID, offset) = preview.tick(now: at) else { return nil }
        start(tune)
        return Tuned(episodeID: episodeID, startSeconds: offset)
    }

    private func playable(_ slot: RadioSlot) async -> EpisodeDetail? {
        guard let episode = slot.playableEpisode, let detail = await catalog.episodeDetail(episode.id),
              detail.defaultRecording != nil else { return nil }
        return detail
    }

    private static func line(_ row: EpisodeRow) -> String {
        let title = ItemLead.episodeTitle(row)
        return [row.seriesName, title != row.seriesName ? title : nil].compactMap { $0 }.joined(separator: " \u{00B7} ")
    }
}
