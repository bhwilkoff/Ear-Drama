import AVFoundation
import SwiftUI

// Finished ear dramas in direction D (D3-7; DESIGN-LOOP owner ruling 3): a tile in the show tile's
// grammar with the voice strip as its mark and the performers credited by their chosen names, the
// Browse scope that lists them, and a page whose head board carries the credits. Everything on
// screen is the Worker's data: nothing here writes a name, a blurb, or a list. tvOS shows and
// plays them; it records nothing.

// MARK: - The tile

enum FinishedTiles {
    static let scripts: [PlayScript] = CastableLibrary.load()?.scripts ?? []

    static func script(for play: FinishedPlay) -> PlayScript? { scripts.first { $0.id == play.scriptID } }

    #if DEBUG
    static let rehearsalPrefix = "door-along:"

    /// The Along door's stand-in for a finished drama: a bundled script (the named one, or the first with a real run of
    /// speech and three parts), never a pinned title. Its page plays nothing.
    static func rehearsal(_ pid: String) -> FinishedPlay? {
        guard pid.hasPrefix(rehearsalPrefix) else { return nil }
        let want = String(pid.dropFirst(rehearsalPrefix.count))
        let found = want == "auto"
            ? scripts.first { $0.lines.filter { $0.kind == .speech }.count >= 60 && $0.roles.count >= 3 }
            : scripts.first { $0.id == want }
        guard let found else { return nil }
        return FinishedPlay(id: pid, scriptID: found.id, title: found.title, source: nil, credits: [], archiveURL: "",
                            publishedAt: 0, scriptRevision: found.revision)
    }
    #endif

    /// A finished drama on the show tile: the drama board, the title, no picture and no run.
    static func row(_ play: FinishedPlay) -> SeriesRow {
        SeriesRow(key: play.id, name: play.title, genre: PlayScript.boardGenre, firstDate: nil, lastDate: nil,
                  networks: [], episodeCount: 0)
    }

    /// The performers first, then the date it was published.
    static func facts(_ play: FinishedPlay) -> [String] {
        [FinishedDramas.creditLine(play.credits), FinishedDramas.dateLine(play)].filter { !$0.isEmpty }
    }
}

struct FinishedTile: View {
    let play: FinishedPlay
    var width: CGFloat = ShowTile.defaultWidth

    var body: some View {
        PushLink(value: Route.drama(play.id)) {
            ShowTile(series: FinishedTiles.row(play), width: width, facts: FinishedTiles.facts(play),
                     castScript: FinishedTiles.script(for: play))
        }
        #if os(tvOS)
        .buttonStyle(.card)
        #else
        .buttonStyle(.plain)
        .navigationLinkIndicatorVisibility(.hidden)
        #endif
        .accessibilityIdentifier("drama-tile")
    }
}

// MARK: - Browse's third scope

/// What Browse lists: the shows, the most heard voices, or the finished ear dramas.
enum BrowseScope: String, CaseIterable, Hashable {
    case shows, voices, dramas
    var title: String {
        switch self {
        case .shows: "Shows"
        case .voices: "Voices"
        case .dramas: "Ear dramas"
        }
    }
}

/// The finished dramas as Browse's scope: the count and the order, then the tiles; loading, empty,
/// failed and offline each say what they are.
struct FinishedBrowse: View {
    @Environment(CatalogStore.self) private var catalog
    @State private var finished = FinishedStore.shared
    @State private var width: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            Color.clear
                .frame(maxWidth: .infinity, minHeight: 1, maxHeight: 1)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            switch finished.phase {
            case .idle, .loading:
                if finished.plays.isEmpty { ProgressView().frame(maxWidth: .infinity).padding(.top, Spacing.s6) }
            case let .failed(line):
                if finished.plays.isEmpty {
                    EmptyState(catalog.isOnline ? line : Connectivity.offlineLine, systemImage: "exclamationmark.triangle",
                               action: .init(title: "Try Again") { Task { await finished.load(force: true) } })
                }
            case .ready:
                if finished.plays.isEmpty {
                    EmptyState("No ear dramas yet", systemImage: "waveform")
                }
            }
            if !finished.plays.isEmpty, width > 0 {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s3) {
                    Text(verbatim: countText(finished.plays.count, "ear drama", "ear dramas") + (finished.hasMore ? "+" : ""))
                        .font(TypeRamp.bodyStrong)
                        .foregroundStyle(Color.brandText)
                    Spacer(minLength: 0)
                    Text("Newest first").font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
                }
                ShowGrid(items: finished.plays, fixedWidth: width) { play, tileWidth in
                    FinishedTile(play: play, width: tileWidth)
                }
                if finished.hasMore {
                    Button("Show more") { Task { await finished.more() } }
                        .buttonStyle(.borderless)
                        .font(TypeRamp.caption)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .task { await finished.load() }
    }
}

