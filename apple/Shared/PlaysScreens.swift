#if os(iOS) || os(macOS)
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

// Plays phase 1, pass the phone (docs/PLAYS-DESIGN.md, binding). The same seven
// verbs on iPhone, iPad, and Mac (§2): pick a play, read the cast sheet, take a
// part, record line by line, pass the phone, listen through, finish and keep it.
// iPhone pushes; iPad puts the cast and the script side by side; the Mac opens
// each production in its own window (ContentView_macOS.swift).

/// An ear drama's pushes, resolved by the one destination registry
/// (`RouteDestinations`, ListScreens.swift).
enum PlayRoute: Hashable {
    case script(String)
    case production(String)
    /// `line` set: replacing that one line of a finished part on a published play (P12).
    case recording(production: String, part: PartID, line: String? = nil)
}

// MARK: - Start an ear drama

// There is no Plays section (Decision 068): a play is a row in Browse and
// Search and a pick on Surprise, and the person's productions are Library's
// Ear dramas. Recording starts from the play's own page.

/// "Start an ear drama" (PLAYS-DESIGN §2.1): makes the production and opens
/// its cast sheet, in place on iPhone and iPad and in its own window on the Mac.
struct StartEarDramaButton: View {
    let script: PlayScript
    @Environment(PlaysLibrary.self) private var plays
    @Environment(AppStore.self) private var app
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Button {
                start()
            } label: {
                Label("Start an ear drama", systemImage: "person.2")
            }
            .pageAction(primary: true)
            if let error {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Color.semanticError)
            }
        }
    }

    private func start() {
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

/// An opened invitation heads Library (iOS-DESIGN §4.6): it is waiting on the
/// person, so it is not left below the settled sections.
struct LibraryInvitation: View {
    @Environment(AppStore.self) private var app
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    var body: some View {
        if let token = app.pendingInvite {
            InvitationSection(token: token, open: open)
        }
    }

    private func open(_ production: Production) {
        #if os(macOS)
        openWindow(id: ProductionWindow_macOS.id, value: production.id)
        #else
        app.selectedTab = .library
        app.push(PlayRoute.production(production.id))
        #endif
    }
}

/// Library's Ear dramas (iOS-DESIGN §4.6, §4.12a): the productions on this
/// device and, signed in, the shared ones not opened here, then Classes.
struct EarDramasSection: View {
    @Environment(PlaysLibrary.self) private var plays
    @Environment(SharedPlays.self) private var shared
    @Environment(AccountStore.self) private var account
    @Environment(AppStore.self) private var app
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    var body: some View {
        let rows = PlaysShare.libraryRows(plays.store, remote: account.isSignedIn ? shared.remote : [])
        if rows.isEmpty {
            Section("Ear dramas") { SectionCaption("Ear dramas you record or join appear here.") }
        } else if !rows.isEmpty {
            Section("Ear dramas") {
                ForEach(rows) { row in
                    if let production = row.local {
                        ProductionLink(production: production)
                    } else if let remote = row.remote {
                        RemoteProductionRow(remote: remote, open: open)
                    }
                }
            }
        }
        if account.isSignedIn {
            ClassesSection()
        }
    }

    private func open(_ production: Production) {
        #if os(macOS)
        openWindow(id: ProductionWindow_macOS.id, value: production.id)
        #else
        app.selectedTab = .library
        app.push(PlayRoute.production(production.id))
        #endif
    }
}

/// A production opens in place on iPhone and iPad, and in its own window on
/// the Mac (§2.2).
struct ProductionLink: View {
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
        HStack(alignment: .top, spacing: Spacing.s3) {
            ArtTile(name: production.title, genre: nil, face: nil)
            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(verbatim: production.title).font(TypeRamp.bodyStrong)
                Text(verbatim: ProductionProgress.line(production, script: plays.castScript(for: production)))
                    .font(TypeRamp.caption)
                    .foregroundStyle(Color.brandTextMuted)
            }
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

struct ScriptRow: View {
    let script: PlayScript

    var body: some View {
        // R11a: a play's row leads with its tile, the title's letter (plays carry no genre).
        HStack(alignment: .top, spacing: Spacing.s3) {
            ArtTile(name: script.title, genre: PlayScript.boardGenre, face: nil)
            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(verbatim: script.title).font(TypeRamp.bodyStrong)
                Text(verbatim: [script.authorLine, "\(script.castParts.filter { $0.id.isSpeaking }.count) parts"]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(TypeRamp.caption)
                    .foregroundStyle(Color.brandTextMuted)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - The script and its rights line

struct PlayScriptScreen: View {
    let id: String
    @Environment(PlaysLibrary.self) private var plays

    var body: some View {
        if let script = plays.script(id) {
            ScrollView { PlayPageBody(script: script) }
            .navigationTitle(script.title)
            .task { await plays.load() }
        } else {
            EmptyState("Play not found", systemImage: "questionmark.square.dashed")
                .task { await plays.load() }
        }
    }
}

/// A play's page: the head board, Start an ear drama, the parts, the rights line (D3-6).
struct PlayPageBody: View {
    let script: PlayScript

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            HeadBoard(kicker: PlayHead.kicker(script), name: script.title, genre: PlayScript.boardGenre, art: nil,
                      first: nil, last: nil, facts: PlayHead.facts(script),
                      credits: script.authorLineWithYears, castScript: script)
            ActionRow { StartEarDramaButton(script: script) }
            Text("Parts").font(TypeRamp.sectionHeader)
            PartGrid {
                ForEach(script.castParts) { part in
                    PartCard(script: script, part: part)
                }
            }
            RightsLine(script: script)
        }
        .padding(Spacing.s4)
        .modifier(ReadableColumn())
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
    @State private var replacing: String?

    var body: some View {
        if let production = plays.store.production(id), let script = plays.castScript(for: production) {
            Group {
                if sizeClass == .regular {
                    HStack(spacing: 0) {
                        CastSheet(production: production, script: script, open: { selected = $0; replacing = nil },
                                  replace: { selected = $0; replacing = $1 })
                            .frame(width: 340)
                        Divider()
                        PartDetail(production: production, script: script, part: selected ?? Relay.current(production, script),
                                   replacing: replacing)
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    CastSheet(production: production, script: script, open: { part in
                        app.push(PlayRoute.recording(production: production.id, part: part))
                    }, replace: { part, line in
                        app.push(PlayRoute.recording(production: production.id, part: part, line: line))
                    })
                }
            }
            .navigationTitle(production.title)
        } else {
            EmptyState("Production not found", systemImage: "questionmark.square.dashed")
        }
    }
}

/// Who takes which part (§2.2-2.5). Parts are listed largest first; any open
/// part can be taken, the suggested one prominent, one at a time (C7).
struct CastSheet: View {
    @Environment(\.scenePhase) private var scenePhase
    let production: Production
    let script: PlayScript
    let open: (PartID) -> Void
    let replace: (PartID, String) -> Void
    @Environment(PlaysLibrary.self) private var plays
    @Environment(SharedPlays.self) private var shared
    @State private var taking: PartID?
    @State private var performer = ""
    @State private var refusal: String?

    var body: some View {
        let rec = shared.record(for: production, in: plays.store)
        List {
            Section {
                HeadBoard(kicker: "Ear drama", name: script.title, genre: PlayScript.boardGenre, art: nil, first: nil,
                          last: nil, facts: PlayHead.facts(script), credits: script.authorLineWithYears, castScript: script)
                    .padding(.horizontal, Spacing.s4)
                    .plainRow()
            }
            Section {
                ListenThrough(production: production, script: script)
            }
            SharedProductionSection(production: production, script: script)
            Section {
                PartGrid {
                    ForEach(script.castParts) { part in
                        if let rec {
                            SharedPartRow(production: production, script: script, part: part, rec: rec, open: open)
                        } else {
                            card(part)
                        }
                    }
                }
                .padding(.horizontal, Spacing.s4)
                .plainRow()
            } footer: {
                if let refusal { Text(verbatim: refusal).foregroundStyle(Color.semanticError).padding(.horizontal, Spacing.s4) }
            }
            if let rec, PlaysShare.published(rec) {
                ChangeLinesSection(production: production, script: script, rec: rec, replace: replace)
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
        .listStyle(.plain)
        .alert("Take this part", isPresented: Binding(get: { taking != nil }, set: { if !$0 { taking = nil } })) {
            TextField("Your name", text: $performer)
            Button("Take Part") { take() }
            Button("Cancel", role: .cancel) { taking = nil }
        }
        .task(id: production.id) { await shared.refresh(production.id, store: plays.store, script: script) }
        #if os(iOS)
        .refreshable { await shared.refresh(production.id, store: plays.store, script: script) }
        #endif
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, plays.store.share(production.id) != nil else { return }
            Task { await shared.refresh(production.id, store: plays.store, script: script) }
        }
    }

    @ViewBuilder private func card(_ part: CastPart) -> some View {
        LocalPartCard(production: production, script: script, part: part, open: { open(part.id) },
                      take: { performer = ""; taking = part.id },
                      leaveSilent: { apply { try Relay.leaveSilent(part.id, in: $0, script: script) } },
                      reopen: { apply { try Relay.reopen(part.id, in: $0, script: script) } })
    }

    private func take() {
        guard let part = taking else { return }
        taking = nil
        if apply({ try Relay.take(part, performer: performer, in: $0, script: script) }) { open(part) }
    }

    @discardableResult
    private func apply(_ change: (Production) throws -> Production) -> Bool {
        guard let latest = plays.store.production(production.id) else { return false }
        do {
            plays.store.update(try change(latest))
            refusal = nil
            return true
        } catch let error as Relay.Refusal {
            refusal = RelayRefusalText.text(error)
        } catch {
            refusal = error.localizedDescription
        }
        return false
    }
}

/// One part as the device keeps it: who holds it, how far along, and the verbs that apply.
struct LocalPartCard: View {
    let production: Production
    let script: PlayScript
    let part: CastPart
    let open: () -> Void
    let take: () -> Void
    let leaveSilent: () -> Void
    let reopen: () -> Void

    var body: some View {
        let state = production.state(of: part.id)
        let next = Relay.next(production, script)
        PartCard(script: script, part: part, holder: holder(state), recorded: state.status == .done,
                 who: who(state), current: state.status == .recording, onOpen: open) {
            switch state.status {
            case .recording:
                Button("Record", action: open).buttonStyle(.play(.ink))
            case .open:
                HStack(spacing: Spacing.s2) {
                    if !part.id.isSpeaking {
                        Button("Leave silent", action: leaveSilent).buttonStyle(.play(.way))
                    }
                    Button("Take part", action: take).buttonStyle(.play(part.id == next ? .ink : .way))
                }
            case .done, .silent:
                Button("Open part", action: reopen)
                    .buttonStyle(.play(.way))
                    .disabled(Relay.current(production, script) != nil)
            }
        }
    }

    private func holder(_ state: PartState) -> PartHolder {
        switch state.status {
        case .open: .deviceVoice
        case .recording, .done: .person(state.performer)
        case .silent: .silent
        }
    }

    private func who(_ state: PartState) -> String {
        switch state.status {
        case .open: "Open"
        case .recording:
            "\(state.performer ?? "You") \u{00B7} \(part.lineCount - Relay.missingLines(part.id, in: production, script: script).count) of \(part.lineCount)"
        case .done: state.performer.map { "\($0) \u{00B7} recorded" } ?? "Recorded"
        case .silent: "Left silent"
        }
    }
}

extension View {
    /// A list row that carries its own layout: no insets, no separator, no row background.
    func plainRow() -> some View {
        listRowInsets(EdgeInsets()).listRowSeparator(.hidden).listRowBackground(Color.clear)
    }
}

enum RelayRefusalText {
    static func text(_ refusal: Relay.Refusal) -> String {
        switch refusal {
        case let .anotherPartIsRecording(part): "\(part.title) is still recording."
        case .notOpen: "That part is not open."
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
    var replacing: String?
    @Environment(PlaysLibrary.self) private var plays

    var body: some View {
        if let production = plays.store.production(productionID), let script = plays.castScript(for: production) {
            PartDetail(production: production, script: script, part: part, replacing: replacing, dismissWhenDone: true)
        } else {
            EmptyState("Production not found", systemImage: "questionmark.square.dashed")
        }
    }
}

/// The part's own panel: its recording when it is the part being recorded,
/// otherwise its lines to read along.
struct PartDetail: View {
    let production: Production
    let script: PlayScript
    let part: PartID?
    /// A line of a finished part being replaced on a published play (P12): the recorder opens on it.
    var replacing: String?
    /// Only iPhone's pushed screen goes back when the part is done; beside the
    /// cast sheet (iPad, the Mac window) the panel simply turns to the lines.
    var dismissWhenDone = false

    var body: some View {
        if let part, production.state(of: part).status == .recording || replacing != nil {
            RecordingScreen(productionID: production.id, part: part, startLine: replacing, dismissWhenDone: dismissWhenDone).id(part)
        } else if let part {
            List(script.lines(for: part)) { line in
                ScriptLineText(line: line)
                    .modifier(ReportTakeMenu(production: production, script: script, lineID: line.id))
            }
            .navigationTitle(part.title)
        } else {
            EmptyState("Choose a part", systemImage: "theatermasks")
        }
    }
}

// MARK: - Listen through, finish, keep

/// Listen through, any time (C5, C6; §2.6-2.7). A complete play plays its
/// rendered mix, and hearing it to the end finishes it. An incomplete one runs
/// the listen plan live: takes from their files, the other speaking lines read
/// by the device voice, labeled, never stored. Export is there whenever the
/// play is complete.
struct ListenThrough: View {
    let production: Production
    let script: PlayScript
    @Environment(PlaysLibrary.self) private var plays
    @Environment(AudioPlayer.self) private var player
    @State private var mix = MixPlayback()
    @State private var live = LiveListenThrough.system()
    @State private var mixing = false
    @State private var error: String?
    @State private var listenedFrom: String?

    var body: some View {
        let missing = Relay.missingSpeech(production, script).count
        let retake = Relay.needsRetake(production, script).count
        let complete = missing == 0 && retake == 0
        Group {
            if live.isRunning {
                liveTransport
            } else if mixing {
                ProgressView()
            } else if complete, mix.duration > 0 {
                transport
            } else {
                ActionRow {
                    Button {
                        if complete { Task { await prepare() } } else { Task { await listenLive() } }
                    } label: {
                        Label(production.isFinished ? "Play" : "Listen through", systemImage: "play.fill")
                    }
                    .pageAction(primary: true)
                    if complete { export.pageAction() }
                }
                if !complete { PersonalVoiceToggle(live: live) }
            }
            if missing > 0 {
                Text(missing == 1 ? "1 line still needs a voice." : "\(missing) lines still need a voice.")
                    .foregroundStyle(Color.brandTextMuted)
            } else if retake > 0 {
                Text(retake == 1 ? "1 line needs a re-take with headphones." : "\(retake) lines need a re-take with headphones.")
                    .foregroundStyle(Color.brandTextMuted)
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Color.semanticError)
            }
        }
        .onChange(of: mix.reachedEnd) { _, ended in
            guard ended, !mix.skipped, let from = listenedFrom else { return }
            plays.store.markListenedThrough(production.id, fingerprint: from)
        }
        .onChange(of: production.chosenFingerprint) {
            mix.stop()
            live.stop()
        }
        .onDisappear {
            mix.stop()
            live.stop()
        }
    }

    private var export: some View {
        ShareLink(item: MixExport(store: plays.store, productionID: production.id),
                  preview: SharePreview(production.title)) {
            ActionLabel(title: "Export", systemImage: "square.and.arrow.up")
        }
    }

    private var transport: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack(spacing: Spacing.s4) {
                Button {
                    player.pause()
                    mix.toggle()
                } label: {
                    Label(mix.isPlaying ? "Pause" : "Play", systemImage: mix.isPlaying ? "pause.fill" : "play.fill")
                        .foregroundStyle(Color.brandPrimary)
                }
                .tint(Color.brandPrimary)
                #if os(iOS)
                .sensoryFeedback(Haptic.selection.feedback, trigger: mix.isPlaying)
                #endif
                export
            }
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                if production.isFinished {
                    Slider(value: Binding(get: { mix.currentTime }, set: { mix.seek(to: $0) }), in: 0...max(mix.duration, 1))
                        .accessibilityLabel("Position")
                } else {
                    ProgressView(value: min(mix.currentTime, mix.duration), total: max(mix.duration, 1))
                }
            }
            .tint(Color.brandPrimary)
        }
    }

    /// The line being heard, its speaker, and "Device voice" when the device
    /// reads it, so a stand-in never passes as a person (§5 rule 3).
    @ViewBuilder private var liveTransport: some View {
        if let entry = live.current, let line = script.lines.first(where: { $0.id == entry.lineID }) {
            VStack(alignment: .leading, spacing: Spacing.s1) {
                if entry.isDeviceVoice {
                    Label("Device voice", systemImage: "waveform").font(TypeRamp.caption)
                        .foregroundStyle(Color.brandSecondary)
                }
                ScriptLineText(line: line)
            }
        }
        Button {
            live.stop()
        } label: {
            Label("Stop", systemImage: "stop.fill")
                .foregroundStyle(Color.brandPrimary)
        }
        .tint(Color.brandPrimary)
    }

    private func prepare() async {
        mixing = true
        defer { mixing = false }
        do {
            let url = try await plays.store.renderMix(production.id)
            listenedFrom = plays.store.production(production.id)?.chosenFingerprint
            try mix.load(url)
            error = nil
            player.pause()
            mix.toggle()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func listenLive() async {
        guard let latest = plays.store.production(production.id) else { return }
        mix.stop()
        player.pause()
        error = nil
        let store = plays.store
        await live.run(Relay.listenPlan(latest, script)) { store.takeURL(latest, $0) }
    }
}

/// "Use my Personal Voice" (§5 rule 6): offered where the system has Personal
/// Voice, for the live listen-through only. Turning it on asks once.
private struct PersonalVoiceToggle: View {
    let live: LiveListenThrough
    @State private var status = SystemListenSpeaker.personalVoiceStatus

    var body: some View {
        if status == .authorized || status == .notDetermined {
            Toggle("Use my Personal Voice", isOn: Binding(get: { live.usesPersonalVoice && status == .authorized }) { on in
                guard on else {
                    live.usesPersonalVoice = false
                    return
                }
                Task {
                    if status == .notDetermined {
                        status = await AVSpeechSynthesizer.requestPersonalVoiceAuthorization()
                    }
                    live.usesPersonalVoice = status == .authorized
                }
            })
        }
    }
}

/// The mix as the share sheet asks for it: rendered first when it is missing
/// or stale (§2.7).
nonisolated struct MixExport: Transferable {
    let store: ProductionStore
    let productionID: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .mpeg4Audio) { export in
            SentTransferredFile(try await export.store.exportMix(export.productionID))
        }
    }
}

// MARK: - A line as printed

/// A script line with its printed directions kept apart from the words said
/// (§3, Decision 059); nothing is rewritten.
struct ScriptLineText: View {
    let line: ScriptLine
    var large = false
    /// The text color on a board (the performer's own line box); nil is the page's.
    var ink: Color? = nil
    var showsRole = true

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            if showsRole, let role = line.role {
                Text(verbatim: role).font(TypeRamp.caption).foregroundStyle(ink ?? Color.brandTextMuted)
            }
            if line.kind == .speech {
                spoken
                .font(large ? TypeRamp.sectionHeader : TypeRamp.body)
                .foregroundStyle(ink ?? Color.brandText)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(verbatim: line.source ?? "")
                    .italic()
                    .font(large ? TypeRamp.sectionHeader : TypeRamp.body)
                    .foregroundStyle(ink ?? Color.brandTextMuted)
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
            Text(verbatim: "(\(words))").italic().foregroundStyle(ink ?? Color.brandTextMuted)
        }
    }
}
#endif
