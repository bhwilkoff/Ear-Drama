#if os(iOS) || os(macOS)
import AVFoundation
import SwiftUI
#if os(iOS)
import GameController
#endif

// The studio inside the reader (PLAYS-DESIGN §2.9 binding; iOS-DESIGN §4.15 "The studio", macOS-DESIGN §4.7; Decision
// 076 S3). One model, three homes: a dock under the page on a phone (the take list, the cast and the rest in a sheet),
// a trailing pane once the reader holds 860 pt (iPad, the open iPhone Duo), and the reader window's inspector on a Mac.
// The engine and the take model are the recorder's (`RecordingSession`, `Production`); `StudioController` moves the
// current line. Red is the record control's and the microphone's only (Decision 064).

/// The record red, named once for the reader's page (the outline while a cue plays and the microphone is open).
enum StudioPalette {
    static let record = Color.brandRecord
    static let onRecord = Color.brandOnRecord
}

// MARK: - The model

@Observable
final class StudioModel {
    enum Gate: Equatable { case ready, microphoneDenied, needsHeadphones, airPlay }

    let target: StudioTarget
    let part: PartID
    let script: PlayScript
    let session: RecordingSession
    let studio: StudioController
    let listen: LiveListenThrough
    var gate: Gate = .ready
    /// The phone's sheet: takes, cast, listen through, delete unused, done.
    var sheet = false
    /// The Mac inspector (⌥⌘I).
    var inspector = true
    var refusal: String?
    var confirmingUnused = false
    /// Set when the part is done and the studio should close.
    var finished = false
    @ObservationIgnored private var doorTaken = false
    @ObservationIgnored private var ended = false
    @ObservationIgnored private let audio: LiveAudio
    @ObservationIgnored private let store: ProductionStore
    @ObservationIgnored let stubbed: Bool

    init?(target: StudioTarget, plays: PlaysLibrary, line: String?) {
        guard let production = plays.store.production(target.production), let script = plays.castScript(for: production) else {
            return nil
        }
        self.target = target
        part = target.partID
        self.script = script
        store = plays.store
        let door = StudioDoor.current
        stubbed = door.stub
        audio = door.stub ? StubLiveAudio() : EngineLiveAudio()
        let voice: StandInVoice = door.stub ? SilentStandIn() : KokoroStandInVoice.app(cast: .production(production.id, script: script))
        session = RecordingSession(production: production, script: script, part: target.partID, store: plays.store,
                                   audio: audio, voice: voice)
        session.setMode(.remembered())
        studio = StudioController(session: session, store: plays.store, line: line)
        listen = .system(cast: .production(production.id, script: script))
        ProductionPresence.appear(production.id)
    }

    var shared: Bool { store.share(target.production) != nil }

    var hue: Color { Color.genre(script.partHue(part)) ?? Color.brandText }

    var started: Bool { session.started && !isRoomTone }

    var isRoomTone: Bool { if case .roomTone = session.phase { true } else { false } }

    var isListening: Bool { if case .listening = session.phase { true } else { false } }

    var isCue: Bool { if case .cue = session.phase { true } else { false } }

    var inReview: Bool {
        if case .review = session.phase { return true }
        return session.phase == .runReview
    }

    /// The microphone is asked for here, at Start Recording, never at launch; the route is checked and refused (§4.3).
    func begin(echoCancelled: Bool, player: AudioPlayer) async {
        if !stubbed {
            guard await AVAudioApplication.requestRecordPermission() else {
                gate = .microphoneDenied
                return
            }
        }
        switch audio.outputRoute() {
        case .airPlay:
            gate = .airPlay
            return
        case .speaker where !echoCancelled:
            gate = .needsHeadphones
            return
        default: break
        }
        gate = .ready
        player.pause()
        await session.begin(echoCancelled: echoCancelled)
    }

    func setMode(_ mode: RecordingSession.Mode) {
        if session.setMode(mode) { mode.remember() }
    }

    func primary() {
        quiet()
        Task { await studio.primary() }
    }

    func again(_ line: String? = nil) {
        quiet()
        if session.phase == .runReview, line == nil, let last = session.runTakes.last {
            Task { await studio.again(last.lineID) }
        } else {
            Task { await studio.again(line) }
        }
    }

