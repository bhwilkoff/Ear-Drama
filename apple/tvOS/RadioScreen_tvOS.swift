#if os(tvOS)
import SwiftUI

// Stations on the TV (tvOS-DESIGN §4.8): a shelf of station cards, Tonight in
// 19xx first and then the genre stations, each listening live into Now
// Playing full screen; then tonight's evening as a schedule the remote
// scrolls, every slot a focus stop so only the focused one is bright.

struct RadioScreen_tvOS: View {
    @Environment(CatalogStore.self) private var catalog
    @State private var load: RadioLoad = .loading
    @State private var stations: StationsLoad = .loading
    @State private var attempt = 0
    @FocusState private var shelfFocused: Bool
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
    }

    @ViewBuilder private func content(now: Date) -> some View {
        switch load {
        case .loading:
            ProgressView()
        case .nothing where !stations.stations.isEmpty:
            ScrollView(.vertical) {
                StationsShelf_tvOS(evening: nil, stations: stations.stations, now: now, focus: $shelfFocused)
                    .padding(.horizontal, 90)
                    .padding(.vertical, 60)
            }
            .defaultFocus($shelfFocused, true)
        case .nothing:
            EmptyState("No evening is published for today", systemImage: "radio")
        case .failed:
            EmptyState("Tonight could not load", systemImage: "wifi.slash",
                       action: .init(title: "Try Again") { attempt += 1 })
        case let .evening(evening):
            Evening_tvOS(evening: evening, stations: stations.stations, now: now, picked: $picked)
        }
    }
}

private struct Evening_tvOS: View {
    let evening: RadioEvening
    let stations: [Station]
    let now: Date
    @Binding var picked: String?
    @Environment(AudioPlayer.self) private var player
    @Environment(AppStore.self) private var store
    @Environment(LiveRadio.self) private var live
    @FocusState private var liveFocused: Bool

    var body: some View {
        let slots = evening.day.slots
        let onAir = RadioClock.onAir(slots, at: now)
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: Spacing.s8) {
                StationsShelf_tvOS(evening: evening, stations: stations, now: now, focus: $liveFocused)

                VStack(alignment: .leading, spacing: Spacing.s3) {
                    Text(verbatim: "Tonight in \(evening.day.year)")
                        .font(TypeRamp.pageTitle)
                        .foregroundStyle(Color.brandText)
                    Text(verbatim: RadioClock.longDate(evening.day.evening))
                        .font(TypeRamp.body)
                        .foregroundStyle(Color.brandText)
                    if let line = evening.day.stationLine {
                        Text(verbatim: line)
                            .font(TypeRamp.caption)
                            .foregroundStyle(Color.brandTextMuted)
                    }
                }
                .accessibilityElement(children: .combine)

                if evening.choices.count > 1 {
                    HStack { yearMenu }.focusSection()
                }

                VStack(alignment: .leading, spacing: Spacing.s2) {
                    ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                        SlotRow_tvOS(slot: slot, zone: evening.zone, detail: evening.detail(for: slot),
                                     isNow: index == onAir.index)
                    }
                }
                .focusSection()

                // The TV opens no web page, so the listing's credit is text.
                if let line = evening.day.witnessLine {
                    Text(verbatim: "Schedule: \(line)")
                        .font(TypeRamp.caption)
                        .foregroundStyle(Color.brandTextMuted)
                }
            }
            .padding(.horizontal, 90)
            .padding(.vertical, 60)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .defaultFocus($liveFocused, true)
    }
}

extension Evening_tvOS {
    /// Decision 067: another published year for the same date, in the action
    /// row; picking one ends listening live. Absent when the date offers none.
    @ViewBuilder var yearMenu: some View {
        if evening.choices.count > 1 {
            Menu {
                ForEach(evening.choices, id: \.self) { choice in
                    Button(String(choice.prefix(4))) {
                        if live.day == evening.day { live.stop() }
                        picked = choice
                    }
                }
            } label: {
                Label("Year \(evening.day.year)", systemImage: "calendar")
            }
        }
    }
}

