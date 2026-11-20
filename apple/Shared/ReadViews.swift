#if os(iOS) || os(macOS)
import SwiftUI

// Reading together on iPhone, iPad and Mac (PLAYS-DESIGN §12, iOS-DESIGN §4.19, macOS-DESIGN §4.9): join a room by
// code, follow the lit line, lead with Back/Next/Again, and the teacher's class page with its casting board. The
// rules are ReadCore's and the transport ReadSession's; these views only draw what the snapshot says.

// MARK: - The room

struct ReadRoomScreen: View {
    let code: String
    var seat: String?
    @Environment(PlaysLibrary.self) private var plays
    @Environment(AppStore.self) private var app
    @State private var session = ReadHandover.take() ?? ReadSession.system()
    @State private var script: PlayScript?
    @State private var failure: String?
    @State private var needsSeat = false
    @State private var following = true
    @State private var hideMine = false
    @State private var classCode = ""
    @State private var seatList: ReadSeatList?
    @State private var sending = false
    @State private var ending = false
    @State private var attempt = 0
    @State private var partsOpen = false
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    private let classWire = WorkerReadClass(api: .shared)

    var body: some View {
        Group {
            if let snap = session.snapshot, session.ended == nil {
                room(snap)
            } else if let ended = session.ended {
                ContentUnavailableView(ReadCore.refusal(ended), systemImage: "waveform.slash")
            } else if needsSeat {
                seatPicker
            } else if let failure {
                VStack(spacing: Spacing.s4) {
                    Label(failure, systemImage: "exclamationmark.triangle").foregroundStyle(Color.semanticError)
                    Button("Try Again") { self.failure = nil; attempt += 1 }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(script?.title ?? "Reading")
        .task(id: attempt) { await join() }
        .onChange(of: session.snapshot?.scriptID) { _, id in
            guard let id, let rev = session.snapshot?.scriptRevision else { return }
            Task {
                let exact = await plays.script(id: id, revision: rev)
                if let exact { script = exact } else { script = (try? await plays.script(id: id)) ?? nil }
            }
        }
        .onDisappear { session.pause() }
    }

    // MARK: Joining

    private func join(seatKey: String? = nil, seatID: String? = nil, move: Bool = false) async {
        guard session.snapshot == nil else { return }
        guard let normal = ReadCore.normalizeCode(code) else { failure = ReadCore.refusal("bad_code"); return }
        var want: [String: Any] = [:]
        if let seatID, let seatKey { want["seat"] = seatID; want["seat_key"] = seatKey }
        if move { want["move"] = true }
        do {
            try await session.join(code: normal, want)
            needsSeat = false
        } catch let f as ReadFailure {
            if f.code == "seat_required" || f.code == "seat_key_required" {
                needsSeat = true
                await seatDoor()
            } else {
                failure = ReadCore.refusal(f.code)
            }
        } catch {
            failure = ReadCore.refusal("error")
        }
    }

    private var seatPicker: some View {
        Form {
            Section {
                TextField("Class code", text: $classCode)
                    #if os(iOS)
                    .textInputAutocapitalization(.characters)
                    #endif
                    .autocorrectionDisabled()
                Button("Show Names") { Task { await loadSeats() } }.disabled(classCode.isEmpty)
            }
            if let seatList {
                Section(seatList.class.name) {
                    ForEach(seatList.seats) { s in
                        Button { Task { await claim(s, move: false) } } label: {
                            HStack {
                                Text(verbatim: s.label).font(TypeRamp.body)
                                Spacer()
                                if s.taken {
                                    Button("Move Here") { Task { await claim(s, move: true) } }.buttonStyle(.borderless)
                                }
                            }
                        }
                    }
                }
            }
            if let failure { Label(failure, systemImage: "exclamationmark.triangle").foregroundStyle(Color.semanticError) }
        }
    }

    /// DEBUG door: APP_START_SEAT=<class code>:<seat id or label> picks that name without a person at the form.
    private func seatDoor() async {
        #if DEBUG
        guard let door = seat, let colon = door.firstIndex(of: ":") else { return }
        classCode = String(door[..<colon])
        let want = String(door[door.index(after: colon)...])
        await loadSeats()
        if let s = seatList?.seats.first(where: { $0.id == want || $0.label == want }) { await claim(s, move: true) }
        #endif
    }

    private func loadSeats() async {
        failure = nil
        do { seatList = try await classWire.seatList(code: classCode) } catch let f as ReadFailure { failure = ReadCore.refusal(f.code) } catch { failure = ReadCore.refusal("error") }
    }

    private func claim(_ s: ReadSeatList.Seat, move: Bool) async {
        failure = nil
        do {
            let r = try await classWire.seatClaim(code: classCode, seat: s.id, move: move)
            ReadSeatKeys.set(r.seatKey, forSeat: r.seat)
            await join(seatKey: r.seatKey, seatID: r.seat, move: move)
        } catch let f as ReadFailure {
            failure = ReadCore.refusal(f.code)
        } catch {
            failure = ReadCore.refusal("error")
        }
    }

    // MARK: Following

    private func room(_ snap: ReadSnapshot) -> some View {
        let lines = script?.lines ?? []
        let cast = lines.map { ($0.id, $0.part.rawValue) }
        let me = snap.meMember
        let roomState = snap.room
        let mine = Set(ReadCore.mineIndexes(roomState, cast: cast, member: me))
        let next = snap.nextMine.map { ReadCore.Next(line: $0.line, inLines: $0.in) }
        let leads = snap.you?.leads == true
        let isScreen = snap.you?.role == "screen"
        return VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Spacing.s3) {
                        ForEach(Array(lines.enumerated()), id: \.element.id) { i, line in
                            lineRow(line, index: i, current: line.id == snap.cursor, mine: mine.contains(i), rehearse: snap.mode == "rehearse")
                                .id(line.id)
                        }
                    }
                    .padding(Spacing.s4)
                }
                .simultaneousGesture(DragGesture(minimumDistance: 12).onChanged { _ in following = false })
                .onChange(of: snap.cursor) { _, cursor in
                    if following { withAnimation { proxy.scrollTo(cursor, anchor: .center) } }
                }
                .onChange(of: following) { _, on in
                    if on { withAnimation { proxy.scrollTo(snap.cursor, anchor: .center) } }
                }
                .overlay(alignment: .bottomTrailing) {
                    if !following {
                        Button("Back to the Line") { following = true }.buttonStyle(.borderedProminent).padding(Spacing.s4)
                    }
                }
            }
            Divider()
            footer(snap, next: next, leads: leads, isScreen: isScreen, cast: cast)
        }
        #if os(iOS)
        .toolbar { ToolbarItem(placement: .primaryAction) { readingMenu(snap, leads: leads) } }
        #else
        .toolbar { ToolbarItem { readingMenu(snap, leads: leads) } }
        #endif
    }

    private func lineRow(_ line: ScriptLine, index: Int, current: Bool, mine: Bool, rehearse: Bool) -> some View {
        ReadLineRow(line: line, current: current, mine: mine, hidden: mine && hideMine && rehearse && !current)
    }

    private func footer(_ snap: ReadSnapshot, next: ReadCore.Next?, leads: Bool, isScreen: Bool, cast: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            let line = ReadScreenText.status(session)
            let fact = ReadCore.nextLine(next) ?? ""
            if !line.isEmpty || !fact.isEmpty {
                Text(verbatim: line.isEmpty ? fact : line).font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
            }
            if let r = session.refusal { Label(ReadCore.refusal(r), systemImage: "exclamationmark.triangle").font(TypeRamp.caption).foregroundStyle(Color.semanticError) }
            HStack {
                if snap.mode == "rehearse" && !leads {
                    Toggle("Hide My Lines", isOn: $hideMine).toggleStyle(.switch).font(TypeRamp.caption)
                }
                Spacer()
                if leads {
                    Button("Back") { move(snap, cast, -1) }.keyboardShortcut(.leftArrow, modifiers: [])
                    if snap.mode == "rehearse" {
                        Button("Again") { again(snap, cast) }
                    }
                    Button("Next") { move(snap, cast, 1) }.keyboardShortcut(.rightArrow, modifiers: []).buttonStyle(.borderedProminent)
                } else if snap.kind == "adult" && !isScreen {
                    Button("Parts") { partsOpen = true }
                }
            }
        }
        .padding(Spacing.s4)
        .sheet(isPresented: $partsOpen) { partsSheet(snap) }
    }

    private func move(_ snap: ReadSnapshot, _ cast: [(String, String)], _ delta: Int) {
        guard let line = ReadCore.step(cast, cursor: snap.cursor, delta: delta) else { return }
        send(["type": "cursor", "line": line, "base": snap.cursorGen])
    }

    private func again(_ snap: ReadSnapshot, _ cast: [(String, String)]) {
        guard let script else { return }
        let starts = ScriptReading.sectionsOf(script).filter { $0.level != .part }.map(\.index)
        if let line = ReadCore.sceneStart(cast, cursor: snap.cursor, starts: starts), line != snap.cursor {
            send(["type": "cursor", "line": line, "base": snap.cursorGen])
        }
    }

    private func send(_ msg: [String: Any]) {
        Task { try? await session.send(msg) }
    }

    private func readingMenu(_ snap: ReadSnapshot, leads: Bool) -> some View {
        Menu("Reading", systemImage: "ellipsis.circle") {
            if leads {
                Picker("Mode", selection: Binding(get: { snap.mode }, set: { send(["type": "mode", "mode": $0]) })) {
                    Text("Table Read").tag("read")
                    Text("Rehearse").tag("rehearse")
                }
                Toggle("Lock Joining", isOn: Binding(get: { snap.locked }, set: { send(["type": "lock", "locked": $0]) }))
                Toggle("Read Open Parts", isOn: Binding(get: { snap.readOpen == true }, set: { send(["type": "read-open", "open": $0]) }))
                Button("Open the Screen") { openScreen(snap.code) }
                Button("End the Reading", role: .destructive) { ending = true }
            }
            Text(verbatim: ReadScreenText.grouped(snap.code))
        }
        .confirmationDialog("End the reading for everyone?", isPresented: $ending) {
            Button("End the Reading", role: .destructive) { send(["type": "end"]) }
        }
    }

    private func openScreen(_ code: String) {
        #if os(macOS)
        openWindow(id: ReadScreenWindow_macOS.id, value: code)
        #else
        app.push(Route.readScreen(code))
        #endif
    }

    private func partsSheet(_ snap: ReadSnapshot) -> some View {
        NavigationStack {
            List {
                ForEach(script?.roles ?? [], id: \.name) { role in
                    let id = PartID.role(role.name).rawValue
                    let holder = snap.claims[id]
                    let mineHeld = holder != nil && holder == snap.you?.id
                    HStack {
                        Text(verbatim: role.name).font(TypeRamp.body)
                        Spacer()
                        if mineHeld {
                            Button("Release") { send(["type": "release", "part": id]) }
                        } else if holder == nil {
                            Button("Take") { send(["type": "claim", "part": id]) }
                        } else {
                            Text("Taken").font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
                        }
                    }
                }
            }
            .navigationTitle("Parts")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { partsOpen = false } } }
        }
    }
}

