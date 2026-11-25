#if os(iOS) || os(macOS)
import SwiftUI

// The parts page (iOS-DESIGN §4.21, macOS-DESIGN §4.11, PLAYS-DESIGN §13 item 3): the script drawn as the reader draws
// it, a line with no part in a dashed box with its nearest speakers, and one panel for the line tapped: a sheet on a
// phone, the trailing column on an iPad and the open Duo, a popover on the Mac. The List draws only the rows near the
// screen. Every change is OwnPartsModel's.

struct OwnPartsScreen: View {
    let id: String
    @Environment(PlaysLibrary.self) private var plays
    @State private var model: OwnPartsModel?
    @State private var missing = false
    @State private var failed = false

    var body: some View {
        Group {
            if let model {
                OwnPartsPage(model: model)
            } else if missing {
                EmptyState("This script is not on this device.", systemImage: "questionmark.square.dashed")
                    .navigationTitle("Parts")
            } else if failed {
                VStack(spacing: Spacing.s3) {
                    EmptyState("This did not load.", systemImage: "exclamationmark.triangle")
                    Button("Try Again") { load() }.buttonStyle(.bordered)
                }
                .navigationTitle("Parts")
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).accessibilityLabel("Loading")
            }
        }
        .task(id: id) { if model == nil { load() } }
        .onDisappear { model?.leave() }
    }

    private func load() {
        failed = false
        do {
            guard let rec = try plays.own.get(id) else { missing = true; return }
            let made = OwnPartsModel(rec, store: plays.own)
            #if DEBUG
            if let line = LaunchDoors.current.ownLine { made.current = made.lines.indices.contains(line) ? made.lines[line].k : made.current }
            #endif
            model = made
        } catch {
            failed = true
        }
    }
}

private enum OwnSmall: Identifiable, Hashable {
    case title, newPart, part(String)
    var id: Self { self }
}