// MARK: - The page

/// A finished ear drama: the head board with the performers credited, Listen, the bill.
struct FinishedDramaScreen: View {
    let id: String
    @Environment(CatalogStore.self) private var catalog
    @Environment(AudioPlayer.self) private var player
    @Environment(AppStore.self) private var app
    @State private var finished = FinishedStore.shared
    @State private var fetched: FinishedPlay?
    @State private var missing: String?
    @State private var listen = FinishedListen()
    @State private var canFollow = false
    @Environment(\.openURL) private var openURL
    #if os(iOS) || os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    private var play: FinishedPlay? { finished.plays.first { $0.id == id } ?? fetched }

    var body: some View {
        Group {
            if let play {
                page(play)
            } else if let missing {
                EmptyState(catalog.isOnline ? missing : Connectivity.offlineLine,
                           systemImage: "questionmark.square.dashed",
                           action: .init(title: "Try Again") { Task { await read() } })
            } else {
                ProgressView()
            }
        }
        .navigationTitle(play?.title ?? "Ear drama")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task(id: id) { await read() }
        .task(id: play?.archiveURL) {
            guard let play, let script = FinishedTiles.script(for: play) else { canFollow = false; return }
            #if DEBUG
            canFollow = FinishedTiles.rehearsal(play.id) != nil ? true : await FinishedListen.canFollow(play, script: script)
            #else
            canFollow = await FinishedListen.canFollow(play, script: script)
            #endif
            #if DEBUG && os(tvOS)
            if canFollow, app.alongDoor == play.id {
                app.alongDoor = nil
                await start(play)
            }
            #endif
        }
        .onDisappear { listen.stop() }
    }

    private func read() async {
        guard play == nil else { return }
        #if DEBUG
        if let stand = FinishedTiles.rehearsal(id) { fetched = stand; return }
        #endif
        missing = nil
        do {
            fetched = try await WorkerOpenPlays(api: .shared).finished(id: id)
        } catch {
            missing = PlaysShare.line(error)
        }
    }

