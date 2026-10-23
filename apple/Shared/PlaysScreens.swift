#if os(iOS) || os(macOS)
import AVFoundation
import SwiftUI

// Plays phase 1, pass the phone (docs/PLAYS-DESIGN.md, binding). The same seven
// verbs on iPhone, iPad, and Mac (§2): pick a play, read the cast sheet, take a
// part, record line by line, pass the phone, listen through, finish and keep it.
// iPhone pushes; iPad puts the cast and the script side by side; the Mac opens
// each production in its own window (ContentView_macOS.swift).

/// The Plays tab's pushes, resolved by the one destination registry
/// (`RouteDestinations`, ListScreens.swift).
enum PlayRoute: Hashable {
    case script(String)
    case production(String)
    case recording(production: String, part: PartID)
}

// MARK: - Pick a play

struct PlaysScreen: View {
    @Environment(PlaysLibrary.self) private var plays

    var body: some View {
        List {
            let productions = plays.store.productions
            if !productions.isEmpty {
                Section("Your plays") {
                    ForEach(productions) { production in
                        ProductionLink(production: production)
                    }
                }
            }
            Section("Plays you can cast") {
                switch plays.state {
                case .loading:
                    ProgressView()
                case .unavailable:
                    ContentUnavailableView("No plays on this device", systemImage: "theatermasks")
                case .ready:
                    ForEach(plays.scripts) { script in
                        NavigationLink(value: PlayRoute.script(script.id)) {
                            ScriptRow(script: script)
                        }
                    }
                }
            }
        }
        .navigationTitle("Plays")
        .task { await plays.load() }
    }
}

/// A production opens in place on iPhone and iPad, and in its own window on
/// the Mac (§2.2).
private struct ProductionLink: View {
    let production: Production
    @Environment(PlaysLibrary.self) private var plays
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif
    @State private var confirming = false

    var body: some View {
        link
            .contextMenu {
                Button("Delete Production", role: .destructive) { confirming = true }
            }
            #if os(iOS)
            .swipeActions {
                Button(role: .destructive) { confirming = true } label: { Label("Delete", systemImage: "trash") }
            }
            #endif
            .deleteProductionDialog(production, isPresented: $confirming)
    }

    @ViewBuilder private var link: some View {
        #if os(macOS)
        Button { openWindow(id: ProductionWindow_macOS.id, value: production.id) } label: { label }
            .buttonStyle(.plain)
        #else
        NavigationLink(value: PlayRoute.production(production.id)) { label }
        #endif
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            Text(verbatim: production.title).font(TypeRamp.bodyStrong)
            Text(verbatim: ProductionProgress.line(production, script: plays.castScript(for: production)))
                .font(TypeRamp.caption)
                .foregroundStyle(Color.brandTextMuted)
        }
        .accessibilityElement(children: .combine)
    }
}

enum ProductionProgress {
    static func line(_ production: Production, script: PlayScript?) -> String {
        if production.isFinished { return "Finished" }
        guard let script else { return "" }
        let total = script.speechLineIDs.count
        let voiced = total - Relay.missingSpeech(production, script).count
        return "\(voiced) of \(total) lines recorded"
    }
}

private struct ScriptRow: View {
    let script: PlayScript

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            Text(verbatim: script.title).font(TypeRamp.bodyStrong)
            Text(verbatim: [script.authorLine, "\(script.castParts.filter { $0.id.isSpeaking }.count) parts"]
                .filter { !$0.isEmpty }.joined(separator: " · "))
                .font(TypeRamp.caption)
                .foregroundStyle(Color.brandTextMuted)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - The script and its rights line

struct PlayScriptScreen: View {
    let id: String
    @Environment(PlaysLibrary.self) private var plays
    @Environment(AppStore.self) private var app
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif
    @State private var error: String?

