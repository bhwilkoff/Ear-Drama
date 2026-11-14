#if os(iOS) || os(macOS)
import SwiftUI
#if os(macOS)
import AppKit
#endif

// The script reader (PLAYS-DESIGN §2.7, iOS-DESIGN §4.15, macOS-DESIGN §4.7; Decision 076 S1). Pages by default:
// a horizontal paging scroll of spreads, one page or two facing pages by width, each page drawn by Core Text from
// the same frame that measured it (ReaderLayout). Scroll is a setting. The reading position is a line id and
// survives every re-layout. I'm Playing highlights a part's lines, finds its next line, and hides its words.
// Every word on a page is the script's (§2.7 rule 9).

// MARK: - What the reader keeps on the device

enum ReaderStore {
    static let prefsKey = "ed.reader.prefs"
    static let positionsKey = "ed.reader.pos"

    static func prefs(_ defaults: UserDefaults = .standard) -> ReaderPrefs { ReaderPrefs.decode(defaults.string(forKey: prefsKey)) }

    static func save(_ prefs: ReaderPrefs, _ defaults: UserDefaults = .standard) { defaults.set(prefs.json, forKey: prefsKey) }

    static func positions(_ defaults: UserDefaults = .standard) -> [ReaderPosition] {
        guard let data = defaults.data(forKey: positionsKey) else { return [] }
        return (try? JSONDecoder().decode([ReaderPosition].self, from: data)) ?? []
    }

    static func position(for scriptID: String, _ defaults: UserDefaults = .standard) -> ReaderPosition? {
        positions(defaults).first { $0.id == scriptID }
    }

    static func remember(_ entry: ReaderPosition, _ defaults: UserDefaults = .standard) {
        let kept = ReaderMath.remember(positions(defaults), entry)
        if let data = try? JSONEncoder().encode(kept) { defaults.set(data, forKey: positionsKey) }
    }
}

/// The seam the read-along and the studio use: `follow(lineID)` turns to a line (the listen-through will call it).
@Observable
final class ReaderController {
    @ObservationIgnored weak var model: ReaderModel?
    func follow(_ lineID: String) { model?.go(to: lineID) }
}

extension FocusedValues {
    @Entry var reader: ReaderModel?
}

// MARK: - The model

@Observable
final class ReaderModel {
    static let gutter: CGFloat = 48
    static let margin: CGFloat = 24

    let script: PlayScript
    let structure: ScriptStructure
    @ObservationIgnored private(set) lazy var searchIndex = ScriptReading.SearchIndex(script)

    var prefs: ReaderPrefs {
        didSet {
            guard prefs != oldValue else { return }
            ReaderStore.save(prefs)
            if prefs.layout == .scroll { scroll.scrollTo(id: script.lines[position].id, anchor: .top) }
            if prefs.layout != oldValue.layout || prefs.size != oldValue.size || prefs.spacing != oldValue.spacing { relayout() }
        }
    }
    /// The line kept through every re-layout: the first showing on the page, or the one last gone to.
    private(set) var position: Int
    var part: PartID? {
        didSet {
            mine = part.map { Set(ScriptReading.lineIndexes(of: $0, in: script)) }
            if part == nil { hide = false }
            peeked = []
            persist()
        }
    }
    private(set) var mine: Set<Int>?
    var hide = false { didSet { peeked = [] } }
    var peeked: Set<Int> = []
    private(set) var layout: ReaderLayout?
    private(set) var per = 1
    /// The spread in view: the paging scroll's position id.
    var spread: Int? {
        didSet { if spread != oldValue { spreadMoved() } }
    }
    var scroll = ScrollPosition(idType: String.self)
    private(set) var area: CGSize = .zero
    var base: CGFloat = 17 {
        didSet { if base != oldValue { relayout() } }
    }
    private(set) var failed = false
    /// A launch door's sheet and page, each taken once (DEBUG doors only).
    var doorSheet: String?
    @ObservationIgnored private var doorPage: Int?
    /// How many lines the scroller shows, so a turn in Scroll moves about a screen.
    @ObservationIgnored private var visibleCount = 8

    @ObservationIgnored private var build: Task<ReaderLayout, any Error>?
    @ObservationIgnored private var kick: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let defaults: UserDefaults