    func keep() { studio.keep() }

    /// Recording and listening never overlap: a record press stops the listen-through first.
    private func quiet() { if listen.isRunning { listen.stop() } }

    /// Listen Through From Here: the play from the current line, takes from their files and the rest in the cast's
    /// device voices, live and never stored (§2.6, §5); the reader follows.
    func listenFromHere() {
        if listen.isRunning { listen.stop(); return }
        let production = session.production
        let at = script.lines.firstIndex { $0.id == studio.current } ?? 0
        let ids = Set(script.lines[at...].map(\.id))
        let plan = Relay.listenPlan(production, script, reads: listen.reads).filter { ids.contains($0.lineID) }
        let store = store
        Task { await listen.run(plan) { store.takeURL(production, $0) } }
    }

    var missing: Int { Relay.missingLines(part, in: session.production, script: script).count }

    func finish() {
        guard let production = store.production(target.production) else { return }
        do {
            store.update(try Relay.finish(part, in: production, script: script))
            end()
            finished = true
        } catch {
            refusal = RelayRefusalText.text(error)
        }
    }

    /// Signed out, a production with no take while another on this device holds one is a second production: the gate
    /// asks for an account in place of Start Recording (PLAYS-DESIGN §2.3 rule 3; the reader's own Record lands here).
    func needsAccount(signedIn: Bool) -> Bool {
        guard !stubbed else { return false }
        let empty = !(store.production(target.production)?.hasTake ?? false)
        return StudioCore.needsAccount(productions: store.productions, signedIn: signedIn, makingNew: empty)
    }

    /// Leaving the reader ends the session and closes the microphone, as leaving the recorder did. A local, unshared
    /// production left with no take is deleted (rule 3a) once its take writes have settled, and never while
    /// its cast sheet is on screen.
    func end() {
        listen.stop()
        session.end()
        guard !ended else { return }
        ended = true
        let store = store, id = target.production
        ProductionPresence.disappear(id)
        Task { await store.removeWhenSettled(id, isHeld: { ProductionPresence.shows(id) }) }
    }

    /// APP_STUDIO_PHASE with the stub engine only (DEBUG): idle starts the studio, listening opens a take on the current
    /// line (Line by line), takes opens the sheet. The stub never opens the microphone, so nothing is recorded.
    func openDoor(player: AudioPlayer) async {
        guard stubbed, !doorTaken, let phase = StudioDoor.current.phase else { return }
        doorTaken = true
        await begin(echoCancelled: false, player: player)
        switch phase {
        case "listening":
            setMode(.lines)
            primary()
        case "takes":
            sheet = true
        default: break
        }
    }

    /// The take list for a line: it becomes current; on a phone the sheet opens on it.
    func openTakes(_ line: String) {
        studio.select(line)
        sheet = true
    }
}

/// Where the studio records: the production and the part (PLAYS-DESIGN §2.9 rule 1's one seam).
enum StudioOpen {
    /// The reader's Record: continue the part where it records, else take it where it is open, else a new production.
    static func resolve(_ plays: PlaysLibrary, script: PlayScript, part: PartID) -> StudioTarget? {
        let store = plays.store
        switch StudioCore.productionFor(store.productions, isShared: { store.share($0) != nil }, script: script, part: part) {
        case let .resume(id):
            return StudioTarget(production: id, part: part.rawValue)
        case let .take(id):
            guard let p = store.production(id), let cast = plays.castScript(for: p),
                  let taken = try? Relay.take(part, performer: nil, in: p, script: cast) else { return nil }
            store.update(taken)
            return StudioTarget(production: id, part: part.rawValue)
        case .make:
            guard let made = try? store.create(script),
                  let taken = try? Relay.take(part, performer: nil, in: made, script: script) else { return nil }
            store.update(taken)
            return StudioTarget(production: made.id, part: part.rawValue)
        }
    }

    /// The cast sheet's doors (Take Part, Record, Open Part): a part being recorded here, or a line being replaced,
    /// opens the studio; in a shared production only the person's own part does (another's keeps its read-along).
    static func target(for part: PartID, production id: String, replacing: String?, plays: PlaysLibrary,
                       shared: SharedPlays) -> StudioTarget? {
        guard let production = plays.store.production(id) else { return nil }
        guard production.state(of: part).status == .recording || replacing != nil else { return nil }
        if plays.store.share(id) != nil {
            guard let rec = shared.record(for: production, in: plays.store), PlaysShare.isMine(rec, part, shared.userID) else {
                return nil
            }
        }
        return StudioTarget(production: id, part: part.rawValue)
    }