    var body: some View {
        if let script = plays.script(id) {
            List {
                Section {
                    VStack(alignment: .leading, spacing: Spacing.s2) {
                        Text(verbatim: script.title).font(TypeRamp.sectionHeader)
                        if !script.authorLine.isEmpty {
                            Text(verbatim: script.authorLine).font(TypeRamp.body)
                        }
                        RightsLine(script: script)
                    }
                    Button {
                        start(script)
                    } label: {
                        Label("Cast this play", systemImage: "person.2")
                    }
                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Color.semanticError)
                    }
                }
                Section("Parts") {
                    ForEach(script.castParts) { part in
                        PartCountRow(part: part)
                    }
                }
            }
            .navigationTitle(script.title)
        } else {
            ContentUnavailableView("Play not found", systemImage: "questionmark.square.dashed")
        }
    }

    private func start(_ script: PlayScript) {
        do {
            let production = try plays.store.create(script)
            #if os(macOS)
            openWindow(id: ProductionWindow_macOS.id, value: production.id)
            #else
            app.push(PlayRoute.production(production.id))
            #endif
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// The record's own evidence, linked so a reader can check it (§2.1).
private struct RightsLine: View {
    let script: PlayScript

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            ForEach(Array(script.rights.evidence.enumerated()), id: \.offset) { _, evidence in
                if let claim = evidence.claim {
                    if let src = evidence.src, let url = URL(string: src) {
                        Link(destination: url) { Text(verbatim: claim) }
                    } else {
                        Text(verbatim: claim)
                    }
                }
            }
            if let url = URL(string: script.source.url) {
                Link(destination: url) { Text(verbatim: script.source.name) }
            }
        }
        .font(TypeRamp.caption)
    }
}

private struct PartCountRow: View {
    let part: CastPart