    init(script: PlayScript, startLine: String?, door: ReaderDoor? = nil, defaults: UserDefaults = .standard) {
        self.script = script
        self.defaults = defaults
        let structure = ScriptStructure(script)
        self.structure = structure
        var prefs = ReaderStore.prefs(defaults)
        if let json = door?.prefs { prefs = ReaderPrefs.decode(json) }
        self.prefs = prefs
        let saved = ReaderStore.position(for: script.id, defaults)
        let index = startLine.flatMap { structure.indexByID[$0] } ?? saved?.line.flatMap { structure.indexByID[$0] } ?? 0
        position = index
        if let name = door?.part ?? saved?.part, script.castParts.contains(where: { $0.id.rawValue == name && $0.id.isSpeaking }) {
            let id = PartID(rawValue: name)
            part = id
            mine = Set(ScriptReading.lineIndexes(of: id, in: script))
        }
        if door?.hide == true, part != nil { hide = true }
        doorSheet = door?.sheet
        doorPage = door?.page
    }

    // MARK: Layout

    func areaChanged(_ size: CGSize) {
        guard size != area, size.width > 40, size.height > 40 else { return }
        area = size
        relayout(delay: layout == nil ? 0 : 0.12)
    }

    /// Lays the script out at the current size and returns to `keep` (a line index), else the kept position. The
    /// position is never recomputed from the new pages, so repeated size changes do not drift backward.
    func relayout(keep: Int? = nil, delay: Double = 0) {
        guard prefs.layout == .pages, area.width > 40 else { return }
        let at = keep ?? position
        generation += 1
        let gen = generation
        build?.cancel()
        kick?.cancel()
        let per = ReaderMath.perSpread(area.width)
        let style = ReaderStyle(base: base, scale: prefs.scale, leading: prefs.lineHeight)
        let width = min(((area.width - 2 * Self.margin - CGFloat(per - 1) * Self.gutter) / CGFloat(per)).rounded(.down), style.size * 36)
        let height = (area.height - 2 * Self.margin).rounded(.down)
        let script = script, structure = structure
        kick = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled else { return }
            let work = Task.detached(priority: .userInitiated) {
                try ReaderLayout.build(script, structure: structure, style: style, pageSize: CGSize(width: width, height: height))
            }
            self?.build = work
            let built = try? await work.value
            guard let self, gen == self.generation, let built else { return }
            self.apply(built, per: per, keep: at)
        }
    }

    private func apply(_ built: ReaderLayout, per: Int, keep: Int) {
        let line = min(max(0, keep), max(0, script.lines.count - 1))
        layout = built
        self.per = per
        position = line
        peeked = []
        var target = built.starts.indices.contains(line) ? ReaderMath.spreadStart(built.starts[line], per: per) / per : 0
        if let page = doorPage {
            doorPage = nil
            target = min(max(0, page), built.pageCount - 1) / per
        }
        withTransaction(Transaction(animation: nil)) { spread = target }
    }

    var spreadCount: Int { layout.map { (max(1, $0.pageCount) + per - 1) / per } ?? 0 }

    /// "12–13 of 140" in pages, a percentage in Scroll.
    var pageLabel: String {
        if prefs.layout == .scroll { return "\(Int((Double(position + 1) / Double(max(1, script.lines.count)) * 100).rounded()))%" }
        guard let layout else { return "" }
        return ReaderMath.pageLabel(page: (spread ?? 0) * per, per: per, count: layout.pageCount)
    }

    var place: (act: ScriptHeading?, scene: ScriptHeading?) { structure.place(of: position) }

    /// "ACT I. · SCENE II.": the act and scene the position is in, as printed.
    var placeLine: String {
        let p = place
        return [p.act?.title, p.scene?.title].compactMap { $0 }.joined(separator: " \u{00B7} ")
    }

    // MARK: Turning

    /// The spread moved (a swipe, a turn, a restore): the kept line stays unless it left the screen.
    private func spreadMoved() {
        peeked = []
        guard let layout, let s = spread else { return }
        let first = s * per
        let on = first..<(first + per)
        if layout.starts.indices.contains(position), layout.starts[position] < on.upperBound, layout.ends[position] >= on.lowerBound { return }
        let line = ReaderMath.lineAtPage(starts: layout.starts, ends: layout.ends, page: first)
        if line >= 0 { position = line }
        persist()
    }

    func turn(_ delta: Int) {
        if prefs.layout == .scroll {
            go(toIndex: min(max(0, position + delta * max(1, visibleCount - 1)), script.lines.count - 1))
            return
        }
        guard let layout, let s = spread else { return }
        let to = ReaderMath.turn(s * per, delta: delta, per: per, count: layout.pageCount) / per
        move(toSpread: to)
    }

    func turnToEdge(last: Bool) {
        if prefs.layout == .scroll {
            go(toIndex: last ? script.lines.count - 1 : 0)
            return
        }
        move(toSpread: last ? max(0, spreadCount - 1) : 0)
    }

    func move(toSpread to: Int) {
        guard to != spread else { return }
        if UIAccessibilityReduceMotion.isOn { spread = to } else { withAnimation(.snappy) { spread = to } }
    }

    func tap(at point: CGPoint) {
        switch ReaderMath.tapZone(x: point.x, width: area.width) {
        case .prev: turn(-1)
        case .next: turn(1)
        case .middle: peekAt(point)
        }
    }

    // MARK: Going to a line

    func go(to lineID: String) {
        if let i = structure.indexByID[lineID] { go(toIndex: i) }
    }

    func go(toIndex index: Int) {
        guard script.lines.indices.contains(index) else { return }
        position = index
        peeked = []
        if prefs.layout == .scroll {
            scroll.scrollTo(id: script.lines[index].id, anchor: .top)
        } else if let layout {
            move(toSpread: ReaderMath.spreadStart(layout.starts[index], per: per) / per)
        }
        persist()
    }

    /// My next (1) or previous (-1) line; past the last, the first again.
    func nextMine(_ direction: Int) {
        guard let part else { return }
        var i = ScriptReading.nextLine(of: part, after: position, direction: direction, in: script)
        if i == nil, direction > 0 { i = ScriptReading.nextLine(of: part, after: -1, in: script) }
        if let i { go(toIndex: i) }
    }

    /// The first line still showing at the top of the scroller (Scroll's position).
    func visible(_ ids: [String]) {
        guard prefs.layout == .scroll, let first = ids.compactMap({ structure.indexByID[$0] }).min() else { return }
        visibleCount = ids.count
        if first != position {
            position = first
            peeked = []
            persist()
        }
    }

    // MARK: Hiding and peeking

    func isHidden(_ line: Int) -> Bool { hide && mine?.contains(line) == true && !peeked.contains(line) }

    func peek(_ line: Int) { peeked = [line] }

    /// A tap on a hidden line shows it until the next tap or turn.
    private func peekAt(_ point: CGPoint) {
        guard hide, let layout, let s = spread else {
            peeked = []
            return
        }
        let pageW = layout.pageSize.width
        let total = CGFloat(per) * pageW + CGFloat(per - 1) * Self.gutter
        let left = (area.width - total) / 2
        let top = (area.height - layout.pageSize.height) / 2
        for k in 0..<per {
            let page = s * per + k
            guard page < layout.pageCount else { continue }
            let x0 = left + CGFloat(k) * (pageW + Self.gutter)
            let local = CGPoint(x: point.x - x0, y: point.y - top)
            guard local.x >= -8, local.x <= pageW + 8 else { continue }
            if let line = layout.line(at: local, page: page), mine?.contains(line) == true { peek(line); return }
        }
        peeked = []
    }

    // MARK: Text size

    func bigger() { if prefs.size < ReaderMath.sizes.count - 1 { prefs.size += 1 } }
    func smaller() { if prefs.size > 0 { prefs.size -= 1 } }
    func resetSize() { prefs.size = ReaderMath.defaultSize }
    var sizePercent: Int { Int((prefs.scale * 100).rounded()) }

    // MARK: Keeping the place

    private func persist() {
        saveTask?.cancel()
        let id = script.id, line = script.lines.indices.contains(position) ? script.lines[position].id : nil, part = part?.rawValue
        saveTask = Task { [defaults] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            ReaderStore.remember(ReaderPosition(id: id, line: line, part: part ?? ""), defaults)
        }
    }

    /// The speaking parts, largest first, as the I'm Playing menu offers them (sound and directions never).
    var playable: [CastPart] { script.castParts.filter { $0.id.isSpeaking } }
}

