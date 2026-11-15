#if os(iOS) || os(macOS)
import SwiftUI
#if os(iOS)
import UIKit
#endif

// Marks in the script reader (PLAYS-DESIGN §2.10, iOS-DESIGN §4.15 "Marks", macOS-DESIGN §4.7; Decision 076 S5): the
// verbs the reader gives a person with words selected, the popover a tap on a mark opens, the Beat and Note sheet,
// the notebook, and Delete's Undo. The rules are MarksCore.swift's; what is drawn is MarkLayout.swift's. Marks are
// the person's own, kept on this device and never synced.

extension MarkKind {
    var title: String {
        switch self {
        case .highlight: "Highlight"
        case .underline: "Underline"
        case .breath: "Breath"
        case .pause: "Pause"
        case .beat: "Beat"
        case .note: "Note"
        }
    }
}

/// A tapped mark: where its popover points, in the spread's own coordinates.
struct MarkTarget: Identifiable, Equatable {
    let id: String
    let spread: Int
    let rect: CGRect
}

/// A Beat or a Note being written: the marked words (a point mark's words around it) above a field.
struct MarkCompose: Identifiable {
    let id = UUID()
    var kind: MarkKind
    /// The mark being edited, or nil for a new one.
    var editing: String?
    var before = ""
    var words = ""
    var after = ""
    var text = ""
    var pieces: [MarkPiece] = []
}

// MARK: - The verbs

extension ReaderModel {
    /// The marks the page draws: shown, and not on a line Hide My Lines is covering.
    var visibleMarks: [Mark] {
        guard showMarks else { return [] }
        return marks.filter { m in structure.indexByID[m.line].map { !isHidden($0) } ?? false }
    }

    /// Every mark in script order, for the notebook.
    var markOrder: [Mark] { MarksCore.order(script, marks) }

    static func markKey(_ key: KeyEquivalent) -> MarkKind? {
        switch key {
        case KeyEquivalent("h"): .highlight
        case KeyEquivalent("u"): .underline
        case KeyEquivalent("/"): .breath
        case KeyEquivalent("p"): .pause
        case KeyEquivalent("b"): .beat
        case KeyEquivalent("n"): .note
        default: nil
        }
    }

    func persistMarks() {
        do {
            try markStore.save(scriptID: script.id, title: script.title, marks + lostMarks)
            markNotice = nil
        } catch {
            markNotice = "Marks could not be saved."
        }
    }

    private func relayoutIfPoints(_ changed: [Mark]) {
        if changed.contains(where: { !$0.isSpan }) { relayout(keep: position) }
    }

    // MARK: Selecting

    private func textPoint(_ p: CGPoint) -> (page: Int, up: CGPoint)? {
        guard let layout, let at = pagePoint(p) else { return nil }
        return (at.page, CGPoint(x: at.local.x - ReaderLayout.inset, y: layout.pageSize.height - at.local.y))
    }

    /// The top-left of a page's view in the spread's coordinates, when the page is in the spread in view.
    private func pageOrigin(_ page: Int) -> CGPoint? {
        guard let layout else { return nil }
        let k = page - (spread ?? 0) * per
        guard k >= 0, k < per else { return nil }
        let w = layout.pageSize.width
        let total = CGFloat(per) * w + CGFloat(per - 1) * Self.gutter
        let viewH = layout.pageSize.height + ReaderLayout.headRoom + pageFoot
        return CGPoint(x: (area.width - total) / 2 + CGFloat(k) * (w + Self.gutter), y: (area.height - viewH) / 2)
    }

    /// A rectangle of a page's text (y up) in the spread's coordinates.
    func spreadRect(_ r: CGRect, page: Int) -> CGRect? {
        guard let layout, let o = pageOrigin(page) else { return nil }
        return layout.viewRect(r).offsetBy(dx: o.x, dy: o.y)
    }

    /// A press on a word selects it.
    @discardableResult
    func beginSelection(at p: CGPoint) -> Bool {
        guard let layout, let t = textPoint(p), let i = layout.stringIndex(at: t.up, page: t.page, strict: true),
              let w = layout.wordRange(at: i) else { return false }
        selectionAnchor = w
        selection = w
        markTarget = nil
        return true
    }

