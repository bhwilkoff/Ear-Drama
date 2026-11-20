import Foundation

// The dial under On the air (WEB-DESIGN §4.2r rule 2; js/app.js `homeDial`): every genre station as a small
// label, its genre's name and the show it has on now; the label's one tick is that broadcast's year.

nonisolated struct DialEntry: Identifiable, Equatable, Sendable {
    let station: Station
    /// What the station has on now, tuned in with `OnAirNow.tuneIn`; nil when nothing playable is on.
    let on: OnAirNow?
    /// The year of the broadcast on now, for the label's tick.
    let year: Int?

    var id: String { station.id }
    var show: String? { on?.episode.series }

    static func entries(_ stations: [Station], now: Date) -> [DialEntry] {
        stations.map { station in
            guard let at = StationClock.onNow(station.slots, at: now), at.slot.playableEpisode != nil else {
                return DialEntry(station: station, on: nil, year: nil)
            }
            let on = OnAirNow(kicker: station.name, slot: at.slot, source: .station(station), note: nil)
            let date = on.episode.id.split(separator: "|", omittingEmptySubsequences: false).dropFirst().first
            let year = date.flatMap { Int($0.prefix(4)) }.flatMap { $0 >= 1900 ? $0 : nil }
            return DialEntry(station: station, on: on, year: year)
        }
    }
}