private struct OwnPartsPage: View {
    @Bindable var model: OwnPartsModel
    @Environment(AppStore.self) private var app
    @Environment(\.undoManager) private var undoManager
    @Environment(\.scenePhase) private var scenePhase
    @State private var openLine: Int?
    @State private var small: OwnSmall?
    @State private var moreParts = false
    @State private var target: Int?
    @State private var showsParts = true
    @State private var finishing = false
    @AccessibilityFocusState private var focus: Int?
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
        page
            .modifier(OwnTitles(title: model.rec.title, sub: OwnText.partsAndLines(model.partCount, model.lines.count)))
            .toolbar { toolbar }
            .sheet(item: $small) { which in smallSheet(which) }
            .onAppear {
                model.undoManager = undoManager
                #if DEBUG
                if let line = LaunchDoors.current.ownLine, model.lines.indices.contains(line) {
                    target = model.lines[line].k
                    if LaunchDoors.current.ownSheet { openLine = model.lines[line].k }
                }
                #endif
            }
            .onChange(of: undoManager) { _, now in model.undoManager = now }
            .onChange(of: scenePhase) { _, phase in if phase != .active { model.flush() } }
            .onChange(of: openLine) { was, now in
                if let now { model.current = now } else if let was { focus = model.line(was) == nil ? model.current : was }
            }
            #if os(iOS)
            .sensoryFeedback(Haptic.selection.feedback, trigger: model.changes)
            .sensoryFeedback(trigger: model.refusal ?? model.problem) { Haptic.forError(from: $0, to: $1)?.feedback }
            #endif
    }

    @ViewBuilder private var page: some View {
        #if os(macOS)
        script
            .inspector(isPresented: $showsParts) {
                column.inspectorColumnWidth(min: 260, ideal: 320, max: 420)
            }
        #else
        HStack(spacing: 0) {
            script
            if wide {
                Divider()
                column.frame(width: 320)
            }
        }
        .sheet(isPresented: Binding(get: { !wide && openLine != nil }, set: { if !$0, !wide { openLine = nil } })) {
            if let k = openLine {
                OwnLinePanel(model: model, k: k) { openLine = nil }
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
        #endif
    }

    // MARK: The script

    private var script: some View {
        VStack(spacing: 0) {
            if let problem = model.problem { OwnProblemBar(words: problem) { Task { await model.write() } } }
            if model.open > 0 { strip }
            if let refusal = model.refusal {
                OwnRefusalText(refusal).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, Spacing.s4).padding(.vertical, Spacing.s2)
            }
            ScrollViewReader { proxy in
                List {
                    if model.isEar {
                        Text(Transcript.label).font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted).ownRow()
                    }
                    if !wide { chips.ownRow() }
                    if model.lines.isEmpty {
                        EmptyState("No lines.", systemImage: "text.alignleft").ownRow()
                    }
                    ForEach(model.lines, id: \.k) { line in
                        row(line).id(line.k).ownRow()
                    }
                }
                .listStyle(.plain)
                .environment(\.defaultMinListRowHeight, 0)
                .scrollContentBackground(.hidden)
                .background(Color.brandBackground)
                .accessibilityIdentifier("own-lines")
                .onChange(of: target) { _, k in
                    guard let k else { return }
                    target = nil
                    proxy.scrollTo(k, anchor: .center)
                    focus = k
                }
                .task {
                    // A door's line, once the List has its rows.
                    #if DEBUG
                    if let line = LaunchDoors.current.ownLine, model.lines.indices.contains(line) {
                        try? await Task.sleep(for: .milliseconds(600))
                        proxy.scrollTo(model.lines[line].k, anchor: .center)
                    }
                    #endif
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.brandBackground)
    }

    private var strip: some View {
        HStack {
            Text(verbatim: OwnText.noPart(model.open))
                .font(TypeRamp.bodyStrong)
                .foregroundStyle(Color.semanticWarning)
                .accessibilityIdentifier("own-open")
            Spacer(minLength: Spacing.s2)
            Button("Next") { target = model.nextOpen() }
                .font(TypeRamp.bodyStrong)
                .buttonStyle(.borderless)
                .frame(minHeight: 44)
                .accessibilityIdentifier("own-next-open")
                #if os(macOS)
                .keyboardShortcut("'", modifiers: .command)
                .help("Next line with no part")
                #endif
        }
        .padding(.horizontal, Spacing.s4)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder private func row(_ line: OwnLine) -> some View {
        let shown = OwnLineView(line: line, hue: model.hue(line.role))
        Group {
            if line.kind == "open" {
                VStack(alignment: .leading, spacing: 0) {
                    Button { openLine = line.k } label: {
                        VStack(alignment: .leading, spacing: Spacing.s1) {
                            Text("No part").font(TypeRamp.caption.weight(.semibold)).foregroundStyle(Color.semanticWarning)
                            shown
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    FlowLayout(spacing: Spacing.s2) {
                        ForEach(model.near[line.k] ?? [], id: \.self) { name in
                            OwnPartChip(name: name, hue: model.hue(name), verb: "Give to") { model.give(line.k, .role(name)) }
                        }
                        Button("Direction") { model.give(line.k, .kind("direction")) }.buttonStyle(OwnChipStyle())
                        Button("More") { openLine = line.k }.buttonStyle(OwnChipStyle())
                    }
                }
                .padding(Spacing.s3)
                .overlay { RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Color.semanticWarning, style: StrokeStyle(lineWidth: 1, dash: [4, 3])) }
                .padding(.vertical, Spacing.s1)
            } else {
                Button { openLine = line.k } label: { shown.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()) }
                    .buttonStyle(.plain)
            }
        }
        .accessibilityFocused($focus, equals: line.k)
        .background {
            if wide, openLine == line.k { RoundedRectangle(cornerRadius: Radius.control).fill(Color.brandSurfaceAlt).padding(-Spacing.s2) }
        }
        #if os(macOS)
        .popover(isPresented: Binding(get: { openLine == line.k }, set: { if !$0, openLine == line.k { openLine = nil } }), arrowEdge: .trailing) {
            OwnLinePanel(model: model, k: line.k) { openLine = nil }.frame(width: 420, height: 460)
        }
        #endif
    }

    // MARK: The parts

    private var chips: some View {
        let shown = moreParts ? model.parts : Array(model.parts.prefix(4))
        return FlowLayout(spacing: Spacing.s2) {
            ForEach(shown, id: \.name) { part in
                OwnPartChip(name: part.name, hue: model.hue(part.name), count: part.lines) { small = .part(part.name) }
            }
            if model.parts.count > shown.count {
                Button("\(model.parts.count - shown.count) more") { moreParts = true }.buttonStyle(OwnChipStyle())
            }
            Button { small = .newPart } label: { Label("Part", systemImage: "plus") }.buttonStyle(OwnChipStyle()).accessibilityLabel("New part")
        }
    }

    /// The trailing column: the parts, or on an iPad and the open Duo the tapped line's controls in their place.
    @ViewBuilder private var column: some View {
        #if os(iOS)
        if let k = openLine {
            OwnLinePanel(model: model, k: k) { openLine = nil }
        } else {
            partsList
        }
        #else
        partsList
        #endif
    }

    private var partsList: some View {
        List {
            Section("Parts") {
                ForEach(model.parts, id: \.name) { part in
                    Button { small = .part(part.name) } label: {
                        HStack(spacing: Spacing.s3) {
                            Circle().fill(Color.genre(model.hue(part.name)) ?? Color.brandTextMuted).frame(width: 12, height: 12)
                            Text(verbatim: part.name).font(TypeRamp.bodyStrong).foregroundStyle(Color.brandText).lineLimit(1)
                            Spacer(minLength: 0)
                            Text(verbatim: OwnText.number(part.lines)).font(TypeRamp.tabular).foregroundStyle(Color.brandTextMuted)
                        }
                        .frame(minHeight: 32)
                        .contentShape(Rectangle())
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(part.name)
                        .accessibilityValue(OwnText.count(part.lines, "line", "lines"))
                    }
                    .buttonStyle(.plain)
                }
                Button { small = .newPart } label: { Label("Part", systemImage: "plus") }.accessibilityLabel("New part")
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.brandBackground)
        #endif
    }

    // MARK: The bar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .secondaryAction) {
            Button { small = .title } label: { Label("Rename", systemImage: "pencil") }
        }
        ToolbarItem(placement: .primaryAction) {
            Button { model.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                .disabled(!model.canUndo)
                .accessibilityIdentifier("own-undo")
                .help("Undo")
        }
        #if os(macOS)
        ToolbarItem {
            Button { showsParts.toggle() } label: { Label("Parts", systemImage: "sidebar.trailing") }.help("Parts")
        }
        #endif
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") { Task { await finish() } }
                .disabled(finishing)
                .accessibilityIdentifier("own-done")
        }
    }

    private func finish() async {
        finishing = true
        defer { finishing = false }
        let wasDone = model.rec.done
        guard await model.finish() else { return }
        if wasDone { app.goBack() } else { app.replaceTop(with: PlayRoute.script(model.rec.id)) }
    }

    @ViewBuilder private func smallSheet(_ which: OwnSmall) -> some View {
        switch which {
        case .title:
            OwnSmallSheet(title: "Title") {
                OwnNameForm(label: "Title", value: model.rec.title, button: "Save") { raw in
                    if let why = model.rename(title: raw) { return OwnText.say(why) }
                    small = nil
                    return nil
                }
            }
        case .newPart:
            OwnSmallSheet(title: "New Part") {
                OwnNameForm(label: "Name", button: "Add") { raw in
                    if let why = model.addPart(raw).refusal { return OwnText.name(why) }
                    moreParts = true
                    small = nil
                    return nil
                }
            }
        case let .part(name):
            OwnSmallSheet(title: name) { OwnPartPanel(model: model, name: name) { small = nil } }
        }
    }
}

private extension View {
    func ownRow() -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: Spacing.s4, bottom: 0, trailing: Spacing.s4))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