    /// Dragging from the pressed word grows the selection by words.
    func extendSelection(to p: CGPoint) {
        guard let anchor = selectionAnchor, let layout, let t = textPoint(p), let i = layout.stringIndex(at: t.up, page: t.page) else { return }
        let w = layout.wordRange(at: i) ?? NSRange(location: i, length: 0)
        let lo = min(anchor.location, w.location), hi = max(anchor.location + anchor.length, w.location + w.length)
        selection = NSRange(location: lo, length: hi - lo)
    }

    /// A handle moved: its edge follows the nearest character.
    func moveHandle(start: Bool, to p: CGPoint) {
        guard let sel = selection, let layout, let t = textPoint(p), let i = layout.stringIndex(at: t.up, page: t.page) else { return }
        let end = sel.location + sel.length
        selection = start ? NSRange(location: min(i, end - 1), length: end - min(i, end - 1))
                          : NSRange(location: sel.location, length: max(i, sel.location + 1) - sel.location)
    }

    /// The pointer (Mac) drags a selection by characters, grown to whole words when it is let go.
    func dragSelect(from start: CGPoint, to p: CGPoint) {
        guard let layout, let s = textPoint(start), let e = textPoint(p) else { return }
        if dragStart == nil { dragStart = layout.stringIndex(at: s.up, page: s.page) }
        guard let a = dragStart, let b = layout.stringIndex(at: e.up, page: e.page) else { return }
        markTarget = nil
        selection = a == b ? nil : NSRange(location: min(a, b), length: abs(a - b))
    }

    func dragEnded() {
        dragStart = nil
        suppressTap = true
        Task { try? await Task.sleep(for: .milliseconds(250)); suppressTap = false }
        guard let sel = selection, let layout else { return }
        let lo = layout.wordRange(at: sel.location)?.location ?? sel.location
        let hi = layout.wordRange(at: sel.location + sel.length - 1).map { $0.location + $0.length } ?? sel.location + sel.length
        selection = NSRange(location: lo, length: max(0, hi - lo))
    }

    func clearSelection() {
        selection = nil
        selectionAnchor = nil
        dragStart = nil
    }

    /// The first and last lines of the selection that show in this spread, in the spread's coordinates.
    func selectionBounds(spread s: Int) -> (start: CGRect, end: CGRect)? {
        guard let layout, let sel = selection, sel.length > 0, spread == s else { return nil }
        let p0 = layout.page(containing: sel.location), p1 = layout.page(containing: sel.location + sel.length - 1)
        guard let first = layout.spans(of: sel, page: p0).first, let last = layout.spans(of: sel, page: p1).last,
              let a = spreadRect(first.rect, page: p0), let b = spreadRect(last.rect, page: p1) else { return nil }
        return (a, b)
    }

    // MARK: Marking

    private func selectedPieces() -> [MarkPiece] {
        guard let layout, let sel = selection else { return [] }
        return layout.pieces(for: sel, ids: script.lines.map(\.id))
    }

    /// The edit menu's, a key's and the Mac menu's one verb: a Beat or a Note asks for its words first.
    func markSelection(_ kind: MarkKind, hue: String? = nil) {
        let pieces = selectedPieces()
        guard !pieces.isEmpty else { return }
        if kind == .beat || kind == .note {
            guard let m = MarksCore.fromSelection(script, pieces, kind, MarkExtra(label: "", note: "")).first else { return }
            compose = MarkCompose(kind: kind, before: kind == .beat ? String(m.prefix.suffix(40)) : "", words: m.text,
                                  after: kind == .beat ? String(m.suffix.prefix(40)) : "", pieces: pieces)
            return
        }
        add(pieces, kind: kind, extra: MarkExtra(hue: hue ?? markHue))
    }

    private func add(_ pieces: [MarkPiece], kind: MarkKind, extra: MarkExtra) {
        let made = MarksCore.fromSelection(script, pieces, kind, extra)
        clearSelection()
        guard !made.isEmpty else { return }
        for m in made { marks = MarksCore.add(script, marks, m) }
        if kind == .highlight, let h = extra.hue { markHue = h; MarkStore.savePrefs(show: true, hue: h, defaults) }
        persistMarks()
        if !showMarks { showMarks = true } else { relayoutIfPoints(made) }
    }