#if os(iOS)
private enum UIAccessibilityReduceMotion {
    static var isOn: Bool { UIAccessibility.isReduceMotionEnabled }
}
#else
private enum UIAccessibilityReduceMotion {
    static var isOn: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
}
#endif

// MARK: - The reader

/// Loads a play's whole script (the library's file, else the bundle's) and reads it.
struct ScriptReaderView: View {
    let scriptID: String
    var startLine: String?
    var dock: AnyView?
    var controller: ReaderController?
    @Environment(PlaysLibrary.self) private var plays
    @Environment(AppStore.self) private var app
    @State private var script: PlayScript?
    @State private var model: ReaderModel?
    @State private var failed = false

    var body: some View {
        Group {
            if let model {
                ReaderScreen(model: model, dock: dock)
            } else if failed {
                VStack(spacing: Spacing.s3) {
                    EmptyState("This play could not be opened", systemImage: "wifi.slash")
                    Button("Try Again") { Task { await load() } }.buttonStyle(.bordered)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.brandBackground)
        .task(id: scriptID) { await load() }
    }

    private func load() async {
        failed = false
        do {
            guard let found = try await plays.script(id: scriptID) else {
                failed = true
                return
            }
            let door = app.readerDoor
            let made = ReaderModel(script: found, startLine: startLine, door: door)
            controller?.model = made
            model = made
        } catch {
            failed = true
        }
    }
}

private struct ReaderScreen: View {
    @Bindable var model: ReaderModel
    var dock: AnyView?
    @Environment(AppStore.self) private var app
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .body) private var body17: CGFloat = 17
    @State private var sheet: ReaderSheet?
    @State private var showContents = false

    var body: some View {
        #if os(macOS)
        NavigationSplitView {
            ReaderContents(model: model)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            reader
        }
        .focusedSceneValue(\.reader, model)
        #else
        reader
            .sheet(item: $sheet) { which in
                switch which {
                case .contents: ReaderContents(model: model, dismiss: { sheet = nil })
                        .presentationDetents([.medium, .large])
                case .search: ReaderSearch(model: model, dismiss: { sheet = nil })
                        .presentationDetents([.medium, .large])
                case .text: ReaderTextSettings(model: model)
                        .presentationDetents([.medium])
                }
            }
        #endif
    }

    private var reader: some View {
        VStack(spacing: 0) {
            // Held to the safe area: the Duo's strip and a notch are inside it, and a scroll view draws under them.
            GeometryReader { _ in
                Group {
                    if model.prefs.layout == .pages { pager } else { scroller }
                }
            }
            .clipped()
            if let dock { dock }
            bottomBar
        }
        .background(Color.brandBackground)
        .navigationTitle(model.script.title)
        .modifier(ReaderSubtitle(text: model.placeLine))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { toolbar }
        .onChange(of: body17, initial: true) { _, size in model.base = size }
        .onAppear {
            if let door = model.doorSheet {
                model.doorSheet = nil
                sheet = ReaderSheet(rawValue: door)
            }
        }
        #if os(macOS)
        .popover(item: $sheet, arrowEdge: .bottom) { which in
            switch which {
            case .search: ReaderSearch(model: model, dismiss: { sheet = nil }).frame(width: 340, height: 420)
            case .text: ReaderTextSettings(model: model).frame(width: 300)
            case .contents: EmptyView()
            }
        }
        #endif
    }

    // MARK: Toolbar and bottom bar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        #if os(iOS)
        ToolbarItem(placement: .cancellationAction) {
            Button { app.reading = nil } label: { Label("Close", systemImage: "xmark") }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { sheet = .contents } label: { Label("Contents", systemImage: "list.bullet") }
            Button { sheet = .search } label: { Label("Search", systemImage: "magnifyingglass") }
            Button { sheet = .text } label: { Label("Text", systemImage: "textformat.size") }
        }
        #else
        ToolbarItemGroup(placement: .primaryAction) {
            Button { sheet = .search } label: { Label("Search", systemImage: "magnifyingglass") }
                .keyboardShortcut("f", modifiers: .command)
            Button { sheet = .text } label: { Label("Text", systemImage: "textformat.size") }
        }
        #endif
    }

