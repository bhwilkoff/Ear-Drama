#if os(iOS) || os(macOS)
import AVFoundation
import SwiftUI

/// Recording one part, line by line (PLAYS-DESIGN §2.3-2.4): the cue line as it
/// plays (labeled when the device voice reads it), the performer's line large,
/// the next one dim, and one record control. Keyboard: Space records or stops,
/// Return keeps the take and moves on, the arrow keys move by line (§2.2, §7).
struct RecordingScreen: View {
    let productionID: String
    let part: PartID
    var dismissWhenDone = false
    @Environment(PlaysLibrary.self) private var plays
    @Environment(AudioPlayer.self) private var player
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
                prompter(session)
            } else {
                start
            }
        }
        .navigationTitle(part.title)
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
            case .ready:
                Image(systemName: "headphones").font(.largeTitle).foregroundStyle(Color.brandPrimary)
                Button {
                    Task { await begin(echoCancelled: false) }
                } label: {
                    Label("Start Recording", systemImage: "mic")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            case .microphoneDenied:
                Text("Ear Drama needs the microphone to record your part.")
                Button("Open Settings") { openSettings() }
            case .needsHeadphones:
                Text("Plug in headphones so the device voice stays out of your recording.")
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
        index = firstUnrecorded(session)
        await session.begin(echoCancelled: echoCancelled)
    }

    private func firstUnrecorded(_ session: RecordingSession) -> Int {
        session.lines.firstIndex { session.production.chosen[$0.id] == nil } ?? 0
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

    // MARK: The teleprompter

    @ViewBuilder private func prompter(_ session: RecordingSession) -> some View {
        let lines = session.lines
        if lines.isEmpty {
            ContentUnavailableView("No lines in this part", systemImage: "text.badge.xmark")
        } else {
            let current = lines[min(index, lines.count - 1)]
            VStack(alignment: .leading, spacing: Spacing.s4) {
                cue(session, before: current)
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.s4) {
                        ScriptLineText(line: current, large: true)
                        if index + 1 < lines.count {
                            ScriptLineText(line: lines[index + 1]).opacity(0.45)
                        }
                    }
                }
                takes(session, line: current)
                controls(session, line: current, count: lines.count)
            }
            .padding(Spacing.s4)
            .frame(maxWidth: 720, maxHeight: .infinity, alignment: .top)
            .frame(maxWidth: .infinity)
            #if os(iOS)
            .sensoryFeedback(Haptic.selection.feedback, trigger: session.phase == .listening(lineID: current.id))
            #endif
        }
    }

    /// The line that cues this one, with its speaker, and a label whenever the
    /// device voice is reading it, so a stand-in never passes as a person.
    @ViewBuilder private func cue(_ session: RecordingSession, before line: ScriptLine) -> some View {
        switch session.phase {
        case let .cue(lineID, deviceVoice):
            if let cueLine = session.script.lines.first(where: { $0.id == lineID }) {
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    if deviceVoice {
                        Label("Device voice", systemImage: "waveform").font(TypeRamp.caption)
                            .foregroundStyle(Color.brandPrimary)
                    }
                    ScriptLineText(line: cueLine)
                }
            }
        case .listening:
            Label("Your line", systemImage: "mic.fill")
                .font(TypeRamp.bodyStrong)
                .foregroundStyle(Color.semanticError)
        default:
            if let previous = Relay.cueLines(before: line.id, in: session.script, runUp: false).last {
                ScriptLineText(line: previous).opacity(0.6)
            }
        }
    }

    @ViewBuilder private func takes(_ session: RecordingSession, line: ScriptLine) -> some View {
        let takes = session.production.takes(for: line.id)
        if !takes.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.s2) {
                if session.lastTakeBleed, session.phase == .review(lineID: line.id) {
                    Label("The device voice is in this take. Re-take it with headphones.",
                          systemImage: "exclamationmark.triangle")
                        .font(TypeRamp.caption)
                        .foregroundStyle(Color.semanticWarning)
                }
                ForEach(Array(takes.enumerated()), id: \.element.id) { number, take in
                    HStack(spacing: Spacing.s3) {
                        Button {
                            Task { await session.playTake(take) }
                        } label: {
                            Label("Take \(number + 1)", systemImage: "play.circle")
                        }
                        .disabled(session.isBusy)
                        Text(Duration.seconds(take.seconds).formatted(.units(allowed: [.seconds], width: .narrow)))
                            .font(TypeRamp.tabular)
                            .foregroundStyle(Color.brandTextMuted)
                        Spacer()
                        if session.production.chosen[line.id] == take.id {
                            Label("Chosen", systemImage: "checkmark.circle.fill").labelStyle(.iconOnly)
                                .foregroundStyle(Color.brandPrimary)
                        } else {
                            Button("Use This Take") { session.choose(take) }
                                .disabled(session.isBusy)
                        }
                    }
                    .font(TypeRamp.body)
                }
            }
        }
    }

    @ViewBuilder private func controls(_ session: RecordingSession, line: ScriptLine, count: Int) -> some View {
        let listening = session.phase == .listening(lineID: line.id)
        VStack(spacing: Spacing.s3) {
            HStack(spacing: Spacing.s4) {
                Button { move(-1, count: count) } label: {
                    Label("Previous Line", systemImage: "chevron.left").labelStyle(.iconOnly)
                }
                .padShortcut(.leftArrow, modifiers: [])
                .disabled(index == 0 || session.isBusy)
                Spacer()
                RecordButton(listening: listening, busy: session.isBusy && !listening) {
                    if listening { session.stopListening() } else { Task { await session.record(line.id) } }
                }
                Spacer()
                Button { move(1, count: count) } label: {
                    Label("Next Line", systemImage: "chevron.right").labelStyle(.iconOnly)
                }
                .padShortcut(.rightArrow, modifiers: [])
                .disabled(index + 1 >= count || session.isBusy)
            }
            HStack(spacing: Spacing.s4) {
                Button("Run-Up") { Task { await session.record(line.id, runUp: true) } }
                    .disabled(session.isBusy)
                Button("Hear It Read") { Task { await session.hearItRead(line.id) } }
                    .disabled(session.isBusy)
                Menu {
                    Picker("Device Voice Speed", selection: Binding(get: { session.standInRate },
                                                                     set: { session.standInRate = $0 })) {
                        Text("Slower").tag(Float(0.8))
                        Text("Normal").tag(Float(1))
                        Text("Faster").tag(Float(1.2))
                    }
                } label: {
                    Label("Device Voice Speed", systemImage: "speedometer").labelStyle(.iconOnly)
                }
                .fixedSize()
                Spacer()
                Button("Keep") { move(1, count: count) }
                    .padShortcut(.return, modifiers: [])
                    .disabled(session.isBusy || session.production.chosen[line.id] == nil || index + 1 >= count)
            }
            .font(TypeRamp.body)
            doneButton(session)
        }
    }

    @ViewBuilder private func doneButton(_ session: RecordingSession) -> some View {
        let missing = Relay.missingLines(part, in: session.production, script: session.script).count
        Button {
            finishPart()
        } label: {
            Text("Done with This Part").frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(session.isBusy || (part.isSpeaking && missing > 0))
        if part.isSpeaking, missing > 0 {
            Text(missing == 1 ? "1 line to go" : "\(missing) lines to go")
                .font(TypeRamp.caption)
                .foregroundStyle(Color.brandTextMuted)
        }
        if let refusal { Text(verbatim: refusal).font(TypeRamp.caption).foregroundStyle(Color.semanticError) }
    }

    private func move(_ step: Int, count: Int) {
        index = min(max(0, index + step), count - 1)
    }

    /// "Done with this part" hands the device on (§2.5).
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

/// The one record control (§7): Record, then Stop while listening.
private struct RecordButton: View {
    let listening: Bool
    let busy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(listening ? "Stop" : "Record", systemImage: listening ? "stop.circle.fill" : "record.circle")
                .labelStyle(.iconOnly)
                .font(.system(size: 64))
                .foregroundStyle(Color.semanticError)
        }
        .buttonStyle(.borderless)
        .padShortcut(.space, modifiers: [])
        .disabled(busy)
        .accessibilityLabel(listening ? "Stop" : "Record")
        .accessibilityInputLabels(listening ? ["Stop"] : ["Record"])
    }
}

/// The recording commands the Mac menu bar carries for the focused window.
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

    func recordOrStop() {
        if isListening {
            session.stopListening()
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
