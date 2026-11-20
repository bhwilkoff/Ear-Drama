#if os(iOS) || os(macOS)
import SwiftUI

// Home's first screen on the iPhone, iPad and Mac (WEB-DESIGN §4.2r rules 1-3, iOS-DESIGN §4.1, macOS-DESIGN §3.1,
// Decision 081): On the air as the hero on its show's board, the dial of genre stations under it, and the two quiet
// doors. "The goal is to have the home view feel more cohesive and inviting from the moment that you open the app."

// MARK: - On the air

struct HomeOnAirSection: View {
    /// The show on the air, reported so the rows under it skip it (a show at most once per Home).
    @Binding var heroKey: String?
    @Environment(CatalogStore.self) private var catalog
    @Environment(AudioPlayer.self) private var player
    @Environment(AppStore.self) private var store
    @Environment(LiveRadio.self) private var radio
    @State private var load: OnAirLoad = .loading
    @State private var attempt = 0
    @State private var now = Date()
    @State private var tuning = false
    @State private var series: SeriesRow?
    private struct Key: Hashable { let date: String; let attempt: Int }

    private var on: OnAirNow? {
        if case let .ready(day, stations) = load { return OnAirNow.pick(day: day, stations: stations, now: now) }
        return nil
    }

    var body: some View {
        Group {
            switch load {
            case .loading:
                PageSection {
                    ProgressView().frame(maxWidth: .infinity).gridRow()
                }
            case .failed:
                PageSection {
                    VStack(alignment: .leading, spacing: Spacing.s2) {
                        Label("Tonight could not load", systemImage: "wifi.slash")
                            .font(TypeRamp.body)
                            .foregroundStyle(Color.brandTextMuted)
                        Button("Try Again") { load = .loading; attempt += 1 }
                            .pageAction()
                    }
                    .gridRow(.words)
                }
            case let .ready(_, stations):
                if let on {
                    PageSection { hero(on).gridRow() }
                }
                let entries = DialEntry.entries(stations, now: now)
                if !entries.isEmpty {
                    PageSection {
                        HomeDial(entries: entries)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .pageBleed()
                    }
                }
            }
        }
        .task(id: Key(date: RadioClock.localDate(now), attempt: attempt)) {
            load = await OnAirLoad.load(now: now)
        }
        .task {
            while !Task.isCancelled {
                guard (try? await Task.sleep(for: .seconds(15))) != nil else { return }
                now = Date()
            }
        }
        .task(id: on?.episode.id) {
            let key = on.map { GrammarSlot.seriesKey($0.episode.id) }
            heroKey = key
            guard let key, !key.isEmpty else { series = nil; return }
            series = await catalog.series([key]).first
        }
    }

    private func hero(_ on: OnAirNow) -> some View {
        let listening = on.isLive(radio)
        return OnAirHeroBoard(on: on, series: series, now: now, listening: listening, tuning: tuning, onListen: {
            if listening {
                on.stopListening(live: radio, player: player)
            } else {
                tuning = true
                Task {
                    await on.tuneIn(catalog: catalog, live: radio, player: player, muted: store.isMuted)
                    tuning = false
                }
            }
        }, onStations: { store.push(Route.stations) })
    }
}

/// The hero board, stateless: its window (the show's picture, else its label with the evening's year ticked) full
/// column width on a phone and 320 pt beside the words on a wider layout, then the kicker, the show's name, the
/// event line, Listen Live and All Stations.
struct OnAirHeroBoard: View {
    let on: OnAirNow
    let series: SeriesRow?
    let now: Date
    let listening: Bool
    var tuning = false
    let onListen: () -> Void
    let onStations: () -> Void
    @State private var width: CGFloat = 0

    /// Past a phone's column the window stands beside the words, 320 pt, as on the web.
    private static let besideFrom: CGFloat = 560
    private static let window: CGFloat = 320

    /// The show's label with the evening's year ticked, for a window with no picture.
    private var label: LabelItem {
        var item = series?.labelItem ?? LabelItem(kind: .series, name: on.episode.series, genre: series?.genre)
        item.tickYear = on.tickYear
        return item
    }

