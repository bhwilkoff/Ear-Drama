#if os(iOS) || os(macOS)
import SwiftUI

// Tonight in 19xx on the iPhone, iPad, and Mac (iOS-DESIGN §4.9, macOS-DESIGN
// §4.3): the evening published for the listener's own date, as a List of its
// slots on the one clock. The TV has its own focus-driven screen.

struct RadioScreen: View {
    @Environment(CatalogStore.self) private var catalog
    @State private var load: RadioLoad = .loading
    @State private var attempt = 0

    private struct Key: Hashable { let date: String; let load: Int; let attempt: Int }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            content(now: context.date)
                .task(id: Key(date: RadioClock.localDate(context.date), load: catalog.loadKey, attempt: attempt)) {
                    load = await RadioLoad.load(catalog: catalog, now: context.date)
                }
        }
        .navigationTitle("Stations")
    }

    @ViewBuilder private func content(now: Date) -> some View {
        switch load {
        case .loading:
            List { SkeletonRows() }
        case .nothing:
            ContentUnavailableView("No evening is published for today", systemImage: "radio")
        case .failed:
            ContentUnavailableView {
                Label("Tonight could not load", systemImage: "wifi.slash")
            } actions: {
                Button("Try Again") { attempt += 1 }
            }
        case let .evening(evening):
            EveningList(evening: evening, now: now)
        }
    }
}

private struct EveningList: View {
    let evening: RadioEvening
    let now: Date
    @Environment(AudioPlayer.self) private var player
    @Environment(AppStore.self) private var store
    @Environment(LiveRadio.self) private var live

    var body: some View {
        let slots = evening.day.slots
        let onAir = RadioClock.onAir(slots, at: now)
        List {
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
                status(onAir)
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

    @ViewBuilder private func status(_ onAir: RadioClock.OnAir) -> some View {
        let slots = evening.day.slots
        switch onAir.phase {
        case .before:
            if let first = slots.first {
                Text(verbatim: "Starts at \(RadioClock.clock(first.utcStart))")
                    .font(TypeRamp.caption)
                    .foregroundStyle(Color.brandTextMuted)
            }
        case .after:
            if let end = RadioClock.end(of: slots) {
                Text(verbatim: "Ended at \(RadioClock.clock(end))")
                    .font(TypeRamp.caption)
                    .foregroundStyle(Color.brandTextMuted)
            }
        case .during:
            if live.day == evening.day {
                Button {
                    player.pause()
                    live.stop()
                } label: {
                    Label("Listening live", systemImage: "dot.radiowaves.left.and.right")
                }
                .buttonStyle(.bordered)
                .tint(Color.brandPrimary)
                .accessibilityValue("On")
                .accessibilityHint("Stops listening live")
            } else if let index = onAir.index, evening.detail(for: slots[index]) != nil {
                Button {
                    player.isMuted = store.isMuted
                    live.tuneIn(evening.day, details: evening.details)
                } label: {
                    Label("Listen live", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.brandPrimary)
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