    private var bottomBar: some View {
        HStack(spacing: Spacing.s3) {
            Menu {
                Picker("I\u{2019}m Playing", selection: $model.part) {
                    Text("Nobody").tag(PartID?.none)
                    ForEach(model.playable) { cast in
                        Text(verbatim: "\(cast.title) (\(cast.lineCount))").tag(PartID?.some(cast.id))
                    }
                }
            } label: {
                Label(model.part?.title ?? "I\u{2019}m Playing", systemImage: "theatermasks")
                    .lineLimit(1)
            }
            .fixedSize()
            .accessibilityIdentifier("reader-part")
            Button { model.nextMine(1) } label: { Label("Next Line", systemImage: "arrow.down.to.line") }
                .labelStyle(.iconOnly)
                .disabled(model.part == nil)
                .accessibilityIdentifier("reader-next-line")
            Toggle(isOn: $model.hide) { Label("Hide My Lines", systemImage: "eye.slash") }
                .toggleStyle(.button)
                .labelStyle(.iconOnly)
                .disabled(model.part == nil)
                .accessibilityIdentifier("reader-hide")
            Spacer(minLength: 0)
            Text(verbatim: model.pageLabel)
                .font(TypeRamp.tabular)
                .foregroundStyle(Color.brandTextMuted)
                .accessibilityIdentifier("reader-page-label")
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s2)
        .background(Color.brandSurface)
    }