/// One line of the script as a reader sees it in a room: the speaker, the words, my lines tinted, the lit line marked.
struct ReadLineRow: View {
    let line: ScriptLine
    let current: Bool
    let mine: Bool
    let hidden: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            if line.kind == .speech { Text(verbatim: line.part.title).font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted) }
            Text(verbatim: hidden ? "\u{2026}" : (line.spokenText.isEmpty ? (line.source ?? "") : line.spokenText))
                .font(current ? TypeRamp.bodyStrong : TypeRamp.body)
        }
        .padding(Spacing.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(mine ? Color.brandSecondary.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .leading) { if current { Rectangle().fill(Color.brandSecondary).frame(width: 3) } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(current ? .isSelected : [])
    }
}

#if os(macOS)
/// The projector's window (macOS-DESIGN §4.9): the room's shared screen, in a window of its own.
struct ReadScreenWindow_macOS: View {
    static let id = "read-screen"
    let code: String
    var body: some View { ReadScreenHost(code: code) }
}
#endif

/// A play page's door: opens an adult room on this play and lands in it (WEB-DESIGN §4.17's twin).
struct ReadStartButton: View {
    let script: PlayScript
    @Environment(AppStore.self) private var app
    @State private var failure: String?
    @State private var busy = false

    var body: some View {
        Button("Read Together") {
            busy = true
            failure = nil
            Task {
                defer { busy = false }
                let session = ReadSession.system()
                do {
                    try await session.open(ReadOpening.body(script), teacher: false)
                    if let code = session.code { ReadHandover.hold(session); app.push(Route.readRoom(code)) }
                } catch let f as ReadFailure { failure = ReadCore.refusal(f.code) } catch { failure = ReadCore.refusal("error") }
            }
        }
        .disabled(busy)
        if let failure { Label(failure, systemImage: "exclamationmark.triangle").foregroundStyle(Color.semanticError) }
    }
}

