import SwiftUI

// Today's Scene (Decision 079; iOS-DESIGN §4.1, macOS-DESIGN §3.1, tvOS-DESIGN §2.1; the web's sceneCard): a short play
// for two, its opening set as a page, and the ways in. Hear It reads the opening live through the device's voices
// (`LiveListenThrough`, `speak`): nothing is rendered to a buffer and nothing is written.

/// Hear It: the opening read aloud live, the speech being read lit, stopped by the person or by the view going.
@Observable
final class SceneReading {
    private(set) var listen: LiveListenThrough?

    var isRunning: Bool { listen?.isRunning ?? false }
    /// The speech being read (`OpeningSpeech.id`).
    var current: String? { listen?.current?.lineID }

    /// Whether this device has a voice to read with.
    static var hasVoice: Bool { !DeviceVoices.castable().isEmpty }

    func start(_ opening: [OpeningSpeech], cast: VoiceCast, player: AudioPlayer) {
        stop()
        let live = LiveListenThrough.system(cast: cast)
        listen = live
        player.pause()
        let plan = opening.map { ListenEntry.voice(lineID: $0.id, part: $0.part, text: $0.text) }
        Task {
            await live.run(plan) { _ in URL(fileURLWithPath: "/dev/null") }
            if listen === live { listen = nil }
        }
    }

    func stop() {
        listen?.stop()
        listen = nil
    }
}

/// The opening as a page on the print ground: each speech its role name over its said words, a 3 pt rule in the part's
/// hue, the speech being read tinted.
struct ScenePage: View {
    let opening: [OpeningSpeech]
    let hue: (PartID) -> Color
    var current: String?
    var lines = 3
    /// Drawn as a page with its own ground and edge; a play's window is already the page (`PlayOpeningWindow`).
    var framed = true

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            ForEach(opening) { speech in
                let color = hue(speech.part)
                HStack(alignment: .top, spacing: 9) {
                    RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: speech.name)
                            #if os(tvOS)
                            .font(TypeRamp.bodyStrong)
                            .foregroundStyle(color)
                            #else
                            .font(TypeRamp.caption.weight(.semibold))
                            #endif
                        SaidText(speech: speech)
                            .font(TypeRamp.body)
                            .lineLimit(lines)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 2)
                .background(speech.id == current ? color.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 2))
                .accessibilityElement(children: .combine)
            }
        }
        .foregroundStyle(Color.brandText)
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(framed ? Color.printGround : .clear, in: RoundedRectangle(cornerRadius: 4))
        .overlay { if framed { RoundedRectangle(cornerRadius: 4).strokeBorder(Color.printEdge, lineWidth: 1) } }
        .accessibilityLabel("The opening")
    }
}

/// An opening speech's words: prose as one run, verse a line to a printed line, the part of a line that turns over
/// indented so it never reads as a line of its own (PLAYS-DESIGN §2.7 rule 10).
struct SaidText: View {
    let speech: OpeningSpeech

    var body: some View {
        if let verse = speech.verse {
            Text(verbatim: "").verseLines(verse)
                .textRenderer(TurnedLines())
                .padding(.trailing, TurnedLines.indent)
        } else {
            Text(verbatim: speech.text)
        }
    }
}

/// Marks the word a printed verse line begins with.
private struct VerseLineStart: TextAttribute {}

private extension Text {
    /// The lines as one `Text`, each line's first word marked so the renderer can tell it from a turned-over part.
    func verseLines(_ rows: [String]) -> Text {
        var out = self
        for (i, row) in rows.enumerated() {
            let word = String(row.prefix { !$0.isWhitespace })
            let rest = Text(verbatim: String(row.dropFirst(word.count)) + (i + 1 < rows.count ? "\n" : ""))
            out = Text("\(out)\(Text(verbatim: word).customAttribute(VerseLineStart()))\(rest)")
        }
        return out
    }
}

/// Draws a laid-out line that no printed line begins moved in by an em: the turned-over part of the line above. The
/// room it moves into is the text's trailing padding.
private struct TurnedLines: TextRenderer {
    static let indent: CGFloat = 16
    var displayPadding: EdgeInsets { EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: Self.indent) }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            var copy = context
            if line.first?[VerseLineStart.self] == nil { copy.translateBy(x: Self.indent, y: 0) }
            copy.draw(line)
        }
    }
}

