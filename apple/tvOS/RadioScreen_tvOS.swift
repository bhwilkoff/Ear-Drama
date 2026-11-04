#if os(tvOS)
import SwiftUI

// Stations on the TV (tvOS-DESIGN §4.8, §4.8a): a shelf of station cards, Tonight in
// 19xx first and then the genre stations, each listening live into Now
// Playing full screen; then tonight's evening as a shelf of slots in time order.

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
                    .padding(.top, TV.rootClearance)
                    .padding(.bottom, 60)
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
            VStack(alignment: .leading, spacing: Spacing.s6) {
                StationsShelf_tvOS(evening: evening, stations: stations, now: now, focus: $liveFocused)

                VStack(alignment: .leading, spacing: Spacing.s1) {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.s4) {
                        Text(verbatim: RadioClock.longDate(evening.day.evening))
                            .font(TypeRamp.sectionHeader)
                            .foregroundStyle(Color.brandText)
                        if let line = evening.day.stationLine {
                            Text(verbatim: line)
                                .font(TypeRamp.caption)
                                .foregroundStyle(Color.brandTextMuted)
                        }
                        Spacer(minLength: 0)
                        yearMenu
                    }
                    .focusSection()

                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: TV.cardGap) {
                            ForEach(RadioClock.entries(slots, isDead: { evening.detail(for: $0) == nil }), id: \.self) { entry in
                                switch entry {
                                case .slot(let index):
                                    SlotCard_tvOS(slot: slots[index], zone: evening.zone, detail: evening.detail(for: slots[index]),
                                                  isNow: index == onAir.index)
                                case .run(let indices):
                                    GapRun_tvOS(slots: indices.map { slots[$0] }, zone: evening.zone,
                                                isNow: onAir.index.map(indices.contains) ?? false)
                                }
                            }
                        }
                        .padding(.vertical, Spacing.s4)
                    }
                    .scrollClipDisabled()
                    .scrollIndicators(.hidden)
                    .focusSection()

                    // The TV opens no web page, so the listing's credit is text.
                    if let line = evening.day.witnessLine {
                        Text(verbatim: "Schedule: \(line)")
                            .font(TypeRamp.caption)
                            .foregroundStyle(Color.brandTextMuted)
                    }
                }
            }
            .padding(.top, TV.rootClearance)
            .padding(.bottom, 60)
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
                    // Two evenings can share a year; only their dates tell them apart.
                    let year = String(choice.prefix(4))
                    Button(evening.choices.filter { $0.hasPrefix(year) }.count > 1 ? AirDate.medium(choice) : year) {
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
            LazyHStack(alignment: .top, spacing: TV.cardGap) {
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
            .padding(.vertical, Spacing.s4)
        }
        .scrollClipDisabled()
        .scrollIndicators(.hidden)
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
        let ended = onAir.phase == .after
        return StationCard_tvOS(name: "Tonight in \(evening.day.year)", genre: nil, slot: slot, note: note,
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

/// A station as the wide card on its genre's board: what is on now, its show's window; focus lifts
/// the whole card through the card style.
private struct StationCard_tvOS: View {
    let name: String
    let genre: String?
    let slot: RadioSlot?
    let note: String?
    let isLive: Bool
    let canListen: Bool
    var startOver = false
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
            TVWideCard(art: show?.windowArt, name: name, genre: genre ?? show?.genre, title: name, display: true,
                       sub: episode?.series ?? note,
                       foot: isLive ? "Listening live" : startOver && canListen ? "Replay from the start" : episode?.title)
        }
        .buttonStyle(.card)
        .accessibilityValue(isLive ? "Listening live" : "")
        .accessibilityHint(isLive ? "Stops listening live" : startOver ? "Replays from the start" : "Listens live")
        .task(id: key) {
            show = key.isEmpty ? nil : await catalog.series([key]).first
        }
    }
}

/// A dead slot or a run of them: narrow and quiet, so what survives leads (§4.8a).
private struct GapCard_tvOS: View {
    let time: String
    let title: String
    var foot: String? = nil
    var isNow = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: time).font(TypeRamp.caption).lineLimit(1)
            Text(verbatim: title).font(TypeRamp.caption).lineLimit(3).multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            if isNow {
                Text(verbatim: "Now").font(TypeRamp.caption.weight(.semibold))
            } else if let foot {
                Text(verbatim: foot).font(TypeRamp.caption).lineLimit(1)
            }
        }
        .foregroundStyle(Color.brandTextMuted)
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s3)
        .frame(width: 320, height: TV.wideCard.height, alignment: .topLeading)
        .background(Color.brandSurface)
    }
}

/// A run of slots with no recording: one focus stop that opens to the individual slots.
private struct GapRun_tvOS: View {
    let slots: [RadioSlot]
    let zone: String
    let isNow: Bool
    @State private var open = false

    var body: some View {
        let label = RadioClock.runLabel(slots)
        Button { open.toggle() } label: {
            GapCard_tvOS(time: label.span, title: label.note, isNow: isNow)
        }
        .buttonStyle(.card)
        .accessibilityValue(open ? "Open" : "Closed")
        if open {
            ForEach(slots) { SlotCard_tvOS(slot: $0, zone: zone, detail: nil, isNow: false) }
        }
    }
}

/// A surviving slot opens its episode (Play is on Detail, §4.4); a gap reads its time, length and
/// why, never the printed text. The time heads the card, the paper's own time at its foot.
private struct SlotCard_tvOS: View {
    let slot: RadioSlot
    let zone: String
    let detail: EpisodeDetail?
    let isNow: Bool

    var body: some View {
        let label = RadioClock.timeLabel(slot, zone: zone)
        let length = "\(slot.lengthMin) min"
        let foot = [label.eastern.map { "Aired \($0)" }, length].compactMap { $0 }.joined(separator: " \u{00B7} ")
        if let detail {
            NavigationLink(value: Route.episode(detail.episode.id)) {
                TVWideCard(art: detail.episode.seriesWindowArt, name: detail.episode.seriesName, genre: detail.episode.seriesGenre,
                           top: label.local, title: slot.playableEpisode?.series ?? detail.episode.seriesName,
                           sub: detail.episode.displayTitle, foot: foot, badge: isNow ? "Now" : nil)
            }
            .buttonStyle(.card)
        } else {
            Button {} label: {
                GapCard_tvOS(time: label.local, title: slot.knownSeries ?? RadioClock.gapNote(slot),
                             foot: slot.knownSeries == nil ? length : RadioClock.gapNote(slot), isNow: isNow)
            }
            .buttonStyle(.card)
        }
    }
}
#endif