/// The stations shelf at ten feet (tvOS-DESIGN §4.8): Tonight first, then each
/// genre station, one card a station in its own focus section, only the
/// focused card lifted. Pressing a card listens live and opens Now Playing;
/// pressing the one on the air pauses and stops.
private struct StationsShelf_tvOS: View {
    let evening: RadioEvening?
    let stations: [Station]
    let now: Date
    var focus: FocusState<Bool>.Binding
    @Environment(AudioPlayer.self) private var player
    @Environment(AppStore.self) private var store
    @Environment(LiveRadio.self) private var live
    @Environment(CatalogStore.self) private var catalog

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: Spacing.s8) {
                if let evening {
                    tonight(evening).focused(focus)
                }
                ForEach(Array(stations.enumerated()), id: \.element.id) { index, station in
                    if index == 0 && evening == nil {
                        card(for: station).focused(focus)
                    } else {
                        card(for: station)
                    }
                }
            }
            .padding(.vertical, Spacing.s6)
        }
        .scrollClipDisabled()
        .focusSection()
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
        return StationCard_tvOS(name: "Tonight in \(evening.day.year)", genre: nil, slot: slot, note: note,
                                isLive: live.day == evening.day,
                                canListen: slot.flatMap { evening.detail(for: $0) } != nil) {
            player.isMuted = store.isMuted
            live.tuneIn(evening.day, details: evening.details)
            store.isPlayerPresented = true
        } stop: { stopLive() }
    }

    private func card(for station: Station) -> some View {
        let on = StationClock.onNow(station.slots, at: now)
        return StationCard_tvOS(name: station.name, genre: station.genre, slot: on?.slot,
                                note: on.flatMap { $0.slot.playableEpisode == nil ? RadioClock.gapNote($0.slot) : nil },
                                isLive: live.station == station.genre,
                                canListen: on?.slot.playableEpisode != nil) {
            Task {
                let slots = StationClock.ahead(station.slots, from: Date())
                let details = await StationsLoad.details(slots, catalog: catalog)
                player.isMuted = store.isMuted
                live.tuneIn(station: station, slots: slots, details: details)
                store.isPlayerPresented = true
            }
        } stop: { stopLive() }
    }

    private func stopLive() {
        player.pause()
        live.stop()
    }
}

/// A station as the grammar's tile on its genre's board: its show's window, the station's name, the
/// strip, and what is on; focus lifts the whole tile through the card style.
private struct StationCard_tvOS: View {
    let name: String
    let genre: String?
    let slot: RadioSlot?
    let note: String?
    let isLive: Bool
    let canListen: Bool
    let listen: () -> Void
    let stop: () -> Void
    @Environment(CatalogStore.self) private var catalog
    @State private var show: SeriesRow?

    var body: some View {
        let episode = slot?.playableEpisode
        let key = episode.map { GrammarSlot.seriesKey($0.id) } ?? ""
        Button {
            if isLive { stop() } else if canListen { listen() }
        } label: {
            ShowTile(series: SeriesRow(key: "station-\(name)", name: name, genre: genre ?? show?.genre, firstDate: nil,
                                       lastDate: nil, networks: [], episodeCount: 0, face: show?.face, picture: show?.picture),
                     facts: [episode?.series, episode?.title ?? note, isLive ? "Listening live" : nil].compactMap { $0 })
        }
        .buttonStyle(.card)
        .accessibilityValue(isLive ? "Listening live" : "")
        .accessibilityHint(isLive ? "Stops listening live" : "Listens live")
        .task(id: key) {
            show = key.isEmpty ? nil : await catalog.series([key]).first
        }
    }
}

/// A surviving slot opens its episode (Play is on Detail, §4.4); a gap is a focus stop that reads
/// its time, length, and why, never the printed text. Each is the grammar's row, "Now" in ink on
/// the slot on the air.
private struct SlotRow_tvOS: View {
    let slot: RadioSlot
    let zone: String
    let detail: EpisodeDetail?
    let isNow: Bool
    @FocusState private var focused: Bool

    var body: some View {
        let label = RadioClock.timeLabel(slot, zone: zone)
        let length = "\(slot.lengthMin) min"
        if let detail {
            NavigationLink(value: Route.episode(detail.episode.id)) {
                GrammarRow(visual: .window(detail.episode.seriesWindowArt, name: detail.episode.seriesName,
                                           genre: detail.episode.seriesGenre),
                           title: slot.playableEpisode?.series ?? detail.episode.seriesName,
                           sub: [label.local, label.eastern, detail.episode.displayTitle, isNow ? length : nil],
                           length: length, badge: isNow ? "Now" : nil)
            }
        } else {
            GrammarRow(visual: .window(nil, name: slot.knownSeries ?? "", genre: nil),
                       title: slot.knownSeries ?? RadioClock.gapNote(slot),
                       sub: [label.local, label.eastern, slot.knownSeries == nil ? nil : RadioClock.gapNote(slot),
                             isNow ? length : nil],
                       length: length, badge: isNow ? "Now" : nil)
                .padding(Spacing.s4)
                .foregroundStyle(focused ? Color.brandText : Color.brandTextMuted)
                .background(RoundedRectangle(cornerRadius: Radius.card).fill(focused ? Color.brandSurfaceAlt : .clear))
                .focusable()
                .focused($focused)
        }
    }
}
#endif
