import SwiftUI

// The shared screen (PLAYS-DESIGN §12.5, tvOS-DESIGN §4.13): the room's current line large, the code, who is here.
// It joins as role "screen", holds no part and records nothing (rule 12). The Apple TV, an iPad or a Mac window
// on a projector all show this one view; the remote or the pointer has nothing to press. On the Apple TV the screen
// is reached by Show a Reading (PLAYS-DESIGN §12.10 item 9): it shows a pairing code and the leader types it.

enum ReadScreenText {
    /// The code in two groups of three, so it reads aloud ("ABC 123").
    static func grouped(_ code: String) -> String {
        code.count == ReadCore.codeLength ? String(code.prefix(3)) + " " + String(code.suffix(3)) : code
    }

    /// The status line: a refusal, a warning, or a fact the room cannot show by itself.
    static func status(_ s: ReadSession) -> String {
        if let e = s.ended { return ReadCore.refusal(e) }
        guard let snap = s.snapshot else { return s.offline ? ReadCore.refusal("offline") : "" }
        if snap.waitingForLeader {
            if let who = ReadCore.waitingFor(snap) { return "Waiting for \(who)" }
            return snap.kind == "class" ? "Waiting for the teacher" : "Waiting for the leader"
        }
        if s.offline { return ReadCore.refusal("offline") }
        return s.slow ? "Slow connection" : ""
    }

    /// "Read open parts" (a leader message): a speech line nobody holds is the device voice's to read.
    static func isOpen(_ snap: ReadSnapshot) -> Bool {
        guard let r = snap.readsNow else { return false }
        return snap.kind == "class" ? r.seat == nil : r.holder == nil
    }
}

/// The room bar's one line: a refusal or warning first, then the reader's next line as a fact, then who is reading.
enum RoomText {
    static func line(_ snap: ReadSnapshot, status: String) -> String {
        if !status.isEmpty { return status }
        let next = snap.nextMine.map { ReadCore.Next(line: $0.line, inLines: $0.in) }
        if let n = ReadCore.nextLine(next) { return n }
        if snap.mode == "record", let who = ReadCore.readerName(snap, snap.readsNow) { return "\(who) is reading" }
        guard let r = snap.readsNow else { return "" }
        let held = snap.kind == "class" ? r.seat != nil : r.holder != nil
        let name = ReadCore.readerName(snap, r)
        return [PartID(rawValue: r.part).title, name, held ? nil : "Open"].compactMap { $0 }.joined(separator: " \u{00B7} ")
    }
}

struct ReadScreenView: View {
    let snapshot: ReadSnapshot?
    let status: String
    let script: PlayScript?

    private var lines: [ScriptLine] { script?.lines ?? [] }

    private func speech(_ line: ScriptLine?, large: Bool) -> some View {
        VStack(spacing: Spacing.s2) {
            if let line {
                if line.kind == .speech { Text(verbatim: line.part.title).font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted) }
                Text(verbatim: line.spokenText.isEmpty ? (line.source ?? "") : line.spokenText)
                    .font(large ? TypeRamp.pageTitle : TypeRamp.body)
                    .foregroundStyle(large ? Color.brandText : Color.brandTextMuted)
                    .multilineTextAlignment(.center)
            }
        }
        .accessibilityElement(children: .combine)
    }

    var body: some View {
        let snap = snapshot
        let i = max(0, lines.firstIndex { $0.id == snap?.cursor } ?? 0)
        VStack(spacing: Spacing.s8) {
            Spacer(minLength: 0)
            if !lines.isEmpty {
                speech(i > 0 ? lines[i - 1] : nil, large: false)
                speech(lines[i], large: true)
                speech(i + 1 < lines.count ? lines[i + 1] : nil, large: false)
            } else if let snap, let r = snap.readsNow {
                Text(verbatim: PartID(rawValue: r.part).title).font(TypeRamp.pageTitle)
            }
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: status).font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
                Spacer()
                if let snap {
                    Text(verbatim: ReadScreenText.grouped(snap.code)).font(TypeRamp.tabular).accessibilityLabel(snap.code.map(String.init).joined(separator: " "))
                    Text("\(snap.present) here").font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
                }
            }
        }
        .padding(Spacing.s6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.brandBackground)
    }
}