    private func page(_ play: FinishedPlay) -> some View {
        let script = FinishedTiles.script(for: play)
        return ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                #if os(tvOS)
                HeadBoard(kicker: script.map { "Ear drama \u{00B7} \($0.kind == "radio" ? "Radio play" : "Stage play")" } ?? "Ear drama",
                          name: play.title, genre: PlayScript.boardGenre, art: nil, first: nil, last: nil,
                          facts: [script?.authorLineWithYears, FinishedDramas.dateLine(play)] as [String?],
                          credits: FinishedDramas.creditLine(play.credits, limit: 4), castScript: script)
                #else
                ItemHeadBoard(kicker: ItemKicker.text(script.map { "Ear drama \u{00B7} \($0.kind == "radio" ? "Radio play" : "Stage play")" } ?? "Ear drama"),
                              name: play.title, genre: PlayScript.boardGenre,
                              label: script?.dramaLabel(title: play.title, published: play.publishedISO)
                                  ?? LabelItem(kind: .drama, name: play.title, finished: play.publishedISO),
                              facts: [script?.authorLineWithYears, FinishedDramas.dateLine(play)] as [String?],
                              credits: FinishedDramas.creditLine(play.credits, limit: 4),
                              cast: script.map(CastSummary.init(script:)))
                #endif
                ActionRow {
                    Button {
                        if listen.isActive { listen.stop() } else { Task { await start(play) } }
                    } label: {
                        Label(listen.isActive ? "Stop" : "Listen", systemImage: listen.isActive ? "stop.fill" : "play.fill")
                    }
                    .pageAction(primary: true)
                    .disabled(listen.state == .preparing)
                    .accessibilityIdentifier("drama-listen")
                    if let url = URL(string: play.archiveURL) {
                        Button { openURL(url) } label: {
                            ActionLabel(title: "View on archive.org", systemImage: "arrow.up.right.square")
                        }
                        .pageAction()
                    }
                    #if os(iOS) || os(macOS)
                    if canFollow {
                        Button { openAlong(play) } label: { ActionLabel(title: "Read Along", systemImage: "text.book.closed") }
                            .pageAction()
                            .accessibilityIdentifier("drama-read-along")
                    }
                    #endif
                }
                #if os(tvOS)
                if let lineID = listen.lineID, let script {
                    ReadAlongPanel_tvOS(lineID: lineID, deviceVoice: false, script: script).padding(.top, Spacing.s4)
                }
                #endif
                if listen.state == .preparing { ProgressView() }
                if case let .failed(line) = listen.state {
                    Label(catalog.isOnline ? line : Connectivity.offlineLine, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color.semanticError)
                }
                bill(play, script: script)
            }
            #if os(tvOS)
            .padding(60)
            #else
            .padding(Spacing.s4)
            #endif
            .modifier(ReadableColumn())
        }
    }

    @ViewBuilder private func bill(_ play: FinishedPlay, script: PlayScript?) -> some View {
        if !play.credits.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.s2) {
                SectionHead(title: "Credits") { EmptyView() }
                ForEach(Array(play.credits.enumerated()), id: \.offset) { _, credit in
                    BillRow(credit: credit, script: script)
                }
            }
        }
    }

    private func start(_ play: FinishedPlay) async {
        player.pause()
        listen.muted = app.isMuted
        #if DEBUG && os(tvOS)
        if FinishedTiles.rehearsal(play.id) != nil, let script = FinishedTiles.script(for: play) {
            listen.rehearse(script)
            return
        }
        #endif
        #if os(tvOS)
        // The TV's panel follows the files; the phone and Mac follow in the reader.
        await listen.start(archiveURL: play.archiveURL, script: canFollow ? FinishedTiles.script(for: play) : nil, revision: play.scriptRevision)
        #else
        await listen.start(archiveURL: play.archiveURL)
        #endif
    }

    #if os(iOS) || os(macOS)
    private func openAlong(_ play: FinishedPlay) {
        listen.stop()
        let target = StudioTarget.drama(play.id, scriptID: play.scriptID)
        #if os(macOS)
        openWindow(id: StudioWindow_macOS.id, value: StudioWindowValue(target: target, line: nil))
        #else
        app.reading = ReaderTarget(scriptID: play.scriptID, studio: target)
        #endif
    }
    #endif
}

/// A part and the name its performer chose; a part whose performer left has no name, never a made-up one.
private struct BillRow: View {
    let credit: FinishedPlay.Credit
    let script: PlayScript?

