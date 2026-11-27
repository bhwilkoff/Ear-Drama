#if os(iOS) || os(macOS)
import SwiftUI

// Reading together on iPhone, iPad and Mac (PLAYS-DESIGN §12, iOS-DESIGN §4.19, macOS-DESIGN §4.9): join a room by
// code (the room itself is the script reader, ReadRoomReader.swift), and the teacher's class page with its casting
// board. The rules are ReadCore's and the transport ReadSession's; these views only draw what the snapshot says.

// MARK: - The room

/// The door to a room: the name and Join (an adult room), a class's seat picker, a refusal in its own words; once
/// joined, the reader itself (`ScriptReaderView(room:)`) follows the room (PLAYS-DESIGN §12.5, §12.10).
struct ReadRoomScreen: View {
    let code: String
    var seat: String?
    @Environment(PlaysLibrary.self) private var plays
    @State private var held: ReadSession?
    @State private var session = ReadSession.system()
    @State private var script: PlayScript?
    @State private var roomModel: RoomReaderModel?
    @State private var failure: String?
    @State private var goneCode: String?
    @State private var needsSeat = false
    @State private var joining = false
    @State private var name = ReadName.remembered
    @State private var classCode = ""
    @State private var seatList: ReadSeatList?
    @State private var attempt = 0
    @State private var scriptFailure = ""

    private let classWire = WorkerReadClass(api: .shared)

    init(code: String, seat: String? = nil) {
        self.code = code
        self.seat = seat
        _held = State(initialValue: ReadHandover.peek(code: code))
    }

    var body: some View {
        Group {
            if let roomModel, session.ended == nil {
                ScriptReaderView(scriptID: roomModel.script.id, room: roomModel)
            } else if let ended = session.ended {
                ContentUnavailableView(ReadCore.refusal(ended), systemImage: "waveform.slash")
            } else if !scriptFailure.isEmpty {
                ContentUnavailableView(scriptFailure, systemImage: "waveform.slash")
            } else if session.snapshot != nil {
                ProgressView()
            } else if let goneCode {
                ContentUnavailableView(ReadCore.refusal(goneCode), systemImage: "waveform.slash")
            } else if needsSeat {
                seatPicker
            } else if held == nil {
                joinForm
            } else {
                ProgressView()
            }
        }
        .navigationTitle(script?.title ?? "Reading")
        .task(id: attempt) { await begin() }
        .onChange(of: session.snapshot?.scriptID) { _, id in loadScript(id) }
        .onChange(of: script?.id) { _, _ in makeModel() }
        .onDisappear { roomModel?.end(); session.pause() }
    }

    private func begin() async {
        if let h = held, session.snapshot == nil {
            session = h
            held = nil
            ReadHandover.release(h)
            loadScript(h.snapshot?.scriptID)
            return
        }
        if held == nil, session.snapshot == nil, let normal = ReadCore.normalizeCode(code), let gone = await WorkerReadWire(api: .shared).gone(code: normal) {
            goneCode = gone
            return
        }
        #if DEBUG
        if seat != nil, session.snapshot == nil { await join() }
        #endif
    }

    private func loadScript(_ id: String?) {
        guard let id, let rev = session.snapshot?.scriptRevision, script == nil else { return }
        Task {
            // A room carrying an own script reads it with its member key; a catalog play at its revision, else the library's latest.
            let snap = session.snapshot
            let who: OwnShare.Who? = session.code.flatMap { code in session.memberKey.map { .room(code: code, key: $0) } }
            let exact = await plays.resolved(id: id, revision: rev, who: who, fit: snap.map(OwnShare.Fit.room) ?? { _ in true })
            if let found = exact.script { script = found.scoped(to: snap?.range) }
            else if PlayScript.isOwnID(id) { scriptFailure = OwnShare.scriptLine(exact.failure); if scriptFailure.isEmpty { scriptFailure = PlaysShare.line(exact.failure) } }
            else { script = ((try? await plays.script(id: id)) ?? nil)?.scoped(to: snap?.range) }
            makeModel()
        }
    }

    private func makeModel() {
        guard roomModel == nil, let script, session.snapshot != nil else { return }
        roomModel = RoomReaderModel(session: session, script: script, store: plays.store, publishing: WorkerPlays(api: .shared))
    }