    func saveCompose(_ c: MarkCompose, text: String) {
        compose = nil
        if let id = c.editing {
            marks = MarksCore.update(marks, id, c.kind == .beat ? MarkPatch(label: text) : MarkPatch(note: text))
            persistMarks()
            return
        }
        add(c.pieces, kind: c.kind, extra: MarkExtra(label: text, note: text))
    }

    func edit(_ m: Mark) {
        markTarget = nil
        compose = MarkCompose(kind: m.kind, editing: m.id, before: m.isSpan ? "" : String(m.prefix.suffix(40)), words: m.text,
                              after: m.isSpan ? "" : String(m.suffix.prefix(40)), text: m.kind == .beat ? (m.label ?? "") : (m.note ?? ""))
    }

    func setHue(_ id: String, _ hue: String) {
        marks = MarksCore.update(marks, id, MarkPatch(hue: hue))
        markHue = hue
        MarkStore.savePrefs(show: showMarks, hue: hue, defaults)
        persistMarks()
    }

    /// Delete is undoable: the Undo bar, and the system's Undo (⌘Z, shake).
    func deleteMark(_ id: String) {
        markTarget = nil
        let r = MarksCore.remove(marks, id)
        guard !r.removed.isEmpty else { return }
        marks = r.marks
        persistMarks()
        relayoutIfPoints(r.removed)
        removedMarks = r.removed
        removedTask?.cancel()
        removedTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled { self?.removedMarks = [] }
        }
        let gone = r.removed
        undoManager?.registerUndo(withTarget: self) { target in MainActor.assumeIsolated { target.restoreMarks(gone) } }
        undoManager?.setActionName("Delete")
    }

    func restoreMarks(_ gone: [Mark]) {
        let have = Set(marks.map(\.id))
        let back = gone.filter { !have.contains($0.id) }
        removedMarks = []
        guard !back.isEmpty else { return }
        marks += back
        persistMarks()
        relayoutIfPoints(back)
    }

    func deleteLost(_ id: String) {
        lostMarks.removeAll { $0.id == id }
        persistMarks()
    }

    /// A tap on a mark opens it (its popover) and never turns the page or changes the studio's line.
    func markTapped(at point: CGPoint) -> Bool {
        guard showMarks, let layout, let s = spread, let t = textPoint(point),
              let m = layout.mark(at: t.up, page: t.page, in: visibleMarks, index: structure.indexByID) else { return false }
        let rect = layout.spans(of: m, page: t.page, index: structure.indexByID).first.flatMap { spreadRect($0.rect, page: t.page) }
            ?? CGRect(origin: point, size: .zero)
        markTarget = MarkTarget(id: m.id, spread: s, rect: rect)
        return true
    }
}

// MARK: - Selecting on the page

/// The selection layer over a spread: iPhone and iPad press a word and drag, with handles and the system's edit menu;
/// the Mac drags with the pointer, double-clicks a word, and right-clicks for the menu.
struct MarkSelecting: ViewModifier {
    let model: ReaderModel
    let spread: Int

    func body(content: Content) -> some View {
        #if os(iOS)
        if model.inkMode {
            content
        } else {
            content.overlay { SelectionLayer(model: model, spread: spread, selection: model.selection) }
        }
        #else
        content
            .simultaneousGesture(DragGesture(minimumDistance: 4)
                .onChanged { model.dragSelect(from: $0.startLocation, to: $0.location) }
                .onEnded { _ in model.dragEnded() })
            .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { _ = model.beginSelection(at: $0.location) })
            .contextMenu { if model.selection != nil { MarkMenuItems(model: model) } }
        #endif
    }
}

#if os(macOS)
/// The six verbs in the selection's context menu, the hues a submenu of Highlight.
struct MarkMenuItems: View {
    let model: ReaderModel

    var body: some View {
        Menu("Highlight") {
            ForEach(MarkHue.all, id: \.self) { hue in
                Button(hue.capitalized) { model.markSelection(.highlight, hue: hue) }
            }
        }
        ForEach([MarkKind.underline, .breath, .pause, .beat, .note], id: \.self) { kind in
            Button(kind.title) { model.markSelection(kind) }
        }
    }
}
#endif

#if os(iOS)
struct SelectionLayer: UIViewRepresentable {
    let model: ReaderModel
    let spread: Int
    /// Read so the layer is updated when the selection changes.
    let selection: NSRange?

