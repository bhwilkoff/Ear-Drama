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
    /// The studio attached (PLAYS-DESIGN §2.9): its part is "I'm playing", its lines are unbreakable on the page.
    var studio: StudioModel?
    /// The read-along (PLAYS-DESIGN §2.11): a production's listen-through, the reader following the line heard.
    var along: AlongModel?
    /// The line heard, lit on the page, and whether Back to the Line is offered.
    private(set) var alongLine: Int?
    private(set) var backToLine = false
    @ObservationIgnored private var follow = ReadAlong.Follow()
    /// A launch door's sheet and page, each taken once (DEBUG doors only).
    var doorSheet: String?
    @ObservationIgnored private var doorPage: Int?
    /// How many lines the scroller shows, so a turn in Scroll moves about a screen.
    @ObservationIgnored private var visibleCount = 8

    // Marks (PLAYS-DESIGN §2.10): the script's marks on this device, never synced; ReaderMarks.swift has the verbs.
    var marks: [Mark] = []
    /// Marks a revision could not place: kept as stored, listed as Not Placed.
    var lostMarks: [Mark] = []
    var showMarks = true {
        didSet {
            guard showMarks != oldValue else { return }
            if !showMarks { inkMode = false }
            MarkStore.savePrefs(show: showMarks, hue: markHue, defaults)
            relayout(keep: position)
        }
    }
    var markHue = MarkHue.all[0]
    // Pencil ink (PLAYS-DESIGN §2.10 rule 1; InkCore.swift, ReaderInk.swift): per line, in block units.
    var inks: [String: LineInk] = [:]
    /// Ink a revision could not place: kept as stored, listed as Not Placed.
    var lostInks: [LineInk] = []
    /// Ink mode (iPad): the Pencil draws on the page; a finger still turns pages.
    var inkMode = false {
        didSet {
            guard inkMode != oldValue else { return }
            if inkMode {
                clearSelection()
                markTarget = nil
                if !showMarks { showMarks = true }
            }
        }
    }
    /// Counts every change to the ink (the page image is cached by it) and, apart, the changes the canvas did not make.
    var inkVersion = 0
    var inkEpoch = 0
    @ObservationIgnored let inkStore = InkStore()
    @ObservationIgnored var inkImages: [String: InkImageBox] = [:]
    #if os(iOS)
    @ObservationIgnored lazy var inkTools = InkTools()
    #endif
    @ObservationIgnored var inkFinger = false
    /// The selected words, a range of the page string, and the word the selection grows from.
    var selection: NSRange?
    @ObservationIgnored var selectionAnchor: NSRange?
    @ObservationIgnored var suppressTap = false
    @ObservationIgnored var dragStart: Int?
    /// A tapped mark (its popover), and a Beat or Note being written.
    var markTarget: MarkTarget?
    /// The part whose device voice the studio's ring opened the picker for.
    var castingPart: PartID?
    var compose: MarkCompose?
    var markNotice: String?
    /// What the last Delete took, for the Undo bar.
    var removedMarks: [Mark] = []
    @ObservationIgnored var undoManager: UndoManager?
    @ObservationIgnored let markStore = MarkStore()
    @ObservationIgnored var removedTask: Task<Void, Never>?

    @ObservationIgnored private var build: Task<ReaderLayout, any Error>?
    @ObservationIgnored private var kick: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored let defaults: UserDefaults
    /// The play's own cast (`s:<script>`): the Voices sheet edits it and Hear the Cast reads through it (§2.8).
    @ObservationIgnored let voices: VoiceCastModel
    /// Hear the Cast: the script read aloud from the first line on the page, the page following each line.
    @ObservationIgnored private(set) lazy var table = TableRead(
        script: script, speaker: SystemListenSpeaker(cast: voices.cast),
        onLine: { [weak self] id in if let id { self?.go(to: id) } })

    init(script: PlayScript, startLine: String?, door: ReaderDoor? = nil, defaults: UserDefaults = .standard,
         production: String? = nil, studioPart: PartID? = nil) {
        self.script = script
        self.defaults = defaults
        // The studio reads the production's cast (§2.8 rule 2); the reader alone, the play's.
        self.voices = VoiceCastModel(cast: production.map { .production($0, script: script) } ?? .script(script))
        let structure = ScriptStructure(script)
        self.structure = structure
        var prefs = ReaderStore.prefs(defaults)
        if let json = door?.prefs { prefs = ReaderPrefs.decode(json) }
        self.prefs = prefs
        let saved = ReaderStore.position(for: script.id, defaults)
        let index = startLine.flatMap { structure.indexByID[$0] } ?? saved?.line.flatMap { structure.indexByID[$0] } ?? 0
        position = index
        if door?.resetMarks == true { try? markStore.save(scriptID: script.id, title: nil, []) }
        let placed = MarksCore.place(script, markStore.load(script.id))
        marks = placed.placed
        lostMarks = placed.lost
        let markPrefs = MarkStore.prefs(defaults)
        showMarks = markPrefs.show
        markHue = markPrefs.hue
        if placed.changed { persistMarks() }
        if door?.resetMarks == true { try? inkStore.save(scriptID: script.id, title: nil, []) }
        let inkPlaced = InkCore.place(script, inkStore.load(script.id))
        inks = Dictionary(inkPlaced.placed.map { ($0.line, $0) }, uniquingKeysWith: { a, _ in a })
        lostInks = inkPlaced.lost
        if inkPlaced.changed { persistInks() }
        inkFinger = door?.inkFinger == true
        if door?.inkDemo == true { seedDemoInk(from: index) }
        inkMode = door?.ink == true
        if let name = door?.part ?? saved?.part, script.castParts.contains(where: { $0.id.rawValue == name && $0.id.isSpeaking }) {
            let id = PartID(rawValue: name)
            part = id
            mine = Set(ScriptReading.lineIndexes(of: id, in: script))
        }
        if let studioPart {
            part = studioPart
            mine = Set(ScriptReading.lineIndexes(of: studioPart, in: script))
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
        let keep = studio?.part.roleName
        let foot = keep == nil ? 0 : ReaderLayout.footRoom
        let height = (area.height - 2 * Self.margin - ReaderLayout.headRoom - foot).rounded(.down)
        let script = script, structure = structure
        let points = showMarks ? marks.filter { !$0.isSpan } : []
        kick = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled else { return }
            let work = Task.detached(priority: .userInitiated) {
                try ReaderLayout.build(script, structure: structure, style: style, pageSize: CGSize(width: width, height: height),
                                       keepRole: keep, points: points)
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
        selection = nil
        selectionAnchor = nil
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

    /// The listen-through reached `id` (nil when it ends): light it, and turn to it unless the person turned away.
    func alongHeard(_ id: String?) {
        let step = follow.line(id)
        alongLine = id.flatMap { structure.indexByID[$0] }
        backToLine = step.back
        if step.turn, let id { go(to: id) }
    }

    /// A touch on the page: the read-along stops turning it.
    func userMoved() {
        guard along != nil, follow.following else { return }
        follow.away()
    }

    func backToTheLine() {
        backToLine = false
        if let id = follow.back() { go(to: id) }
    }

    func resumeFollowing() { _ = follow.back(); backToLine = false }

    func turn(_ delta: Int) {
        userMoved()
        if prefs.layout == .scroll {
            go(toIndex: min(max(0, position + delta * max(1, visibleCount - 1)), script.lines.count - 1))
            return
        }
        guard let layout, let s = spread else { return }
        let to = ReaderMath.turn(s * per, delta: delta, per: per, count: layout.pageCount) / per
        move(toSpread: to)
    }

    func turnToEdge(last: Bool) {
        userMoved()
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
        if suppressTap { return }
        if selection != nil { clearSelection(); return }
        if markTapped(at: point) { return }
        if studioTap(point) { return }
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
        if let studio {
            if studio.studio.move(direction), let id = studio.studio.current { go(to: id) }
            return
        }
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
        guard hide, let layout, let at = pagePoint(point) else {
            peeked = []
            return
        }
        if let line = layout.line(at: at.local, page: at.page), mine?.contains(line) == true { peek(line); return }
        peeked = []
    }

    /// The page under a point of the spread, and the point in that page's text column (top-left origin).
    func pagePoint(_ point: CGPoint) -> (page: Int, local: CGPoint)? {
        guard let layout, let s = spread else { return nil }
        let pageW = layout.pageSize.width
        let total = CGFloat(per) * pageW + CGFloat(per - 1) * Self.gutter
        let left = (area.width - total) / 2
        let viewH = layout.pageSize.height + ReaderLayout.headRoom + pageFoot
        let top = (area.height - viewH) / 2 + ReaderLayout.headRoom
        for k in 0..<per {
            let page = s * per + k
            guard page < layout.pageCount else { continue }
            let x0 = left + CGFloat(k) * (pageW + Self.gutter)
            let local = CGPoint(x: point.x - x0, y: point.y - top)
            guard local.x >= -8, local.x <= pageW + 8 else { continue }
            return (page, local)
        }
        return nil
    }

    /// The room under a page's text: the studio keeps 8 pt for the current line's outline.
    var pageFoot: CGFloat { layout?.keepRole == nil ? 0 : ReaderLayout.footRoom }

    // MARK: The studio on the page

    /// The take state of each of my lines on a page (the studio's marks).
    func studioTakes(onPage page: Int) -> [Int: StudioCore.LineState] {
        guard let studio, let layout, let mine else { return [:] }
        var out: [Int: StudioCore.LineState] = [:]
        for i in layout.lines(onPage: page) where mine.contains(i) { out[i] = studio.studio.lineState(script.lines[i].id) }
        return out
    }

    /// Each other part's speech line without a usable take, on a page: its voice's short name, for the ring after the
    /// speaker's name (§2.9 rule 3a).
    func studioRings(onPage page: Int) -> [ReaderLayout.RingKey: String] {
        guard let studio, let layout, let me = studio.part.roleName else { return [:] }
        var said: [String: String] = [:]
        var out: [ReaderLayout.RingKey: String] = [:]
        for i in layout.lines(onPage: page) {
            let line = script.lines[i]
            guard line.kind == .speech, let role = line.role, role != me,
                  studio.session.production.usableTake(for: line.id) == nil else { continue }
            if said[role] == nil { said[role] = VoiceChipText.short(voices.resolve(.role(role))) }
            out[ReaderLayout.RingKey(line: i, role: role)] = said[role]
        }
        return out
    }

    /// A tap on my line's name or its mark opens its take list; elsewhere on one of my lines it becomes current. A tap on
    /// another part's ring opens that part's voice picker. Either way the page does not turn (§2.9 rule 2).
    private func studioTap(_ point: CGPoint) -> Bool {
        guard let studio, let me = part?.roleName, let layout, let at = pagePoint(point) else { return false }
        let up = CGPoint(x: at.local.x - ReaderLayout.inset, y: layout.pageSize.height - at.local.y)
        if let ring = layout.ringSpots(page: at.page, rings: studioRings(onPage: at.page)).first(where: { $0.hit.contains(up) }) {
            castingPart = .role(ring.key.role)
            return true
        }
        if let spot = layout.takeMarkSpots(page: at.page, role: me, takes: studioTakes(onPage: at.page)).first(where: { $0.hit.contains(up) }) {
            studio.openTakes(script.lines[spot.line].id)
            return true
        }
        if let line = layout.line(at: at.local, page: at.page), mine?.contains(line) == true {
            studio.studio.select(script.lines[line].id)
            return true
        }
        return false
    }

    /// The studio has started: Space and the other keys are the studio's.
    var studioActive: Bool { studio?.started == true }

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

    func hearTheCast() {
        if table.isPlaying {
            table.stop()
        } else {
            let from = position
            Task { await table.play(from: from) }
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
    /// The studio attached: the production's own script, the part, the recorder (PLAYS-DESIGN §2.9).
    var studio: StudioTarget?
    var dock: AnyView?
    var controller: ReaderController?
    @Environment(PlaysLibrary.self) private var plays
    @Environment(AppStore.self) private var app
    @State private var script: PlayScript?
    @State private var model: ReaderModel?
    @State private var studioModel: StudioModel?
    @State private var failed = false

    var body: some View {
        Group {
            if let model {
                ReaderScreen(model: model, dock: dock, studio: studioModel)
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
        // The loader, not the reader, ends what plays: the reader is rebuilt when the studio moves between the dock and
        // the pane (a fold, a rotation, a resize), and a take or a cast reading goes on through that (Decision 080).
        .onDisappear { studioModel?.end(); model?.along?.stop(); model?.table.stop() }
    }

    private func load() async {
        failed = false
        if let target = studio, target.isDrama {
            let play: FinishedPlay?
            if let known = FinishedStore.shared.plays.first(where: { $0.id == target.production }) { play = known }
            else { play = try? await WorkerOpenPlays(api: .shared).finished(id: target.production) }
            guard let play, let found = try? await plays.script(id: play.scriptID),
                  await FinishedListen.canFollow(play, script: found) else {
                failed = true
                return
            }
            let made = ReaderModel(script: found, startLine: startLine, door: app.readerDoor)
            made.along = AlongModel(play: play, script: found)
            controller?.model = made
            model = made
            return
        }
        if let target = studio, !target.isAlong {
            // The production's own copy of the script, never the library's, so line ids match the takes.
            guard let s = StudioModel(target: target, plays: plays, line: startLine) else {
                failed = true
                return
            }
            let made = ReaderModel(script: s.script, startLine: s.studio.current, door: app.readerDoor,
                                   production: target.production, studioPart: target.partID)
            made.studio = s
            s.studio.onFollow = { [weak made] id in made?.go(to: id) }
            controller?.model = made
            studioModel = s
            model = made
            return
        }
        if let target = studio, target.isAlong {
            guard let production = plays.store.production(target.production), let found = plays.castScript(for: production) else {
                failed = true
                return
            }
            let made = ReaderModel(script: found, startLine: startLine, door: app.readerDoor, production: target.production)
            made.along = AlongModel(production: production, script: found, plays: plays)
            controller?.model = made
            model = made
            return
        }
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
    var studio: StudioModel?
    @Environment(AppStore.self) private var app
    @Environment(PlaysLibrary.self) private var plays
    @Environment(AudioPlayer.self) private var player
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @Environment(\.undoManager) private var undoManager
    @ScaledMetric(relativeTo: .body) private var body17: CGFloat = 17
    @State private var sheet: ReaderSheet?
    @State private var showContents = false
    /// The reader holds 860 pt: the studio stands beside the script (§2.9 rule 7), measured, never the idiom.
    @State private var wide = false

    var body: some View {
        #if os(macOS)
        NavigationSplitView {
            VStack(spacing: 0) {
                ReaderContents(model: model)
                Divider()
                MarksNotebook(model: model)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            reader
        }
        .modifier(StudioInspector(studio: studio, voices: model.voices))
        .focusedSceneValue(\.reader, model)
        .focusedSceneValue(\.studio, studio)
        .onChange(of: studio?.finished ?? false) { _, done in if done { dismiss() } }
        #else
        arranged
            .onGeometryChange(for: Bool.self) { $0.size.width >= ReaderMath.spreadMin } action: { wide = $0 }
            .onChange(of: studio?.finished ?? false) { _, done in if done { app.reading = nil } }
            .sheet(item: Binding(get: { sheet == .text ? nil : sheet }, set: { sheet = $0 })) { which in
                switch which {
                case .contents: ReaderContents(model: model, dismiss: { sheet = nil })
                        .presentationDetents([.medium, .large])
                case .search: ReaderSearch(model: model, dismiss: { sheet = nil })
                        .presentationDetents([.medium, .large])
                case .text: EmptyView()
                case .voices: ReaderVoices(model: model.voices, script: model.script, dismiss: { sheet = nil })
                        .presentationDetents([.medium, .large])
                case .marks: MarksNotebook(model: model, dismiss: { sheet = nil })
                        .presentationDetents([.medium, .large])
                }
            }
        #endif
    }

    #if os(iOS)
    /// The script and, once the reader holds 860 pt with the studio attached, the studio's pane beside it: an
    /// `ArrangementView` on iOS 27.1 (the open iPhone Duo), a plain side-by-side before it.
    @ViewBuilder private var arranged: some View {
        if let studio, wide {
            #if compiler(>=6.4)
            if #available(iOS 27.1, *) {
                ArrangementView { reader } secondary: { pane(studio) }
                    .arrangementViewStyle(.split.axes(.horizontal))
            } else {
                sideBySide(studio)
            }
            #else
            sideBySide(studio)
            #endif
        } else {
            reader
        }
    }

    private func sideBySide(_ studio: StudioModel) -> some View {
        HStack(spacing: 0) {
            reader
            Divider()
            pane(studio).frame(width: 360)
        }
    }

    private func pane(_ studio: StudioModel) -> some View {
        NavigationStack { StudioPanel(model: studio, voices: model.voices, full: true) }
            .modifier(AvoidsFold())
    }
    #endif

    private var reader: some View {
        VStack(spacing: 0) {
            // Held to the safe area: the Duo's strip and a notch are inside it, and a scroll view draws under them.
            GeometryReader { _ in
                Group {
                    if model.prefs.layout == .pages { pager } else { scroller }
                }
            }
            .clipped()
            if model.table.isPlaying, let line = model.table.line { hearing(line) }
            if let along = model.along, along.deviceVoice,
               let line = model.script.lines.first(where: { $0.id == along.lineID }) { hearing(line) }
            if model.backToLine { backToLineButton() }
            if let dock { dock }
            #if os(iOS)
            if let studio, !wide { StudioDock(model: studio).modifier(AvoidsFold()) }
            #endif
            bottomBar
        }
        .background(Color.brandBackground)
        .navigationTitle(model.script.title)
        .modifier(ReaderSubtitle(text: model.placeLine))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { toolbar }
        .sheet(item: $model.compose) { c in MarkComposeSheet(model: model, compose: c) }
        .sheet(item: $model.castingPart) { part in
            #if os(iOS)
            NavigationStack {
                VoicePickerScreen(model: model.voices, script: model.script, part: part) { model.castingPart = nil }
                    .navigationTitle(part.title)
                    .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium, .large])
            #else
            VStack(spacing: 0) {
                VoicePickerForm(model: model.voices, script: model.script, part: part)
                Divider()
                HStack {
                    Spacer()
                    Button("Done") { model.castingPart = nil }.keyboardShortcut(.defaultAction)
                }
                .padding(Spacing.s3)
            }
            .frame(width: 360, height: 520)
            #endif
        }
        .overlay(alignment: .bottom) { MarkUndoBar(model: model) }
        .onChange(of: undoManager, initial: true) { _, u in model.undoManager = u }
        .onChange(of: body17, initial: true) { _, size in model.base = size }
        .repaintsOnVoiceChange(model.voices)
        .onChange(of: model.along?.lineID) { _, id in model.alongHeard(id) }
        .onChange(of: studio?.studio.current) { _, id in if let id { model.go(to: id) } }
        .onChange(of: studio?.listen.current?.lineID) { _, id in if let id { model.go(to: id) } }
        #if os(iOS)
        .onChange(of: wide) { _, now in if now { studio?.sheet = false } }
        .sheet(isPresented: Binding(get: { (studio?.sheet ?? false) && !wide }, set: { studio?.sheet = $0 })) {
            if let studio {
                NavigationStack { StudioPanel(model: studio, voices: model.voices, close: { studio.sheet = false }) }
                    .presentationDetents([.medium, .large])
            }
        }
        #endif
        .onAppear {
            if app.readerDoor?.studio == true, studio == nil, let part = model.part {
                app.readerDoor?.studio = false
                record(part)
            }
            if app.readerDoor?.hear == true {
                app.readerDoor = nil
                Task { try? await Task.sleep(for: .seconds(1)); model.hearTheCast() }
            }
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
            case .voices: ReaderVoices(model: model.voices, script: model.script).frame(width: 380, height: 460)
            case .contents, .marks: EmptyView()
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
            // Three controls: a popover on its button at regular width, the medium sheet on a phone (iOS-DESIGN §3.6c;
            // on the open Duo the sheet stood 650 pt wide and two-thirds empty).
            Button { sheet = .text } label: { Label("Text", systemImage: "textformat.size") }
                .popover(isPresented: Binding(get: { sheet == .text }, set: { if !$0, sheet == .text { sheet = nil } })) {
                    ReaderTextSettings(model: model)
                        .frame(idealWidth: 340)
                        .fixedSize(horizontal: false, vertical: true)
                        .presentationCompactAdaptation(.sheet)
                        .presentationDetents([.medium])
                }
            Button { sheet = .voices } label: { Label("Voices", systemImage: "person.wave.2") }
            Button { sheet = .marks } label: { Label("Marks", systemImage: "bookmark") }
            if ReaderModel.canDrawInk, model.prefs.layout == .pages {
                Toggle(isOn: $model.inkMode) { Label("Ink", systemImage: "pencil.tip") }
                    .toggleStyle(.button)
                    .accessibilityIdentifier("ink-toggle")
            }
        }
        #else
        ToolbarItemGroup(placement: .primaryAction) {
            if let studio {
                Button { studio.inspector.toggle() } label: { Label("Studio", systemImage: "slider.horizontal.3") }
            }
            Button { sheet = .search } label: { Label("Search", systemImage: "magnifyingglass") }
                .keyboardShortcut("f", modifiers: .command)
            Button { sheet = .text } label: { Label("Text", systemImage: "textformat.size") }
            Button { sheet = .voices } label: { Label("Voices", systemImage: "person.wave.2") }
        }
        #endif
    }

    @ViewBuilder private var bottomBar: some View {
        if let studio { studioBar(studio) } else if let along = model.along { alongBar(along) } else { readerBar }
    }

    /// Read along (§2.11): Listen Through is the transport; Back to the Line shows after a touch turned the page away.
    private func alongBar(_ along: AlongModel) -> some View {
        HStack(spacing: Spacing.s3) {
            Button { model.resumeFollowing(); along.toggle(from: model.position, player: player, muted: app.isMuted) } label: {
                Label(along.isRunning ? "Stop" : "Listen Through", systemImage: along.isRunning ? "stop.fill" : "play.fill")
            }
            .labelStyle(HearTheCastLabelStyle())
            .accessibilityIdentifier("reader-listen-through")
            Spacer(minLength: 0)
            Text(verbatim: model.pageLabel)
                .lineLimit(1)
                .fixedSize()
                .layoutPriority(1)
                .font(TypeRamp.tabular)
                .foregroundStyle(Color.brandTextMuted)
                .accessibilityIdentifier("reader-page-label")
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s2)
        .background(Color.brandSurface)
    }

    private func backToLineButton() -> some View {
        Button { model.backToTheLine() } label: { Label("Back to the Line", systemImage: "arrow.uturn.backward") }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.s1)
            .background(Color.brandSurface)
            .accessibilityIdentifier("reader-back-to-line")
    }

    /// In the studio the bar keeps Hide My Lines and the page count; the dock is the transport, and the Studio button
    /// opens the sheet (on a phone the review hides both so its three buttons fit at 320 pt).
    private func studioBar(_ studio: StudioModel) -> some View {
        HStack(spacing: Spacing.s3) {
            Toggle(isOn: $model.hide) { Label("Hide My Lines", systemImage: "eye.slash") }
                .toggleStyle(.button)
                .labelStyle(.iconOnly)
                .accessibilityIdentifier("reader-hide")
            #if os(iOS)
            if !wide, !(studio.inReview) {
                Button { studio.sheet = true } label: { Label("Studio", systemImage: "slider.horizontal.3") }
                    .accessibilityIdentifier("studio-button")
            }
            #endif
            Spacer(minLength: 0)
            if wide || !studio.inReview {
                Text(verbatim: model.pageLabel)
                    .lineLimit(1)
                    .fixedSize()
                    .font(TypeRamp.tabular)
                    .foregroundStyle(Color.brandTextMuted)
                    .accessibilityIdentifier("reader-page-label")
            }
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s2)
        .background(Color.brandSurface)
    }

    /// Record (§2.9 rule 1): continue the part where it records, else take it, else a new production; the studio opens.
    private func record(_ part: PartID) {
        guard let target = StudioOpen.resolve(plays, script: model.script, part: part) else { return }
        let line = model.script.lines.indices.contains(model.position) ? model.script.lines[model.position].id : nil
        StudioOpen.open(target, scriptID: model.script.id, line: line, app: app, openWindow: openWindow)
    }

    private var readerBar: some View {
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
            Button { model.hearTheCast() } label: {
                Label(model.table.isPlaying ? "Stop" : "Hear the Cast",
                      systemImage: model.table.isPlaying ? "stop.fill" : "play.fill")
            }
            .labelStyle(HearTheCastLabelStyle())
            .accessibilityIdentifier("reader-hear-cast")
            if let part = model.part {
                Button { record(part) } label: { Label("Record", systemImage: "mic") }
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("reader-record")
            }
            Spacer(minLength: 0)
            Text(verbatim: model.pageLabel)
                .lineLimit(1)
                .fixedSize()
                .layoutPriority(1)
                .font(TypeRamp.tabular)
                .foregroundStyle(Color.brandTextMuted)
                .accessibilityIdentifier("reader-page-label")
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s2)
        .background(Color.brandSurface)
    }

    /// One line while the cast reads: a device voice never passes as a person (§5 rule 3).
    private func hearing(_ line: ScriptLine) -> some View {
        Label("Device voice \u{00B7} \(line.role ?? line.part.title)", systemImage: "waveform")
            .font(TypeRamp.caption)
            .foregroundStyle(Color.brandSecondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.s4)
            .padding(.vertical, Spacing.s1)
            .background(Color.brandSurface)
            .accessibilityIdentifier("reader-hearing")
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
        .onScrollPhaseChange { _, phase in if phase == .interacting { model.userMoved() } }
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
        .onScrollPhaseChange { _, phase in if phase == .interacting { model.userMoved() } }
        .onScrollTargetVisibilityChange(idType: String.self, threshold: 0.5) { model.visible($0) }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { model.areaChanged($0) }
        .task { model.scroll.scrollTo(id: model.script.lines[model.position].id, anchor: .top) }
        #if os(iOS)
        .modifier(ReaderKeys(model: model))
        #endif
    }
}

/// Icon only on a phone, the words from regular width.
private struct HearTheCastLabelStyle: LabelStyle {
    @Environment(\.horizontalSizeClass) private var sizeClass

    func makeBody(configuration: Configuration) -> some View {
        #if os(macOS)
        Label(configuration)
        #else
        if sizeClass == .regular { Label(configuration) } else { configuration.icon }
        #endif
    }
}

private enum ReaderSheet: String, Identifiable {
    case contents, search, text, voices, marks
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
                               KeyEquivalent("j"), KeyEquivalent("k"), KeyEquivalent("r"), .return, .escape,
                               KeyEquivalent("h"), KeyEquivalent("u"), KeyEquivalent("/"), KeyEquivalent("p"),
                               KeyEquivalent("b"), KeyEquivalent("n")]) { press in
                // With words selected the mark keys come first: H, U, /, P, B, N; Esc lets go.
                if model.selection != nil {
                    if press.key == .escape { model.clearSelection(); return .handled }
                    if let kind = ReaderModel.markKey(press.key) { model.markSelection(kind); return .handled }
                }
                // The studio's keys come first (§2.9 rule 8): Space records, stops or cancels; R again; Return keeps.
                if model.studioActive, let studio = model.studio {
                    switch press.key {
                    case .space: studio.primary(); return .handled
                    case KeyEquivalent("r"): studio.again(); return .handled
                    case .return: studio.keep(); return .handled
                    default: break
                    }
                }
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
            .modifier(MarkSelecting(model: model, spread: spread))
            .popover(item: Binding(get: { model.markTarget.flatMap { $0.spread == spread ? $0 : nil } }, set: { model.markTarget = $0 }),
                     attachmentAnchor: .rect(.rect(model.markTarget?.rect ?? .zero)), arrowEdge: .top) { target in
                MarkPopover(model: model, target: target)
                    #if os(iOS)
                    .presentationCompactAdaptation(.popover)
                    #endif
            }
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
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        var marks = ReaderLayout.Marks(role: model.part?.roleName, hide: model.hide, peeked: model.peeked)
        let takes = model.studioTakes(onPage: page)
        let rings = model.studioRings(onPage: page)
        marks.marks = model.visibleMarks
        marks.lineIndex = model.structure.indexByID
        marks.selection = model.selection
        marks.along = model.alongLine
        if let studio = model.studio {
            marks.current = studio.studio.current.flatMap { model.structure.indexByID[$0] }
            marks.outline = Self.outline(studio)
            marks.takes = takes
            marks.rings = rings
        }
        let scheme = scheme
        let ink = model.inkImage(layout, page: page, dark: scheme == .dark, scale: displayScale)
        let scale = displayScale
        return Canvas { context, size in
            // The token colors are dynamic: resolved against the scheme the page is in, not the thread's appearance.
            func cg(_ color: Color) -> CGColor { Self.cgColor(color, dark: scheme == .dark) }
            let muted = cg(Color.brandTextMuted)
            let theme = ReaderLayout.Theme(ink: cg(Color.brandText), muted: muted,
                                           hues: PlayScript.partHues.map { Color.genre($0).map(cg) ?? muted },
                                           background: cg(Color.brandBackground), block: cg(Color.brandSurfaceAlt),
                                           record: cg(StudioPalette.record), warning: cg(Color.semanticWarning),
                                           markHues: Dictionary(uniqueKeysWithValues: MarkHue.all.map { ($0, cg(Color.mark($0))) }),
                                           selection: cg(Color.brandSecondary).copy(alpha: 0.30))
            context.withCGContext { layout.draw(page: page, in: $0, theme: theme, marks: marks) }
            if let ink { context.draw(Image(decorative: ink, scale: scale), in: CGRect(origin: .zero, size: size)) }
        }
        .frame(width: layout.pageSize.width, height: layout.pageSize.height + ReaderLayout.headRoom + model.pageFoot, alignment: .top)
        #if os(iOS)
        .overlay { InkOverlay(model: model, layout: layout, page: page) }
        #endif
        .accessibilityChildren {
            ForEach(Array(layout.lines(onPage: page)), id: \.self) { i in
                if let state = takes[i], let studio = model.studio {
                    Button("\(Self.spoken(model.script.lines[i])). \(StudioCore.spoken(state))") {
                        studio.openTakes(model.script.lines[i].id)
                    }
                } else if model.isHidden(i) {
                    Button("Show line") { model.peek(i) }
                } else {
                    Text(verbatim: Self.spoken(model.script.lines[i]))
                        .modifier(MarkActions(model: model, line: i))
                }
                if let role = model.script.lines[i].role, rings[ReaderLayout.RingKey(line: i, role: role)] != nil {
                    Button("Device voice for \(PartID.role(role).title): \(VoiceChipText.title(model.voices.resolve(.role(role))))") {
                        model.castingPart = .role(role)
                    }
                }
            }
        }
    }

    /// Ink on the current line; dashed record red while a cue leads to it; solid while the microphone is open.
    static func outline(_ studio: StudioModel) -> ReaderLayout.Outline {
        switch studio.session.phase {
        case .listening: .recording
        case let .cue(id, _): studio.session.run != nil || !studio.studio.mine.contains(id) ? .armed : .ink
        default: .ink
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

/// One script line as its own view, keyed by its id (Scroll): the same Ear Drama page as the pages, set in SwiftUI
/// from `PlayPage.layoutOf` (a printed verse line wraps without the pages' hanging indent: `Text` has none).
private struct ReaderLineView: View {
    let model: ReaderModel
    let index: Int
    let size: CGFloat

    private var gutter: Bool {
        let width = min(model.area.width - 2 * ReaderModel.margin, size * 36)
        return width / size >= PlayPage.gutterMinEm
    }

    private var roles: [String] { model.script.roles.map(\.name) }

    private func hueColor(_ role: String) -> Color {
        let h = model.structure.speaking.firstIndex { $0.roleName == role }
        return h.flatMap { $0 < PlayScript.partHues.count ? Color.genre(PlayScript.partHues[$0]) : nil } ?? Color.brandTextMuted
    }

    private var gap: CGFloat { size * 0.7 }

    var body: some View {
        let line = model.script.lines[index]
        VStack(alignment: .leading, spacing: 0) {
            ForEach(model.structure.setAside[index] ?? []) { head in
                heading(head.title, head.level)
            }
            if let head = model.structure.headLines[index] {
                heading(ScriptReading.runsOf(line).map(\.text).joined(), head.level)
            } else if line.kind == .speech, line.parts != nil {
                speechBlocks(line)
            } else {
                block(line)
            }
        }
        .background(model.alongLine == index ? Color.brandText.opacity(0.10) : Color.clear)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.isHidden(index) ? "Show line" : ReaderPageView.spoken(line))
        .accessibilityAddTraits(model.isHidden(index) ? .isButton : [])
    }

    private func heading(_ text: String, _ level: SectionLevel) -> some View {
        Text(verbatim: text)
            .font(.custom(TypeRamp.displayFontName, size: size * (level == .scene ? 1.25 : 1.75)))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, size * 1.4)
            .padding(.bottom, size * 0.6)
    }

    // MARK: A speech

    private func speechBlocks(_ line: ScriptLine) -> some View {
        let layout = PlayPage.layoutOf(line, roles: roles)
        let beside = gutter
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(layout.speeches.enumerated()), id: \.offset) { k, sp in
                speech(line, layout: layout, k: k, sp: sp, beside: beside)
            }
        }
    }

    private func speech(_ line: ScriptLine, layout: PageLine, k: Int, sp: PageSpeech, beside: Bool) -> some View {
        let color = hueColor(sp.role)
        let mine = model.part?.roleName == sp.role
        let name = sp.name?.text ?? sp.role
        let hidden = model.isHidden(index) && mine
        let cueFrom = cueStart(line, layout: layout, k: k)
        let words = VStack(alignment: .leading, spacing: size * 0.1) {
            ForEach(Array(sp.rows.enumerated()), id: \.offset) { r, row in
                if row.cue {
                    cue(row)
                } else {
                    Text(attributed(row, hidden: hidden, color: color, cueFrom: r == sp.rows.count - 1 ? cueFrom : nil))
                        .lineSpacing(size * (model.prefs.lineHeight - 1.2))
                        .padding(.leading, layout.verse && row.indent ? size * 2.5 : 0)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        let title = Text(verbatim: name).font(.system(size: size * 0.9, weight: .semibold)).kerning(size * 0.02).foregroundStyle(color)
        return Group {
            if beside, !sp.rows.isEmpty, !(sp.rows.first?.cue ?? false) {
                HStack(alignment: .firstTextBaseline, spacing: size) {
                    title.frame(width: size * 8.5, alignment: .trailing)
                    words
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    title
                    words
                }
            }
        }
        .padding(.vertical, size * 0.3)
        .padding(.horizontal, 14)
        .background(mine ? color.opacity(0.10) : Color.clear)
        .overlay(alignment: .leading) { if mine { Rectangle().fill(color).frame(width: 3) } }
        .padding(.horizontal, -14)
        .padding(.bottom, gap - size * 0.6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { if mine, model.hide { model.peek(index) } }
    }

    /// Where the cue begins in this speech's last said run, when the next speaker is the part being played.
    private func cueStart(_ line: ScriptLine, layout: PageLine, k: Int) -> (at: Int, color: Color)? {
        guard let me = model.part?.roleName else { return nil }
        let sp = layout.speeches[k]
        guard sp.role != me else { return nil }
        let next: String?
        if k + 1 < layout.speeches.count {
            next = layout.speeches[k + 1].role
        } else {
            var j = index + 1
            var found: String?
            while j < model.script.lines.count, found == nil {
                let l = model.script.lines[j]
                if l.kind == .speech, l.parts != nil { found = PlayPage.layoutOf(l, roles: roles).speeches.first?.role }
                j += 1
            }
            next = found
        }
        guard next == me else { return nil }
        guard let last = sp.rows.last(where: { !$0.cue })?.runs.last(where: \.said) else { return nil }
        return (last.at + PlayPage.cueTail(last.text), hueColor(me))
    }

    private func cue(_ row: PageRow) -> some View {
        HStack(spacing: size * 0.35) {
            Image(systemName: "speaker.wave.2")
            Text(verbatim: row.runs.map(\.text).joined(separator: " ").uppercased()).kerning(size * 0.05)
        }
        .font(.system(size: size * 0.8125, weight: .semibold))
        .foregroundStyle(Color.brandText)
        .padding(.horizontal, size * 0.5)
        .padding(.vertical, size * 0.15)
        .background(Color.brandSurfaceAlt, in: RoundedRectangle(cornerRadius: 4))
        .padding(.vertical, size * 0.15)
    }

    private func attributed(_ row: PageRow, hidden: Bool, color: Color, cueFrom: (at: Int, color: Color)?) -> AttributedString {
        var out = AttributedString()
        func add(_ text: String, _ font: Font, _ ink: Color, hide: Bool = false, underline: Color? = nil) {
            guard !text.isEmpty else { return }
            var run = AttributedString(text)
            run.font = font
            run.foregroundColor = hide ? .clear : ink
            if hide { run.backgroundColor = color.opacity(0.3) }
            if let underline {
                run.underlineStyle = Text.LineStyle(pattern: .solid, color: underline)
            }
            out.append(run)
        }
        let serif = Font.system(size: size, design: .serif)
        let names = DirectionNames(roles: roles)
        var previous: PageRun?
        for (n, r) in row.runs.enumerated() {
            if let p = previous, p.piece != r.piece, ScriptReading.spaceBetween(p.text, r.text) { add(" ", serif, Color.brandText) }
            previous = r
            if r.said {
                let font = r.kind == .em ? serif.italic() : serif
                if let c = cueFrom, r.at + r.text.utf16.count > c.at {
                    let k = max(0, c.at - r.at)
                    let ns = r.text as NSString
                    add(ns.substring(to: k), font, Color.brandText, hide: hidden)
                    add(ns.substring(from: k), font, Color.brandText, hide: hidden, underline: c.color)
                } else {
                    add(r.text, font, Color.brandText, hide: hidden)
                }
                continue
            }
            let whole = row.runs.filter { $0.piece == r.piece && !$0.said }.map(\.text).joined()
            let open = (n == 0 || row.runs[n - 1].piece != r.piece) && whole.range(of: "^\\s*[(\\[]", options: .regularExpression) == nil
            let close = (n == row.runs.count - 1 || row.runs[n + 1].piece != r.piece)
                && whole.range(of: "[)\\]][.,;:!?]*\\s*$", options: .regularExpression) == nil
            if open { add("(", serif, Color.brandTextMuted) }
            direction(r.text, italic: r.kind != .plain, names: names, add: add)
            if close { add(")", serif, Color.brandTextMuted) }
        }
        return out
    }

    /// A direction's words, a part it names in capitals in that part's hue, upright and strong.
    private func direction(_ raw: String, italic: Bool, names: DirectionNames,
                           add: (String, Font, Color, Bool, Color?) -> Void) {
        let text = PlayPage.drawn(raw)
        let ns = text as NSString
        var last = 0
        let base = Font.system(size: size, design: .serif)
        for m in names.matches(in: text) {
            if m.range.location > last { add(ns.substring(with: NSRange(location: last, length: m.range.location - last)), italic ? base.italic() : base, Color.brandTextMuted, false, nil) }
            let n = ns.substring(with: m.range)
            let known = model.structure.speaking.contains { $0.roleName == n }
            add(n, known ? base.weight(.semibold) : (italic ? base.italic() : base), known ? hueColor(n) : Color.brandTextMuted, false, nil)
            last = m.range.location + m.range.length
        }
        if last < ns.length { add(ns.substring(from: last), italic ? base.italic() : base, Color.brandTextMuted, false, nil) }
    }

    // MARK: A block

    private func block(_ line: ScriptLine) -> some View {
        let layout = PlayPage.layoutOf(line, roles: roles)
        let row = layout.rows.first ?? PageRow(cue: false, indent: false, runs: [])
        let indent = gutter ? size * 9.5 : size * 1.5
        let names = DirectionNames(roles: roles)
        return Group {
            if row.cue {
                cue(row)
            } else {
                Text(blockText(row, names: names))
                    .lineSpacing(size * (model.prefs.lineHeight - 1.2))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.leading, indent)
        .padding(.vertical, size * 0.15)
        .padding(.bottom, gap - size * 0.3)
    }

    private func blockText(_ row: PageRow, names: DirectionNames) -> AttributedString {
        var out = AttributedString()
        func add(_ text: String, _ font: Font, _ ink: Color, _: Bool, _: Color?) {
            var run = AttributedString(text)
            run.font = font
            run.foregroundColor = ink
            out.append(run)
        }
        for r in row.runs { direction(r.text, italic: r.kind == .plain, names: names, add: add) }
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
            // In a studio Space is the record control's (the Recording menu).
            Button("Turn Page") { reader?.turn(1) }.keyboardShortcut(.space, modifiers: []).disabled(reader == nil || reader?.studio != nil)
            Button("Turn Page Back") { reader?.turn(-1) }.keyboardShortcut(.space, modifiers: .shift).disabled(reader == nil)
            Button("First Page") { reader?.turnToEdge(last: false) }.keyboardShortcut(.home, modifiers: []).disabled(reader == nil)
            Button("Last Page") { reader?.turnToEdge(last: true) }.keyboardShortcut(.end, modifiers: []).disabled(reader == nil)
            Divider()
            Button("My Next Line") { reader?.nextMine(1) }.keyboardShortcut("j", modifiers: []).disabled(reader?.part == nil || reader?.studio != nil)
            Button("My Previous Line") { reader?.nextMine(-1) }.keyboardShortcut("k", modifiers: []).disabled(reader?.part == nil || reader?.studio != nil)
            Divider()
            Button("Bigger Text") { reader?.bigger() }.keyboardShortcut("+", modifiers: .command).disabled(reader == nil)
            Button("Smaller Text") { reader?.smaller() }.keyboardShortcut("-", modifiers: .command).disabled(reader == nil)
            Button("Default Text Size") { reader?.resetSize() }.keyboardShortcut("0", modifiers: .command).disabled(reader == nil)
        }
        CommandMenu("Marks") {
            Button("Highlight") { reader?.markSelection(.highlight) }.keyboardShortcut("h", modifiers: [.command, .shift])
                .disabled(reader?.selection == nil)
            Button("Underline") { reader?.markSelection(.underline) }.keyboardShortcut("u", modifiers: .command)
                .disabled(reader?.selection == nil)
            Button("Breath") { reader?.markSelection(.breath) }.keyboardShortcut("/", modifiers: .command)
                .disabled(reader?.selection == nil)
            Button("Pause") { reader?.markSelection(.pause) }.keyboardShortcut("/", modifiers: [.command, .shift])
                .disabled(reader?.selection == nil)
            Button("Beat") { reader?.markSelection(.beat) }.keyboardShortcut("b", modifiers: [.command, .shift])
                .disabled(reader?.selection == nil)
            Button("Note") { reader?.markSelection(.note) }.keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(reader?.selection == nil)
            Divider()
            Button(reader?.showMarks == false ? "Show Marks" : "Hide Marks") { reader?.showMarks.toggle() }
                .keyboardShortcut("m", modifiers: [.command, .shift]).disabled(reader == nil)
        }
    }
}
#endif
#endif