/// The screen's voice (PLAYS-DESIGN §12.10 item 10): a line nobody holds is read aloud by the live stand-in only while
/// the leader's Read Open Parts is on, and it stops the moment the cursor moves, so it never sounds during a take.
enum ReadScreenVoice {
    struct Step: Equatable, Sendable {
        var cancel: Bool
        /// The line to speak now (the cursor's), or nil.
        var speak: String?
        /// The line last spoken, kept so a line is read once.
        var spokenAt: String?
    }

    static func step(_ snap: ReadSnapshot, spokenAt: String?) -> Step {
        var cancel = false
        var at = spokenAt
        if let a = at, a != snap.cursor { cancel = true; at = nil }
        let wants = snap.readOpen == true && !snap.ended && ReadScreenText.isOpen(snap)
            && snap.readsNow.map { PartID(rawValue: $0.part).isSpeaking } == true
        guard wants else {
            if at != nil { cancel = true; at = nil }
            return Step(cancel: cancel, speak: nil, spokenAt: nil)
        }
        if at == snap.cursor { return Step(cancel: cancel, speak: nil, spokenAt: at) }
        return Step(cancel: cancel, speak: snap.cursor, spokenAt: snap.cursor)
    }
}

#if os(iOS) || os(macOS) || os(tvOS)
/// Speaks what `ReadScreenVoice` says with the device voice, live: nothing is rendered to a buffer or written.
@MainActor
final class ScreenSpeaker {
    private let speaker: any ListenSpeaker
    private var spokenAt: String?
    private var task: Task<Void, Never>?

    init(speaker: any ListenSpeaker = SystemListenSpeaker(cast: nil)) { self.speaker = speaker }

    func follow(_ snap: ReadSnapshot?, script: PlayScript?) {
        guard let snap else { stop(); return }
        let step = ReadScreenVoice.step(snap, spokenAt: spokenAt)
        spokenAt = step.spokenAt
        if step.cancel { stop() }
        guard let id = step.speak, let line = script?.lines.first(where: { $0.id == id }), !line.spokenText.isEmpty else { return }
        let speaker = speaker
        task = Task { await speaker.speak(line.spokenText, part: line.part, personalVoice: false) }
    }

    func stop() {
        task?.cancel()
        task = nil
        speaker.stop()
    }
}
#endif

/// The room as a shared screen, over a session that has joined it: the lines, the status, the voice, the script.
struct ReadScreenBody: View {
    let session: ReadSession
    @State private var script: PlayScript?
    #if os(iOS) || os(macOS) || os(tvOS)
    @State private var voice = ScreenSpeaker()
    #endif

    var body: some View {
        ReadScreenView(snapshot: session.snapshot, status: ReadScreenText.status(session), script: script)
            .onAppear { load(session.snapshot?.scriptID) }
            .onChange(of: session.snapshot?.scriptID) { _, id in load(id) }
            #if os(iOS) || os(macOS) || os(tvOS)
            .onChange(of: session.snapshot) { _, snap in voice.follow(snap, script: script) }
            .onDisappear { voice.stop(); session.leave() }
            #else
            .onDisappear { session.leave() }
            #endif
    }

    private func load(_ id: String?) {
        guard let id else { return }
        script = CastableLibrary.load()?.scripts.first { $0.id == id }
    }
}

/// Joins a room as its shared screen by its code and shows it: the debug door and `eardrama://read/CODE?screen`, and the
/// Mac's projector window.
struct ReadScreenHost: View {
    let code: String
    @State private var session = ReadSession.system()
    @State private var failure: String?
    @State private var attempt = 0