    func makeUIView(context: Context) -> SelectionView { SelectionView(model: model) }

    func updateUIView(_ view: SelectionView, context: Context) {
        view.spread = spread
        view.sync()
    }
}

final class SelectionView: UIView, UIEditMenuInteractionDelegate, UIGestureRecognizerDelegate {
    let model: ReaderModel
    var spread = 0
    private let startHandle = HandleView(top: true)
    private let endHandle = HandleView(top: false)
    private var menu: UIEditMenuInteraction?
    private var dragging = false
    private var scroller: UIScrollView?

    init(model: ReaderModel) {
        self.model = model
        super.init(frame: .zero)
        backgroundColor = .clear
        let press = UILongPressGestureRecognizer(target: self, action: #selector(pressed(_:)))
        press.minimumPressDuration = 0.35
        press.delegate = self
        addGestureRecognizer(press)
        let interaction = UIEditMenuInteraction(delegate: self)
        addInteraction(interaction)
        menu = interaction
        for handle in [startHandle, endHandle] {
            handle.isHidden = true
            handle.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(panned(_:))))
            addSubview(handle)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    // MARK: Gestures

    @objc private func pressed(_ g: UILongPressGestureRecognizer) {
        switch g.state {
        case .began:
            guard model.beginSelection(at: g.location(in: self)) else { return }
            dragging = true
            model.suppressTap = true
            freezeScroll(true)
        case .changed:
            if dragging { model.extendSelection(to: g.location(in: self)); sync() }
        case .ended, .cancelled, .failed:
            guard dragging else { return }
            dragging = false
            freezeScroll(false)
            sync()
            presentMenu()
            release()
        default: break
        }
    }

    @objc private func panned(_ g: UIPanGestureRecognizer) {
        let start = g.view === startHandle
        switch g.state {
        case .began:
            model.suppressTap = true
            freezeScroll(true)
            menu?.dismissMenu()
        case .changed:
            let p = g.location(in: self)
            model.moveHandle(start: start, to: CGPoint(x: p.x, y: p.y + (start ? 14 : -14)))
            sync()
        case .ended, .cancelled, .failed:
            freezeScroll(false)
            presentMenu()
            release()
        default: break
        }
    }

    /// The paging scroll stands still while words are selected.
    private func freezeScroll(_ on: Bool) {
        if on {
            scroller = sequence(first: superview, next: { $0?.superview }).compactMap { $0 as? UIScrollView }.first
            scroller?.isScrollEnabled = false
        } else {
            scroller?.isScrollEnabled = true
            scroller = nil
        }
    }

    private func release() {
        Task { @MainActor [model] in
            try? await Task.sleep(for: .milliseconds(250))
            model.suppressTap = false
        }
    }

    // MARK: Handles and menu

    func sync() {
        guard let b = model.selectionBounds(spread: spread) else {
            startHandle.isHidden = true
            endHandle.isHidden = true
            menu?.dismissMenu()
            return
        }
        startHandle.isHidden = false
        endHandle.isHidden = false
        startHandle.frame = CGRect(x: b.start.minX - 12, y: b.start.minY - 12, width: 24, height: b.start.height + 12)
        endHandle.frame = CGRect(x: b.end.maxX - 12, y: b.end.minY, width: 24, height: b.end.height + 12)
    }

    private func union() -> CGRect? {
        model.selectionBounds(spread: spread).map { $0.start.union($0.end) }
    }

    private func presentMenu() {
        guard let r = union() else { return }
        let config = UIEditMenuConfiguration(identifier: nil, sourcePoint: CGPoint(x: r.midX, y: r.minY))
        config.preferredArrowDirection = .down
        menu?.presentEditMenu(with: config)
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction, targetRectFor configuration: UIEditMenuConfiguration) -> CGRect {
        union() ?? .zero
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration,
                             suggestedActions: [UIMenuElement]) -> UIMenu? {
        let swatch = UIImage(systemName: "circle.fill")?
            .withTintColor(UIColor(Color.mark(model.markHue)), renderingMode: .alwaysOriginal)
        let model = model
        let items: [UIMenuElement] = [
            UIAction(title: MarkKind.highlight.title, image: swatch) { _ in model.markSelection(.highlight) },
            UIAction(title: MarkKind.underline.title) { _ in model.markSelection(.underline) },
            UIAction(title: MarkKind.breath.title) { _ in model.markSelection(.breath) },
            UIAction(title: MarkKind.pause.title) { _ in model.markSelection(.pause) },
            UIAction(title: MarkKind.beat.title) { _ in model.markSelection(.beat) },
            UIAction(title: MarkKind.note.title) { _ in model.markSelection(.note) },
        ]
        return UIMenu(children: items)
    }
}

/// A selection's handle: a stem along the line's edge and a knob beyond it.
final class HandleView: UIView {
    let top: Bool