    // MARK: Joining

    private var joinForm: some View {
        Form {
            Section {
                Text(verbatim: ReadScreenText.grouped(ReadCore.normalizeCode(code) ?? code)).font(TypeRamp.tabular)
                TextField("Your name", text: $name)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("read-name")
                Button("Join") { Task { await join() } }.disabled(joining)
                    .accessibilityIdentifier("read-join")
                PushLink(value: Route.parts) { Text("Your Parts") }
            }
            if let failure { Label(failure, systemImage: "exclamationmark.triangle").foregroundStyle(Color.semanticError) }
        }
    }

    private func join(seatKey: String? = nil, seatID: String? = nil, move: Bool = false) async {
        guard session.snapshot == nil else { return }
        guard let normal = ReadCore.normalizeCode(code) else { failure = ReadCore.refusal("bad_code"); return }
        var want: [String: Any] = [:]
        if let seatID, let seatKey { want["seat"] = seatID; want["seat_key"] = seatKey }
        if move { want["move"] = true }
        let typed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty, seatID == nil { want["name"] = typed }
        joining = true
        defer { joining = false }
        failure = nil
        do {
            try await session.join(code: normal, want)
            needsSeat = false
            ReadName.keep(typed)
            loadScript(session.snapshot?.scriptID)
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
}

/// The name an adult reads under: the last one typed on this device, kept as a convenience (the app has no chosen name).
nonisolated enum ReadName {
    static let key = "ed.readName"
    static var remembered: String { UserDefaults.standard.string(forKey: key) ?? "" }
    static func keep(_ name: String) { if !name.isEmpty { UserDefaults.standard.set(String(name.prefix(ReadCore.nameMax)), forKey: key) } }
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
        Button {
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
        } label: {
            ActionLabel(title: "Read Together", systemImage: "person.2")
        }
        .pageAction()
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
    /// Read without taking: a view may be built more than once before it keeps its state.
    static func peek(code: String) -> ReadSession? { held?.code == ReadCore.normalizeCode(code) ? held : nil }
    static func release(_ s: ReadSession) { if held === s { held = nil } }
}

nonisolated enum ReadOpening {
    static func body(_ script: PlayScript, classID: String? = nil, productionID: String? = nil, mode: String = "read",
                     range: ProductionRange? = nil) -> [String: Any] {
        let range = range ?? script.scope
        let script = script.whole
        var o: [String: Any] = [
            "script_id": script.id, "script_revision": script.revision, "mode": mode,
            "cast": script.lines.map { ["id": $0.id, "part": $0.part.rawValue] },
        ]
        if classID == nil, !ReadName.remembered.isEmpty { o["owner_name"] = String(ReadName.remembered.prefix(ReadCore.nameMax)) }
        if let classID { o["kind"] = "class"; o["class_id"] = classID }
        if let productionID { o["production_id"] = productionID }
        if let range { o["range"] = ["from": range.from, "to": range.to] }
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
    @State private var pickQuery = ""
    @State private var starting = false
    @State private var inbox: ClassInbox?
    @State private var waiting: [ClassReviewItem] = []
    @State private var reviewScripts: [String: PlayScript] = [:]
    @State private var recordScripts: [String: String] = [:]
    @State private var heard = SystemTakePlayer()
    @State private var working = false
    @State private var classFailure: String?
    @State private var approvalFailure: String?
    @State private var exported: ClassExportFile?
    @State private var exporting = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(SharedPlays.self) private var shared

    private let wire = WorkerReadClass(api: .shared)

    var body: some View {
        List {
            if let failure { Label(failure, systemImage: "exclamationmark.triangle").foregroundStyle(Color.semanticError) }
            if inbox?.idle == true {
                Section { Button("Keep receiving takes") { inbox?.keepReceiving() } }
            }
            if detail?.under13 == true, detail?.schoolConsent != true {
                Section("School approval") {
                    SchoolApprovalRows(failure: approvalFailure, busy: working) { reference in recordApproval(reference) }
                }
            }
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
            if !waiting.isEmpty {
                Section("Review") {
                    ForEach(waiting) { item in
                        let line = reviewScripts[scriptID(of: item)]?.lines.first { $0.id == item.take.lineID }
                        ClassReviewRow(item: item, seatLabel: seatLabel(item), partTitle: PartID(rawValue: item.take.part).title,
                                       words: line?.spokenText ?? "", canPlay: localTake(item) != nil,
                                       play: { play(item) }, decide: { state, note in decide(item, state, note) })
                    }
                }
            }
            if let progress, !progress.productions.isEmpty {
                ForEach(progress.productions) { p in
                    Section(p.title) {
                        ForEach(p.seats) { row in
                            let lines = row.parts.reduce(0) { $0 + $1.lines }
                            let done = row.parts.reduce(0) { $0 + $1.recorded }
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
            if let detail {
                Section("Class") {
                    ClassSectionRows(name: detail.name, endsOn: detail.endsOn, failure: classFailure, busy: working,
                                     change: changeDate, export: exportClass, delete: deleteClass)
                }
            }
        }
        .fileExporter(isPresented: $exporting, document: exported ?? ClassExportFile(data: Data()), contentType: .json,
                      defaultFilename: ClassExportFile.filename(detail?.name ?? "")) { _ in exported = nil }
        .navigationTitle(detail?.name ?? "Class")
        .task { await load() }
        .refreshable { await load() }
        .onDisappear { inbox?.release() }
        .onChange(of: scenePhase) { _, phase in inbox?.setActive(phase == .active) }
        .sheet(isPresented: $choosing) { playPicker }
    }

    private func recordApproval(_ reference: String) {
        guard !reference.isEmpty else { approvalFailure = ReadCore.refusal("confirmations_required"); return }
        working = true
        Task {
            defer { working = false }
            do { try await wire.schoolConsent(id, reference: reference); approvalFailure = nil; await load() }
            catch let f as ReadFailure { approvalFailure = ReadCore.refusal(f.code) } catch { approvalFailure = ReadCore.refusal("error") }
        }
    }

    private func changeDate(_ day: String) {
        working = true
        Task {
            defer { working = false }
            do { _ = try await wire.setEnd(id, endsOn: day); classFailure = nil; await load() }
            catch let f as ReadFailure { classFailure = ReadCore.refusal(f.code) } catch { classFailure = ReadCore.refusal("error") }
        }
    }

    private func exportClass() {
        working = true
        Task {
            defer { working = false }
            do { exported = ClassExportFile(data: try await wire.exportClass(id)); classFailure = nil; exporting = true }
            catch let f as ReadFailure { classFailure = ReadCore.refusal(f.code) } catch { classFailure = ReadCore.refusal("error") }
        }
    }

    private func deleteClass() {
        working = true
        Task {
            defer { working = false }
            do { try await wire.deleteClass(id); await shared.loadClasses(); dismiss() }
            catch let f as ReadFailure { classFailure = ReadCore.refusal(f.code) } catch { classFailure = ReadCore.refusal("error") }
        }
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
            holdPickups()
            await loadReviews()
        } catch let f as ReadFailure { failure = ReadCore.refusal(f.code) } catch { failure = ReadCore.refusal("error") }
    }

    /// Relay across time (PLAYS-DESIGN §12.11): while this page is open the teacher's app holds each production's pickup, so
    /// takes recorded at home pass through; the progress list moves on every arrival.
    private func holdPickups() {
        let box = inbox ?? ClassInbox(store: plays.store, script: { pid, id, rev in await plays.resolved(id: id, revision: rev, who: .member(pid: pid)).script })
        if inbox == nil {
            box.onArrival = { Task { @MainActor in progress = try? await wire.progress(id); await loadReviews() } }
            box.setActive(scenePhase == .active)
            inbox = box
        }
        for p in progress?.productions ?? [] {
            Task {
                guard let info = try? await wire.production(p.id) else { return }
                box.hold(p.id, scriptID: info.scriptID, revision: info.scriptRevision)
            }
        }
    }

    /// The seats' chosen takes with no review, read from each class production's record (the Worker merges them).
    private func loadReviews() async {
        let transport = WorkerPlays(api: .shared)
        var records: [SharedRecord] = []
        for p in progress?.productions ?? [] { if let r = try? await transport.get(p.id) { records.append(r) } }
        var scripts = reviewScripts
        for r in records where scripts[r.scriptID] == nil {
            if let s = await plays.resolved(id: r.scriptID, revision: r.scriptRevision, who: .member(pid: r.id), fit: OwnShare.Fit.record(r)).script { scripts[r.scriptID] = s }
        }
        reviewScripts = scripts
        recordScripts = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0.scriptID) })
        waiting = ClassReview.queue(records) { rec, line in scripts[rec.scriptID]?.lines.firstIndex { $0.id == line } ?? -1 }
    }

    private func scriptID(of item: ClassReviewItem) -> String { recordScripts[item.pid] ?? "" }

    private func seatLabel(_ item: ClassReviewItem) -> String {
        (detail?.seats ?? []).first { $0.id == item.take.seat }?.label ?? "A seat"
    }

    /// The take, when it passed through to this device and is kept in the class production's folder.
    private func localTake(_ item: ClassReviewItem) -> (Production, Take)? {
        guard let local = plays.store.findShared(item.pid), let take = local.take(item.take.id) else { return nil }
        return (local, take)
    }

    private func play(_ item: ClassReviewItem) {
        guard let (local, take) = localTake(item) else { return }
        let url = plays.store.takeURL(local, take)
        heard.stop()
        Task { await heard.play(url) }
    }

    private func decide(_ item: ClassReviewItem, _ state: String, _ note: String?) {
        Task {
            do {
                try await WorkerPlays(api: .shared).reviewTake(item.pid, takeID: item.take.id, state: state, note: note)
                waiting.removeAll { $0.id == item.id }
                failure = nil
                progress = try? await wire.progress(id)
            } catch let r as PlaysRefusal { failure = ReadCore.refusal(r.code ?? "error") } catch { failure = ReadCore.refusal("error") }
        }
    }

    private var playPicker: some View {
        NavigationStack {
            List {
                ForEach(PlayBrowse.pickList(plays.rows).filter { pickQuery.isEmpty || $0.label.localizedStandardContains(pickQuery) }) { pick in
                    Button(pick.label) { choosing = false; start(pick.id) }
                }
                let mine = plays.own.rows.filter { $0.done && (pickQuery.isEmpty || $0.title.localizedStandardContains(pickQuery)) }
                if !mine.isEmpty {
                    Section {
                        ForEach(mine) { row in Button(row.title) { choosing = false; start(row.id) } }
                    } header: {
                        Text("Your Scripts")
                    } footer: {
                        Text(OwnShare.classReaders)
                    }
                }
            }
            .searchable(text: $pickQuery)
            .task { await plays.load() }
            .navigationTitle("Start a Reading")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { choosing = false } } }
        }
    }

    /// The class's production for this play (made on first use), then a class room over its casting.
    private func start(_ scriptID: String) {
        Task {
            do {
                guard let script = try await plays.script(id: scriptID) else { failure = ReadCore.refusal("not_castable"); return }
                let prod: ReadClassProduction
                if PlayScript.isOwnID(script.id) {
                    prod = try await wire.classProduction(id, own: OwnShare.makeBody(script))
                    let own = plays.own
                    if let unsent = await OwnShare.sendOrUndo(WorkerPlays(api: .shared), pid: prod.id, script: script, freeze: { try? await own.freeze(script.id) }) {
                        failure = OwnShare.passes(unsent) ? OwnShare.notSent : PlaysShare.line(unsent)
                        return
                    }
                } else {
                    prod = try await wire.classProduction(id, scriptID: script.id, revision: script.revision, cast: PlaysShare.castSheet(script))
                }
                let session = ReadSession.system()
                try await session.open(ReadOpening.body(script, classID: id, productionID: prod.id), teacher: true)
                if let code = session.code { ReadHandover.hold(session); app.push(Route.readRoom(code)) }
            } catch let f as ReadFailure { failure = ReadCore.refusal(f.code) } catch let r as PlaysRefusal { failure = PlaysShare.line(r) } catch { failure = ReadCore.refusal("error") }
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
            let got = await plays.resolved(id: info.scriptID, revision: info.scriptRevision, who: .member(pid: productionID))
            script = got.script
            if let found = got.script { facts = ReadCastingFacts(found) } else { failure = PlaysShare.line(got.failure) }
        } catch let f as ReadFailure { failure = ReadCore.refusal(f.code) } catch { failure = ReadCore.refusal("error") }
    }
}
#endif
