#if os(iOS) || os(macOS)
import Accessibility
import SwiftUI

// Casting an episode by ear (iOS-DESIGN §4.22, macOS-DESIGN §4.11, PLAYS-DESIGN §13 item 10): the automatic transcript
// in lines, the episode in the app's own player, the line being said outlined, and the parts in reach. What a tap does
// is EarCore's; what is kept is OwnScripts'. It proposes no speaker. Not on the TV.

/// Record This on an episode with no castable script: it stands only when it is sure to open (the transcript's times
/// were read, or a casting was begun here). 88% of episodes have no transcript, and nothing is said of them.
struct EarDoor: View {
    let episodeID: String
    @Environment(AppStore.self) private var app

    var body: some View {
        // A Button, not a link: a List draws a link as a row of its own.
        Button { app.push(PlayRoute.cast(episodeID)) } label: { Label("Record This", systemImage: "mic") }
            .pageAction(primary: true)
            .accessibilityIdentifier("ear-door")
    }

    /// Asked by the page, not by the button: a List never runs the task of a row with nothing in it.
    static func opens(_ detail: EpisodeDetail, plays: PlaysLibrary, forwarding: IDForwarding) async -> Bool {
        guard EarCues.url(detail.episode.transcriptURL) != nil, !detail.recordings.isEmpty else { return false }
        if plays.own.row(ofEpisode: detail.episode.id, forwarding: forwarding) != nil { return true }
        guard let cues = try? await EarCueCache.shared.cues(detail.episode.transcriptURL) else { return false }
        return EarCore.refusal(OwnScript.fromCues(cues)) == nil
    }
}

struct EarScreen: View {
    let id: String
    @Environment(PlaysLibrary.self) private var plays
    @Environment(CatalogStore.self) private var catalog
    @Environment(AudioPlayer.self) private var player
    @Environment(AppStore.self) private var app
    @State private var phase: Phase = .loading

    private enum Phase {
        case loading, failed, missing
        case ready(EarModel)
    }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).accessibilityLabel("Loading").navigationTitle("Record This")
            case .missing:
                EmptyState("Not in the catalog.", systemImage: "questionmark.square.dashed").navigationTitle("Record This")
            case .failed:
                VStack(spacing: Spacing.s3) {
                    EmptyState(catalog.isOnline ? "This did not load." : "You are offline.", systemImage: catalog.isOnline ? "exclamationmark.triangle" : "wifi.slash")
                    Button("Try Again") { Task { await load() } }.buttonStyle(.bordered)
                }
                .navigationTitle("Record This")
            case let .ready(model):
                EarPage(model: model)
            }
        }
        .task(id: id) {
            if case .ready = phase { return }
            await load()
        }
        .onAppear { app.isCasting = true }
        .onDisappear {
            app.isCasting = false
            if case let .ready(model) = phase { model.leave() }
        }
    }

    private func load() async {
        phase = .loading
        await catalog.whenReady()
        guard let detail = await catalog.episodeDetail(catalog.forwarding.resolve(id)), let copy = detail.defaultRecording else {
            phase = .missing
            return
        }
        do {
            let row = plays.own.row(ofEpisode: detail.episode.id, forwarding: catalog.forwarding)
            let rec = try row.flatMap { try plays.own.get($0.id) }
            var cues: [OwnCue] = []
            var doc = OwnScript.newDoc([])
            if rec == nil {
                cues = try await EarCueCache.shared.cues(detail.episode.transcriptURL)
                let found = cues
                doc = await Task.detached { OwnScript.fromCues(found) }.value
                guard EarCore.refusal(doc) == nil else { phase = .failed; return }
            }
            let model = EarModel(detail: detail, copy: copy, title: ItemLead.episodeTitle(detail.episode), rec: rec, cues: cues, doc: doc,
                                 store: plays.own, audio: player)
            phase = .ready(model)
            if let ear = rec?.ear { await remade(model, ear, copy, detail) }
        } catch {
            phase = .failed
        }
    }

    /// A kept casting keeps its own lines. When archive.org has made the transcript or the copy again since, that is said.
    private func remade(_ model: EarModel, _ ear: OwnRecord.Ear, _ copy: Recording, _ detail: EpisodeDetail) async {
        if !ear.copy.isEmpty, ear.copy != copy.url.absoluteString {
            model.note = "The recording has changed. The times may be off."
        } else if let cues = try? await EarCueCache.shared.cues(detail.episode.transcriptURL), EarCore.signature(cues) != ear.sig {
            model.note = "The transcript has changed. Your lines are kept."
        }
    }
}