    init(top: Bool) {
        self.top = top
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { bounds.insetBy(dx: -14, dy: -12).contains(point) }

    override func draw(_ rect: CGRect) {
        guard let c = UIGraphicsGetCurrentContext() else { return }
        c.setFillColor(UIColor(Color.brandSecondary).cgColor)
        let x = bounds.midX
        if top {
            c.fillEllipse(in: CGRect(x: x - 5, y: 0, width: 10, height: 10))
            c.fill(CGRect(x: x - 1, y: 8, width: 2, height: max(0, bounds.height - 8)))
        } else {
            c.fill(CGRect(x: x - 1, y: 0, width: 2, height: max(0, bounds.height - 8)))
            c.fillEllipse(in: CGRect(x: x - 5, y: bounds.height - 10, width: 10, height: 10))
        }
    }
}
#endif

// MARK: - A tapped mark

struct MarkPopover: View {
    let model: ReaderModel
    let target: MarkTarget

    var body: some View {
        if let m = model.marks.first(where: { $0.id == target.id }) {
            VStack(alignment: .leading, spacing: Spacing.s3) {
                if m.kind == .note, let note = m.note, !note.isEmpty {
                    Text(verbatim: note).font(TypeRamp.body).frame(maxWidth: 260, alignment: .leading)
                }
                if m.kind == .highlight {
                    HStack(spacing: Spacing.s3) {
                        ForEach(MarkHue.all, id: \.self) { hue in
                            Button { model.setHue(m.id, hue) } label: {
                                Circle().fill(Color.mark(hue)).frame(width: 32, height: 32)
                                    .overlay(Circle().strokeBorder(Color.brandText, lineWidth: m.hue == hue ? 2.5 : 0.5))
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(hue.capitalized)
                            .accessibilityAddTraits(m.hue == hue ? .isSelected : [])
                        }
                    }
                }
                HStack(spacing: Spacing.s3) {
                    if m.kind == .beat || m.kind == .note {
                        Button("Edit") { model.edit(m) }.buttonStyle(.bordered)
                    }
                    Button("Delete", role: .destructive) { model.deleteMark(m.id) }.buttonStyle(.bordered)
                }
            }
            .padding(Spacing.s4)
            .presentationBackground(Color.brandSurface)
        }
    }
}

// MARK: - A Beat or a Note

struct MarkComposeSheet: View {
    let model: ReaderModel
    let compose: MarkCompose
    @State private var text: String
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    init(model: ReaderModel, compose: MarkCompose) {
        self.model = model
        self.compose = compose
        _text = State(initialValue: compose.text)
    }

    private var words: AttributedString {
        var out = AttributedString(compose.before.isEmpty ? "" : "\u{2026}" + compose.before + " ")
        out.foregroundColor = Color.brandTextMuted
        var marked = AttributedString(compose.kind == .beat ? "\u{2044}\u{2044}" : compose.words)
        marked.font = TypeRamp.bodyStrong
        out.append(marked)
        var after = AttributedString(compose.after.isEmpty ? "" : " " + compose.after + "\u{2026}")
        after.foregroundColor = Color.brandTextMuted
        out.append(after)
        return out
    }

