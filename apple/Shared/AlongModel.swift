#if os(iOS) || os(macOS)
import SwiftUI

/// The read-along inside the reader (PLAYS-DESIGN §2.11): a production's listen-through (takes from their files, open
/// lines in the cast's device voices), a finished drama's line files, or the reader's Hear the Cast (every line in the
/// play's cast voices). Device voices are live and never stored. The reader follows `lineID` and draws `word`; the
/// transport plays, pauses at a line, steps a line either way, sets the speed and stops.
@Observable
final class AlongModel {
    enum Kind: Equatable { case production, drama, table }

    let kind: Kind
    /// The listen-through (a production, or Hear the Cast); nil for a finished drama.
    let listen: LiveListenThrough?
    /// A finished drama's files, the file playing naming the line heard (rule 11); nil otherwise.
    let drama: FinishedListen?
    /// The line a pause holds (lit, not playing); nil while playing or stopped.
    private(set) var held: String?
    /// Starting a line (the gap while the last one stops), so the transport does not flicker to Play.
    private(set) var starting = false
    /// The transport's speed, a multiplier on each part's own speed, remembered on this device (rule 7).
    var speed: Double {
        didSet {
            ReadAlong.saveSpeed(speed)
            listen?.speed = speed
            drama?.speed = speed
        }
    }

    @ObservationIgnored private let production: Production?
    @ObservationIgnored private let play: FinishedPlay?
    @ObservationIgnored private let script: PlayScript
    @ObservationIgnored private let store: ProductionStore?
    @ObservationIgnored private let lineIndex: [String: Int]
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var spoken: (id: String, value: ReadAlong.Spoken)?
    /// The doors that open the reader start reading at once (rule 1); Hear the Cast starts on its press.
    @ObservationIgnored var startsOnOpen: Bool

    init(production: Production, script: PlayScript, plays: PlaysLibrary) {
        kind = .production
        self.production = production
        self.script = script
        play = nil
        drama = nil
        store = plays.store
        listen = .system(cast: .production(production.id, script: script))
        speed = ReadAlong.savedSpeed()
        lineIndex = Self.index(script)
        startsOnOpen = true
        listen?.speed = speed
    }

    init(play: FinishedPlay, script: PlayScript) {
        kind = .drama
        self.play = play
        self.script = script
        production = nil
        store = nil
        listen = nil
        drama = FinishedListen()
        speed = ReadAlong.savedSpeed()
        lineIndex = Self.index(script)
        startsOnOpen = true
        drama?.speed = speed
    }

    /// Hear the Cast: the script read from a line, each part in the play's cast voice (§2.8 rule 2).
    init(table script: PlayScript, cast: VoiceCast) {
        kind = .table
        self.script = script
        production = nil
        play = nil
        store = nil
        drama = nil
        listen = .system(cast: cast)
        speed = ReadAlong.savedSpeed()
        lineIndex = Self.index(script)
        startsOnOpen = false
        listen?.speed = speed
    }

    private static func index(_ script: PlayScript) -> [String: Int] {
        Dictionary(script.lines.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    var isRunning: Bool { starting || (listen?.isRunning ?? drama?.isActive ?? false) }
    var isPaused: Bool { !isRunning && held != nil }
    /// Playing or holding a line: the transport and the light stay.
    var isActive: Bool { isRunning || held != nil }
    /// The line heard now, or the line a pause holds.
    var lineID: String? { listen?.current?.lineID ?? drama?.lineID ?? held }
    /// A line the device reads aloud; a finished drama has only voices.
    var deviceVoice: Bool { listen?.current?.isDeviceVoice ?? false }
    /// The line heard, for the transport's speaker.
    var line: ScriptLine? { lineID.flatMap { lineIndex[$0] }.map { script.lines[$0] } }

    /// The word heard, as offsets into the line's printed words (rule 3); nil for a take, a drama, or a voice with no
    /// word timing.
    var word: ReadAlong.Word? {
        guard let w = listen?.word, case let .voice(id, _, text)? = listen?.current,
              let i = lineIndex[id] else { return nil }
        let s: ReadAlong.Spoken
        if let cached = spoken, cached.id == id { s = cached.value } else {
            s = ReadAlong.spoken(script.lines[i])
            spoken = (id, s)
        }
        guard s.said == DeviceVoices.said(text) else { return nil }
        return ReadAlong.word(s, location: w.start, length: w.end - w.start)
    }

    // MARK: The transport

    /// Plays from script line `index` (the reader's place, or a line stepped to).
    func play(from index: Int, player: AudioPlayer, muted: Bool = false) {
        guard !script.lines.isEmpty else { return }
        player.pause()
        let from = min(max(0, index), script.lines.count - 1)
        held = nil
        starting = true
        task?.cancel()
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.halt()
            guard !Task.isCancelled else { return }
            if let drama = self.drama, let play = self.play {
                drama.muted = muted
                self.starting = false
                await drama.start(archiveURL: play.archiveURL, script: self.script, revision: play.scriptRevision,
                                  from: self.script.lines[from].id)
                return
            }
            guard let listen = self.listen else { return }
            let plan = self.plan(from: from)
            self.starting = false
            if let production = self.production, let store = self.store {
                let latest = store.production(production.id) ?? production
                await listen.run(plan) { store.takeURL(latest, $0) }
            } else {
                await listen.run(plan) { _ in URL(fileURLWithPath: "/dev/null") }
            }
        }
    }

    /// The plan from script line `from` on: a production's takes and open lines, or every line the cast reads.
    private func plan(from: Int) -> [ListenEntry] {
        let ids = Set(script.lines[from...].map(\.id))
        if let production, let store, let listen {
            let latest = store.production(production.id) ?? production
            return Relay.listenPlan(latest, script, reads: listen.reads).filter { ids.contains($0.lineID) }
        }
        guard let listen else { return [] }
        return script.lines[from...].compactMap { line in
            guard line.kind == .speech || listen.reads(line.part), !DeviceVoices.said(line.spokenText).isEmpty else { return nil }
            return .voice(lineID: line.id, part: line.part, text: line.spokenText)
        }
    }

    /// Stops what plays and waits until it has stopped.
    private func halt() async {
        listen?.stop()
        drama?.stop()
        while listen?.isRunning == true { try? await Task.sleep(for: .milliseconds(20)) }
    }

    /// Pause holds the line heard; Play starts that line again from its beginning (rule 6).
    func togglePlay(position: Int, player: AudioPlayer, muted: Bool = false) {
        if isRunning {
            pause()
        } else {
            let at = held.flatMap { lineIndex[$0] } ?? position
            play(from: at, player: player, muted: muted)
        }
    }

    func pause() {
        let now = lineID
        task?.cancel()
        starting = false
        listen?.stop()
        drama?.stop()
        held = now
    }

    /// The previous (-1) or next (1) line the read-along reads: playing, it plays from there; paused, it holds there.
    func step(_ direction: Int, position: Int, player: AudioPlayer, muted: Bool = false) {
        let at = lineID.flatMap { lineIndex[$0] } ?? position
        guard let target = nextLine(after: at, direction: direction) else { return }
        if isRunning {
            play(from: target, player: player, muted: muted)
        } else {
            held = script.lines[target].id
        }
    }

    /// The nearest line after `at` in `direction` that the read-along would read (a speech, or a part with a voice).
    func nextLine(after at: Int, direction: Int) -> Int? {
        var i = at + (direction < 0 ? -1 : 1)
        while script.lines.indices.contains(i) {
            let line = script.lines[i]
            let reads = line.kind == .speech || (listen?.reads(line.part) ?? false)
            if reads, !DeviceVoices.said(line.spokenText).isEmpty { return i }
            i += direction < 0 ? -1 : 1
        }
        return nil
    }

    func stop() {
        task?.cancel()
        starting = false
        held = nil
        listen?.stop()
        drama?.stop()
    }
}

/// The read-along's transport (PLAYS-DESIGN §2.11 rule 6): who is speaking, previous line, play or pause, next line,
/// speed, stop. Icons on a phone, words from regular width (and on the Mac), where the page count shows too.
struct AlongTransport: View {
    let along: AlongModel
    let pageLabel: String
    let hue: (ScriptLine) -> Color
    let playPause: () -> Void
    let step: (Int) -> Void
    let stop: () -> Void
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var wide: Bool {
        #if os(macOS)
        true
        #else
        sizeClass == .regular
        #endif
    }

