#if os(iOS) || os(macOS)
import AVFoundation
import SwiftUI

/// Recording one part (PLAYS-DESIGN §2.3-2.4) in the three modes of owner ruling 4: Run through, Line
/// by line, Step. This screen asks for the microphone and checks the route; the recorder itself is
/// `RecorderView`. Keyboard: Space records, stops or pauses, Return keeps, R records again, the arrow
/// keys move by line (§2.2, §7).
struct RecordingScreen: View {
    let productionID: String
    let part: PartID
    /// Replacing one line of a finished part (P12): the recorder opens on it.
    var startLine: String?
    var dismissWhenDone = false
    @Environment(PlaysLibrary.self) private var plays
    @Environment(AudioPlayer.self) private var player
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var session: RecordingSession?
    @State private var preflight: Preflight = .ready
    @State private var index = 0
    @State private var refusal: String?

    enum Preflight: Equatable {
        case ready
        case microphoneDenied
        case needsHeadphones
        case airPlay
    }

    var body: some View {
        Group {
            if let session, case let .roomTone(seconds) = session.phase {
                roomTone(seconds)
            } else if let session, session.started {
                RecorderView(session: session, index: $index, showsDone: plays.store.share(productionID) == nil,
                             refusal: refusal, finish: finishPart)
            } else {
                start
            }
        }
        #if os(iOS)
        .navigationTitle(session?.started == true ? "" : part.title)
        .navigationBarTitleDisplayMode(.inline)
        #else
        .navigationTitle(part.title)
        #endif
        .onDisappear {
            session?.end()
            session = nil
        }
        .focusedSceneValue(\.recordingControls, session.map { RecordingControls(session: $0, index: $index) })
    }

    // MARK: Before the first line

