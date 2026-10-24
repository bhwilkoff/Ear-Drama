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
            ContentUnavailableView("No evening is published for today", systemImage: "radio")
        case .failed:
            ContentUnavailableView {
                Label("Tonight could not load", systemImage: "wifi.slash")
            } actions: {
                Button("Try Again") { attempt += 1 }
            }
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
        return StationCard_tvOS(name: "Tonight in \(evening.day.year)", slot: slot, note: note,
                                isLive: live.day == evening.day,
                                canListen: slot.flatMap { evening.detail(for: $0) } != nil) {
            player.isMuted = store.isMuted
            live.tuneIn(evening.day, details: evening.details)
            store.isPlayerPresented = true
        } stop: { stopLive() }
    }

    private func card(for station: Station) -> some View {
        let on = StationClock.onNow(station.slots, at: now)
        return StationCard_tvOS(name: station.name, slot: on?.slot,
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

private struct StationCard_tvOS: View {
    let name: String
    let slot: RadioSlot?
    let note: String?
    let isLive: Bool
    let canListen: Bool
    let listen: () -> Void
    let stop: () -> Void

    var body: some View {
        Button {
            if isLive { stop() } else if canListen { listen() }
        } label: {
            VStack(alignment: .leading, spacing: Spacing.s2) {
                Text(verbatim: name).font(TypeRamp.bodyStrong)
                if let episode = slot?.playableEpisode {
                    Text(episode.series).font(TypeRamp.body).lineLimit(1)
                    if let title = episode.title {
                        Text(title).font(TypeRamp.caption).lineLimit(1)
                    }
                }
                if let note {
                    Text(verbatim: note).font(TypeRamp.caption)
                }
                Spacer(minLength: 0)
                if isLive {
                    Label("Listening live", systemImage: "dot.radiowaves.left.and.right")
                        .font(TypeRamp.caption)
                } else if canListen {
                    Label("Listen live", systemImage: "play.fill")
                        .font(TypeRamp.caption)
                }
            }
            .frame(width: 520, height: 260, alignment: .topLeading)
            .padding(Spacing.s6)
        }
        .buttonStyle(.card)
        .accessibilityValue(isLive ? "Listening live" : "")
    }
}

/// A surviving slot opens its episode (Play is on Detail, §4.4); a gap is a
/// focus stop that reads its time, length, and why, never the printed text.
private struct SlotRow_tvOS: View {
    let slot: RadioSlot
    let zone: String
    let detail: EpisodeDetail?
    let isNow: Bool
    @FocusState private var focused: Bool

    var body: some View {
        if let detail {
            NavigationLink(value: Route.episode(detail.episode.id)) {
                row(title: slot.playableEpisode?.series ?? detail.episode.seriesName,
                    subtitle: detail.episode.displayTitle, note: nil)
            }
        } else {
            row(title: slot.knownSeries, subtitle: nil, note: RadioClock.gapNote(slot))
                .padding(Spacing.s4)
                .foregroundStyle(focused ? Color.brandText : Color.brandTextMuted)
                .background(RoundedRectangle(cornerRadius: Radius.card).fill(focused ? Color.brandSurfaceAlt : .clear))
                .focusable()
                .focused($focused)
        }
    }

    private func row(title: String?, subtitle: String?, note: String?) -> some View {
        let label = RadioClock.timeLabel(slot, zone: zone)
        let caption = ((isNow ? ["Now"] : []) + [note].compactMap { $0 } + ["\(slot.lengthMin) min"])
            .joined(separator: " · ")
        return HStack(alignment: .firstTextBaseline, spacing: Spacing.s6) {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: label.local).font(TypeRamp.tabular)
                if let eastern = label.eastern {
                    Text(verbatim: eastern).font(TypeRamp.caption)
                }
            }
            .frame(minWidth: 240, alignment: .leading)
            VStack(alignment: .leading, spacing: Spacing.s1) {
                if let title { Text(title).font(TypeRamp.bodyStrong) }
                if let subtitle { Text(subtitle).font(TypeRamp.body).lineLimit(2) }
                Text(verbatim: caption).font(TypeRamp.caption)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 1400, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
#endif