// MARK: - A line as the reader draws it

/// One line set by the reader's own layout (`PlayPage`), the speaker over the speech. Brackets are the person's own,
/// so "(she laughs)" is a direction, never words said.
struct OwnLineView: View {
    let line: OwnLine
    let hue: String?

    var body: some View {
        let shown = OwnLineView.scriptLine(line)
        let layout = PlayPage.layoutOf(shown, roles: [], emphasis: false)
        VStack(alignment: .leading, spacing: 2) {
            if line.kind == "speech" {
                Text(verbatim: line.role ?? "")
                    .font(TypeRamp.bodyStrong)
                    .foregroundStyle(Color.genre(hue) ?? Color.brandTextMuted)
                ForEach(Array(layout.speeches.enumerated()), id: \.offset) { _, speech in
                    ForEach(Array(speech.rows.enumerated()), id: \.offset) { _, row in
                        draw(row, verse: layout.verse)
                    }
                }
            } else if line.kind == "open" {
                Text(verbatim: PlayPage.isVerse([line.text]) ? line.text : line.text.replacingOccurrences(of: "\n", with: " "))
                    .font(Self.words)
                    .foregroundStyle(Color.brandText)
            } else {
                ForEach(Array(layout.rows.enumerated()), id: \.offset) { _, row in
                    draw(row, verse: false).padding(.leading, row.cue ? 0 : Spacing.s6)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Spacing.s2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.role.map { "\($0). \(line.text)" } ?? line.text)
    }

    static let words = Font.system(.body, design: .serif)

    @ViewBuilder private func draw(_ row: PageRow, verse: Bool) -> some View {
        if row.cue {
            Label {
                Text(verbatim: row.runs.map(\.text).joined(separator: " ").uppercased())
            } icon: {
                Image(systemName: "speaker.wave.2")
            }
            .font(TypeRamp.caption.weight(.semibold))
            .foregroundStyle(Color.brandText)
            .padding(.horizontal, Spacing.s2)
            .padding(.vertical, 2)
            .background(Color.brandSurfaceAlt, in: RoundedRectangle(cornerRadius: 4))
        } else {
            Text(Self.styled(row, speech: line.kind == "speech"))
                .padding(.leading, verse && row.indent ? Spacing.s8 : 0)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private static func styled(_ row: PageRow, speech: Bool) -> AttributedString {
        var out = AttributedString()
        for (n, r) in row.runs.enumerated() {
            let before = n > 0 ? row.runs[n - 1] : nil
            if let before, before.piece != r.piece, ScriptReading.spaceBetween(before.text, r.text) { out.append(AttributedString(" ")) }
            var words = PlayPage.drawn(r.text)
            if speech, !r.said {
                if before?.piece != r.piece { words = "(" + words }
                if n + 1 == row.runs.count || row.runs[n + 1].piece != r.piece { words += ")" }
            }
            var run = AttributedString(words)
            run.font = r.said ? Self.words : Self.words.italic()
            run.foregroundColor = r.said ? Color.brandText : Color.brandTextMuted
            out.append(run)
        }
        return out
    }

    static func scriptLine(_ line: OwnLine) -> ScriptLine {
        let id = line.id ?? "k\(line.k)"
        switch line.kind {
        case "speech":
            let parts: [LinePart] = OwnScript.pieces(line.text).map { p in
                switch p {
                case let .say(t): .say(t)
                case let .direction(t): .direction(t)
                }
            }
            return ScriptLine(id: id, kind: .speech, role: line.role, parts: parts)
        case "sound": return ScriptLine(id: id, kind: .sound, source: line.text)
        case "music": return ScriptLine(id: id, kind: .music, source: line.text)
        default: return ScriptLine(id: id, kind: .direction, source: line.text)
        }
    }
}

// MARK: - The cut

/// A line's words with a place to cut, set by a tap between two of them. One adjustable control to VoiceOver; Left and
/// Right move it a word.
struct OwnCutter: View {
    let text: String
    /// The cut in UTF-16 units, or -1.
    @Binding var at: Int
    @State private var gap = 0
    private let words: [Word]

    struct Word: Identifiable {
        let id: Int
        let text: String
        let at: Int
        let row: Int
    }

    init(text: String, at: Binding<Int>) {
        self.text = text
        _at = at
        words = Self.words(text)
    }

    static func words(_ text: String) -> [Word] {
        var out: [Word] = []
        var word: [UInt16] = []
        var start = 0, row = 0
        func end() {
            guard !word.isEmpty else { return }
            out.append(Word(id: out.count, text: String(decoding: word, as: UTF16.self), at: start, row: row))
            word = []
        }
        for (i, u) in text.utf16.enumerated() {
            if u == 32 || u == 9 || u == 10 {
                end()
                if u == 10 { row += 1 }
            } else {
                if word.isEmpty { start = i }
                word.append(u)
            }
        }
        end()
        return out
    }

    var body: some View {
        let verse = PlayPage.isVerse([text])
        VStack(alignment: .leading, spacing: 0) {
            if verse {
                ForEach(Array(Set(words.map(\.row))).sorted(), id: \.self) { row in flow(words.filter { $0.row == row }) }
            } else {
                flow(words)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cut. \(text)")
        .accessibilityValue(spoken)
        .accessibilityAdjustableAction { direction in place(gap + (direction == .increment ? 1 : -1)) }
        .accessibilityIdentifier("own-cut")
        .focusable(words.count > 1)
        .onKeyPress(.leftArrow) { place(gap - 1); return .handled }
        .onKeyPress(.rightArrow) { place(gap + 1); return .handled }
    }

    private func flow(_ words: [Word]) -> some View {
        FlowLayout(spacing: 0) {
            ForEach(words) { word in
                Text(verbatim: word.text + " ")
                    .font(OwnLineView.words)
                    .foregroundStyle(Color.brandText)
                    .padding(.vertical, 3)
                    .overlay(alignment: .leading) { if cutsBefore(word) { caret.offset(x: -2) } }
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .local) { point in
                        place(point.x < CGFloat(word.text.count) * 4.5 ? word.id : word.id + 1)
                    }
            }
        }
    }

    private var caret: some View { Rectangle().fill(Color.brandSecondary).frame(width: 2) }

    private func cutsBefore(_ word: Word) -> Bool {
        guard at > 0 else { return false }
        // A cut pushed out of a direction's brackets stands before the first word at or after it.
        return word.at >= at && (word.id == 0 || words[word.id - 1].at < at)
    }

    private func place(_ to: Int) {
        guard words.count > 1 else { return }
        gap = min(max(0, to), words.count - 1)
        at = gap > 0 ? OwnScript.cutAt(text, words[gap].at) : -1
    }

    private var spoken: String {
        guard at > 0, words.indices.contains(gap) else { return "None" }
        let before = words[max(0, gap - 3)..<gap].map(\.text).joined(separator: " ")
        let after = words[gap..<min(words.count, gap + 3)].map(\.text).joined(separator: " ")
        return "\(before) | \(after)"
    }
}

// MARK: - The line's panel

/// A line's controls under their own Close. Not a navigation stack: in the trailing column and the Mac's popover a
/// second bar would put its Close in the window's.
struct OwnPanel<Content: View>: View {
    let close: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                HStack {
                    Text("Line").font(TypeRamp.sectionHeader).foregroundStyle(Color.brandText).accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    Button("Close", action: close).pageAction().keyboardShortcut(.cancelAction)
                }
                content()
            }
            .padding(Spacing.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.brandBackground)
    }
}

struct OwnLinePanel: View {
    let model: OwnPartsModel
    let k: Int
    let close: () -> Void
    @State private var cut = -1
    @State private var refusal: String?
    @State private var editing = false
    @State private var words = ""
    @State private var allParts = false
    @State private var more = false
    @FocusState private var typing: Bool

    var body: some View {
        OwnPanel(close: close) {
            if let line = model.line(k) { content(line) }
            if let refusal { OwnRefusalText(refusal) }
        }
        .id(k)
    }

    @ViewBuilder private func content(_ line: OwnLine) -> some View {
        if editing {
            TextEditor(text: $words)
                .font(OwnLineView.words)
                .frame(minHeight: 140)
                .overlay { RoundedRectangle(cornerRadius: Radius.control).strokeBorder(Color.brandBorder) }
                .focused($typing)
                .accessibilityLabel("Words")
                .accessibilityIdentifier("own-words")
            HStack(spacing: Spacing.s2) {
                Button("Save") { act(OwnOp(op: .words, line: k, text: words)) }.pageAction(primary: true)
                Button("Cancel", action: close).pageAction()
            }
        } else if model.isLocked(line) {
            Text(verbatim: line.text).font(OwnLineView.words)
            OwnRefusalText(OwnText.say(.line_has_take))
            Button("Edit Words") { edit(line) }.pageAction()
        } else {
            OwnCutter(text: line.text, at: $cut)
            partChips(line)
            if allParts {
                OwnNameForm(label: "New part", button: "Give") { raw in
                    let got = model.addPart(raw)
                    if let why = got.refusal { return OwnText.name(why) }
                    act(OwnOp(op: .assign, line: k, to: .role(got.name)))
                    return nil
                }
            }
            verbs(line)
        }
    }

    @ViewBuilder private func partChips(_ line: OwnLine) -> some View {
        let near = nearest(line)
        let rest = model.parts.map(\.name).filter { !near.contains($0) }
        let showAll = allParts || model.parts.count <= 6
        FlowLayout(spacing: Spacing.s2) {
            ForEach(near + (showAll ? rest : []), id: \.self) { name in
                OwnPartChip(name: name, hue: model.hue(name), selected: line.kind == "speech" && line.role == name) {
                    act(OwnOp(op: .assign, line: k, to: .role(name)))
                }
            }
            if !allParts {
                Button(model.parts.count <= 6 ? "New Part" : "All Parts") { allParts = true }.buttonStyle(OwnChipStyle())
            }
            kind("Direction", "direction", line)
            kind("Sound", "sound", line)
            if line.kind == "music" { kind("Music", "music", line) }
        }
    }

    private func nearest(_ line: OwnLine) -> [String] {
        let i = model.index(k) ?? 0
        var out: [String] = []
        for name in [line.role].compactMap({ $0 }) + (model.near[k] ?? OwnScript.nearestParts(model.lines, i)) where !out.contains(name) { out.append(name) }
        return out
    }

    private func kind(_ title: String, _ kind: String, _ line: OwnLine) -> some View {
        Button(title) { act(OwnOp(op: .assign, line: k, to: .kind(kind))) }
            .buttonStyle(OwnChipStyle(selected: line.kind == kind))
            .accessibilityAddTraits(line.kind == kind ? .isSelected : [])
    }

    @ViewBuilder private func verbs(_ line: OwnLine) -> some View {
        let i = model.index(k) ?? 0
        let last = i == model.lines.count - 1
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Spacing.s2)], alignment: .leading, spacing: Spacing.s2) {
            if OwnCutter.words(line.text).count > 1 {
                Button("Split Here") { act(OwnOp(op: .split, line: k, at: cut)) }.disabled(cut < 0).ownVerb()
                    .accessibilityIdentifier("own-split")
            }
            if i > 0 { Button("Join to Line Above") { act(OwnOp(op: .join, line: k)) }.ownVerb() }
            Button("Edit Words") { edit(line) }.ownVerb()
            Button("Leave Out") { act(OwnOp(op: .leaveOut, line: k)) }.ownVerb()
            if more {
                if i > 0 { Button("Leave Out Everything Above") { act(OwnOp(op: .leaveOutAbove, line: k)) }.ownVerb() }
                if !last { Button("Leave Out Everything Below") { act(OwnOp(op: .leaveOutBelow, line: k)) }.ownVerb() }
            } else if i > 0 || !last {
                Button("More") { more = true }.ownVerb()
            }
        }
    }