    var body: some View {
        @Bindable var along = along
        HStack(spacing: Spacing.s2) {
            if let line = along.line {
                Text(verbatim: line.role ?? line.part.title)
                    .font(TypeRamp.bodyStrong)
                    .foregroundStyle(hue(line))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .accessibilityIdentifier("along-speaker")
            }
            Spacer(minLength: 0)
            button("Previous Line", "backward.end.fill", id: "along-previous") { step(-1) }
                #if os(macOS)
                .keyboardShortcut(.leftArrow, modifiers: .option)
                #endif
            button(along.isRunning ? "Pause" : "Play", along.isRunning ? "pause.fill" : "play.fill", id: "along-play", action: playPause)
                #if os(macOS)
                .keyboardShortcut(.space, modifiers: [])
                #endif
            button("Next Line", "forward.end.fill", id: "along-next") { step(1) }
                #if os(macOS)
                .keyboardShortcut(.rightArrow, modifiers: .option)
                #endif
            Menu {
                Picker("Speed", selection: $along.speed) {
                    ForEach(ReadAlong.speeds, id: \.self) { x in Text(verbatim: ReadAlong.speedLabel(x)).tag(x) }
                }
            } label: {
                Text(verbatim: ReadAlong.speedLabel(along.speed))
                    .font(TypeRamp.tabular)
                    .frame(minWidth: 36, minHeight: 28)
            }
            .menuIndicator(.hidden)
            .accessibilityLabel("Speed")
            .accessibilityValue(ReadAlong.speedLabel(along.speed))
            .accessibilityIdentifier("along-speed")
            if along.isActive {
                button("Stop", "stop.fill", id: "along-stop", action: stop)
            }
            if wide {
                Text(verbatim: pageLabel)
                    .lineLimit(1)
                    .fixedSize()
                    .font(TypeRamp.tabular)
                    .foregroundStyle(Color.brandTextMuted)
                    .accessibilityIdentifier("reader-page-label")
            }
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s2)
        .background(Color.brandSurface)
    }

    @ViewBuilder private func button(_ title: String, _ symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if wide, symbol == "play.fill" || symbol == "pause.fill" {
                Label(title, systemImage: symbol)
            } else {
                Label(title, systemImage: symbol).labelStyle(.iconOnly)
            }
        }
        .accessibilityIdentifier(id)
    }
}

/// Read Along on a production's page: opens the reader on the production's own script, reading along at once.
struct ReadAlongButton: View {
    let production: Production
    @Environment(AppStore.self) private var app
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    var body: some View {
        Button { open() } label: { ActionLabel(title: "Read Along", systemImage: "text.book.closed") }
            .pageAction()
            .accessibilityIdentifier("read-along-button")
    }

    private func open() {
        let target = StudioTarget.along(production.id)
        #if os(macOS)
        openWindow(id: StudioWindow_macOS.id, value: StudioWindowValue(target: target, line: nil))
        #else
        app.reading = ReaderTarget(scriptID: production.scriptID, studio: target)
        #endif
    }
}
#endif