/// The room a leader just opened is already joined as its leader: the screen it lands on takes this session
/// instead of joining again (a second join would be a second member).
@MainActor
enum ReadHandover {
    private static var held: ReadSession?
    static func hold(_ s: ReadSession) { held = s }
    static func take() -> ReadSession? { defer { held = nil }; return held }
}

nonisolated enum ReadOpening {
    static func body(_ script: PlayScript, classID: String? = nil, productionID: String? = nil, mode: String = "read") -> [String: Any] {
        var o: [String: Any] = [
            "script_id": script.id, "script_revision": script.revision, "mode": mode,
            "cast": script.lines.map { ["id": $0.id, "part": $0.part.rawValue] },
        ]
        if let classID { o["kind"] = "class"; o["class_id"] = classID }
        if let productionID { o["production_id"] = productionID }
        return o
    }
}

// MARK: - The class page

struct ClassPageScreen: View {
    let id: String
    @Environment(PlaysLibrary.self) private var plays
    @Environment(AppStore.self) private var app
    @State private var detail: ReadClassDetail?
    @State private var progress: ReadProgress?
    @State private var failure: String?
    @State private var paste = ""
    @State private var showCode = false
    @State private var choosing = false
    @State private var starting = false

    private let wire = WorkerReadClass(api: .shared)