    /// Opens the reader with the studio: a full-screen cover on iPhone and iPad, its own window on a Mac.
    static func open(_ target: StudioTarget, scriptID: String, line: String?, app: AppStore, openWindow: OpenWindowAction) {
        #if os(macOS)
        openWindow(id: StudioWindow_macOS.id, value: StudioWindowValue(target: target, line: line))
        #else
        app.reading = ReaderTarget(scriptID: scriptID, line: line, studio: target)
        #endif
    }
}

/// DEBUG doors for frames without a microphone (never in a Release build): APP_STUDIO_STUB=1 records nothing and
/// plays nothing (a stub engine that never opens the microphone); APP_STUDIO_PHASE=listening starts a take on the
/// current line so the recording state can be seen, `takes` opens the take list.
struct StudioDoor {
    var stub = false
    var phase: String?

    static let current: StudioDoor = {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        return StudioDoor(stub: env["APP_STUDIO_STUB"] == "1", phase: env["APP_STUDIO_PHASE"])
        #else
        return StudioDoor()
        #endif
    }()
}

/// Opens no microphone and plays nothing: room tone and every take come back empty, so nothing is written.
private final class StubLiveAudio: LiveAudio {
    func outputRoute() -> AudioRoute { .headphones }
    func start(echoCancelled: Bool) throws {}
    func play(_ cue: CueAudio) async {}
    func beginCapture(_ onChunk: @escaping @MainActor @Sendable ([Float]) -> Void) {}
    func endCapture() -> MicrophoneCapture { MicrophoneCapture(samples: [], sampleRate: TakeAudio.sampleRate) }
    func stop() {}
}

private final class SilentStandIn: StandInVoice {
    func render(_ text: String, part: PartID, rate: Float) async -> StandInAudio? { nil }
}

// MARK: - The dock (compact)

/// Under the page on a phone, the closed Duo and a narrow window (§2.9 rule 6): the mode, one status row, the transport.
struct StudioDock: View {
    let model: StudioModel

    var body: some View {
        VStack(spacing: Spacing.s2) {
            StudioControls(model: model, compact: true)
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.top, Spacing.s2)
        .frame(maxWidth: .infinity)
        .background(Color.brandSurface)
        .accessibilityIdentifier("studio-dock")
    }
}

/// The mode, the status row and the transport, or before the first take the gate. One view for the dock and the pane.
struct StudioControls: View {
    let model: StudioModel
    var compact: Bool
    @Environment(AccountStore.self) private var account
    @Environment(AudioPlayer.self) private var player
    @Environment(CatalogStore.self) private var catalog