    private func edit(_ line: OwnLine) {
        words = line.text
        refusal = nil
        editing = true
        typing = true
    }

    /// Does it and closes; a refusal stays in the panel.
    private func act(_ op: OwnOp) {
        let i = model.index(k) ?? 0
        if let why = model.change(op) {
            refusal = OwnText.say(why)
            return
        }
        if model.line(k) == nil { model.current = model.lines.indices.contains(i) ? model.lines[i].k : model.lines.last?.k ?? 0 }
        close()
    }
}

extension View {
    /// A verb of the line's panel: the page's bordered button, as wide as its column.
    func ownVerb() -> some View { buttonStyle(OwnVerbStyle()) }
}

private struct OwnVerbStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TypeRamp.bodyStrong)
            .foregroundStyle(Color.brandText)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Spacing.s2)
            .frame(maxWidth: .infinity, minHeight: 44)
            .overlay { RoundedRectangle(cornerRadius: Radius.control).strokeBorder(Color.brandBorder) }
            .contentShape(Rectangle())
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
    }
}

// MARK: - A part's panel

private struct OwnPartPanel: View {
    let model: OwnPartsModel
    let name: String
    let close: () -> Void
    @State private var refusal: String?

    var body: some View {
        let mine = model.parts.first { $0.name == name }
        if model.hasTake(part: name) {
            OwnRefusalText(OwnText.say(.part_has_take))
        } else if (mine?.lines ?? 0) == 0 {
            Button("Leave Out") {
                model.dropPart(name)
                close()
            }
            .pageAction()
        } else {
            OwnNameForm(label: "Name", value: name, button: "Rename") { raw in
                let to = OwnScript.partName(OwnScript.normalize(raw))
                if let why = OwnScript.partNameRefusal(to) { return OwnText.name(why) }
                act(OwnOp(op: .rename, part: name, rename: raw))
                return nil
            }
            let others = model.parts.filter { $0.name != name }
            if !others.isEmpty {
                Text("Join to").font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
                FlowLayout(spacing: Spacing.s2) {
                    ForEach(others, id: \.name) { part in
                        OwnPartChip(name: part.name, hue: model.hue(part.name), count: part.lines, verb: "Join to") {
                            act(OwnOp(op: .rename, part: name, rename: part.name))
                        }
                    }
                }
            }
            Button("Not a Part") { act(OwnOp(op: .notPart, part: name)) }.pageAction()
            if let refusal { OwnRefusalText(refusal) }
        }
    }

    private func act(_ op: OwnOp) {
        if let why = model.change(op) { refusal = OwnText.say(why) } else { close() }
    }
}
#endif