    var body: some View {
        List {
            if let failure { Label(failure, systemImage: "exclamationmark.triangle").foregroundStyle(Color.semanticError) }
            if let code = detail?.code {
                Section {
                    HStack {
                        Text(verbatim: showCode ? SharedPlays.grouped(code) : "\u{2022}\u{2022}\u{2022}\u{2022} \u{2022}\u{2022}\u{2022}\u{2022}").font(TypeRamp.tabular)
                        Spacer()
                        Button(showCode ? "Hide Code" : "Show Code") { showCode.toggle() }
                    }
                }
            }
            Section("Seats") {
                ForEach(detail?.seats ?? []) { s in
                    HStack {
                        Text(verbatim: s.label).font(TypeRamp.body)
                        Spacer()
                        if s.claimed { Text("In").font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted) }
                    }
                    .swipeActions {
                        Button("Remove", role: .destructive) { act { try await wire.removeSeat(id, seat: s.id) } }
                        if s.claimed { Button("Release") { act { try await wire.releaseSeat(id, seat: s.id) } }.tint(Color.brandSecondary) }
                    }
                }
                TextField("Paste names, one a line", text: $paste, axis: .vertical).lineLimit(1...6)
                Button("Add Names") { let text = paste; paste = ""; act { try await wire.addSeats(id, text: text) } }.disabled(paste.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Section {
                Button("Start a Reading") { choosing = true }
            }
            if let progress, !progress.productions.isEmpty {
                ForEach(progress.productions) { p in
                    Section(p.title) {
                        ForEach(p.seats) { row in
                            let lines = row.parts.reduce(0) { $0 + $1.lines }
                            let done = row.parts.reduce(0) { $0 + $1.approved }
                            HStack {
                                Text(verbatim: row.label).font(TypeRamp.body)
                                Spacer()
                                Text("\(done) of \(lines)").font(TypeRamp.tabular).foregroundStyle(Color.brandTextMuted)
                            }
                        }
                        PushLink(value: Route.classCasting(id, p.id)) { Text("Casting") }
                    }
                }
            }
        }
        .navigationTitle(detail?.name ?? "Class")
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $choosing) { playPicker }
    }

