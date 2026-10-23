#if os(tvOS)
import SwiftUI

// Tonight in 19xx on the TV (tvOS-DESIGN §4.8): the evening as a schedule
// the remote scrolls, every slot a focus stop so only the focused one is
// bright, Listen live in the action row, and Now Playing full screen.

struct RadioScreen_tvOS: View {
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
    }

    @ViewBuilder private func content(now: Date) -> some View {
        switch load {
        case .loading:
            ProgressView()
        case .nothing:
            ContentUnavailableView("No evening is published for today", systemImage: "radio")
        case .failed:
            ContentUnavailableView {
                Label("Tonight could not load", systemImage: "wifi.slash")
            } actions: {
                Button("Try Again") { attempt += 1 }
            }
        case let .evening(evening):
            Evening_tvOS(evening: evening, now: now)
        }
    }
}

private struct Evening_tvOS: View {
    let evening: RadioEvening
    let now: Date
    @Environment(AudioPlayer.self) private var player
    @Environment(AppStore.self) private var store
    @Environment(LiveRadio.self) private var live
    @FocusState private var liveFocused: Bool

    var body: some View {
        let slots = evening.day.slots
        let onAir = RadioClock.onAir(slots, at: now)
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: Spacing.s8) {
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

                status(onAir)

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
            HStack(spacing: Spacing.s6) {
                if live.day == evening.day {
                    Button {
                        player.pause()
                        live.stop()
                    } label: {
                        Label("Listening live", systemImage: "dot.radiowaves.left.and.right")
                    }
                    .focused($liveFocused)
                    .accessibilityValue("On")
                    .accessibilityHint("Stops listening live")
                } else if let index = onAir.index, evening.detail(for: slots[index]) != nil {
                    Button {
                        player.isMuted = store.isMuted
                        live.tuneIn(evening.day, details: evening.details)
                        store.isPlayerPresented = true
                    } label: {
                        Label("Listen live", systemImage: "play.fill")
                    }
                    .focused($liveFocused)
                }
            }
            .focusSection()
        }
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