    // MARK: Pages

    private var pager: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(0..<model.spreadCount, id: \.self) { s in
                    ReaderSpread(model: model, spread: s)
                        .containerRelativeFrame(.horizontal)
                        .id(s)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $model.spread)
        .scrollIndicators(.hidden)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { model.areaChanged($0) }
        .overlay { if model.layout == nil { ProgressView() } }
        #if os(iOS)
        .modifier(ReaderKeys(model: model))
        #endif
        .accessibilityIdentifier("reader-pager")
    }

    private var scroller: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(model.script.lines.indices, id: \.self) { i in
                    ReaderLineView(model: model, index: i, size: body17 * CGFloat(model.prefs.scale))
                        .id(model.script.lines[i].id)
                }
            }
            .scrollTargetLayout()
            .frame(maxWidth: body17 * CGFloat(model.prefs.scale) * 36)
            .padding(.horizontal, ReaderModel.margin)
            .padding(.vertical, ReaderModel.margin)
            .frame(maxWidth: .infinity)
        }
        .scrollPosition($model.scroll)
        .onScrollTargetVisibilityChange(idType: String.self, threshold: 0.5) { model.visible($0) }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { model.areaChanged($0) }
        .task { model.scroll.scrollTo(id: model.script.lines[model.position].id, anchor: .top) }
        #if os(iOS)
        .modifier(ReaderKeys(model: model))
        #endif
    }
}

private enum ReaderSheet: String, Identifiable {
    case contents, search, text
    var id: String { rawValue }
}

private struct ReaderSubtitle: ViewModifier {
    let text: String

    func body(content: Content) -> some View {
        if #available(iOS 26, macOS 26, *) {
            content.navigationSubtitle(text)
        } else {
            content
        }
    }
}

#if os(iOS)
/// The pager holds key focus when the reader opens, so a pedal's arrow turns the page instead of moving focus.
private struct ReaderKeys: ViewModifier {
    let model: ReaderModel
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            .onAppear { focused = true }
            .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .pageUp, .pageDown, .space, .home, .end,
                               KeyEquivalent("j"), KeyEquivalent("k")]) { press in
                switch press.key {
                case .rightArrow, .downArrow, .pageDown: model.turn(1)
                case .leftArrow, .upArrow, .pageUp: model.turn(-1)
                case .space: model.turn(press.modifiers.contains(.shift) ? -1 : 1)
                case .home: model.turnToEdge(last: false)
                case .end: model.turnToEdge(last: true)
                case KeyEquivalent("j"): model.nextMine(1)
                case KeyEquivalent("k"): model.nextMine(-1)
                default: return .ignored
                }
                return .handled
            }
    }
}
#endif

// MARK: - A spread and its pages

private struct ReaderSpread: View {
    let model: ReaderModel
    let spread: Int

