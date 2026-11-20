import SwiftUI

// The shared screen (PLAYS-DESIGN §12.5, tvOS-DESIGN §4.13): the room's current line large, the code, who is here.
// It joins as role "screen", holds no part and records nothing (rule 12). The Apple TV, an iPad or a Mac window
// on a projector all show this one view; the remote or the pointer has nothing to press.

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

/// Joins a room as its shared screen and shows it. On the TV this is the whole pairing: the code on the room's
/// leader's screen is typed on the TV's own keyboard, or arrives by `eardrama://read/CODE?screen`.
struct ReadScreenHost: View {
    let code: String
    @State private var session = ReadSession.system()
    @State private var failure: String?
    @State private var script: PlayScript?
    @State private var attempt = 0

    var body: some View {
        ZStack {
            ReadScreenView(snapshot: session.snapshot, status: ReadScreenText.status(session), script: script)
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
        .onChange(of: session.snapshot?.scriptID) { _, id in
            guard let id else { return }
            script = CastableLibrary.load()?.scripts.first { $0.id == id }
        }
        .onDisappear { session.leave() }
    }
}