    private func act(_ work: @escaping () async throws -> Void) {
        Task {
            do { try await work(); await load() } catch let f as ReadFailure { failure = ReadCore.refusal(f.code) } catch { failure = ReadCore.refusal("error") }
        }
    }

    private func load() async {
        do {
            async let d = wire.detail(id)
            async let p = wire.progress(id)
            (detail, progress) = try await (d, p)
            failure = nil
        } catch let f as ReadFailure { failure = ReadCore.refusal(f.code) } catch { failure = ReadCore.refusal("error") }
    }

    private var playPicker: some View {
        NavigationStack {
            List(CastableLibrary.load()?.scripts ?? [], id: \.id) { script in
                Button(script.title) { choosing = false; start(script) }
            }
            .navigationTitle("Start a Reading")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { choosing = false } } }
        }
    }

    /// The class's production for this play (made on first use), then a class room over its casting.
    private func start(_ script: PlayScript) {
        Task {
            do {
                let prod = try await wire.classProduction(id, scriptID: script.id, revision: script.revision, cast: PlaysShare.castSheet(script))
                let session = ReadSession.system()
                try await session.open(ReadOpening.body(script, classID: id, productionID: prod.id), teacher: true)
                if let code = session.code { ReadHandover.hold(session); app.push(Route.readRoom(code)) }
            } catch let f as ReadFailure { failure = ReadCore.refusal(f.code) } catch { failure = ReadCore.refusal("error") }
        }
    }
}

// MARK: - The casting board

struct CastingBoardScreen: View {
    let classID: String
    let productionID: String
    @Environment(PlaysLibrary.self) private var plays
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var detail: ReadClassDetail?
    @State private var script: PlayScript?
    @State private var facts: ReadCastingFacts?
    @State private var assignments: [ReadCore.Assignment] = []
    @State private var dirty = false
    @State private var failure: String?
    @State private var saved = false

    private let wire = WorkerReadClass(api: .shared)

    private var seats: [ReadCore.Seat] { (detail?.seats ?? []).map { ReadCore.Seat(id: $0.id, label: $0.label) } }

    private func label(_ seat: String) -> String { seats.first { $0.id == seat }?.label ?? "" }