    var body: some View {
        Group {
            if model.started {
                Picker("Mode", selection: Binding(get: { model.session.mode }, set: { model.setMode($0) })) {
                    ForEach(RecordingSession.Mode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(model.studio.locked)
                .accessibilityIdentifier("studio-mode")
                StudioStatus(model: model, compact: compact)
                StudioTransport(model: model)
            } else {
                gate
            }
        }
        #if os(iOS)
        .sensoryFeedback(Haptic.selection.feedback, trigger: model.session.listeningSince != nil)
        #endif
        .task { await model.openDoor(player: player) }
    }

    @ViewBuilder private var gate: some View {
        VStack(spacing: Spacing.s2) {
            if case let .roomTone(seconds) = model.session.phase {
                HStack(spacing: Spacing.s3) {
                    Text("Quiet, please. Recording the room.").font(TypeRamp.bodyStrong)
                    Text(verbatim: "\(seconds)").font(TypeRamp.sectionHeader).monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            } else if model.needsAccount(signedIn: account.status != .signedOut) {
                Text("A second production needs an account.").font(TypeRamp.bodyStrong)
                if catalog.isOnline {
                    if account.status == .signedOut { SignInButtons().frame(maxWidth: 320) }
                } else {
                    Label(Connectivity.offlineLine, systemImage: "wifi.slash")
                        .font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
                }
            } else {
                switch model.gate {
                case .ready:
                    Button {
                        Task { await model.begin(echoCancelled: false, player: player) }
                    } label: {
                        Label("Start Recording", systemImage: "mic").frame(maxWidth: 320)
                    }
                    .buttonStyle(.play(.record))
                    .accessibilityIdentifier("studio-start")
                    Label("Headphones on", systemImage: "headphones")
                        .font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
                case .microphoneDenied:
                    Text("Ear Drama needs the microphone to record your part.").foregroundStyle(Color.semanticError)
                    OpenSettingsButton()
                case .needsHeadphones:
                    Text("Plug in headphones.").foregroundStyle(Color.semanticError)
                    HStack {
                        Button("Check Again") { Task { await model.begin(echoCancelled: false, player: player) } }
                            .buttonStyle(.play(.way))
                        Button("Record Without Headphones") {
                            Task { await model.begin(echoCancelled: true, player: player) }
                        }
                        .buttonStyle(.play(.way))
                    }
                case .airPlay:
                    Text("AirPlay delays sound too much to record. Choose headphones.").foregroundStyle(Color.semanticError)
                    Button("Check Again") { Task { await model.begin(echoCancelled: false, player: player) } }
                        .buttonStyle(.play(.way))
                }
            }
            if case let .failed(message) = model.session.phase {
                Label(message, systemImage: "exclamationmark.triangle").font(TypeRamp.caption).foregroundStyle(Color.semanticError)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.s2)
        .accessibilityIdentifier("studio-gate")
    }
}

private struct OpenSettingsButton: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button("Open Settings") {
            #if os(iOS)
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            #else
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") { openURL(url) }
            #endif
        }
        .buttonStyle(.play(.way))
    }
}

/// One row: the line's place and its takes; the speaker during a cue; "Recording 0:03" and the meter while listening.
private struct StudioStatus: View {
    let model: StudioModel
    var compact: Bool

    var body: some View {
        let session = model.session
        Group {
            switch session.phase {
            case .listening:
                HStack(spacing: Spacing.s3) {
                    Circle().fill(StudioPalette.record).frame(width: 10, height: 10)
                    if let since = session.listeningSince {
                        TimelineView(.periodic(from: since, by: 1)) { context in
                            let s = max(0, Int(context.date.timeIntervalSince(since)))
                            Text(verbatim: "Recording \(s / 60):\(String(format: "%02d", s % 60))").monospacedDigit()
                        }
                    } else {
                        Text("Recording")
                    }
                    StudioMeter(levels: session.levels)
                }
                .font(TypeRamp.bodyStrong)
                .foregroundStyle(StudioPalette.record)
                .accessibilityElement(children: .combine)
            case let .cue(lineID, deviceVoice):
                let line = model.script.lines.first { $0.id == lineID }
                HStack(spacing: Spacing.s2) {
                    Text(verbatim: line?.part.title ?? "")
                        .font(TypeRamp.bodyStrong)
                        .foregroundStyle(line.flatMap { Color.genre(model.script.partHue($0.part)) } ?? Color.brandText)
                    if deviceVoice { Text("Device voice").font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted) }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            default:
                let place = model.studio.place
                let state = model.studio.current.map(model.studio.lineState)
                HStack(spacing: Spacing.s2) {
                    Text(verbatim: "Line \(place.at) of \(place.of)").font(TypeRamp.tabular).foregroundStyle(Color.brandTextMuted)
                    Spacer(minLength: 0)
                    if session.mode == .run, session.run == nil, let state, state.state != .none, let line = model.studio.current {
                        Button { model.again(line) } label: {
                            Label("Again", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(.play(.again))
                        .disabled(session.isBusy)
                        .accessibilityIdentifier("studio-again-line")
                    }
                    if let state {
                        Button {
                            if let line = model.studio.current { model.openTakes(line) }
                        } label: {
                            Label(StudioCore.takesLabel(state), systemImage: TakeMarkGlyph.symbol(state.state))
                                .font(TypeRamp.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .tint(state.state == .flagged ? Color.semanticWarning : model.hue)
                        .disabled(!compact)
                        .accessibilityLabel(StudioCore.spoken(state))
                        .accessibilityIdentifier("studio-takes")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
    }
}

/// The take-state glyphs (§2.9 rule 3): an empty ring, a filled ring with the count, the warning.
enum TakeMarkGlyph {
    static func symbol(_ kind: StudioCore.LineState.Kind) -> String {
        switch kind {
        case .none: "circle"
        case .chosen: "circle.fill"
        case .flagged: "exclamationmark.triangle.fill"
        }
    }
}

private struct StudioMeter: View {
    let levels: [Float]

    var body: some View {
        let shown = Array(levels.suffix(24))
        HStack(spacing: 2) {
            ForEach(0..<24, id: \.self) { i in
                let slot = i - (24 - shown.count)
                Capsule()
                    .fill(StudioPalette.record)
                    .frame(width: 3, height: slot >= 0 ? max(3, 22 * CGFloat(shown[slot])) : 3)
            }
        }
        .frame(height: 24)
        .accessibilityHidden(true)
    }
}

/// Previous, the one round control, Next; Step's review Again, With Cue, Keep; a run's review Discard or Keep N.
struct StudioTransport: View {
    let model: StudioModel

    var body: some View {
        let session = model.session
        Group {
            if case let .review(id) = session.phase {
                HStack(spacing: Spacing.s2) {
                    Button { model.again(id) } label: {
                        Label("Again", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.play(.again))
                    .accessibilityIdentifier("studio-again")
                    Button {
                        if let take = session.production.chosenTake(for: id) { Task { await session.playWithCue(take) } }
                    } label: {
                        Label("With Cue", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.play(.way))
                    Button { model.keep() } label: {
                        Label("Keep", systemImage: "checkmark").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.play(.ink))
                    .accessibilityIdentifier("studio-keep")
                }
            } else if session.phase == .runReview {
                let n = session.runTakes.count
                HStack(spacing: Spacing.s2) {
                    Button { session.discardRun() } label: { Text("Discard the Run").frame(maxWidth: .infinity) }
                        .buttonStyle(.play(.way))
                    Button { model.keep() } label: {
                        Label(n == 1 ? "Keep 1 Take" : "Keep \(n) Takes", systemImage: "checkmark").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.play(.ink))
                    .accessibilityIdentifier("studio-keep")
                }
            } else {
                let hearing = model.listen.isRunning
                HStack {
                    Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
                    Button { move(-1) } label: {
                        Label("Previous Line", systemImage: "backward.end").labelStyle(.iconOnly).frame(width: 44, height: 44)
                    }
                    .disabled(model.studio.locked || model.studio.current == model.studio.mine.first)
                    .accessibilityIdentifier("studio-previous")
                    Spacer()
                    RecordControl(model: model)
                    Spacer()
                    Button { move(1) } label: {
                        Label("Next Line", systemImage: "forward.end").labelStyle(.iconOnly).frame(width: 44, height: 44)
                    }
                    .disabled(model.studio.locked || model.studio.current == model.studio.mine.last)
                    .accessibilityIdentifier("studio-next")
                    Button { model.listenFromHere() } label: {
                        Label(hearing ? "Stop" : "Listen From Here", systemImage: hearing ? "stop.fill" : "play.fill")
                            .labelStyle(.iconOnly)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(hearing ? Color.brandSurfaceAlt : Color.clear))
                    }
                    .disabled(!hearing && (session.isBusy || session.run != nil))
                    .accessibilityAddTraits(hearing ? .isSelected : [])
                    .accessibilityIdentifier("studio-listen")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.brandSecondary)
            }
        }
        .padding(.bottom, Spacing.s2)
    }

    private func move(_ delta: Int) {
        if model.studio.move(delta), let id = model.studio.current { model.studio.onFollow?(id) }
    }
}

/// The round record control, 52 pt: Record (From Here in Run through), Stop while the microphone is open, Cancel in
/// ink while a cue plays, Pause during a run.
private struct RecordControl: View {
    let model: StudioModel

    var body: some View {
        let session = model.session
        let (title, symbol, red): (String, String, Bool) = {
            if session.run != nil { return model.isListening ? ("Stop", "stop.fill", true) : ("Pause", "pause.fill", false) }
            if model.isListening { return ("Stop", "stop.fill", true) }
            if model.isCue { return ("Cancel", "xmark", false) }
            return session.mode == .run ? ("From Here", "mic.fill", true) : ("Record", "mic.fill", true)
        }()
        VStack(spacing: 2) {
            Button { model.primary() } label: {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(red ? StudioPalette.onRecord : Color.brandOnPrimary)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(red ? StudioPalette.record : Color.brandPrimary))
            }
            .buttonStyle(.plain)
            .disabled(session.isBusy && !model.isListening && !model.isCue && session.run == nil)
            .accessibilityLabel(title)
            .accessibilityInputLabels([title])
            .accessibilityIdentifier("studio-record")
            Text(verbatim: title).font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
        }
    }
}

// MARK: - The panel (the sheet, the pane, the inspector)

/// Takes for the current line, the cast, Listen Through From Here, Delete Unused Takes, Done With This Part, and the
/// keys. `full` (the pane and the inspector) adds the mode, status and transport, since there is no dock there.
struct StudioPanel: View {
    let model: StudioModel
    let voices: VoiceCastModel
    var full = false
    var close: (() -> Void)?
    @Environment(\.openWindow) private var openWindow
    #if os(iOS)
    @State private var picking: PartID?
    #endif

    var body: some View {
        let studio = model.studio
        List {
            Section {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: model.part.title).font(TypeRamp.sectionHeader).foregroundStyle(model.hue)
                    Spacer()
                    Text(verbatim: "\(studio.kept) of \(studio.mine.count)").font(TypeRamp.tabular).foregroundStyle(Color.brandTextMuted)
                }
                .accessibilityElement(children: .combine)
                if full {
                    VStack(spacing: Spacing.s2) { StudioControls(model: model, compact: false) }
                        .listRowSeparator(.hidden)
                }
            }
            takesSection
            Section("Cast") {
                ForEach(model.script.castParts) { part in
                    HStack {
                        Text(verbatim: part.title).font(TypeRamp.body).lineLimit(1)
                        Spacer(minLength: Spacing.s2)
                        if part.id == model.part {
                            Text("You").font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
                        } else {
                            chip(part.id)
                        }
                    }
                }
            }
            Section {
                Button {
                    model.listenFromHere()
                } label: {
                    Label(model.listen.isRunning ? "Stop Listening" : "Listen Through From Here",
                          systemImage: model.listen.isRunning ? "stop.fill" : "play.fill")
                }
                .disabled(model.session.isBusy)
                if !studio.unused.isEmpty {
                    // The confirmation hangs on this button (iOS-DESIGN §3.6c), not on the panel's List.
                    Button("Delete Unused Takes", role: .destructive) { model.confirmingUnused = true }
                        .disabled(studio.locked)
                        .confirmationDialog(unusedTitle, isPresented: Binding(get: { model.confirmingUnused },
                                                                              set: { model.confirmingUnused = $0 }),
                                            titleVisibility: .visible) {
                            Button("Delete Unused Takes", role: .destructive) { model.studio.deleteUnused() }
                        } message: {
                            Text("The chosen take of each line stays.")
                        }
                }
                if !model.shared {
                    Button("Done With This Part") { model.finish() }
                        .disabled(studio.locked || model.missing > 0)
                    if model.missing > 0 {
                        Text(model.missing == 1 ? "1 line to go" : "\(model.missing) lines to go")
                            .font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
                    }
                }
                if let refusal = model.refusal {
                    Text(verbatim: refusal).font(TypeRamp.caption).foregroundStyle(Color.semanticError)
                }
            }
            if hasKeyboard {
                Section("Keys") {
                    key("Space", "Record, stop or cancel")
                    key("J  K", "My next or previous line")
                    key("R", "Record again")
                    key("Return", "Keep")
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        // Beside the script at regular width the panel's cards began flush against the reader (iOS-DESIGN §3.6a).
        .pageMargins()
        .navigationTitle("Studio")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $picking) { part in VoicePickerScreen(model: voices, script: model.script, part: part) }
        .toolbar {
            if let close { ToolbarItem(placement: .confirmationAction) { Button("Done", action: close) } }
        }
        #else
        .listStyle(.sidebar)
        #endif
        .repaintsOnVoiceChange(voices)
        .accessibilityIdentifier("studio-panel")
    }

    private var unusedTitle: String {
        let n = model.studio.unused.count
        return n == 1 ? "Delete 1 unused take?" : "Delete \(n) unused takes?"
    }

    @ViewBuilder private var takesSection: some View {
        let session = model.session
        if session.phase == .runReview {
            Section("This Run") {
                ForEach(session.runTakes) { take in
                    HStack {
                        Text(verbatim: "Line \(lineNumber(take.lineID))").font(TypeRamp.body)
                        Text(verbatim: String(format: "%.1f s", take.seconds)).font(TypeRamp.tabular).foregroundStyle(Color.brandTextMuted)
                        Spacer()
                        Button { Task { await session.playWithCue(take) } } label: { Label("Play With Cue", systemImage: "play.fill") }
                            .labelStyle(.iconOnly)
                            .disabled(session.isBusy)
                        Button { model.again(take.lineID) } label: { Text("Again") }
                            .buttonStyle(.play(.again))
                            .disabled(session.isBusy)
                    }
                }
            }
        } else if let line = model.studio.current {
            let takes = model.studio.takes(line)
            Section {
                ForEach(Array(takes.enumerated()), id: \.element.id) { n, take in
                    TakeRow(model: model, take: take, number: n + 1, chosen: session.production.chosen[line] == take.id)
                }
                if model.started {
                    Button { model.again(line) } label: { Label(takes.isEmpty ? "Record" : "Record Again", systemImage: "mic") }
                        .disabled(session.isBusy || session.run != nil)
                }
            } header: {
                Text(verbatim: "Takes \u{00B7} Line \(lineNumber(line))")
            }
        }
    }

    private func lineNumber(_ id: String) -> Int { (model.studio.mine.firstIndex(of: id) ?? 0) + 1 }

    @ViewBuilder private func chip(_ part: PartID) -> some View {
        #if os(iOS)
        VoiceChip(model: voices, part: part) { picking = part }
        #else
        VoiceChip(model: voices, script: model.script, part: part)
        #endif
    }

    private var hasKeyboard: Bool {
        #if os(macOS)
        true
        #else
        GCKeyboard.coalesced != nil
        #endif
    }

    private func key(_ key: String, _ action: String) -> some View {
        HStack {
            Text(verbatim: key).font(TypeRamp.caption.weight(.semibold).monospaced())
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.brandSurfaceAlt, in: RoundedRectangle(cornerRadius: 4))
            Text(verbatim: action).font(TypeRamp.caption)
        }
    }
}

/// One take: choose it (a radio), "Take 2" over its length, Play, With Cue, and Delete on an unchosen take only.
private struct TakeRow: View {
    let model: StudioModel
    let take: Take
    let number: Int
    let chosen: Bool

    var body: some View {
        let session = model.session
        HStack(spacing: Spacing.s3) {
            Button { model.studio.choose(take) } label: {
                Image(systemName: chosen ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(chosen ? model.hue : Color.brandTextMuted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Choose take \(number)")
            .accessibilityAddTraits(chosen ? .isSelected : [])
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "Take \(number)").font(TypeRamp.bodyStrong)
                HStack(spacing: Spacing.s1) {
                    Text(verbatim: String(format: "%.1f s", take.seconds)).font(TypeRamp.tabular)
                    if take.bleed {
                        Label("Re-take", systemImage: "exclamationmark.triangle.fill").foregroundStyle(Color.semanticWarning)
                    }
                }
                .font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
            }
            Spacer(minLength: 0)
            Button { Task { await session.playTake(take) } } label: { Label("Play", systemImage: "play.fill") }
                .labelStyle(.iconOnly)
                .disabled(!model.started || session.isBusy)
            Button { Task { await session.playWithCue(take) } } label: { Text("With Cue") }
                .disabled(!model.started || session.isBusy)
            if !chosen {
                Button(role: .destructive) { model.studio.deleteTake(take) } label: { Label("Delete", systemImage: "trash") }
                    .labelStyle(.iconOnly)
                    .disabled(session.isBusy)
                    .accessibilityIdentifier("take-delete")
            }
        }
        .buttonStyle(.borderless)
        .contextMenu {
            Button("Choose") { model.studio.choose(take) }
            if !chosen { Button("Delete", role: .destructive) { model.studio.deleteTake(take) } }
        }
        #if os(iOS)
        .swipeActions {
            if !chosen { Button("Delete", role: .destructive) { model.studio.deleteTake(take) } }
        }
        #endif
    }
}

// MARK: - The Mac window and menu

#if os(macOS)
/// A studio window's value: the production, the part, and a line to open at.
struct StudioWindowValue: Codable, Hashable, Sendable {
    let target: StudioTarget
    var line: String?
}

/// The reader window with the studio as its inspector (macOS-DESIGN §4.7).
struct StudioWindow_macOS: View {
    static let id = "studio"
    let value: StudioWindowValue
    @Environment(PlaysLibrary.self) private var plays

    var body: some View {
        Group {
            if let scriptID = value.target.dramaScriptID {
                ScriptReaderView(scriptID: scriptID, startLine: value.line, studio: value.target)
            } else if let production = plays.store.production(value.target.production) {
                ScriptReaderView(scriptID: production.scriptID, startLine: value.line, studio: value.target)
            } else {
                EmptyState("Production not found", systemImage: "questionmark.square.dashed")
            }
        }
        .frame(minWidth: 720, minHeight: 520)
    }
}
#endif

extension FocusedValues {
    @Entry var studio: StudioModel?
}

/// Keeps the studio's controls off the open Duo's fold (`reservedRegions(kind: .division)`, iOS 27.1): the view is
/// padded by each active division's margins. Elsewhere, and before iOS 27.1, a no-op.
struct AvoidsFold: ViewModifier {
    @State private var pad = EdgeInsets()

    func body(content: Content) -> some View {
        #if os(iOS) && compiler(>=6.4)
        content
            .padding(pad)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { measure(proxy) }
                        .onChange(of: proxy.size) { measure(proxy) }
                }
            }
        #else
        content
        #endif
    }

    #if os(iOS) && compiler(>=6.4)
    private func measure(_ proxy: GeometryProxy) {
        guard #available(iOS 27.1, *) else { return }
        let regions = proxy.reservedRegions(kind: .division).filter(\.isActive)
        let next = regions.reduce(EdgeInsets()) { sum, r in
            EdgeInsets(top: max(sum.top, r.margins.top), leading: max(sum.leading, r.margins.leading),
                       bottom: max(sum.bottom, r.margins.bottom), trailing: max(sum.trailing, r.margins.trailing))
        }
        if next != pad { pad = next }
    }
    #endif
}

#if os(macOS)
/// The studio as the reader window's inspector, 320-380 pt, toggled with ⌥⌘I (macOS-DESIGN §4.7).
struct StudioInspector: ViewModifier {
    let studio: StudioModel?
    let voices: VoiceCastModel

    func body(content: Content) -> some View {
        if let studio {
            content.inspector(isPresented: Binding(get: { studio.inspector }, set: { studio.inspector = $0 })) {
                StudioPanel(model: studio, voices: voices, full: true)
                    .inspectorColumnWidth(min: 320, ideal: 360, max: 380)
            }
        } else {
            content
        }
    }
}

/// The Recording menu for a studio window: Space, J, K, R, Return and the inspector; disabled, never hidden.
struct StudioCommandItems: View {
    let studio: StudioModel

    var body: some View {
        let session = studio.session
        Button(studio.isListening ? "Stop" : session.run != nil ? "Pause" : studio.isCue ? "Cancel" : "Record") { studio.primary() }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(!studio.started || session.phase == .runReview)
        Button("Keep") { studio.keep() }
            .keyboardShortcut(.return, modifiers: [])
            .disabled(!studio.inReview)
        Button("Record Again") { studio.again() }
            .keyboardShortcut("r", modifiers: [])
            .disabled(!studio.started || session.isBusy)
        Divider()
        Button("My Next Line") { studio.studio.move(1) }
            .keyboardShortcut("j", modifiers: [])
            .disabled(studio.studio.locked)
        Button("My Previous Line") { studio.studio.move(-1) }
            .keyboardShortcut("k", modifiers: [])
            .disabled(studio.studio.locked)
        Divider()
        Button(studio.inspector ? "Hide Studio" : "Show Studio") { studio.inspector.toggle() }
            .keyboardShortcut("i", modifiers: [.command, .option])
    }
}
#endif
#endif