/// The scene's script, fetched once for the card (the index row's opening stands in until it comes, or if it fails).
enum SceneScript {
    /// A part's mark color, or the muted ink before the script (and its cast) is known.
    static func hue(_ script: PlayScript?, _ part: PartID) -> Color {
        script.flatMap { Color.genre($0.partHue(part)) } ?? Color.brandTextMuted
    }
}

#if os(iOS) || os(macOS)
/// DEBUG door for frames (never in a Release build): APP_SCENE=try presses Try a Line, hear presses Hear It, once.
enum SceneDoor {
    static let action: String? = {
        #if DEBUG
        ProcessInfo.processInfo.environment["APP_SCENE"]
        #else
        nil
        #endif
    }()
    static var taken = false
}

/// Home's wide card (WEB-DESIGN §4.2r rule 6): the drama board holds only the page, the words stand on the page ground,
/// beside the board from 560 pt of column and under it on a phone.
struct SceneWideLayout<Words: View, Page: View>: View {
    let hasPage: Bool
    @ViewBuilder let words: () -> Words
    @ViewBuilder let page: () -> Page
    @State private var width: CGFloat = 0

    private static var besideFrom: CGFloat { 560 }
    private static var boardSide: CGFloat { 320 }

    var body: some View {
        let beside = width >= Self.besideFrom
        let board = page()
            .padding(Spacing.s3)
            .frame(maxWidth: beside ? Self.boardSide : .infinity, alignment: .leading)
            .background(Color.board(PlayScript.boardGenre), in: RoundedRectangle(cornerRadius: Radius.card))
        Group {
            if beside {
                HStack(alignment: .center, spacing: Spacing.s6) {
                    if hasPage { board }
                    words()
                }
            } else {
                VStack(alignment: .leading, spacing: Spacing.s3) {
                    words()
                    if hasPage { board }
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

/// The card on Home and Record (iOS-DESIGN §4.1 "Today's Scene"; macOS-DESIGN §3.1): the drama board with the kicker,
/// the title and the event line (the link to the play's page), the opening, then Try a Line, Hear It and Read in one
/// row that never wraps.
struct TodaysSceneCard: View {
    let row: PlayRow
    /// Home's card (WEB-DESIGN §4.2r rule 6): the drama board holds only the opening, the words and buttons stand on the
    /// page ground, beside the board once the column is wide enough and under it on a phone.
    var wide = false
    @Environment(PlaysLibrary.self) private var plays
    @Environment(AppStore.self) private var app
    @Environment(AudioPlayer.self) private var player
    @Environment(AccountStore.self) private var account
    @Environment(\.openWindow) private var openWindow
    @State private var whole: PlayScript?
    @State private var reading = SceneReading()
    @State private var asking = false
    @State private var trying = false
    @State private var error: String?

    private var opening: [OpeningSpeech] { whole?.opening(n: 4) ?? row.opening(n: 4) }
    private var board: Color { Color.board(PlayScript.boardGenre) }
    private var ink: Color { Color.onBoard(PlayScript.boardGenre) }

    var body: some View {
        Group {
            if wide { wideCard } else { boardCard }
        }
        .accessibilityIdentifier("todays-scene")
        .task(id: row.id) {
            whole = (try? await plays.script(id: row.id)) ?? nil
            await openDoor()
        }
        .onDisappear { reading.stop() }
        .sheet(isPresented: $asking) { SecondProductionSheet() }
    }

    private func head(ink: Color) -> some View {
        PushLink(value: PlayRoute.script(row.id)) {
            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text("Today\u{2019}s Scene").font(TypeRamp.caption)
                Text(verbatim: row.title)
                    .font(TypeRamp.sectionHeader)
                    .multilineTextAlignment(.leading)
                EventLine(facts: [row.authorLine, row.voicesText, row.minutesText], color: ink)
            }
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("scene-head")
    }

    private var page: some View {
        ScenePage(opening: opening, hue: { SceneScript.hue(whole, $0) }, current: reading.current)
    }

    @ViewBuilder private var buttons: some View {
        ActionRow {
            Button { Task { await tryLine() } } label: { Label("Try a Line", systemImage: "mic") }
                .pageAction(primary: true)
                .disabled(trying)
                .accessibilityIdentifier("scene-try")
            if whole != nil, !opening.isEmpty, SceneReading.hasVoice {
                Button { hear() } label: {
                    ActionLabel(title: reading.isRunning ? "Stop" : "Hear It",
                                systemImage: reading.isRunning ? "stop.fill" : "speaker.wave.2")
                }
                .pageAction()
                .accessibilityIdentifier("scene-hear")
                .accessibilityAddTraits(reading.isRunning ? .isSelected : [])
            }
            ReadButton(scriptID: row.id)
        }
    }

    private var boardCard: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            head(ink: ink)
            if !opening.isEmpty { page }
            buttons.environment(\.actionBoard, .some(PlayScript.boardGenre))
            if let error {
                Label(error, systemImage: "exclamationmark.triangle").font(TypeRamp.caption).foregroundStyle(ink)
            }
        }
        .padding(.vertical, Spacing.s4)
        .modifier(WidthPadding(compact: Spacing.s4, regular: PageRowInsets.wordsMargin))
        .background(board, in: RoundedRectangle(cornerRadius: Radius.card))
    }

    private var wideCard: some View {
        SceneWideLayout(
            hasPage: !opening.isEmpty,
            words: {
                VStack(alignment: .leading, spacing: Spacing.s3) {
                    head(ink: Color.brandText)
                    buttons
                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle").font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
                    }
                }
            },
            page: { page })
    }

    private func hear() {
        if reading.isRunning { reading.stop(); return }
        guard let whole else { return }
        reading.start(opening, cast: .script(whole), player: player)
    }

    /// Try a Line: the reader's Record for the answering voice (PLAYS-DESIGN §2.9 rule 1), the studio on that part's
    /// first line. Signed out, a new production while another holds a take asks for an account instead (§2.3 rule 3).
    private func tryLine() async {
        reading.stop()
        trying = true
        defer { trying = false }
        error = nil
        let fetched = if let whole { whole } else { (try? await plays.script(id: row.id)) ?? nil }
        guard let script = fetched else {
            error = "This play could not be found."
            return
        }
        let first = script.opening(n: 4)
        guard let part = script.answeringPart(first) else { return }
        let store = plays.store
        let pick = StudioCore.productionFor(store.productions, isShared: { store.share($0) != nil }, script: script, part: part)
        let makingNew = switch pick {
        case .make: true
        case let .resume(id), let .take(id): !(store.production(id)?.hasTake ?? false)
        }
        if StudioCore.needsAccount(productions: store.productions, signedIn: account.status != .signedOut, makingNew: makingNew) {
            asking = true
            return
        }
        guard let target = StudioOpen.resolve(plays, script: script, part: part) else {
            error = "This device could not save a production."
            return
        }
        let line = first.first { $0.part == part }?.lineID ?? script.lines(for: part).first?.id
        StudioOpen.open(target, scriptID: script.id, line: line, app: app, openWindow: openWindow)
    }

    private func openDoor() async {
        guard let action = SceneDoor.action, !SceneDoor.taken else { return }
        SceneDoor.taken = true
        switch action {
        case "try": await tryLine()
        case "hear": hear()
        default: break
        }
    }
}

/// Signed out, a second production: the reason and the sign-in, in place of the studio (PLAYS-DESIGN §2.3 rule 3).
struct SecondProductionSheet: View {
    @Environment(AccountStore.self) private var account
    @Environment(CatalogStore.self) private var catalog
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.s4) {
                Text("A second production needs an account.")
                    .font(TypeRamp.bodyStrong)
                    .multilineTextAlignment(.center)
                if catalog.isOnline {
                    SignInButtons().frame(maxWidth: 320)
                } else {
                    Label(Connectivity.offlineLine, systemImage: "wifi.slash")
                        .font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
                }
            }
            .padding(Spacing.s6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 240)
        #else
        .presentationDetents([.medium])
        #endif
        .onChange(of: account.isSignedIn) { _, signedIn in if signedIn { dismiss() } }
        .accessibilityIdentifier("second-production")
    }
}
#endif