    private var disabled: Bool { compose.kind == .note && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        let content = VStack(alignment: .leading, spacing: Spacing.s4) {
            Text(words).font(TypeRamp.body).lineLimit(4)
            if compose.kind == .note {
                TextField("Note", text: $text, axis: .vertical).lineLimit(3...8).textFieldStyle(.roundedBorder).focused($focused)
            } else {
                TextField("Label", text: $text).textFieldStyle(.roundedBorder).focused($focused)
                    .onChange(of: text) { _, new in if new.count > MarksCore.labelMax { text = String(new.prefix(MarksCore.labelMax)) } }
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.s4)
        .onAppear { focused = true }
        .accessibilityIdentifier("mark-compose")
        #if os(iOS)
        NavigationStack {
            content
                .navigationTitle(compose.kind.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { model.compose = nil } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { model.saveCompose(compose, text: text) }.disabled(disabled) }
                }
        }
        .presentationDetents([.medium])
        #else
        VStack(spacing: 0) {
            Text(compose.kind.title).font(TypeRamp.bodyStrong).padding(.top, Spacing.s4)
            content
            HStack {
                Spacer()
                Button("Cancel") { model.compose = nil }.keyboardShortcut(.cancelAction)
                Button("Save") { model.saveCompose(compose, text: text) }.keyboardShortcut(.defaultAction).disabled(disabled)
            }
            .padding([.horizontal, .bottom], Spacing.s4)
        }
        .frame(width: 380, height: 260)
        #endif
    }
}

// MARK: - The notebook

/// Every mark in script order; a tap goes to its line. Not Placed: marks a revision could not anchor, each deletable.
struct MarksNotebook: View {
    @Bindable var model: ReaderModel
    var dismiss: (() -> Void)?

    var body: some View {
        #if os(iOS)
        NavigationStack {
            list
                .navigationTitle("Marks")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss?() } } }
        }
        #else
        list
        #endif
    }

    private var list: some View {
        let rows = model.markOrder
        return List {
            Section {
                Toggle("Show Marks", isOn: $model.showMarks).accessibilityIdentifier("marks-show")
            }
            if rows.isEmpty, model.lostMarks.isEmpty, model.inks.isEmpty, model.lostInks.isEmpty {
                Text("Select words on the page to mark them.")
                    .font(TypeRamp.body)
                    .foregroundStyle(Color.brandTextMuted)
                    .accessibilityIdentifier("marks-empty")
            } else {
                Section {
                    ForEach(rows) { m in row(m) }
                }
                if !model.inks.isEmpty {
                    Section("Ink") {
                        ForEach(model.inkOrder) { i in inkRow(i, placed: true) }
                    }
                }
                if !model.lostMarks.isEmpty || !model.lostInks.isEmpty {
                    Section("Not Placed") {
                        ForEach(model.lostMarks) { m in lostRow(m) }
                        ForEach(model.lostInks) { i in inkRow(i, placed: false) }
                    }
                }
            }
        }
        .listStyle(.plain)
        .accessibilityIdentifier("marks-notebook")
    }

    private func speaker(_ m: Mark) -> String? {
        guard let i = model.structure.indexByID[m.line] else { return nil }
        let line = model.script.lines[i]
        return line.kind == .speech ? line.role : nil
    }

    private func words(_ m: Mark) -> String {
        m.isSpan ? m.text : "\(m.prefix.suffix(28)) \u{2044}\u{2044} \(m.suffix.prefix(28))"
    }

    @ViewBuilder private func glyph(_ m: Mark) -> some View {
        switch m.kind {
        case .highlight: Image(systemName: "circle.fill").foregroundStyle(Color.mark(m.hue))
        case .underline: Image(systemName: "underline")
        case .note: Image(systemName: "note.text")
        case .breath: Text(verbatim: "/").font(TypeRamp.bodyStrong)
        case .pause, .beat: Text(verbatim: "//").font(TypeRamp.bodyStrong)
        }
    }

    private func label(_ m: Mark) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s3) {
            glyph(m).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                if let role = speaker(m) {
                    Text(verbatim: role).font(TypeRamp.caption.weight(.semibold)).foregroundStyle(Color.brandTextMuted)
                }
                Text(verbatim: words(m)).font(TypeRamp.body).lineLimit(3)
                if let l = m.label, !l.isEmpty {
                    Text(verbatim: l.uppercased()).font(TypeRamp.caption.weight(.semibold)).foregroundStyle(Color.brandTextMuted)
                }
                if let n = m.note, !n.isEmpty {
                    Text(verbatim: n).font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted).lineLimit(3)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func row(_ m: Mark) -> some View {
        Button {
            model.go(to: m.line)
            dismiss?()
        } label: { label(m) }
            .buttonStyle(.plain)
            .swipeActions { Button("Delete", role: .destructive) { model.deleteMark(m.id) } }
            .contextMenu { Button("Delete", role: .destructive) { model.deleteMark(m.id) } }
            .accessibilityLabel("\(m.kind.title): \(m.isSpan ? m.text : (m.label ?? ""))")
    }

    private func inkRow(_ i: LineInk, placed: Bool) -> some View {
        InkNotebookRow(model: model, ink: i, placed: placed, dismiss: dismiss)
    }

    private func lostRow(_ m: Mark) -> some View {
        label(m)
            .swipeActions { Button("Delete", role: .destructive) { model.deleteLost(m.id) } }
            .contextMenu { Button("Delete", role: .destructive) { model.deleteLost(m.id) } }
    }
}