    var body: some View {
        ZStack {
            ReadScreenBody(session: session)
            if let message = failure {
                VStack(spacing: Spacing.s4) {
                    Text(verbatim: message).font(TypeRamp.bodyStrong).foregroundStyle(Color.semanticError)
                    Button("Try Again") { self.failure = nil; self.attempt += 1 }
                }
            }
        }
        .task(id: attempt) {
            guard failure == nil else { return }
            guard let normal = ReadCore.normalizeCode(code) else { failure = ReadCore.refusal("bad_code"); return }
            do {
                try await session.join(code: normal, ["role": "screen"])
            } catch let f as ReadFailure {
                failure = ReadCore.refusal(f.code)
            } catch {
                failure = ReadCore.refusal("error")
            }
        }
    }
}

// MARK: - Show a Reading (the TV's pairing)

/// The TV asks for a code, shows it, and asks every 2 seconds whether a leader attached it; the answer is the room's
/// snapshot with the TV's member key. An expired code is replaced at once, without a word.
@Observable
final class ReadPairingModel {
    private(set) var pairing: ReadPairing?
    /// A refusal worth showing (rate limit, offline); expiry never is.
    private(set) var status = ""
    private(set) var joined: ReadJoined?
    @ObservationIgnored private let wire: any ReadWire
    @ObservationIgnored private let sleep: (Duration) async -> Void
    static let pollSeconds = 2

    init(wire: any ReadWire, sleep: @escaping (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.wire = wire
        self.sleep = sleep
    }

    static func system() -> ReadPairingModel { ReadPairingModel(wire: WorkerReadWire(api: .shared)) }

    /// One turn: ask for a code when there is none, else ask whether it was attached.
    func step() async {
        do {
            guard let pairing else {
                pairing = try await wire.pair()
                status = ""
                return
            }
            if let room = try await wire.pairWait(pairing) { joined = room }
            status = ""
        } catch let f as ReadFailure {
            if f.code == "pair_expired" || f.code == "no_such_pair" {
                pairing = nil
                await step()
            } else {
                status = ReadCore.refusal(f.code)
            }
        } catch {
            status = ReadCore.refusal("error")
        }
    }

    func run() async {
        while joined == nil, !Task.isCancelled {
            await step()
            if joined != nil { break }
            await sleep(.seconds(Self.pollSeconds))
        }
    }
}

/// The pairing screen: the code at ten feet, split 3 + 3, and the one line the viewer cannot discover by looking.
struct ReadPairView: View {
    let code: String?
    let status: String
    /// 76 pt is the floor (tvOS-DESIGN §4.13); the code is the screen.
    static let codeSize: CGFloat = 112

    var body: some View {
        VStack(spacing: Spacing.s8) {
            Spacer(minLength: 0)
            Text(verbatim: code.map(ReadScreenText.grouped) ?? "\u{2026}")
                .font(.custom(TypeRamp.displayFontName, fixedSize: Self.codeSize))
                .monospacedDigit()
                .foregroundStyle(Color.brandText)
                .accessibilityLabel(code.map { $0.map(String.init).joined(separator: " ") } ?? "")
                .accessibilityIdentifier("read-pair-code")
            Text("On the leader\u{2019}s device: Reading, then Add a Screen.")
                .font(TypeRamp.body)
                .foregroundStyle(Color.brandTextMuted)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
            Text(verbatim: status).font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted).frame(minHeight: 40)
        }
        .padding(Spacing.s6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.brandBackground)
    }
}

/// Show a Reading: pairs, then becomes the room's screen.
struct ReadPairHost: View {
    @State private var model = ReadPairingModel.system()
    @State private var session = ReadSession.system()
    @State private var adopted = false

    var body: some View {
        if adopted {
            ReadScreenBody(session: session)
        } else {
            ReadPairView(code: model.pairing?.code, status: model.status)
                .task {
                    await model.run()
                    if let joined = model.joined {
                        session.adopt(joined)
                        adopted = true
                    }
                }
        }
    }
}
