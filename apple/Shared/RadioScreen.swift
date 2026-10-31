#if os(iOS) || os(macOS)
import SwiftUI

// Stations on the iPhone, iPad, and Mac (iOS-DESIGN §4.9, macOS-DESIGN §4.3):
// a row a station, Tonight in 19xx first and then the genre stations, each
// with what is on now and Listen live; then tonight's evening as a List of its
// slots on the one clock. The TV has its own focus-driven screen.

struct RadioScreen: View {
    @Environment(CatalogStore.self) private var catalog
    @State private var load: RadioLoad = .loading
    @State private var stations: StationsLoad = .loading
    @State private var attempt = 0
    /// The year the listener picked for today, or nil for the published one.
    @State private var picked: String?

    private struct Key: Hashable { let date: String; let load: Int; let attempt: Int; let picked: String? }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            content(now: context.date)
                .task(id: Key(date: RadioClock.localDate(context.date), load: catalog.loadKey, attempt: attempt,
                              picked: picked)) {
                    load = await RadioLoad.load(catalog: catalog, now: context.date, evening: picked)
                }
        }
        .task(id: attempt) { stations = await StationsLoad.load() }
        .navigationTitle("Stations")
    }

    @ViewBuilder private func content(now: Date) -> some View {
        switch load {
        case .loading:
            List { SkeletonRows() }
        case .nothing where !stations.stations.isEmpty:
            List { StationsSection(evening: nil, stations: stations.stations, now: now) }
        case .nothing:
            EmptyState("No evening is published for today", systemImage: "radio")
        case .failed:
            EmptyState("Tonight could not load", systemImage: "wifi.slash",
                       action: .init(title: "Try Again") { attempt += 1 })
        case let .evening(evening):
            EveningList(evening: evening, stations: stations.stations, now: now, picked: $picked)
        }
    }
}

private struct EveningList: View {
    let evening: RadioEvening
    let stations: [Station]
    let now: Date
    @Binding var picked: String?
    @Environment(AudioPlayer.self) private var player
    @Environment(AppStore.self) private var store
    @Environment(LiveRadio.self) private var live