/// One line's ink in the notebook: its strokes as a picture, the speaker, the line's first words. A placed one
/// goes to its line; one not placed is only listed, and deletable.
private struct InkNotebookRow: View {
    let model: ReaderModel
    let ink: LineInk
    let placed: Bool
    var dismiss: (() -> Void)?
    @Environment(\.colorScheme) private var scheme

    private var speaker: String? {
        guard let i = model.structure.indexByID[ink.line] else { return nil }
        let line = model.script.lines[i]
        return line.kind == .speech ? line.role : nil
    }

    private var label: some View {
        HStack(alignment: .center, spacing: Spacing.s3) {
            Group {
                if let cg = InkRender.thumbnail(ink, dark: scheme == .dark) {
                    Image(decorative: cg, scale: 2).resizable().scaledToFit()
                } else {
                    Image(systemName: "pencil.tip")
                }
            }
            .frame(width: 72, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                if let role = speaker {
                    Text(verbatim: role).font(TypeRamp.caption.weight(.semibold)).foregroundStyle(Color.brandTextMuted)
                }
                Text(verbatim: ink.text).font(TypeRamp.body).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    var body: some View {
        Group {
            if placed {
                Button {
                    model.go(to: ink.line)
                    dismiss?()
                } label: { label }
                    .buttonStyle(.plain)
            } else {
                label
            }
        }
        .swipeActions { Button("Delete", role: .destructive) { remove() } }
        .contextMenu { Button("Delete", role: .destructive) { remove() } }
        .accessibilityIdentifier(placed ? "ink-row" : "ink-lost-row")
    }

    private func remove() {
        if placed { model.deleteInk(ink.line) } else { model.deleteLostInk(ink.id) }
    }
}

// MARK: - Undo, a failed write, VoiceOver

/// What Delete just took, with Undo; or the one refusal a failed write earns.
struct MarkUndoBar: View {
    let model: ReaderModel

    var body: some View {
        Group {
            if let notice = model.markNotice {
                Label(notice, systemImage: "exclamationmark.triangle.fill")
                    .font(TypeRamp.caption)
                    .foregroundStyle(Color.semanticWarning)
                    .accessibilityIdentifier("marks-notice")
            } else if !model.removedMarks.isEmpty {
                HStack(spacing: Spacing.s3) {
                    Text("Deleted").font(TypeRamp.caption)
                    Button("Undo") { model.restoreMarks(model.removedMarks) }
                        .font(TypeRamp.caption.weight(.semibold))
                        .accessibilityIdentifier("marks-undo")
                }
            }
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s2)
        .background(.regularMaterial, in: Capsule())
        .padding(.bottom, 64)
        .opacity(model.markNotice != nil || !model.removedMarks.isEmpty ? 1 : 0)
        .allowsHitTesting(model.markNotice != nil || !model.removedMarks.isEmpty)
        .sensoryFeedback(Haptic.error.feedback, trigger: model.markNotice)
    }
}

/// Each mark on a line is a custom action on its speech: "Highlight: first thing", in reading order.
struct MarkActions: ViewModifier {
    let model: ReaderModel
    let line: Int

    func body(content: Content) -> some View {
        let id = model.script.lines[line].id
        let here = MarksCore.order(model.script, model.marks.filter { $0.line == id })
        content.accessibilityActions {
            ForEach(here) { m in
                Button("\(m.kind.title): \(m.isSpan ? m.text : (m.label ?? ""))") {
                    model.markTarget = MarkTarget(id: m.id, spread: model.spread ?? 0, rect: .zero)
                }
            }
        }
    }
}
#endif