    var body: some View {
        let beside = width >= Self.besideFrom
        let genre = series?.genre
        let ink = Color.onBoard(genre)
        let episode = on.episode
        let side = beside ? Self.window : max(width, 1)
        let window = PushLink(value: Route.episode(episode.id)) {
            PictureWindow(art: series?.windowArt, name: episode.series, genre: genre, side: side, label: label)
        }
        .buttonStyle(.plain)
        .accessibilityHidden(true)
        let words = VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack(spacing: Spacing.s2) {
                Circle().fill(ink).frame(width: 8, height: 8).accessibilityHidden(true)
                Text(verbatim: "On the air \u{00B7} \(on.kicker)".uppercased())
                    .font(TypeRamp.caption)
                    .tracking(1.2)
                    .lineLimit(1)
            }
            PushLink(value: Route.episode(episode.id)) {
                Text(verbatim: series?.name ?? episode.series)
                    .font(TypeRamp.pageTitle)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("on-air-row")
            EventLine(facts: [HomeShows.heroTitle(episode.title, id: episode.id), "\(on.minutesIn(now)) min in"], color: ink)
            if let note = on.note {
                Text(verbatim: note).font(TypeRamp.caption)
            }
            buttons.padding(.top, Spacing.s1)
        }
        .foregroundStyle(ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        Group {
            if beside {
                HStack(alignment: .center, spacing: 0) {
                    window
                    words.padding(Spacing.s6)
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    window
                    words.padding(Spacing.s4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.board(genre))
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .accessibilityElement(children: .contain)
    }

    private var buttons: some View {
        ActionRow {
            Button(action: onListen) {
                Label(listening ? "Listening Live" : "Listen Live",
                      systemImage: listening ? "waveform" : "dot.radiowaves.left.and.right")
            }
            .pageAction(primary: true)
            .disabled(tuning)
            .accessibilityIdentifier("listen-live")
            .accessibilityAddTraits(listening ? .isSelected : [])
            Button(action: onStations) { ActionLabel(title: "All Stations", systemImage: "radio") }
                .pageAction()
                .accessibilityIdentifier("all-stations")
        }
        .environment(\.actionBoard, .some(series?.genre))
    }
}

// MARK: - The dial

/// Every genre station as a small label, its genre's name and the show on now; a press tunes in. It does what
/// the Listen door did.
struct HomeDial: View {
    let entries: [DialEntry]
    @Environment(CatalogStore.self) private var catalog
    @Environment(AudioPlayer.self) private var player
    @Environment(AppStore.self) private var store
    @Environment(LiveRadio.self) private var radio
    @State private var tuning = false

    var body: some View {
        DialRow(entries: entries, listening: radio.station, busy: tuning) { entry in
            guard let on = entry.on else { return }
            if radio.station == entry.station.genre {
                on.stopListening(live: radio, player: player)
            } else {
                tuning = true
                Task {
                    await on.tuneIn(catalog: catalog, live: radio, player: player, muted: store.isMuted)
                    tuning = false
                }
            }
        }
    }
}

/// The dial, stateless: `listening` is the genre of the station tuned in, if any.
struct DialRow: View {
    let entries: [DialEntry]
    let listening: String?
    var busy = false
    /// False draws the stations in one unscrolled row (the render rig: ImageRenderer cannot draw a ScrollView).
    var scrolls = true
    let tune: (DialEntry) -> Void

    private static let mark: CGFloat = 56
    private static let column: CGFloat = 96

    var body: some View {
        let row = HStack(alignment: .top, spacing: Spacing.s2) {
            ForEach(entries) { entry in station(entry) }
        }
        .railPadding()
        .padding(.vertical, Spacing.s2)
        Group {
            if scrolls {
                ScrollView(.horizontal) { row }.scrollIndicators(.hidden)
            } else {
                row
            }
        }
        .accessibilityIdentifier("home-dial")
    }

    private func station(_ entry: DialEntry) -> some View {
        let on = listening == entry.station.genre
        return Button { tune(entry) } label: {
            VStack(spacing: 2) {
                StationMark(station: entry.station, year: entry.year, side: Self.mark)
                    .padding(.bottom, Spacing.s1)
                Text(verbatim: entry.station.name)
                    .font(TypeRamp.caption.weight(.semibold))
                    .foregroundStyle(on ? Color.brandSecondary : Color.brandText)
                Text(verbatim: entry.show ?? "")
                    .font(TypeRamp.caption)
                    .foregroundStyle(Color.brandTextMuted)
            }
            .lineLimit(1)
            .frame(width: Self.column)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(Haptic.selection.feedback, trigger: listening)
        .disabled(entry.on == nil || busy)
        .accessibilityLabel(entry.show.map { "\(on ? "Listening live to" : "Listen live to") \(entry.station.name): \($0)" }
                            ?? "\(entry.station.name): nothing on")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: - The doors

/// Two quiet buttons in one row (WEB-DESIGN §4.2r rule 3; iOS-DESIGN §4.1r: borderless, an SF Symbol and a verb each):
/// the dial does what the Listen door did.
struct HomeDoors: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        PageSection {
            HStack(spacing: Spacing.s6) {
                Button { store.selectedTab = .browse } label: { Label("Find a Show", systemImage: AppTab.browse.symbol) }
                    .accessibilityIdentifier("door-Find a Show")
                Button { store.selectedTab = .record } label: { Label("Record a Play", systemImage: AppTab.record.symbol) }
                    .accessibilityIdentifier("door-Record a Play")
                Spacer(minLength: 0)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.brandSecondary)
            .font(TypeRamp.bodyStrong)
            .lineLimit(1)
            .frame(minHeight: 44)
            .gridRow(.words)
        }
    }
}
#endif