    @ViewBuilder private var start: some View {
        VStack(spacing: Spacing.s4) {
            switch preflight {
            case .ready where !account.isSignedIn:
                Text("Recording needs an account.")
                if account.status == .signedOut {
                    SignInButtons().frame(maxWidth: 320)
                }
            case .ready:
                Image(systemName: "headphones").font(.largeTitle).foregroundStyle(Color.brandSecondary)
                Button {
                    Task { await begin(echoCancelled: false) }
                } label: {
                    Label("Start Recording", systemImage: "mic")
                        .foregroundStyle(Color.brandOnRecord)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.brandRecord)
                .keyboardShortcut(.defaultAction)
            case .microphoneDenied:
                Text("Ear Drama needs the microphone to record your part.")
                Button("Open Settings") { openSettings() }
            case .needsHeadphones:
                Text("Plug in headphones.")
                Button("Check Again") { Task { await begin(echoCancelled: false) } }
                    .buttonStyle(.borderedProminent)
                Button("Record Without Headphones") { Task { await begin(echoCancelled: true) } }
            case .airPlay:
                Text("AirPlay delays sound too much to record. Choose headphones.")
                Button("Check Again") { Task { await begin(echoCancelled: false) } }
            }
            if let failure = failureText { Text(verbatim: failure).foregroundStyle(Color.semanticError) }
        }
        .multilineTextAlignment(.center)
        .padding(Spacing.s6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var failureText: String? {
        if case let .failed(message) = session?.phase { return message }
        return nil
    }

    private func roomTone(_ seconds: Int) -> some View {
        VStack(spacing: Spacing.s3) {
            Text("Quiet, please. Recording the room.").font(TypeRamp.bodyStrong)
            Text(verbatim: "\(seconds)").font(TypeRamp.pageTitle).monospacedDigit()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// The microphone is asked for here, at the moment of recording, never at launch.
    private func begin(echoCancelled: Bool) async {
        guard account.isSignedIn else { return }
        guard await AVAudioApplication.requestRecordPermission() else {
            preflight = .microphoneDenied
            return
        }
        guard let production = plays.store.production(productionID),
              let script = plays.castScript(for: production) else { return }
        let audio = EngineLiveAudio()
        switch audio.outputRoute() {
        case .airPlay:
            preflight = .airPlay
            return
        case .speaker where !echoCancelled:
            preflight = .needsHeadphones
            return
        default: break
        }
        preflight = .ready
        player.pause()
        let session = RecordingSession(production: production, script: script, part: part, store: plays.store,
                                       audio: audio, voice: SystemStandInVoice())
        self.session = session
        index = startLine.flatMap { id in session.lines.firstIndex { $0.id == id } } ?? firstUnrecorded(session)
        await session.begin(echoCancelled: echoCancelled)
    }

    private func firstUnrecorded(_ session: RecordingSession) -> Int {
        session.lines.firstIndex { session.production.usableTake(for: $0.id) == nil } ?? 0
    }

    private func openSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        #else
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            openURL(url)
        }
        #endif
    }

    // MARK: The recorder

    private func finishPart() {
        guard let production = plays.store.production(productionID),
              let script = plays.castScript(for: production) else { return }
        do {
            plays.store.update(try Relay.finish(part, in: production, script: script))
            session?.end()
            if dismissWhenDone { dismiss() }
        } catch {
            refusal = RelayRefusalText.text(error)
        }
    }
}

// MARK: - The recorder, in direction D

/// The recorder (D3-6; PLAYS-DESIGN §2.3-2.4): fixed slots that never move between modes or states.
/// The header, the strip of this part's lines, the mode control, the scene, the dock. Wide, the scene
/// stands between two rails: who is in it, and this line's aids (on a Mac, the keys).
struct RecorderView: View {
    let session: RecordingSession
    @Binding var index: Int
    /// A shared part is finished on the Worker, from the cast sheet (PLAYS-DESIGN §11.7 rule 5).
    var showsDone = true
    var refusal: String?
    var finish: () -> Void = {}
    @State private var wide = false

    var body: some View {
        let lines = session.lines
        if lines.isEmpty {
            EmptyState("No lines in this part", systemImage: "text.badge.xmark")
        } else {
            let at = min(index, lines.count - 1)
            let current = lines[at]
            let controls = RecordingControls(session: session, index: $index)
            VStack(spacing: Spacing.s3) {
                RecorderHeader(session: session)
                LineStrip(session: session, index: at)
                if wide {
                    HStack(alignment: .top, spacing: 0) {
                        SceneRail(session: session, line: current).frame(width: 220)
                        Divider()
                        column(current, controls: controls, aids: false).padding(.horizontal, Spacing.s4)
                        Divider()
                        AidsRail(session: session, line: current, controls: controls).frame(width: 240)
                    }
                } else {
                    column(current, controls: controls, aids: true)
                }
            }
            .padding(.horizontal, wide ? Spacing.s6 : Spacing.s4)
            .padding(.vertical, Spacing.s3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onGeometryChange(for: Bool.self) { $0.size.width >= 840 } action: { wide = $0 }
            .onChange(of: session.phase) { _, phase in
                if case let .listening(id) = phase, let i = lines.firstIndex(where: { $0.id == id }) { index = i }
            }
            #if os(iOS)
            .sensoryFeedback(Haptic.selection.feedback, trigger: session.listeningSince != nil)
            #endif
        }
    }

    private func column(_ current: ScriptLine, controls: RecordingControls, aids: Bool) -> some View {
        VStack(spacing: Spacing.s3) {
            Picker("Mode", selection: Binding(get: { session.mode }, set: { session.setMode($0) })) {
                ForEach(RecordingSession.Mode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(session.isBusy || session.run != nil)
            if case let .failed(message) = session.phase {
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(Color.semanticError)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Group {
                if session.mode == .lines {
                    LinesScene(session: session, index: $index, controls: controls)
                } else if session.phase == .runReview {
                    RunReviewScene(session: session, controls: controls)
                } else {
                    StepScene(session: session, current: current)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            if aids, session.mode != .run {
                AidsRow(session: session, line: current)
            }
            Dock(session: session, current: current, controls: controls)
            if showsDone { doneButton }
        }
        .frame(maxWidth: 720)
    }

    @ViewBuilder private var doneButton: some View {
        let missing = Relay.missingLines(session.part, in: session.production, script: session.script).count
        VStack(spacing: Spacing.s1) {
            Button(action: finish) {
                Text("Done with This Part").frame(maxWidth: .infinity)
            }
            .buttonStyle(.play(.way))
            .disabled(session.isBusy || session.run != nil || (session.part.isSpeaking && missing > 0))
            if session.part.isSpeaking, missing > 0 {
                Text(missing == 1 ? "1 line to go" : "\(missing) lines to go")
                    .font(TypeRamp.caption)
                    .foregroundStyle(Color.brandTextMuted)
            }
            if let refusal { Text(verbatim: refusal).font(TypeRamp.caption).foregroundStyle(Color.semanticError) }
        }
    }
}

// MARK: Header and strip

private struct RecorderHeader: View {
    let session: RecordingSession

    var body: some View {
        let kept = session.lines.filter { session.production.usableTake(for: $0.id) != nil }.count
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: session.part.title).font(TypeRamp.sectionHeader).foregroundStyle(Color.brandText)
                Text(verbatim: session.script.title).font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
            }
            Spacer()
            Text(verbatim: "\(kept) of \(session.lines.count)").font(TypeRamp.tabular).foregroundStyle(Color.brandTextMuted)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One cell per line of the part: kept in the part's mark, the current one outlined (red while it records).
private struct LineStrip: View {
    let session: RecordingSession
    let index: Int

    var body: some View {
        let lines = session.lines
        let mark = Color.genre(session.script.partHue(session.part)) ?? Color.brandText
        let recording = session.listeningSince != nil
        HStack(spacing: lines.count > 120 ? 0 : 1) {
            ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                let kept = session.production.usableTake(for: line.id) != nil
                Rectangle()
                    .fill(kept ? mark : Color.brandSurfaceAlt)
                    .overlay {
                        if i == index {
                            Rectangle().strokeBorder(recording ? Color.brandRecord : Color.brandText, lineWidth: 1.5)
                        }
                    }
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 14)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(lines.filter { session.production.usableTake(for: $0.id) != nil }.count) of \(lines.count) lines kept")
    }
}

// MARK: Who and what is on stage

private extension RecordingSession {
    /// Who reads a line: you, the performer of a recorded take, or the device voice.
    func who(of line: ScriptLine) -> String? {
        guard line.kind == .speech else { return nil }
        if line.part == part { return "You" }
        if production.usableTake(for: line.id) != nil { return production.state(of: line.part).performer ?? "Recorded" }
        return "Device voice"
    }

    func holder(of line: ScriptLine) -> PartHolder {
        guard line.kind == .speech else { return .silent }
        if line.part == part { return .person(production.state(of: part).performer) }
        if production.usableTake(for: line.id) != nil { return .person(production.state(of: line.part).performer) }
        return .deviceVoice
    }

    var scriptLines: [ScriptLine] { script.lines }

    func position(_ id: String) -> Int? { script.lines.firstIndex { $0.id == id } }

    /// The line of this part the box shows: the one listening, or while a run plays the next one coming.
    func boxLine(_ fallback: ScriptLine) -> ScriptLine {
        switch phase {
        case let .listening(id):
            return script.lines.first { $0.id == id } ?? fallback
        case let .cue(id, _) where run != nil:
            guard let at = position(id) else { return fallback }
            return script.lines[at...].first { $0.part == part } ?? fallback
        default:
            return fallback
        }
    }

    /// The cue on screen: the line playing now, else the one that cues the box line.
    func cueLine(for box: ScriptLine) -> ScriptLine? {
        if case let .cue(id, _) = phase, id != box.id { return script.lines.first { $0.id == id } }
        return Relay.cueLines(before: box.id, in: script, runUp: false).first
    }
}

/// A line of the play beside the one being recorded: a face, who says it, the words.
private struct SceneLine: View {
    let session: RecordingSession
    let line: ScriptLine
    var card = false
    var dim = false

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s3) {
            PartFace(hue: session.script.partHue(line.part), holder: session.holder(of: line), side: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.s2) {
                    Text(verbatim: line.part.title.uppercased())
                        .font(TypeRamp.caption.weight(.bold)).tracking(1)
                    if let who = session.who(of: line) {
                        Text(verbatim: who).font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
                    }
                }
                .foregroundStyle(dim ? Color.brandTextMuted : Color.brandText)
                if line.kind == .speech {
                    Text(verbatim: line.spokenText)
                        .font(TypeRamp.body)
                        .foregroundStyle(dim ? Color.brandTextMuted : Color.brandText)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(verbatim: line.source ?? "").italic().font(TypeRamp.body).foregroundStyle(Color.brandTextMuted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(card ? Spacing.s3 : 0)
        .background(card ? Color.brandSurface : Color.clear, in: RoundedRectangle(cornerRadius: Radius.card))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: The line box

/// The performer's own line on their part's board: armed (dashed red edge, "Next") while the cue plays,
/// recording (solid red edge, the pill, the level), or kept (its take, its length, the take count).
private struct LineBox: View {
    enum Look { case ready, armed, recording, review }

    let session: RecordingSession
    let line: ScriptLine
    let state: Look

    private var ink: Color { Color.onBoard(session.script.partHue(session.part)) }

    var body: some View {
        let hue = session.script.partHue(session.part)
        let shape = RoundedRectangle(cornerRadius: Radius.card)
        VStack(alignment: .leading, spacing: Spacing.s3) {
            HStack {
                Text(verbatim: "\(session.part.title) \u{00B7} You")
                    .font(TypeRamp.caption.weight(.bold)).tracking(1.2).textCase(.uppercase)
                Spacer()
                trailing
            }
            ScriptLineText(line: line, large: true, ink: ink, showsRole: false)
            switch state {
            case .recording: LevelMeter(levels: session.levels)
            case .review: review
            default: EmptyView()
            }
            if session.production.chosenTake(for: line.id)?.bleed == true {
                Label("The device voice is in this take. Re-take it with headphones.", systemImage: "exclamationmark.triangle")
                    .font(TypeRamp.caption.weight(.semibold))
            }
        }
        .foregroundStyle(ink)
        .padding(Spacing.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.board(hue), in: shape)
        .overlay {
            switch state {
            case .armed: shape.strokeBorder(Color.brandRecord, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            case .recording: shape.strokeBorder(Color.brandRecord, lineWidth: 3)
            default: EmptyView()
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var trailing: some View {
        switch state {
        case .armed:
            HStack(spacing: 6) {
                Circle().fill(Color.brandRecord).frame(width: 8, height: 8)
                Text("Next")
            }
            .font(TypeRamp.caption.weight(.bold))
            .foregroundStyle(Color.brandText)
            .padding(.horizontal, Spacing.s3).padding(.vertical, 4)
            .background(Color.brandBackground, in: Capsule())
        case .recording:
            HStack(spacing: 6) {
                Circle().fill(Color.brandOnRecord).frame(width: 8, height: 8)
                if let since = session.listeningSince {
                    TimelineView(.periodic(from: since, by: 1)) { context in
                        let seconds = max(0, Int(context.date.timeIntervalSince(since)))
                        Text(verbatim: "Recording \(seconds / 60):\(String(format: "%02d", seconds % 60))").monospacedDigit()
                    }
                } else {
                    Text("Recording")
                }
            }
            .font(TypeRamp.caption.weight(.bold))
            .foregroundStyle(Color.brandOnRecord)
            .padding(.horizontal, Spacing.s3).padding(.vertical, 4)
            .background(Color.brandRecord, in: Capsule())
        case .review:
            let takes = session.production.takes(for: line.id)
            if takes.count > 1 {
                HStack(spacing: Spacing.s2) {
                    ForEach(Array(takes.enumerated()), id: \.element.id) { n, take in
                        let chosen = session.production.chosen[line.id] == take.id
                        Button { session.choose(take) } label: {
                            Text(verbatim: "\(n + 1)")
                                .font(TypeRamp.caption.weight(.bold))
                                .foregroundStyle(chosen ? Color.board(session.script.partHue(session.part)) : ink)
                                .frame(width: 28, height: 28)
                                .background(chosen ? ink : Color.clear, in: Circle())
                                .overlay { Circle().strokeBorder(ink, lineWidth: 1.5) }
                        }
                        .buttonStyle(.plain)
                        .disabled(session.isBusy)
                        .accessibilityLabel("Take \(n + 1)")
                        .accessibilityAddTraits(chosen ? .isSelected : [])
                    }
                }
            }
        default: EmptyView()
        }
    }

    @ViewBuilder private var review: some View {
        if let take = session.production.chosenTake(for: line.id) {
            let playing: Bool = { if case .cue = session.phase { true } else { false } }()
            HStack(spacing: Spacing.s3) {
                Button { Task { await session.playTake(take) } } label: {
                    Image(systemName: playing ? "speaker.wave.2.fill" : "play.fill")
                        .frame(width: 40, height: 40)
                        .background(Circle().strokeBorder(Color.onBoard(session.script.partHue(session.part)), lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .disabled(session.isBusy)
                .accessibilityLabel("Play this take")
                StaticWave(seed: take.id)
                Text(verbatim: lengthText(take))
                    .font(TypeRamp.tabular)
            }
        }
    }
}

private func lengthText(_ take: Take) -> String { String(format: "%.1f s", take.seconds) }

/// A take's shape, drawn from its id: the take's own audio is not read for a picture.
private struct StaticWave: View {
    let seed: String

    var body: some View {
        let heights = (0..<32).map { i -> CGFloat in
            let h = (seed.unicodeScalars.reduce(UInt32(7)) { ($0 &* 31) &+ $1.value } &+ UInt32(i * 2654435761 % 97)) % 100
            return 6 + CGFloat(h) / 100 * 20
        }
        HStack(spacing: 2) {
            ForEach(Array(heights.enumerated()), id: \.offset) { _, h in
                Capsule().frame(width: 2, height: h)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(0.7)
        .accessibilityHidden(true)
    }
}

private struct LevelMeter: View {
    let levels: [Float]

    var body: some View {
        let shown = Array(levels.suffix(40))
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<40, id: \.self) { i in
                let slot = i - (40 - shown.count)
                Capsule()
                    .fill(Color.brandRecord)
                    .frame(width: 3, height: slot >= 0 ? max(3, 28 * CGFloat(shown[slot])) : 3)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 32)
        .padding(.horizontal, Spacing.s3).padding(.vertical, Spacing.s2)
        .background(Color.white, in: RoundedRectangle(cornerRadius: Radius.control))
        .accessibilityHidden(true)
    }
}

// MARK: Scenes

private struct SceneScrollsKey: EnvironmentKey { static let defaultValue = true }

extension EnvironmentValues {
    /// False only where a picture is drawn offline: ImageRenderer cannot draw a ScrollView.
    var recorderScrolls: Bool {
        get { self[SceneScrollsKey.self] }
        set { self[SceneScrollsKey.self] = newValue }
    }
}

/// The scene's scrolling container.
private struct SceneScroll<Content: View>: View {
    @Environment(\.recorderScrolls) private var scrolls
    @ViewBuilder let content: () -> Content

    var body: some View {
        if scrolls {
            ScrollView { content() }.scrollBounceBehavior(.basedOnSize)
        } else {
            content().frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

/// Step and Run through: the line before, the cue, the performer's line, the line after.
private struct StepScene: View {
    let session: RecordingSession
    let current: ScriptLine

    var body: some View {
        let box = session.boxLine(current)
        let cue = session.cueLine(for: box)
        let at = session.position(box.id) ?? 0
        let anchor = cue.flatMap { session.position($0.id) } ?? at
        SceneScroll {
            VStack(alignment: .leading, spacing: Spacing.s3) {
                if anchor > 0 { SceneLine(session: session, line: session.scriptLines[anchor - 1], dim: true) }
                if let cue { SceneLine(session: session, line: cue, card: true) }
                LineBox(session: session, line: box, state: state(box))
                if at + 1 < session.scriptLines.count { SceneLine(session: session, line: session.scriptLines[at + 1], dim: true) }
            }
        }
    }

    private func state(_ box: ScriptLine) -> LineBox.Look {
        switch session.phase {
        case let .listening(id) where id == box.id: .recording
        case let .cue(id, _) where id != box.id: .armed
        case let .cue(id, deviceVoice) where id == box.id && !deviceVoice && session.production.chosenTake(for: id) != nil: .review
        case let .review(id) where id == box.id: .review
        default: .ready
        }
    }
}

/// Line by line: every line of the part, its state at the right; the selected one opens in place.
private struct LinesScene: View {
    let session: RecordingSession
    @Binding var index: Int
    let controls: RecordingControls

    var body: some View {
        let lines = session.lines
        ScrollViewReader { proxy in
            SceneScroll {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { i, line in
                        if i == min(index, lines.count - 1) { open(line) } else { row(line, number: i + 1, at: i) }
                        Divider()
                    }
                }
            }
            .onChange(of: index) { _, new in withAnimation { proxy.scrollTo(lines[min(new, lines.count - 1)].id, anchor: .center) } }
        }
    }

    private func row(_ line: ScriptLine, number: Int, at i: Int) -> some View {
        let takes = session.production.takes(for: line.id).count
        return Button {
            if !session.isBusy { index = i }
        } label: {
            HStack(alignment: .top, spacing: Spacing.s3) {
                Text(verbatim: "\(number)").font(TypeRamp.tabular).foregroundStyle(Color.brandTextMuted).frame(width: 32, alignment: .leading)
                ScriptLineText(line: line, showsRole: false)
                Group {
                    if takes > 0 {
                        Label("Take \(takes)", systemImage: "checkmark").font(TypeRamp.caption).foregroundStyle(Color.brandText)
                    } else {
                        Text("Not yet").font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
                    }
                }
                .fixedSize()
            }
            .padding(.vertical, Spacing.s3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(line.id)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens this line")
    }

    @ViewBuilder private func open(_ line: ScriptLine) -> some View {
        let listening: Bool = { if case let .listening(id) = session.phase { id == line.id } else { false } }()
        let armed: Bool = { if case let .cue(id, _) = session.phase { id != line.id } else { false } }()
        VStack(alignment: .leading, spacing: Spacing.s3) {
            if let cue = session.cueLine(for: line) { SceneLine(session: session, line: cue, card: true) }
            LineBox(session: session, line: line, state: listening ? .recording : armed ? .armed : .ready)
            HStack(spacing: Spacing.s2) {
                Button {
                    if listening { session.stopListening() } else { Task { await session.record(line.id) } }
                } label: {
                    Label(listening ? "Stop" : "Record", systemImage: listening ? "stop.fill" : "mic.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.play(.record))
                .disabled(session.isBusy && !listening)
                Button {
                    Task { await session.playCue(line.id) }
                } label: {
                    Label("Cue", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.play(.way))
                .disabled(session.isBusy)
            }
        }
        .padding(.vertical, Spacing.s3)
        .id(line.id)
    }
}

/// The run's takes, each played with its cue or recorded again, before they are kept.
private struct RunReviewScene: View {
    let session: RecordingSession
    let controls: RecordingControls

    var body: some View {
        let takes = session.runTakes
        SceneScroll {
            VStack(alignment: .leading, spacing: Spacing.s3) {
                Text(verbatim: "This run \u{00B7} \(takes.count) \(takes.count == 1 ? "take" : "takes")")
                    .font(TypeRamp.sectionHeader)
                ForEach(takes) { take in
                    let number = (session.lines.firstIndex { $0.id == take.lineID } ?? 0) + 1
                    VStack(alignment: .leading, spacing: Spacing.s2) {
                        HStack {
                            Text(verbatim: "Line \(number)").font(TypeRamp.tabular).foregroundStyle(Color.brandTextMuted)
                            Spacer()
                            if take.bleed {
                                Label("The device voice is in this take.", systemImage: "exclamationmark.triangle")
                                    .font(TypeRamp.caption).foregroundStyle(Color.semanticWarning)
                            }
                        }
                        if let line = session.lines.first(where: { $0.id == take.lineID }) { ScriptLineText(line: line, showsRole: false) }
                        HStack(spacing: Spacing.s3) {
                            Button { Task { await session.playWithCue(take) } } label: {
                                Image(systemName: "play.fill").frame(width: 44, height: 44)
                                    .background(Circle().strokeBorder(Color.brandBorder, lineWidth: 1.5))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.brandSecondary)
                            .disabled(session.isBusy)
                            .accessibilityLabel("Play with its cue")
                            StaticWave(seed: take.id).foregroundStyle(Color.brandTextMuted)
                            Text(verbatim: lengthText(take))
                                .font(TypeRamp.tabular).foregroundStyle(Color.brandTextMuted)
                            Button {
                                Task { await session.record(take.lineID) }
                            } label: {
                                HStack(spacing: 6) { Circle().fill(Color.brandRecord).frame(width: 10, height: 10); Text("Again") }
                            }
                            .buttonStyle(.play(.again))
                            .disabled(session.isBusy)
                        }
                    }
                    .padding(Spacing.s3)
                    .background(Color.brandSurface, in: RoundedRectangle(cornerRadius: Radius.card))
                }
            }
        }
    }
}

// MARK: The dock

private struct Dock: View {
    let session: RecordingSession
    let current: ScriptLine
    let controls: RecordingControls

    var body: some View {
        switch session.mode {
        case .lines: EmptyView()
        case .run: run
        case .step: step
        }
    }

    // Step: Previous, the one round control, Next; in review Again, With cue, Keep.
    @ViewBuilder private var step: some View {
        if case let .review(id) = session.phase, let take = session.production.chosenTake(for: id) {
            HStack(spacing: Spacing.s2) {
                Button { Task { await session.record(id) } } label: {
                    HStack(spacing: 6) { Circle().fill(Color.brandRecord).frame(width: 10, height: 10); Text("Again") }
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.play(.again))
                .padShortcut("r", modifiers: [])
                Button { Task { await session.playWithCue(take) } } label: {
                    Label("With cue", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.play(.way))
                Button { controls.keep() } label: {
                    Label("Keep", systemImage: "checkmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.play(.ink))
                .padShortcut(.return, modifiers: [])
            }
        } else {
            let listening: Bool = { if case .listening = session.phase { true } else { false } }()
            let cueing: Bool = { if case .cue = session.phase { true } else { false } }()
            HStack {
                Button { controls.move(-1) } label: {
                    Label("Previous Line", systemImage: "backward.end").labelStyle(.iconOnly).frame(width: 44, height: 44)
                }
                .padShortcut(.leftArrow, modifiers: [])
                .disabled(session.isBusy || controls.atStart)
                Spacer()
                RoundControl(title: listening ? "Stop" : cueing ? "Cancel" : "Record",
                             symbol: listening ? "stop.fill" : cueing ? "xmark" : "mic.fill", kind: .record) {
                    controls.recordOrStop()
                }
                .padShortcut(.space, modifiers: [])
                .disabled(session.isBusy && !listening && !cueing)
                Spacer()
                Button { controls.move(1) } label: {
                    Label("Next Line", systemImage: "forward.end").labelStyle(.iconOnly).frame(width: 44, height: 44)
                }
                .padShortcut(.rightArrow, modifiers: [])
                .disabled(session.isBusy || controls.atEnd)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.brandSecondary)
        }
    }

    // Run through: From here; Pause (Stop while the microphone is open); then Discard the run or Keep N takes.
    @ViewBuilder private var run: some View {
        if session.phase == .runReview {
            let count = session.runTakes.count
            HStack(spacing: Spacing.s2) {
                Button("Discard the run") { session.discardRun() }
                    .buttonStyle(.play(.way))
                    .frame(maxWidth: .infinity)
                Button { session.keepRun() } label: {
                    Label(count == 1 ? "Keep 1 take" : "Keep \(count) takes", systemImage: "checkmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.play(.ink))
                .padShortcut(.return, modifiers: [])
            }
        } else if session.run != nil {
            let listening: Bool = { if case .listening = session.phase { true } else { false } }()
            HStack {
                Text(verbatim: "\(session.runTakes.count) taken").font(TypeRamp.tabular).foregroundStyle(Color.brandTextMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                RoundControl(title: listening ? "Stop" : "Pause", symbol: listening ? "stop.fill" : "pause.fill",
                             kind: listening ? .record : .ink) { session.pause() }
                    .padShortcut(.space, modifiers: [])
                Color.clear.frame(maxWidth: .infinity)
            }
        } else {
            RoundControl(title: "From here", symbol: "mic.fill", kind: .record) { controls.recordOrStop() }
                .padShortcut(.space, modifiers: [])
                .disabled(session.isBusy)
        }
    }
}

/// The big round control with its word under it: Record, Stop, Cancel, Pause, From here.
private struct RoundControl: View {
    let title: String
    let symbol: String
    let kind: PlayButtonStyle.Kind
    let action: () -> Void

    var body: some View {
        VStack(spacing: Spacing.s1) {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(kind == .record ? Color.brandOnRecord : Color.brandOnPrimary)
                    .frame(width: 76, height: 76)
                    .background(Circle().fill(kind == .record ? Color.brandRecord : Color.brandPrimary))
                    .overlay { Circle().strokeBorder((kind == .record ? Color.brandRecord : Color.brandPrimary).opacity(0.3), lineWidth: 4).padding(-5) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityInputLabels([title])
            Text(verbatim: title).font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: Aids and rails

/// Run-up, Hear it read and the device voice's speed: the aids for the line in hand.
private struct AidsRow: View {
    let session: RecordingSession
    let line: ScriptLine

    var body: some View {
        HStack(spacing: Spacing.s2) {
            AidButtons(session: session, line: line)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct AidButtons: View {
    let session: RecordingSession
    let line: ScriptLine

    var body: some View {
        Button { Task { await session.record(line.id, runUp: true) } } label: {
            Label("Run-up", systemImage: "arrow.counterclockwise")
        }
        .buttonStyle(.play(.way))
        .disabled(session.isBusy || session.run != nil)
        Button { Task { await session.hearItRead(line.id) } } label: {
            Label("Hear it read", systemImage: "ear")
        }
        .buttonStyle(.play(.way))
        .disabled(session.isBusy || session.run != nil)
        Menu {
            Picker("Device Voice Speed", selection: Binding(get: { session.standInRate }, set: { session.standInRate = $0 })) {
                Text("Slower").tag(Float(0.8))
                Text("Normal").tag(Float(1))
                Text("Faster").tag(Float(1.2))
            }
        } label: {
            Label("\(session.standInRate == 1 ? "1" : session.standInRate < 1 ? "0.8" : "1.2")\u{00D7}", systemImage: "speedometer")
        }
        .menuStyle(.button)
        .buttonStyle(.play(.way))
        .fixedSize()
        .accessibilityLabel("Device voice speed")
    }
}

/// Wide: who is in the scene near this line, and who holds each.
private struct SceneRail: View {
    let session: RecordingSession
    let line: ScriptLine

    var body: some View {
        let box = session.boxLine(line)
        let at = session.position(box.id) ?? 0
        let near = session.scriptLines[max(0, at - 2)..<min(session.scriptLines.count, at + 2)]
        var seen = Set<PartID>()
        let parts = near.map(\.part).filter { $0.isSpeaking && seen.insert($0).inserted }
        VStack(alignment: .leading, spacing: Spacing.s3) {
            Text("In this scene").font(TypeRamp.caption.weight(.bold)).tracking(1.2).textCase(.uppercase)
                .foregroundStyle(Color.brandTextMuted)
            ForEach(parts, id: \.self) { part in
                let state = session.production.state(of: part)
                let mine = part == session.part
                HStack(spacing: Spacing.s3) {
                    PartFace(hue: session.script.partHue(part),
                             holder: mine || state.status != .open ? .person(state.performer) : .deviceVoice, side: 44)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: part.title).font(TypeRamp.sectionHeader).foregroundStyle(Color.brandText)
                        Text(verbatim: mine ? ["You", state.performer].compactMap { $0 }.joined(separator: " \u{00B7} ")
                             : state.performer ?? (state.status == .open ? "Device voice" : "Recorded"))
                            .font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            Spacer()
        }
        .padding(Spacing.s4)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// Wide: the aids for this line, and on a Mac the keys.
private struct AidsRail: View {
    let session: RecordingSession
    let line: ScriptLine
    let controls: RecordingControls

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            if session.mode != .run {
                Text("This line").font(TypeRamp.caption.weight(.bold)).tracking(1.2).textCase(.uppercase)
                    .foregroundStyle(Color.brandTextMuted)
                VStack(alignment: .leading, spacing: Spacing.s2) { AidButtons(session: session, line: line) }
            }
            #if os(macOS)
            Text("Keys").font(TypeRamp.caption.weight(.bold)).tracking(1.2).textCase(.uppercase)
                .foregroundStyle(Color.brandTextMuted)
            Grid(alignment: .leading, horizontalSpacing: Spacing.s3, verticalSpacing: Spacing.s2) {
                key("Space", "Record, stop or pause")
                key("Return", "Keep")
                key("R", "Again")
                key("\u{2190} \u{2192}", "Line")
            }
            #endif
            Spacer()
        }
        .padding(Spacing.s4)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    #if os(macOS)
    private func key(_ key: String, _ action: String) -> some View {
        GridRow {
            Text(verbatim: key).font(TypeRamp.caption.weight(.semibold).monospaced())
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.brandSurfaceAlt, in: RoundedRectangle(cornerRadius: 4))
            Text(verbatim: action).font(TypeRamp.caption).foregroundStyle(Color.brandText)
        }
    }
    #endif
}

// MARK: - The commands

/// The recording commands the Mac menu bar carries for the focused window, and the one place the
/// dock's keys and buttons ask: the same verbs on every platform.
struct RecordingControls {
    let session: RecordingSession
    let index: Binding<Int>

    var line: ScriptLine? {
        let lines = session.lines
        return lines.isEmpty ? nil : lines[min(index.wrappedValue, lines.count - 1)]
    }

    var isListening: Bool {
        if case .listening = session.phase { true } else { false }
    }

    /// Whether Space does anything now: record, stop, pause, or cancel a cue.
    var canPress: Bool {
        if session.run != nil { return session.phase != .runReview }
        if isListening { return true }
        if case .cue = session.phase { return true }
        return !session.isBusy
    }

    var atStart: Bool { index.wrappedValue <= 0 }
    var atEnd: Bool { index.wrappedValue + 1 >= session.lines.count }

    /// Space: record or stop; pause while a run plays; cancel a cue that is playing.
    func recordOrStop() {
        if session.run != nil, session.phase != .runReview {
            session.pause()
        } else if isListening {
            session.stopListening()
        } else if case .cue = session.phase {
            session.cancel()
        } else if let line {
            if session.mode == .run {
                Task { await session.runThrough(from: line.id) }
            } else {
                Task { await session.record(line.id) }
            }
        }
    }

    /// Return: keep what was just taken. A run's takes are kept, a Step take stays and the next line is ready.
    func keep() {
        if session.phase == .runReview {
            session.keepRun()
        } else if !session.isBusy {
            session.dismissReview()
            move(1)
        }
    }

    /// R: record the line again, or the last line of the run under review.
    func again() {
        guard !session.isBusy else { return }
        if session.phase == .runReview, let take = session.runTakes.last {
            Task { await session.record(take.lineID) }
        } else if let line {
            Task { await session.record(line.id) }
        }
    }

    func move(_ step: Int) {
        index.wrappedValue = min(max(0, index.wrappedValue + step), max(0, session.lines.count - 1))
    }
}

extension FocusedValues {
    @Entry var recordingControls: RecordingControls?
}

extension View {
    /// iPad's hardware keyboard drives the buttons directly; on the Mac the same
    /// keys belong to the Recording menu (RecordingCommands_macOS), so they stay
    /// in the menu bar and are not claimed twice.
    @ViewBuilder func padShortcut(_ key: KeyEquivalent, modifiers: EventModifiers) -> some View {
        #if os(iOS)
        keyboardShortcut(key, modifiers: modifiers)
        #else
        self
        #endif
    }
}
#endif