    var body: some View {
        if let layout = model.layout {
            let first = spread * model.per
            HStack(spacing: ReaderModel.gutter) {
                ForEach(first..<min(first + model.per, layout.pageCount), id: \.self) { page in
                    ReaderPageView(model: model, layout: layout, page: page)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { model.tap(at: $0) }
        } else {
            Color.clear
        }
    }
}

private struct ReaderPageView: View {
    let model: ReaderModel
    let layout: ReaderLayout
    let page: Int
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let marks = ReaderLayout.Marks(mine: model.mine, hide: model.hide, peeked: model.peeked)
        let scheme = scheme
        Canvas { context, _ in
            // The token colors are dynamic: resolved against the scheme the page is in, not the thread's appearance.
            func cg(_ color: Color) -> CGColor { Self.cgColor(color, dark: scheme == .dark) }
            let muted = cg(Color.brandTextMuted)
            let theme = ReaderLayout.Theme(ink: cg(Color.brandText), muted: muted,
                                           hues: PlayScript.partHues.map { Color.genre($0).map(cg) ?? muted },
                                           background: cg(Color.brandBackground))
            context.withCGContext { layout.draw(page: page, in: $0, theme: theme, marks: marks) }
        }
        .frame(width: layout.pageSize.width, height: layout.pageSize.height)
        .accessibilityChildren {
            ForEach(Array(layout.lines(onPage: page)), id: \.self) { i in
                if model.isHidden(i) {
                    Button("Show line") { model.peek(i) }
                } else {
                    Text(verbatim: Self.spoken(model.script.lines[i]))
                }
            }
        }
    }

    nonisolated static func cgColor(_ color: Color, dark: Bool) -> CGColor {
        #if os(iOS)
        return UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light)).cgColor
        #else
        var out = NSColor(color).cgColor
        NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance { out = NSColor(color).cgColor }
        return out
        #endif
    }

    static func spoken(_ line: ScriptLine) -> String {
        let text = ScriptReading.lineText(line).replacingOccurrences(of: "_", with: "")
        return line.kind == .speech ? "\(line.role ?? ""). \(text)" : text
    }
}

// MARK: - Scroll

/// One script line as its own view, keyed by its id (Scroll; marks come in S5).
private struct ReaderLineView: View {
    let model: ReaderModel
    let index: Int
    let size: CGFloat

    var body: some View {
        let line = model.script.lines[index]
        let hidden = model.isHidden(index)
        let hue = model.structure.hueOfLine[index]
        let color = (hue >= 0 ? Color.genre(PlayScript.partHues[hue]) : nil) ?? Color.brandTextMuted
        VStack(alignment: .leading, spacing: 0) {
            ForEach(model.structure.setAside[index] ?? []) { head in
                Text(verbatim: head.title)
                    .font(.custom(TypeRamp.displayFontName, size: size * (head.level == .scene ? 1.15 : 1.4)))
                    .frame(maxWidth: .infinity)
                    .padding(.top, size * 1.2)
                    .padding(.bottom, size * 0.8)
            }
            Text(attributed(line, hidden: hidden, color: color))
                .lineSpacing(size * (model.prefs.lineHeight - 1.2))
                .padding(.leading, line.kind == .speech ? 0 : size * 1.25)
                .padding(.vertical, size * 0.3)
                .padding(.horizontal, model.mine?.contains(index) == true ? 8 : 0)
                .background(model.mine?.contains(index) == true ? color.opacity(0.09) : Color.clear)
                .overlay(alignment: .leading) {
                    if model.mine?.contains(index) == true { Rectangle().fill(color).frame(width: 3) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { if model.mine?.contains(index) == true, model.hide { model.peek(index) } }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(hidden ? "Show line" : ReaderPageView.spoken(line))
                .accessibilityAddTraits(hidden ? .isButton : [])
        }
    }

    private func attributed(_ line: ScriptLine, hidden: Bool, color: Color) -> AttributedString {
        var out = AttributedString()
        func add(_ text: String, _ font: Font, _ ink: Color, hide: Bool = false) {
            var run = AttributedString(text)
            run.font = font
            run.foregroundColor = hide ? .clear : ink
            if hide { run.backgroundColor = color.opacity(0.3) }
            out.append(run)
        }
        let serif = Font.system(size: size, design: .serif)
        let runs = ScriptReading.runsOf(line)
        if let head = model.structure.headLines[index] {
            let font = Font.custom(TypeRamp.displayFontName, size: size * (head.level == .scene ? 1.15 : 1.4))
            for r in runs { add(r.text, font, Color.brandText) }
            return out
        }
        if line.kind == .speech {
            add((line.role ?? "") + " ", Font.system(size: size * 0.8125, weight: .semibold), color)
            var previous: ScriptReading.Run?
            for r in runs {
                if let p = previous, p.piece != r.piece, ScriptReading.spaceBetween(p.text, r.text) { add(" ", serif, Color.brandText) }
                switch r.kind {
                case .say: add(r.text, serif, Color.brandText, hide: hidden)
                case .em: add(r.text, serif.italic(), Color.brandText, hide: hidden)
                case .aside: add(r.text, serif.italic(), Color.brandTextMuted)
                case .plain: add(r.text, serif, Color.brandTextMuted)
                }
                previous = r
            }
            return out
        }
        let cue = line.kind != .direction
        for r in runs {
            let font = cue ? Font.system(size: size * 0.8125, weight: .semibold) : Font.system(size: size * 0.95, design: .serif).italic()
            add(r.text, r.kind == .em && !cue ? Font.system(size: size * 0.95, design: .serif) : font, Color.brandTextMuted)
        }
        return out
    }
}

// MARK: - Contents, Search, Text

private struct ReaderContents: View {
    let model: ReaderModel
    var dismiss: (() -> Void)?

    var body: some View {
        let contents = model.structure.contents
        let here = model.place
        let content = Group {
            if contents.isEmpty {
                Text("This script prints no acts or scenes.")
                    .font(TypeRamp.body)
                    .foregroundStyle(Color.brandTextMuted)
                    .padding(Spacing.s4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                List {
                    ForEach(contents) { top in
                        row(top.heading, indent: false, current: here.act == top.heading && here.scene == nil)
                        ForEach(top.scenes) { scene in row(scene, indent: true, current: here.scene == scene) }
                    }
                }
                .listStyle(.plain)
            }
        }
        #if os(iOS)
        NavigationStack {
            content
                .navigationTitle("Contents")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss?() } } }
        }
        #else
        content
        #endif
    }