// MARK: - The page

private struct EarPage: View {
    @Bindable var model: EarModel
    @Environment(AppStore.self) private var app
    @Environment(AudioPlayer.self) private var player
    @Environment(\.undoManager) private var undoManager
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var still
    @State private var openLine: Int?
    @State private var naming = false
    @State private var finishing = false
    @FocusState private var pageFocused: Bool
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    private var wide: Bool {
        #if os(iOS)
        sizeClass == .regular
        #else
        true
        #endif
    }

    var body: some View {
        HStack(spacing: 0) {
            lines
                .safeAreaInset(edge: .bottom, spacing: 0) { if !wide { EarDock(model: model, name: name) } }
            if wide {
                Divider()
                EarRail(model: model, name: name).frame(width: 320)
            }
        }
        .background(Color.brandBackground)
        .modifier(OwnTitles(title: model.title, sub: model.refusal ?? OwnText.castLine(model.count.cast, model.count.lines)))
        .toolbar { toolbar }
        #if os(iOS)
        .toolbar(wide ? .automatic : .hidden, for: .tabBar)
        .background { if !model.sheetOpen { EarKeys_iOS(model: model) } }
        .sheet(item: Binding(get: { openLine.map(EarLineID.init) }, set: { openLine = $0?.k }), onDismiss: { model.closeSheet() }) { line in
            EarLinePanel(model: model, k: line.k) { openLine = nil }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sensoryFeedback(Haptic.selection.feedback, trigger: model.changes)
        .sensoryFeedback(trigger: model.refusal ?? model.problem?.words) { Haptic.forError(from: $0, to: $1)?.feedback }
        #else
        .focusable()
        .focusEffectDisabled()
        .focused($pageFocused)
        .onKeyPress(phases: .down) { press in key(press) }
        .focusedSceneValue(\.casting, model)
        #endif
        .sheet(isPresented: $naming, onDismiss: { model.closeSheet() }) {
            OwnSmallSheet(title: "New Part") {
                OwnNameForm(label: "Name", button: "Add") { raw in
                    if let why = model.add(raw) { return why }
                    naming = false
                    return nil
                }
            }
        }
        .onAppear {
            model.undoManager = undoManager
            model.announce = { AccessibilityNotification.Announcement($0).post() }
            model.appear()
            pageFocused = true
        }
        .onChange(of: undoManager) { _, now in model.undoManager = now }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refreshTakes() } else if model.rec != nil { Task { await model.write() } }
        }
        // The audio's own clock, read as it plays; in the background it plays on and what it plays was heard.
        .task {
            while !Task.isCancelled {
                model.sync()
                try? await Task.sleep(for: .milliseconds(player.isPlaying ? 50 : 200))
            }
        }
        #if DEBUG
        .task { await EarDoorSteps.run(model) }
        #endif
    }

    private func name() {
        model.openSheet()
        naming = true
    }

    private func open(_ k: Int) {
        model.openSheet()
        openLine = k
    }

    // MARK: The lines

    private var lines: some View {
        VStack(spacing: 0) {
            if let problem = model.problem { OwnProblemBar(words: problem.words) { model.tryAgain() } }
            if let note = model.note {
                Text(verbatim: note)
                    .font(TypeRamp.caption)
                    .foregroundStyle(Color.brandTextMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.s4)
                    .padding(.vertical, Spacing.s2)
                    .background(Color.brandSurface)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        Text(Transcript.label)
                            .font(TypeRamp.caption)
                            .foregroundStyle(Color.brandTextMuted)
                            .padding(.vertical, Spacing.s3)
                            .padding(.horizontal, Spacing.s3)
                        ForEach(model.rows) { row in
                            EarRowView(row: row, hue: hue(row), lit: model.lit == row.k) { open(row.k) }
                                .id(row.k)
                                #if os(macOS)
                                .popover(isPresented: Binding(get: { openLine == row.k }, set: { if !$0, openLine == row.k { openLine = nil; model.closeSheet() } }),
                                         arrowEdge: .trailing) {
                                    EarLinePanel(model: model, k: row.k) { openLine = nil; model.closeSheet(); pageFocused = true }
                                        .frame(width: 420, height: 440)
                                }
                                #endif
                        }
                    }
                    .padding(.horizontal, Spacing.s2)
                    .padding(.bottom, Spacing.s8)
                    .frame(maxWidth: 820, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("ear-lines")
                .onScrollPhaseChange { _, phase in if phase == .interacting { model.away() } }
                .onChange(of: model.bring, initial: true) { _, bring in
                    guard let bring else { return }
                    withAnimation(still ? nil : .easeInOut(duration: 0.25)) { proxy.scrollTo(bring.k, anchor: UnitPoint(x: 0.5, y: 0.42)) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if model.backToLine {
                Button("Back to the Line") { model.refollow() }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.brandPrimary)
                    .foregroundStyle(Color.brandOnPrimary)
                    .padding(Spacing.s3)
                    .accessibilityIdentifier("ear-back-line")
            }
        }
    }

    private func hue(_ row: EarCore.Row) -> String? {
        if case let .role(name)? = row.who { model.hue(name) } else { nil }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { model.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                .disabled(!model.session.canUndo)
                .help("Undo")
                .accessibilityIdentifier("ear-undo")
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") { Task { await finish() } }
                .disabled(finishing)
                .accessibilityIdentifier("ear-done")
        }
    }

    private func finish() async {
        finishing = true
        defer { finishing = false }
        guard let script = await model.finish() else { return }
        app.replaceTop(with: PlayRoute.script(script))
    }

    #if os(macOS)
    private func key(_ press: KeyPress) -> KeyPress.Result {
        guard !model.sheetOpen, !naming else { return .ignored }
        let what: EarCore.Press? = press.key == .leftArrow ? .left : press.characters.first.map { .character($0) }
        guard let what, let key = EarCore.key(what, command: press.modifiers.contains(.command), control: press.modifiers.contains(.control),
                                              option: press.modifiers.contains(.option), shift: press.modifiers.contains(.shift)) else { return .ignored }
        model.press(key)
        return .handled
    }
    #endif
}

extension EarModel {
    func press(_ key: EarCore.Key) {
        switch key {
        case let .part(n): give(number: n)
        case .toggle: toggle()
        case .back: back()
        case .undo: undo()
        }
    }
}

private struct EarLineID: Identifiable {
    let k: Int
    var id: Int { k }
}

#if os(iOS)
/// A hardware keyboard's 1 to 9, Space, Left and U: the system's own shortcuts, so a field being typed in takes its keys first.
private struct EarKeys_iOS: View {
    let model: EarModel

    var body: some View {
        ZStack {
            ForEach(0..<9, id: \.self) { n in
                key(KeyEquivalent(Character(String(n + 1))), .part(n))
            }
            key(.space, .toggle)
            key(.leftArrow, .back)
            key("u", .undo)
        }
        .accessibilityHidden(true)
    }

    private func key(_ key: KeyEquivalent, _ act: EarCore.Key) -> some View {
        Button("") { model.press(act) }
            .keyboardShortcut(key, modifiers: [])
            .opacity(0)
            .frame(width: 0, height: 0)
    }
}
#endif

#if os(macOS)
extension FocusedValues {
    @Entry var casting: EarModel?
}

/// The menu bar's casting commands (macOS-DESIGN §4.11): no item takes a bare key (§5.3); those are the page's own.
struct CastingCommands_macOS: Commands {
    @FocusedValue(\.casting) private var casting

    var body: some Commands {
        CommandMenu("Casting") {
            Button(casting?.isPlaying == true ? "Pause Episode" : "Play Episode") { casting?.toggle() }.disabled(casting == nil)
            Button("Back 5 Seconds") { casting?.back() }.disabled(casting == nil)
            Button("Back to the Line") { casting?.refollow() }.disabled(casting?.backToLine != true)
            Divider()
            Button("Leave Out") { casting?.leaveOut() }.disabled(casting == nil || casting?.lit == 0)
            Menu("Give to") {
                ForEach(casting?.parts ?? [], id: \.name) { part in
                    Button(part.name) { casting?.give(part.name) }
                }
            }
            .disabled(casting?.parts.isEmpty != false)
        }
    }
}
#endif

#if os(macOS)
/// File > New Script and Open Script (macOS-DESIGN §4.11): New Script takes Command-N, New Window Shift-Command-N.
struct ScriptCommands_macOS: Commands {
    let store: AppStore
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Script\u{2026}") { store.wantsAddScript = true }
                .keyboardShortcut("n", modifiers: .command)
            Button("Open Script\u{2026}") { store.wantsAddScript = true; store.wantsScriptFile = true }
                .keyboardShortcut("o", modifiers: .command)
            Button("New Window") { openWindow(id: "main") }
                .keyboardShortcut("n", modifiers: [.command, .shift])
        }
    }
}
#endif

