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
        return StationRow(name: "Tonight in \(evening.day.year)", slot: slot, note: note,
                          isLive: live.day == evening.day,
                          canListen: slot.flatMap { evening.detail(for: $0) } != nil) {
            player.isMuted = store.isMuted
            live.tuneIn(evening.day, details: evening.details)
        } stop: { stopLive() }
    }

    private func station(for station: Station) -> some View {
        let on = StationClock.onNow(station.slots, at: now)
        return StationRow(name: station.name, slot: on?.slot,
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

private struct StationRow: View {
    let name: String
    let slot: RadioSlot?
    let note: String?
    let isLive: Bool
    let canListen: Bool
    let listen: () -> Void
    let stop: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.s3) {
            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(verbatim: name).font(TypeRamp.bodyStrong)
                if let episode = slot?.playableEpisode {
                    Text(episode.series).font(TypeRamp.body)
                    if let title = episode.title {
                        Text(title)
                            .font(TypeRamp.caption)
                            .foregroundStyle(Color.brandTextMuted)
                            .lineLimit(1)
                    }
                }
                if let note {
                    Text(verbatim: note)
                        .font(TypeRamp.caption)
                        .foregroundStyle(Color.brandTextMuted)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
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
                    Label("Listen live", systemImage: "play.fill")
                        .foregroundStyle(Color.brandOnPrimary)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.brandPrimary)
                .accessibilityLabel("Listen live to \(name)")
            }
        }
    }
}

private struct SlotRow: View {
    let slot: RadioSlot
    let zone: String
    let detail: EpisodeDetail?
    let isNow: Bool
    let play: (EpisodeDetail) -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s3) {
            if let detail {
                NavigationLink(value: Route.episode(detail.episode.id)) {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.s3) {
                        time
                        VStack(alignment: .leading, spacing: Spacing.s1) {
                            Text(slot.playableEpisode?.series ?? detail.episode.seriesName)
                                .font(TypeRamp.bodyStrong)
                            Text(detail.episode.displayTitle)
                                .font(TypeRamp.body)
                            caption([])
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                Button { play(detail) } label: {
                    Image(systemName: "play.fill")
                }
                .buttonStyle(.borderless)
                .tint(Color.brandPrimary)
                .accessibilityLabel("Play \(detail.episode.displayTitle), \(slot.playableEpisode?.series ?? detail.episode.seriesName)")
            } else {
                // A gap is stated, never filled (R9). The paper's printed text
                // is not drawn until the owner rules on it.
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s3) {
                    time
                    VStack(alignment: .leading, spacing: Spacing.s1) {
                        if let known = slot.knownSeries {
                            Text(known).font(TypeRamp.body)
                        }
                        caption([RadioClock.gapNote(slot)])
                    }
                }
                .foregroundStyle(Color.brandTextMuted)
                .accessibilityElement(children: .combine)
            }
        }
        .listRowBackground(isNow ? Color.brandSurfaceAlt : nil)
        .accessibilityAddTraits(isNow ? .isSelected : [])
    }

    private var time: some View {
        let label = RadioClock.timeLabel(slot, zone: zone)
        return VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: label.local).font(TypeRamp.tabular)
            if let eastern = label.eastern {
                Text(verbatim: eastern)
                    .font(TypeRamp.caption)
                    .foregroundStyle(Color.brandTextMuted)
            }
        }
        .frame(minWidth: 96, alignment: .leading)
    }

    private func caption(_ middle: [String]) -> some View {
        let parts = (isNow ? ["Now"] : []) + middle + ["\(slot.lengthMin) min"]
        return Text(verbatim: parts.joined(separator: " · "))
            .font(TypeRamp.caption)
            .foregroundStyle(Color.brandTextMuted)
    }
}
#endif