    var body: some View {
        List {
            if let failure { Label(failure, systemImage: "exclamationmark.triangle").foregroundStyle(Color.semanticError) }
            if let facts {
                Section("Seats") {
                    let totals = ReadCore.seatTotals(cast: facts.cast, words: facts.words, assignments: assignments, seats: seats)
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(seats) { s in
                                let t = totals.first { $0.seat == s.id }
                                VStack(alignment: .leading) {
                                    Text(verbatim: s.label).font(TypeRamp.bodyStrong)
                                    Text("\(Self.n(t?.lines ?? 0, "line")), \(Self.n(t?.words ?? 0, "word"))").font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
                                }
                                .padding(Spacing.s2)
                                .background(Color.brandSurface, in: RoundedRectangle(cornerRadius: 8))
                                .draggable(s.id)
                            }
                        }
                    }
                }
                Section("Parts") {
                    ForEach(facts.facts) { f in
                        part(f, facts: facts)
                    }
                }
            }
        }
        .navigationTitle("Casting")
        .toolbar {
            ToolbarItemGroup {
                Menu("Fill") {
                    Button("Fill Evenly") { fill() }
                    Button("Clear", role: .destructive) { set([]) }
                }
                Button("Save") { save() }.disabled(!dirty)
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private func part(_ f: ReadCore.PartFacts, facts: ReadCastingFacts) -> some View {
        let whole = assignments.first { $0.part == f.part && $0.from == nil && $0.to == nil }
        let ranges = ReadCore.sceneRanges(cast: facts.cast, part: f.part, starts: facts.starts)
        VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack {
                VStack(alignment: .leading) {
                    Text(verbatim: PartID(rawValue: f.part).title).font(TypeRamp.bodyStrong)
                    Text("\(Self.n(f.lines, "line")), \(Self.n(f.words, "word")), \(Self.n(f.scenes, "scene")), longest \(f.longest)").font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
                }
                Spacer()
                Picker("Seat", selection: Binding(get: { whole?.seat ?? "" }, set: { assignWhole(f.part, seat: $0) })) {
                    Text("None").tag("")
                    ForEach(seats) { Text(verbatim: $0.label).tag($0.id) }
                }
                .labelsHidden()
            }
            if ranges.count > 1 && whole == nil {
                Menu("Split by Scene") {
                    ForEach(Array(ranges.enumerated()), id: \.offset) { _, r in
                        Menu("Scene from \(r.from)") {
                            ForEach(seats) { s in
                                Button(s.label) { assignRange(f.part, r, seat: s.id) }
                            }
                        }
                    }
                }
                ForEach(assignments.filter { $0.part == f.part }, id: \.from) { a in
                    Text("\(label(a.seat)): \(a.from ?? "start") to \(a.to ?? "end")").font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
                }
            }
        }
        .dropDestination(for: String.self) { items, _ in
            guard let seat = items.first, seats.contains(where: { $0.id == seat }) else { return false }
            assignWhole(f.part, seat: seat)
            return true
        }
    }

    private static func n(_ count: Int, _ noun: String) -> String { count == 1 ? "1 \(noun)" : "\(count) \(noun)s" }

    private func set(_ next: [ReadCore.Assignment]) { assignments = next; dirty = true; saved = false }

    private func assignWhole(_ part: String, seat: String) {
        set(assignments.filter { $0.part != part } + (seat.isEmpty ? [] : [ReadCore.Assignment(part: part, seat: seat)]))
    }

    private func assignRange(_ part: String, _ r: ReadCore.SceneRange, seat: String) {
        set(assignments.filter { !($0.part == part && $0.from == nil) && !($0.part == part && $0.from == r.from) }
            + [ReadCore.Assignment(part: part, seat: seat, from: r.from, to: r.to)])
    }

    private func fill() {
        guard let facts else { return }
        set(ReadCore.fillEvenly(parts: facts.facts, seats: seats, assignments: assignments, cast: facts.cast, words: facts.words))
    }

    private func save() {
        Task {
            do {
                assignments = try await wire.assign(productionID, assignments: assignments)
                dirty = false
                saved = true
                failure = nil
            } catch let f as ReadFailure { failure = ReadCore.refusal(f.code) } catch { failure = ReadCore.refusal("error") }
        }
    }

    private func load() async {
        do {
            detail = try await wire.detail(classID)
            let info = try await wire.production(productionID)
            assignments = (info.assignments ?? []).map { ReadCore.Assignment(part: $0.part, seat: $0.seat, from: $0.from, to: $0.to) }
            let found = await plays.script(id: info.scriptID, revision: info.scriptRevision)
            script = found
            if let found { facts = ReadCastingFacts(found) } else { failure = ReadCore.refusal("revision_mismatch") }
        } catch let f as ReadFailure { failure = ReadCore.refusal(f.code) } catch { failure = ReadCore.refusal("error") }
    }
}
#endif