/// Add a Script asked for from outside Record, and the DEBUG doors of these pages (LaunchDoors).
struct OwnDoors: ViewModifier {
    @Environment(AppStore.self) private var store
    @Environment(PlaysLibrary.self) private var plays

    func body(content: Content) -> some View {
        content
            .onChange(of: store.wantsAddScript, initial: true) { _, wants in
                guard wants else { return }
                store.wantsAddScript = false
                store.selectedTab = .record
                guard !store.isAddingScript else { return }
                store.paths[.record] = NavigationPath([PlayRoute.addScript])
            }
            .task(id: store.ownDoor) { await openOwn() }
            .task(id: store.castDoor) {
                guard let id = store.castDoor else { return }
                store.castDoor = nil
                store.push(PlayRoute.cast(id))
            }
    }

    private func openOwn() async {
        guard let door = store.ownDoor, LaunchDoors.scratchRoot != nil else { return }
        store.ownDoor = nil
        await plays.load()
        let from = LaunchDoors.current.ownFrom ?? plays.scripts.first?.id ?? ""
        guard let play = (try? await plays.script(id: from)) ?? nil else { return }
        let text = OwnBuild.asText(play)
        store.selectedTab = .record
        if door == "add" {
            try? plays.own.setDraft(OwnScripts.Draft(title: play.title, text: text))
            store.paths[.record] = NavigationPath([PlayRoute.addScript])
            return
        }
        guard var rec = try? await plays.own.create(title: play.title, text: text) else { return }
        if door == "script" {
            rec.doc = OwnScript.done(rec.doc)
            rec.done = true
            _ = try? await plays.own.keep(rec)
        }
        store.paths[.record] = NavigationPath([door == "script" ? PlayRoute.script(rec.id) : PlayRoute.parts(rec.id)])
    }
}