    var body: some View {
        let slots = evening.day.slots
        let onAir = RadioClock.onAir(slots, at: now)
        List {
            StationsSection(evening: evening, stations: stations, now: now)
            Section {
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Text(verbatim: "Tonight in \(evening.day.year)")
                        .font(TypeRamp.sectionHeader)
                    Text(verbatim: RadioClock.longDate(evening.day.evening))
                        .font(TypeRamp.body)
                    if let line = evening.day.stationLine {
                        Text(verbatim: line)
                            .font(TypeRamp.caption)
                            .foregroundStyle(Color.brandTextMuted)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                if evening.choices.count > 1 {
                    // Decision 067: another published year for the same date.
                    Picker("Year", selection: Binding(get: { evening.day.evening }, set: { year in
                        if live.day == evening.day { live.stop() }
                        picked = year
                    })) {
                        ForEach(evening.choices, id: \.self) { Text(verbatim: String($0.prefix(4))).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
            }
            Section {
                ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                    SlotRow(slot: slot, zone: evening.zone, detail: evening.detail(for: slot),
                            isNow: index == onAir.index) { detail in
                        live.stop()
                        player.isMuted = store.isMuted
                        player.play(detail, from: 0)
                    }
                }
            }
            if let url = evening.day.witness?.url, let line = evening.day.witnessLine {
                Section {
                    Link(destination: url) {
                        Text(verbatim: "Schedule: \(line)")
                            .font(TypeRamp.caption)
                    }
                }
            }
        }
    }
}

/// The stations row (iOS-DESIGN §4.9): Tonight in 19xx first, then each genre
/// station, each with what is on now and one Listen live. A genre station's
/// episodes are resolved only when someone tunes in.
private struct StationsSection: View {
    let evening: RadioEvening?
    let stations: [Station]
    let now: Date
    @Environment(AudioPlayer.self) private var player
    @Environment(AppStore.self) private var store
    @Environment(LiveRadio.self) private var live
    @Environment(CatalogStore.self) private var catalog

    var body: some View {
        Section {
            if let evening { tonight(evening) }
            ForEach(stations) { station(for: $0) }
        }
    }

    private func tonight(_ evening: RadioEvening) -> some View {
        let slots = evening.day.slots
        let onAir = RadioClock.onAir(slots, at: now)
        let slot = onAir.index.map { slots[$0] }
        let note: String? = switch onAir.phase {
        case .before: slots.first.map { "Starts at \(RadioClock.clock($0.utcStart))" }
        case .after: RadioClock.end(of: slots).map { "Ended at \(RadioClock.clock($0))" }
        case .during: slot.flatMap { evening.detail(for: $0) == nil ? RadioClock.gapNote($0) : nil }
        }
        let ended = onAir.phase == .after
        return StationRow(name: "Tonight in \(evening.day.year)", genre: nil, slot: slot, note: note,
                          isLive: live.day == evening.day,
                          canListen: ended ? evening.firstPlayable != nil : slot.flatMap { evening.detail(for: $0) } != nil,
                          startOver: ended) {
            player.isMuted = store.isMuted
            if ended, let first = evening.firstPlayable {
                live.stop()
                player.play(first, from: 0)
            } else {
                live.tuneIn(evening.day, details: evening.details)
            }
        } stop: { stopLive() }
    }

    private func station(for station: Station) -> some View {
        let on = StationClock.onNow(station.slots, at: now)
        return StationRow(name: station.name, genre: station.genre, slot: on?.slot,
                          note: on.flatMap { $0.slot.playableEpisode == nil ? RadioClock.gapNote($0.slot) : nil },
                          isLive: live.station == station.genre,
                          canListen: on?.slot.playableEpisode != nil) {
            Task {
                let slots = StationClock.ahead(station.slots, from: Date())
                let details = await StationsLoad.details(slots, catalog: catalog)
                player.isMuted = store.isMuted
                live.tuneIn(station: station, slots: slots, details: details)
            }
        } stop: { stopLive() }
    }

    private func stopLive() {
        player.pause()
        live.stop()
    }
}

/// A station as the grammar's row: its show's window (the picture, else the star, else the title
/// block), the station's name, an event line of what is on, and Listen live.
struct StationRow: View {
    let name: String
    let genre: String?
    let slot: RadioSlot?
    let note: String?
    let isLive: Bool
    let canListen: Bool
    var startOver = false
    let listen: () -> Void
    let stop: () -> Void

    var body: some View {
        let episode = slot?.playableEpisode
        HStack(alignment: .center, spacing: Spacing.s3) {
            HStack(spacing: Spacing.s3) {
                if let episode {
                    SeriesKeyWindow(key: GrammarSlot.seriesKey(episode.id), name: episode.series, side: 48)
                } else {
                    PictureWindow(art: nil, name: name, genre: genre, side: 48)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: name)
                        .font(TypeRamp.bodyStrong)
                        .foregroundStyle(Color.brandText)
                        .multilineTextAlignment(.leading)
                    EventLine(facts: [episode?.series, episode?.title, note])
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            if isLive {
                Button(action: stop) {
                    Label("Listening live", systemImage: "dot.radiowaves.left.and.right")
                }
                .buttonStyle(.bordered)
                .tint(Color.brandPrimary)
                .accessibilityValue("On")
                .accessibilityHint("Stops listening live")
            } else if canListen {
                Button(action: listen) {
                    Label(startOver ? "Replay" : "Listen live", systemImage: "play.fill")
                        .foregroundStyle(Color.brandOnPrimary)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.brandPrimary)
                .accessibilityLabel(startOver ? "Replay \(name) from the start" : "Listen live to \(name)")
            }
        }
        .frame(minHeight: 64)
        .listRowBackground(isLive ? Color.brandSurfaceAlt : nil)
    }
}

/// A slot on the evening's clock as the grammar's row: the series' window, the series, an event
/// line of the time and the episode, and the length, or "Now" in ink on the slot on the air.
struct SlotRow: View {
    let slot: RadioSlot
    let zone: String
    let detail: EpisodeDetail?
    let isNow: Bool
    let play: (EpisodeDetail) -> Void

    var body: some View {
        let label = RadioClock.timeLabel(slot, zone: zone)
        let length = "\(slot.lengthMin) min"
        if let detail {
            NavigationLink(value: Route.episode(detail.episode.id)) {
                GrammarRow(visual: .window(detail.episode.seriesWindowArt, name: detail.episode.seriesName,
                                           genre: detail.episode.seriesGenre),
                           title: slot.playableEpisode?.series ?? detail.episode.seriesName,
                           sub: [label.local, label.eastern, detail.episode.displayTitle, isNow ? length : nil],
                           length: length, badge: isNow ? "Now" : nil,
                           playLabel: "Play \(detail.episode.displayTitle), \(slot.playableEpisode?.series ?? detail.episode.seriesName)",
                           onPlay: { play(detail) })
            }
            .listRowBackground(isNow ? Color.brandSurfaceAlt : nil)
            .accessibilityAddTraits(isNow ? .isSelected : [])
        } else {
            // A gap is stated, never filled (R9). The paper's printed text is not drawn until the owner rules on it.
            GrammarRow(visual: .window(nil, name: slot.knownSeries ?? "", genre: nil),
                       title: slot.knownSeries ?? RadioClock.gapNote(slot),
                       sub: [label.local, label.eastern, slot.knownSeries == nil ? nil : RadioClock.gapNote(slot),
                             isNow ? length : nil],
                       length: length, badge: isNow ? "Now" : nil)
                .listRowBackground(isNow ? Color.brandSurfaceAlt : nil)
                .accessibilityAddTraits(isNow ? .isSelected : [])
        }
    }
}

#endif