    var body: some View {
        let part = PartID(rawValue: credit.part)
        let named = !credit.name.trimmingCharacters(in: .whitespaces).isEmpty
        HStack(spacing: Spacing.s3) {
            #if os(iOS) || os(macOS)
            PartFace(hue: script?.partHue(part), holder: .person(named ? credit.name : nil))
            #endif
            Text(verbatim: part.title)
                .font(TypeRamp.bodyStrong)
                .foregroundStyle(Color.brandText)
                .lineLimit(2)
            Spacer(minLength: Spacing.s3)
            if named {
                Text(verbatim: credit.name)
                    .font(TypeRamp.body)
                    .foregroundStyle(Color.brandTextMuted)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }
        }
        .frame(minHeight: 48)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Hearing it

/// Plays a published item's line files in script order, from archive.org. Never stored.
@Observable
final class FinishedListen {
    enum State: Equatable { case idle, preparing, playing, failed(String) }

    private(set) var state: State = .idle
    var muted = false
    var isActive: Bool { state == .preparing || state == .playing }
    /// The script line the file playing speaks (PLAYS-DESIGN 2.11 rule 6); nil while stopped or without a line timeline.
    private(set) var lineID: String?

    @ObservationIgnored private var queue: AVQueuePlayer?
    @ObservationIgnored private var watch: Task<Void, Never>?

    /// The item's metadata from archive.org: its line files and their lengths.
    private static func metadata(_ archiveURL: String) async throws -> (Data, String)? {
        guard let id = FinishedDramas.identifier(archiveURL),
              let meta = URL(string: "https://archive.org/metadata/\(id)") else { return nil }
        return (try await URLSession.shared.data(from: meta).0, id)
    }

    /// Whether the item's audio has a line timeline for `script`: Read Along is offered only then, never a guessed sync.
    static func canFollow(_ play: FinishedPlay, script: PlayScript) async -> Bool {
        guard let (data, id) = try? await metadata(play.archiveURL) else { return false }
        return FinishedDramas.linePlan(metadata: data, identifier: id, script: script, revision: play.scriptRevision) != nil
    }

    /// Plays the item's line files in order; with `script`, the file playing names the line heard (`lineID`), and
    /// `from` starts at that line.
    func start(archiveURL: String, script: PlayScript? = nil, revision: String? = nil, from: String? = nil) async {
        guard !isActive else { return }
        state = .preparing
        let files: [URL]
        var plan: [FinishedLine] = []
        do {
            guard let (data, id) = try await Self.metadata(archiveURL) else {
                state = .failed("This recording would not play.")
                return
            }
            if let script, let found = FinishedDramas.linePlan(metadata: data, identifier: id, script: script, revision: revision) {
                let first = from.flatMap { id in script.lines.firstIndex { $0.id == id } }.map { $0 + 1 } ?? 0
                plan = found.filter { $0.seq >= first }
                files = plan.map(\.url)
            } else {
                files = FinishedDramas.lineFiles(metadata: data, identifier: id)
            }
        } catch {
            state = .failed(Connectivity.playerProblem(error))
            return
        }
        guard !files.isEmpty, state == .preparing else {
            if state == .preparing { state = .failed("Not ready to play yet.") }
            return
        }
        #if os(iOS) || os(tvOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        let items = files.map { AVPlayerItem(url: $0) }
        let q = AVQueuePlayer(items: items)
        q.isMuted = muted
        queue = q
        state = .playing
        q.play()
        watch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(150))
                guard let self, let q = self.queue else { return }
                if !plan.isEmpty {
                    let heard = q.currentItem.flatMap { now in items.firstIndex { $0 === now } }.flatMap { ReadAlong.line(files: plan, at: $0) }
                    if heard != self.lineID { self.lineID = heard }
                }
                if let failed = items.first(where: { $0.status == .failed }) {
                    self.finish(.failed(Connectivity.playerProblem(failed.error)))
                    return
                }
                if q.items().isEmpty { self.finish(.idle); return }
            }
        }
    }

    #if DEBUG
    /// The Along door's rehearsal: steps `lineID` through the script's speech lines every three seconds and plays nothing.
    func rehearse(_ script: PlayScript) {
        guard !isActive else { return }
        let ids = script.lines.filter { $0.kind == .speech }.map(\.id)
        guard ids.count > 12 else { return }
        state = .playing
        watch = Task { [weak self] in
            var i = 8
            while !Task.isCancelled, i < ids.count {
                self?.lineID = ids[i]
                i += 1
                try? await Task.sleep(for: .seconds(3))
            }
            self?.finish(.idle)
        }
    }
    #endif

    func stop() {
        guard queue != nil || state == .preparing || watch != nil else { return }
        finish(.idle)
    }

    private func finish(_ next: State) {
        watch?.cancel()
        watch = nil
        queue?.pause()
        queue = nil
        lineID = nil
        state = next
    }
}