// MARK: - A line

private struct EarRowView: View, Equatable {
    let row: EarCore.Row
    let hue: String?
    let lit: Bool
    let open: () -> Void

    nonisolated static func == (a: EarRowView, b: EarRowView) -> Bool { a.row == b.row && a.hue == b.hue && a.lit == b.lit }

    private var label: String? {
        switch row.who {
        case let .role(name): name
        case .out: "Left out"
        case nil: nil
        }
    }

    var body: some View {
        let nobody = row.who == nil && row.kind == "open"
        Button(action: open) {
            VStack(alignment: .leading, spacing: 0) {
                if row.named, let label {
                    Text(verbatim: label)
                        .font(TypeRamp.bodyStrong)
                        .foregroundStyle(row.who == .out ? Color.brandTextMuted : Color.genre(hue) ?? Color.brandTextMuted)
                        .padding(.top, Spacing.s1)
                }
                Text(verbatim: row.text)
                    .font(row.kind == "direction" || row.kind == "sound" ? TypeRamp.body.italic() : TypeRamp.body)
                    .strikethrough(row.who == .out)
                    .foregroundStyle(nobody || row.who == .out ? Color.brandTextMuted : Color.brandText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Spacing.s3)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .background { if lit { RoundedRectangle(cornerRadius: Radius.control).fill(Color.brandSurface) } }
            .overlay { if lit { RoundedRectangle(cornerRadius: Radius.control).strokeBorder(Color.brandPrimary, lineWidth: 2) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label.map { "\($0). \(row.text)" } ?? row.text)
        .accessibilityAddTraits(lit ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - The parts, docked or a rail

private struct EarDock: View {
    let model: EarModel
    let name: () -> Void

    var body: some View {
        VStack(spacing: Spacing.s1) {
            if model.parts.count > 4 {
                ScrollViewReader { proxy in
                    ScrollView { chips }
                        .frame(height: 96)
                        .onChange(of: model.who) { _, who in
                            if case let .role(name)? = who { proxy.scrollTo(name) }
                        }
                }
                HStack(spacing: Spacing.s2) { verbs; Spacer(minLength: 0) }
            } else {
                FlowLayout(spacing: Spacing.s2) { partChips; verbs }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            EarTransport(model: model)
        }
        .padding(.horizontal, Spacing.s3)
        .padding(.vertical, Spacing.s2)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var chips: some View {
        FlowLayout(spacing: Spacing.s2) { partChips }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var partChips: some View {
        ForEach(model.parts, id: \.name) { part in
            OwnPartChip(name: part.name, hue: model.hue(part.name), selected: model.who == .role(part.name)) { model.give(part.name) }
                .accessibilityHint(model.hint)
                .id(part.name)
        }
    }

    @ViewBuilder private var verbs: some View { EarVerbs(model: model, name: name) }
}

private extension EarModel {
    /// What a part's button gives it: the lit line (read by VoiceOver as the button's hint).
    var hint: String { session.line(session.lit)?.text ?? "" }
}

private struct EarVerbs: View {
    let model: EarModel
    let name: () -> Void

    var body: some View {
        Button(action: name) { Label("Part", systemImage: "plus") }
            .buttonStyle(OwnChipStyle())
            .accessibilityLabel("New part")
            .accessibilityIdentifier("ear-new-part")
        Button("Leave Out") { model.leaveOut() }
            .buttonStyle(OwnChipStyle(selected: model.who == .out))
            .disabled(model.session.lit == 0)
            .accessibilityHint(model.hint)
            .accessibilityIdentifier("ear-leave-out")
    }
}

private struct EarRail: View {
    let model: EarModel
    let name: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(model.parts.enumerated()), id: \.element.name) { n, part in
                        row(n, part)
                        Divider()
                    }
                    FlowLayout(spacing: Spacing.s2) { EarVerbs(model: model, name: name) }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, Spacing.s3)
                }
                .padding(Spacing.s4)
            }
            Divider()
            EarTransport(model: model).padding(Spacing.s4)
        }
        .background(Color.brandBackground)
    }

    private func row(_ n: Int, _ part: OwnPart) -> some View {
        let on = model.who == .role(part.name)
        return HStack(spacing: Spacing.s2) {
            Button { model.give(part.name) } label: {
                HStack(spacing: Spacing.s3) {
                    Text(verbatim: n < 9 ? String(n + 1) : " ")
                        .font(TypeRamp.tabular)
                        .foregroundStyle(Color.brandTextMuted)
                        .frame(width: 20)
                    PartFace(hue: model.hue(part.name), holder: .person(part.name))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: part.name).font(TypeRamp.bodyStrong).foregroundStyle(Color.brandText).lineLimit(1).minimumScaleFactor(0.6)
                        Text(verbatim: OwnText.count(part.lines, "line", "lines")).font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, Spacing.s2)
                .padding(.horizontal, Spacing.s2)
                .background { if on { RoundedRectangle(cornerRadius: Radius.control).fill(Color.brandSurfaceAlt) } }
                .overlay { if on { RoundedRectangle(cornerRadius: Radius.control).strokeBorder(Color.brandPrimary, lineWidth: 2) } }
                .contentShape(Rectangle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(part.name)
                .accessibilityValue(OwnText.count(part.lines, "line", "lines"))
                .accessibilityHint(model.hint)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            .buttonStyle(.plain)
            Button { model.hear(part: part.name) } label: { Image(systemName: "play.fill").frame(width: 44, height: 44) }
                .buttonStyle(.plain)
                .disabled(part.lines == 0)
                .opacity(part.lines == 0 ? 0.3 : 1)
                .accessibilityLabel("Hear \(part.name)")
                .help("Hear \(part.name)")
        }
    }
}

private struct EarTransport: View {
    let model: EarModel
    @Environment(AudioPlayer.self) private var player

    var body: some View {
        HStack {
            Text(verbatim: EpisodeRow.clock(Double(model.seconds)))
                .font(TypeRamp.tabular)
                .foregroundStyle(Color.brandTextMuted)
                .frame(minWidth: 56, alignment: .leading)
                .accessibilityIdentifier("ear-clock")
            Spacer(minLength: 0)
            Button { model.back() } label: { Image(systemName: "gobackward.5").font(.title3).frame(width: 44, height: 44) }
                .buttonStyle(.plain)
                .disabled(player.isFollowing)
                .accessibilityLabel("Back 5 seconds")
                .accessibilityIdentifier("ear-back")
            Spacer(minLength: 0)
            Button { model.toggle() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
                    .foregroundStyle(Color.brandOnPrimary)
                    .frame(width: 52, height: 52)
                    .background(Color.brandPrimary, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
            .accessibilityIdentifier("ear-play")
            Spacer(minLength: 0)
            Menu {
                Picker("Speed", selection: Binding(get: { model.speed }, set: { model.setSpeed($0) })) {
                    ForEach(AudioPlayer.speeds, id: \.self) { Text(SpeedMenu.label($0)).tag($0) }
                }
            } label: {
                Text(verbatim: SpeedMenu.label(model.speed)).font(TypeRamp.bodyStrong.monospacedDigit()).frame(minWidth: 56, minHeight: 44)
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(player.isFollowing)
            .accessibilityLabel("Speed")
            .accessibilityValue(SpeedMenu.label(model.speed))
        }
    }
}

// MARK: - The line's panel

private struct EarLinePanel: View {
    let model: EarModel
    let k: Int
    let close: () -> Void
    @State private var cut = -1
    @State private var refusal: String?
    @State private var editing = false
    @State private var words = ""
    @FocusState private var typing: Bool

    var body: some View {
        OwnPanel(close: close) {
            if let line = model.session.line(k) { content(line) }
            if let refusal { OwnRefusalText(refusal) }
        }
        // Hear It runs while the sheet is open; the page's own clock keeps reading behind it.
        .task {
            while !Task.isCancelled {
                model.sync()
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    @ViewBuilder private func content(_ line: OwnLine) -> some View {
        if editing {
            TextEditor(text: $words)
                .font(TypeRamp.body)
                .frame(minHeight: 140)
                .overlay { RoundedRectangle(cornerRadius: Radius.control).strokeBorder(Color.brandBorder) }
                .focused($typing)
                .accessibilityLabel("Words")
            HStack(spacing: Spacing.s2) {
                Button("Save") { act { $0.apply(OwnOp(op: .words, line: k, text: words)) } }.pageAction(primary: true)
                Button("Cancel", action: close).pageAction()
            }
        } else if model.isLocked(line) {
            Text(verbatim: line.text).font(TypeRamp.body)
            OwnRefusalText(OwnText.say(.line_has_take))
            FlowLayout(spacing: Spacing.s2, rowSpacing: Spacing.s2) {
                if line.at != nil { Button("Hear It") { model.hear(line) }.pageAction() }
                Button("Edit Words") { edit(line) }.pageAction()
                if line.at != nil { Button("Play From Here") { playFrom(line) }.pageAction() }
            }
        } else {
            OwnCutter(text: line.text, at: $cut)
            chips(line)
            verbs(line)
        }
    }

    private func chips(_ line: OwnLine) -> some View {
        let who = model.session.who(k)
        return FlowLayout(spacing: Spacing.s2) {
            ForEach(model.parts, id: \.name) { part in
                OwnPartChip(name: part.name, hue: model.hue(part.name), selected: who == .role(part.name)) {
                    act { $0.assign(k, .role(part.name)) }
                }
            }
            Button("Direction") { act { $0.assign(k, .kind("direction")) } }.buttonStyle(OwnChipStyle(selected: line.kind == "direction"))
            Button("Sound") { act { $0.assign(k, .kind("sound")) } }.buttonStyle(OwnChipStyle(selected: line.kind == "sound"))
        }
    }

    private func verbs(_ line: OwnLine) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Spacing.s2)], alignment: .leading, spacing: Spacing.s2) {
            if line.at != nil { Button("Hear It") { model.hear(line) }.ownVerb().accessibilityIdentifier("ear-hear") }
            Button("Edit Words") { edit(line) }.ownVerb()
            if OwnCutter.words(line.text).count > 1 {
                Button("Split Here") { act { $0.apply(OwnOp(op: .split, line: k, at: cut)) } }.disabled(cut < 0).ownVerb()
            }
            if model.rows.first?.k != k { Button("Join to Line Above") { act { $0.apply(OwnOp(op: .join, line: k)) } }.ownVerb() }
            Button("Leave Out") { act { $0.leaveOutLine(k) } }.ownVerb()
            if line.at != nil { Button("Play From Here") { playFrom(line) }.ownVerb() }
        }
    }

    private func edit(_ line: OwnLine) {
        words = line.text
        refusal = nil
        editing = true
        typing = true
    }

    private func playFrom(_ line: OwnLine) {
        model.play(from: line)
        close()
    }

    private func act(_ does: (inout EarSession) -> OwnRefusal?) {
        if let why = model.change(does) { refusal = why } else { close() }
    }
}

#if DEBUG
/// APP_CAST_STEPS: a device nobody can tap, driven for a frame. `parts=A,B` names them, `play` presses Play, `give=A@3`
/// gives the lit line to A three seconds after Play, `pause@8` pauses, `line=2` opens nothing but seeks there.
enum EarDoorSteps {
    static func run(_ model: EarModel) async {
        guard let raw = LaunchDoors.current.castSteps else { return }
        for step in raw.split(separator: ";").map(String.init) {
            let bits = step.split(separator: "@", maxSplits: 1).map(String.init)
            if bits.count == 2, let wait = Double(bits[1]) { try? await Task.sleep(for: .seconds(wait)) }
            let verb = bits[0].split(separator: "=", maxSplits: 1).map(String.init)
            switch verb[0] {
            case "parts": for name in (verb.last ?? "").split(separator: ",") { _ = model.add(String(name)) }
            case "play": if !model.isPlaying { model.toggle() }
            case "pause": if model.isPlaying { model.toggle() }
            case "give": model.give(verb.last ?? "")
            case "out": model.leaveOut()
            case "undo": model.undo()
            case "back": model.back()
            case "from":
                if let n = Int(verb.last ?? ""), model.session.doc.lines.indices.contains(n) { model.play(from: model.session.doc.lines[n]) }
            default: break
            }
            print("CAST \(step) lit \(model.session.lit) count \(model.count.cast)/\(model.count.lines) at \(model.seconds) playing \(model.isPlaying)")
        }
    }
}
#endif
#endif
