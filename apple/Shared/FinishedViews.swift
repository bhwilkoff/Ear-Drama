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
        NavigationLink(value: Route.drama(play.id)) {
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
    @Environment(\.openURL) private var openURL

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
        .onDisappear { listen.stop() }
    }

    private func read() async {
        guard play == nil else { return }
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
                HeadBoard(kicker: script.map { "Ear drama \u{00B7} \($0.kind == "radio" ? "Radio play" : "Stage play")" } ?? "Ear drama",
                          name: play.title, genre: PlayScript.boardGenre, art: nil, first: nil, last: nil,
                          facts: [script?.authorLineWithYears, FinishedDramas.dateLine(play)] as [String?],
                          credits: FinishedDramas.creditLine(play.credits, limit: 4), castScript: script)
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
                }
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
        await listen.start(archiveURL: play.archiveURL)
    }
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

    @ObservationIgnored private var queue: AVQueuePlayer?
    @ObservationIgnored private var watch: Task<Void, Never>?

    func start(archiveURL: String) async {
        guard !isActive else { return }
        state = .preparing
        guard let id = FinishedDramas.identifier(archiveURL),
              let meta = URL(string: "https://archive.org/metadata/\(id)") else {
            state = .failed("This recording would not play.")
            return
        }
        let files: [URL]
        do {
            let (data, _) = try await URLSession.shared.data(from: meta)
            files = FinishedDramas.lineFiles(metadata: data, identifier: id)
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
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, let q = self.queue else { return }
                if let failed = items.first(where: { $0.status == .failed }) {
                    self.finish(.failed(Connectivity.playerProblem(failed.error)))
                    return
                }
                if q.items().isEmpty { self.finish(.idle); return }
            }
        }
    }

    func stop() {
        guard queue != nil || state == .preparing else { return }
        finish(.idle)
    }

    private func finish(_ next: State) {
        watch?.cancel()
        watch = nil
        queue?.pause()
        queue = nil
        state = next
    }
}