    var body: some View {
        HStack {
            Text(verbatim: part.title)
            Spacer()
            Text(part.lineCount == 1 ? "1 line" : "\(part.lineCount) lines")
                .font(TypeRamp.tabular)
                .foregroundStyle(Color.brandTextMuted)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - The cast sheet

/// iPhone: the cast sheet, pushing each part's recording. iPad (regular
/// width): the cast sheet and the part's script side by side, so the person
/// waiting their turn can follow along (§2.2).
struct ProductionScreen: View {
    let id: String
    @Environment(PlaysLibrary.self) private var plays
    @Environment(AppStore.self) private var app
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selected: PartID?

    var body: some View {
        if let production = plays.store.production(id), let script = plays.castScript(for: production) {
            Group {
                if sizeClass == .regular {
                    HStack(spacing: 0) {
                        CastSheet(production: production, script: script) { selected = $0 }
                            .frame(width: 340)
                        Divider()
                        PartDetail(production: production, script: script, part: selected ?? Relay.current(production, script))
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    CastSheet(production: production, script: script) { part in
                        app.push(PlayRoute.recording(production: production.id, part: part))
                    }
                }
            }
            .navigationTitle(production.title)
        } else {
            ContentUnavailableView("Production not found", systemImage: "questionmark.square.dashed")
        }
    }
}

/// Who takes which part (§2.2-2.5). Parts are listed largest first; only the
/// relay's next part can be taken, one at a time (pending owner, C7).
struct CastSheet: View {
    let production: Production
    let script: PlayScript
    let open: (PartID) -> Void
    @Environment(PlaysLibrary.self) private var plays
    @State private var taking: PartID?
    @State private var performer = ""
    @State private var refusal: String?

    var body: some View {
        List {
            Section {
                ForEach(script.castParts) { part in
                    row(part)
                }
            } footer: {
                if let refusal { Text(verbatim: refusal).foregroundStyle(Color.semanticError) }
            }
            Section {
                ListenThrough(production: production, script: script)
            }
            Section {
                DeleteProductionButton(production: production)
                if !production.unusedTakes.isEmpty {
                    Button("Discard Unused Takes") {
                        do { try plays.store.discardUnusedTakes(production.id) } catch {
                            refusal = error.localizedDescription
                        }
                    }
                }
            }
        }
        .alert("Take this part", isPresented: Binding(get: { taking != nil }, set: { if !$0 { taking = nil } })) {
            TextField("Your name", text: $performer)
            Button("Take Part") { take() }
            Button("Cancel", role: .cancel) { taking = nil }
        }
    }

    @ViewBuilder private func row(_ part: CastPart) -> some View {
        let state = production.state(of: part.id)
        let next = Relay.next(production, script)
        HStack(spacing: Spacing.s3) {
            // Each control in the row is its own button (borderless or bordered),
            // so a tap on one never fires the others.
            Button { open(part.id) } label: {
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Text(verbatim: part.title).font(TypeRamp.bodyStrong).foregroundStyle(Color.brandText)
                    Text(verbatim: status(part, state))
                        .font(TypeRamp.caption)
                        .foregroundStyle(Color.brandTextMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityElement(children: .combine)
            switch state.status {
            case .recording:
                Button("Record") { open(part.id) }.buttonStyle(.borderedProminent)
            case .open where part.id == next:
                if !part.id.isSpeaking {
                    Button("Leave Silent") { apply { try Relay.leaveSilent(part.id, in: $0, script: script) } }
                        .buttonStyle(.bordered)
                }
                Button("Take Part") {
                    performer = ""
                    taking = part.id
                }
                .buttonStyle(.borderedProminent)
            case .done, .silent:
                Menu {
                    Button("Open Part") { apply { try Relay.reopen(part.id, in: $0, script: script) } }
                } label: {
                    Image(systemName: "ellipsis.circle").accessibilityLabel("More")
                }
                .menuStyle(.borderlessButton)
                .disabled(Relay.current(production, script) != nil)
                .fixedSize()
            case .open:
                EmptyView()
            }
        }
    }

    private func status(_ part: CastPart, _ state: PartState) -> String {
        let lines = part.lineCount == 1 ? "1 line" : "\(part.lineCount) lines"
        let missing = Relay.missingLines(part.id, in: production, script: script).count
        let name = state.performer.map { " · \($0)" } ?? ""
        return switch state.status {
        case .open: lines
        case .recording: "\(part.lineCount - missing) of \(lines) recorded\(name)"
        case .done: "Recorded\(name)"
        case .silent: "Left silent"
        }
    }

    private func take() {
        guard let part = taking else { return }
        taking = nil
        apply { try Relay.take(part, performer: performer, in: $0, script: script) }
        open(part)
    }

    private func apply(_ change: (Production) throws -> Production) {
        guard let latest = plays.store.production(production.id) else { return }
        do {
            plays.store.update(try change(latest))
            refusal = nil
        } catch let error as Relay.Refusal {
            refusal = RelayRefusalText.text(error)
        } catch {
            refusal = error.localizedDescription
        }
    }
}

enum RelayRefusalText {
    static func text(_ refusal: Relay.Refusal) -> String {
        switch refusal {
        case let .anotherPartIsRecording(part): "\(part.title) is still recording."
        case let .notNext(expected): expected.map { "\($0.title) is next." } ?? "No part is open."
        case let .linesMissing(lines): lines.count == 1 ? "1 line still needs a take." : "\(lines.count) lines still need a take."
        case .speakingPartCannotBeSilent: "A speaking part needs a voice."
        }
    }
}

struct DeleteProductionButton: View {
    let production: Production
    @Environment(PlaysLibrary.self) private var plays
    @Environment(\.dismiss) private var dismiss
    @State private var confirming = false

    var body: some View {
        Button("Delete Production", role: .destructive) { confirming = true }
            .deleteProductionDialog(production, isPresented: $confirming) { dismiss() }
    }
}

extension View {
    /// Deleting a production deletes its folder: every take, the room tone, the mix (§6).
    func deleteProductionDialog(_ production: Production, isPresented: Binding<Bool>,
                                then done: @escaping () -> Void = {}) -> some View {
        modifier(DeleteProductionDialog(production: production, isPresented: isPresented, done: done))
    }
}

private struct DeleteProductionDialog: ViewModifier {
    let production: Production
    @Binding var isPresented: Bool
    let done: () -> Void
    @Environment(PlaysLibrary.self) private var plays

    func body(content: Content) -> some View {
        content.confirmationDialog("Delete \(production.title)?", isPresented: $isPresented) {
            Button("Delete Production and Its Recordings", role: .destructive) {
                try? plays.store.delete(production.id)
                done()
            }
        } message: {
            Text("Every take is removed from this device.")
        }
    }
}

/// iPhone's push for one part.
struct PartScreen: View {
    let productionID: String
    let part: PartID
    @Environment(PlaysLibrary.self) private var plays

    var body: some View {
        if let production = plays.store.production(productionID), let script = plays.castScript(for: production) {
            PartDetail(production: production, script: script, part: part, dismissWhenDone: true)
        } else {
            ContentUnavailableView("Production not found", systemImage: "questionmark.square.dashed")
        }
    }
}

/// The part's own panel: its recording when it is the part being recorded,
/// otherwise its lines to read along.
struct PartDetail: View {
    let production: Production
    let script: PlayScript
    let part: PartID?
    /// Only iPhone's pushed screen goes back when the part is done; beside the
    /// cast sheet (iPad, the Mac window) the panel simply turns to the lines.
    var dismissWhenDone = false

    var body: some View {
        if let part, production.state(of: part).status == .recording {
            RecordingScreen(productionID: production.id, part: part, dismissWhenDone: dismissWhenDone).id(part)
        } else if let part {
            List(script.lines(for: part)) { line in
                ScriptLineText(line: line)
            }
            .navigationTitle(part.title)
        } else {
            ContentUnavailableView("Choose a part", systemImage: "theatermasks")
        }
    }
}

// MARK: - Listen through, finish, keep

/// Pending owner (C5): a half-recorded play is not previewed outside the
/// recording flow. Listening through is offered only when every speaking line
/// has a human take, so it never holds a device voice; reaching the end of it
/// finishes the play (§2.6-2.7).
struct ListenThrough: View {
    let production: Production
    let script: PlayScript
    @Environment(PlaysLibrary.self) private var plays
    @Environment(AudioPlayer.self) private var player
    @State private var mix = MixPlayback()
    @State private var mixing = false
    @State private var error: String?
    @State private var listenedFrom: String?

    var body: some View {
        let missing = Relay.missingSpeech(production, script).count
        Group {
            if missing > 0 {
                Text(missing == 1 ? "1 line still needs a voice." : "\(missing) lines still need a voice.")
                    .foregroundStyle(Color.brandTextMuted)
            } else if mixing {
                ProgressView()
            } else if mix.duration > 0 {
                transport
            } else {
                Button {
                    Task { await prepare(andPlay: true) }
                } label: {
                    Label(production.isFinished ? "Play" : "Listen Through", systemImage: "play.fill")
                }
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Color.semanticError)
            }
        }
        .onChange(of: mix.reachedEnd) { _, ended in
            guard ended, !mix.skipped, let from = listenedFrom else { return }
            plays.store.markListenedThrough(production.id, fingerprint: from)
        }
        .onChange(of: production.chosenFingerprint) { mix.stop() }
        .onDisappear { mix.stop() }
    }

    private var transport: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack(spacing: Spacing.s4) {
                Button {
                    player.pause()
                    mix.toggle()
                } label: {
                    Label(mix.isPlaying ? "Pause" : "Play", systemImage: mix.isPlaying ? "pause.fill" : "play.fill")
                }
                #if os(iOS)
                .sensoryFeedback(Haptic.selection.feedback, trigger: mix.isPlaying)
                #endif
                if production.isFinished {
                    ShareLink(item: plays.store.mixURL(production.id)) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
            }
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                if production.isFinished {
                    Slider(value: Binding(get: { mix.currentTime }, set: { mix.seek(to: $0) }), in: 0...max(mix.duration, 1))
                        .accessibilityLabel("Position")
                } else {
                    ProgressView(value: min(mix.currentTime, mix.duration), total: max(mix.duration, 1))
                }
            }
        }
    }

    private func prepare(andPlay: Bool) async {
        mixing = true
        defer { mixing = false }
        do {
            let url = try await plays.store.renderMix(production.id)
            listenedFrom = plays.store.production(production.id)?.chosenFingerprint
            try mix.load(url)
            error = nil
            if andPlay {
                player.pause()
                mix.toggle()
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - A line as printed

/// A script line with its printed directions kept apart from the words said
/// (§3, Decision 059); nothing is rewritten.
struct ScriptLineText: View {
    let line: ScriptLine
    var large = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            if let role = line.role {
                Text(verbatim: role).font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
            }
            if line.kind == .speech {
                spoken
                .font(large ? TypeRamp.sectionHeader : TypeRamp.body)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(verbatim: line.source ?? "")
                    .italic()
                    .font(large ? TypeRamp.sectionHeader : TypeRamp.body)
                    .foregroundStyle(Color.brandTextMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var spoken: Text {
        let parts = line.parts ?? []
        guard let first = parts.first else { return Text(verbatim: "") }
        return parts.dropFirst().reduce(styled(first)) { text, part in Text("\(text) \(styled(part))") }
    }

    private func styled(_ part: LinePart) -> Text {
        switch part {
        case let .say(words): Text(verbatim: words)
        case let .direction(words), let .mic(words), let .sound(words):
            Text(verbatim: "(\(words))").italic().foregroundStyle(Color.brandTextMuted)
        }
    }
}
#endif
