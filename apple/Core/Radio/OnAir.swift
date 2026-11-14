import Foundation

// Home's "On the air" (iOS-DESIGN §4.1, WEB-DESIGN §4.2; js/app.js `onAirNow`): tonight's slot on now,
// else the first genre station with a playable slot. The one clock is Stations' own; this only chooses
// which of its slots to put at the top of Home.

nonisolated struct OnAirNow: Equatable, Sendable {
    enum Source: Equatable, Sendable {
        case evening(TonightDay)
        case station(Station)
    }

    /// "Tonight in 1942", or the station's name.
    let kicker: String
    let slot: RadioSlot
    let source: Source
    /// "Tonight in 1942 · Starts at 8:00 PM", when a station stands in before the evening starts.
    let note: String?

    var episode: RadioSlot.Episode { slot.playableEpisode ?? slot.episode! }

    /// Whole minutes since the slot started.
    func minutesIn(_ now: Date) -> Int { max(0, Int(now.timeIntervalSince(slot.utcStart) / 60)) }

    /// "{episode title} · {N} min in".
    func eventFacts(_ now: Date) -> [String?] { [episode.title, "\(minutesIn(now)) min in"] }

    static func pick(day: TonightDay?, stations: [Station], now: Date) -> OnAirNow? {
        if let day {
            let on = RadioClock.onAir(day.slots, at: now)
            if let index = on.index, day.slots[index].playableEpisode != nil {
                return OnAirNow(kicker: "Tonight in \(day.year)", slot: day.slots[index], source: .evening(day), note: nil)
            }
        }
        var note: String?
        if let day, RadioClock.onAir(day.slots, at: now).phase == .before, let first = day.slots.first {
            note = "Tonight in \(day.year) \u{00B7} Starts at \(RadioClock.clock(first.utcStart))"
        }
        for station in stations {
            if let on = StationClock.onNow(station.slots, at: now), on.slot.playableEpisode != nil {
                return OnAirNow(kicker: station.name, slot: on.slot, source: .station(station), note: note)
            }
        }
        return nil
    }
}

/// What the Home block reads: tonight's evening and the genre stations, through the one API client. A
/// stations file that fails alone is no stations, as Stations treats it; tonight's failing is a problem.
enum OnAirLoad: Equatable {
    case loading
    case ready(day: TonightDay?, stations: [Station])
    case failed

    static func load(now: Date = Date()) async -> OnAirLoad {
        async let stationsLoad = StationsLoad.load()
        let day: TonightDay?
        do {
            day = try await APIClient.shared.tonight()?.day(for: RadioClock.localDate(now))
        } catch {
            print("[Home] tonight.json unreachable: \(error.localizedDescription)")
            return .failed
        }
        return .ready(day: day, stations: await stationsLoad.stations)
    }
}

extension OnAirNow {
    /// Whether the one live listener is on this source now.
    func isLive(_ live: LiveRadio) -> Bool {
        switch source {
        case let .evening(day): live.day == day
        case let .station(station): live.station == station.genre
        }
    }

    /// Listen live: the episodes of the evening (or the station's next hours) resolved against the open
    /// catalog, then the one tune-in Stations uses.
    func tuneIn(catalog: CatalogStore, live: LiveRadio, player: AudioPlayer, muted: Bool, now: Date = Date()) async {
        switch source {
        case let .evening(day):
            let details = await StationsLoad.details(day.slots, catalog: catalog)
            player.isMuted = muted
            live.tuneIn(day, details: details)
        case let .station(station):
            let slots = StationClock.ahead(station.slots, from: now)
            let details = await StationsLoad.details(slots, catalog: catalog)
            player.isMuted = muted
            live.tuneIn(station: station, slots: slots, details: details)
        }
    }

    func stopListening(live: LiveRadio, player: AudioPlayer) {
        player.pause()
        live.stop()
    }
}