    private func row(_ heading: ScriptHeading, indent: Bool, current: Bool) -> some View {
        Button {
            model.go(toIndex: heading.index)
            dismiss?()
        } label: {
            HStack {
                Text(verbatim: heading.title).font(indent ? TypeRamp.body : TypeRamp.bodyStrong).lineLimit(2)
                Spacer(minLength: 0)
                if current { Image(systemName: "checkmark").foregroundStyle(Color.brandSecondary) }
            }
            .padding(.leading, indent ? Spacing.s4 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(current ? .isSelected : [])
    }
}

private struct ReaderSearch: View {
    let model: ReaderModel
    let dismiss: () -> Void
    @State private var query = ""

    var body: some View {
        let found = model.searchIndex.search(query)
        #if os(iOS)
        NavigationStack { results(found) }
        #else
        results(found)
        #endif
    }

    private func results(_ found: (total: Int, hits: [ScriptReading.Hit])) -> some View {
        List {
            if query.trimmingCharacters(in: .whitespaces).count >= 2 {
                if found.hits.isEmpty {
                    Text("No line has these words.").foregroundStyle(Color.brandTextMuted)
                } else {
                    Section {
                        ForEach(found.hits) { hit in
                            Button {
                                model.go(toIndex: hit.index)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    if let role = hit.role {
                                        Text(verbatim: role).font(TypeRamp.caption.weight(.semibold)).foregroundStyle(Color.brandTextMuted)
                                    }
                                    Text(highlighted(hit)).font(TypeRamp.body).lineLimit(3)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text(verbatim: found.total > found.hits.count
                             ? "\(found.hits.count.formatted()) lines \u{00B7} \((found.total - found.hits.count).formatted()) more"
                             : countText(found.total, "line", "lines"))
                    }
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $query, placement: .automatic, prompt: "Search the script")
        .navigationTitle("Search")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", action: dismiss) } }
        #endif
    }

    private func highlighted(_ hit: ScriptReading.Hit) -> AttributedString {
        var before = AttributedString(hit.before)
        var match = AttributedString(hit.match)
        match.font = TypeRamp.body.bold()
        match.foregroundColor = Color.brandSecondary
        before.append(match)
        before.append(AttributedString(hit.after))
        return before
    }
}

private struct ReaderTextSettings: View {
    @Bindable var model: ReaderModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            HStack(spacing: Spacing.s3) {
                Button { model.smaller() } label: { Label("Smaller", systemImage: "textformat.size.smaller") }
                    .labelStyle(.iconOnly)
                    .disabled(model.prefs.size == 0)
                Text(verbatim: "\(model.sizePercent)%")
                    .font(TypeRamp.tabular)
                    .frame(minWidth: 64)
                    .accessibilityLabel("Text size \(model.sizePercent) percent")
                Button { model.bigger() } label: { Label("Larger", systemImage: "textformat.size.larger") }
                    .labelStyle(.iconOnly)
                    .disabled(model.prefs.size == ReaderMath.sizes.count - 1)
            }
            .buttonStyle(.bordered)
            Picker("Line Spacing", selection: $model.prefs.spacing) {
                ForEach(ReaderPrefs.Spacing.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Layout", selection: $model.prefs.layout) {
                Text("Pages").tag(ReaderPrefs.Layout.pages)
                Text("Scroll").tag(ReaderPrefs.Layout.scroll)
            }
            .pickerStyle(.segmented)
        }
        .padding(Spacing.s4)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - The doors

/// Read (PLAYS-DESIGN §2.7 rule 1): opens the script reader on a play. A full-screen cover on iPhone and iPad,
/// its own window on the Mac. It needs no account, no part, no microphone.
struct ReadButton: View {
    let scriptID: String
    var line: String?
    @Environment(AppStore.self) private var app
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    var body: some View {
        Button { open() } label: { ActionLabel(title: "Read", systemImage: "book") }
            .pageAction()
            .accessibilityIdentifier("read-button")
    }

    private func open() {
        #if os(macOS)
        openWindow(id: ReaderWindow_macOS.id, value: scriptID)
        #else
        app.reading = ReaderTarget(scriptID: scriptID, line: line)
        #endif
    }
}

/// The book button on a Record tile's corner.
struct ReadTileButton: View {
    let scriptID: String
    let title: String
    @Environment(AppStore.self) private var app
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    var body: some View {
        Button {
            #if os(macOS)
            openWindow(id: ReaderWindow_macOS.id, value: scriptID)
            #else
            app.reading = ReaderTarget(scriptID: scriptID)
            #endif
        } label: {
            Image(systemName: "book.fill")
                .font(TypeRamp.body)
                .foregroundStyle(Color.brandOnPrimary)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.brandPrimary))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(2)
        .accessibilityLabel("Read \(title)")
        .accessibilityIdentifier("tile-read")
    }
}

#if os(macOS)
/// A script is a window (macOS-DESIGN §4.7), one per play, restored with the window.
struct ReaderWindow_macOS: View {
    static let id = "reader"
    let scriptID: String

    var body: some View {
        ScriptReaderView(scriptID: scriptID)
            .frame(minWidth: 520, minHeight: 480)
    }
}

/// The Reader menu: every key of macOS-DESIGN §4.7, for the focused reader window; disabled, never hidden, with none.
struct ReaderCommands_macOS: Commands {
    @FocusedValue(\.reader) private var reader

    var body: some Commands {
        CommandMenu("Reader") {
            Button("Next Page") { reader?.turn(1) }.keyboardShortcut(.rightArrow, modifiers: []).disabled(reader == nil)
            Button("Previous Page") { reader?.turn(-1) }.keyboardShortcut(.leftArrow, modifiers: []).disabled(reader == nil)
            Button("Page Down") { reader?.turn(1) }.keyboardShortcut(.pageDown, modifiers: []).disabled(reader == nil)
            Button("Page Up") { reader?.turn(-1) }.keyboardShortcut(.pageUp, modifiers: []).disabled(reader == nil)
            Button("Turn Page") { reader?.turn(1) }.keyboardShortcut(.space, modifiers: []).disabled(reader == nil)
            Button("Turn Page Back") { reader?.turn(-1) }.keyboardShortcut(.space, modifiers: .shift).disabled(reader == nil)
            Button("First Page") { reader?.turnToEdge(last: false) }.keyboardShortcut(.home, modifiers: []).disabled(reader == nil)
            Button("Last Page") { reader?.turnToEdge(last: true) }.keyboardShortcut(.end, modifiers: []).disabled(reader == nil)
            Divider()
            Button("My Next Line") { reader?.nextMine(1) }.keyboardShortcut("j", modifiers: []).disabled(reader?.part == nil)
            Button("My Previous Line") { reader?.nextMine(-1) }.keyboardShortcut("k", modifiers: []).disabled(reader?.part == nil)
            Divider()
            Button("Bigger Text") { reader?.bigger() }.keyboardShortcut("+", modifiers: .command).disabled(reader == nil)
            Button("Smaller Text") { reader?.smaller() }.keyboardShortcut("-", modifiers: .command).disabled(reader == nil)
            Button("Default Text Size") { reader?.resetSize() }.keyboardShortcut("0", modifiers: .command).disabled(reader == nil)
        }
    }
}
#endif
#endif
