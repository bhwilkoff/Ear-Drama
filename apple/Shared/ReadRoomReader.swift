#if os(iOS) || os(macOS)
import AVFoundation
import SwiftUI

// The room inside the reader (PLAYS-DESIGN §12.5 and §12.10, iOS-DESIGN §4.19, macOS-DESIGN §4.9): the reader's own
// pages follow the room's cursor (`ReaderModel.room`, the studio's seam for a room), my lines are tinted from the
// room's claims or seat ranges, and the room bar under the page holds the fact, who is here, the leader's Back / Next /
// Again, the Reading menu and the Record row. A reader device makes no sound; the receiving device plays only in its
// Takes sheet. The rules are ReadCore's, the take engine ReadRoomRecorder's.

@Observable
final class RoomReaderModel {
    enum Sheet: String, Identifiable {
        case parts, takes, screen
        var id: String { rawValue }
    }

    let session: ReadSession
    let script: PlayScript
    let cast: [(String, String)]
    let recorder: ReadRoomRecorder
    var hideMine = false
    var sheet: Sheet?
    var notice: String?
    @ObservationIgnored let store: ProductionStore
    @ObservationIgnored let publishing: (any RoomPublishing)?
    @ObservationIgnored private var started = false

    init(session: ReadSession, script: PlayScript, store: ProductionStore, publishing: (any RoomPublishing)?,
         audio: @escaping () -> LiveAudio = { StudioDoor.current.stub ? StubLiveAudio(speaking: true) : EngineLiveAudio() }) {
        self.session = session
        self.script = script
        self.store = store
        self.publishing = publishing
        cast = script.lines.map { ($0.id, $0.part.rawValue) }
        recorder = ReadRoomRecorder(link: session, store: store, script: script, publishing: publishing) { production, part in
            RecordingSession(production: production, script: script, part: part, store: store, audio: audio(), voice: SilentStandIn())
        }
    }

    var snapshot: ReadSnapshot? { session.snapshot }
    var leads: Bool { snapshot?.you?.leads == true }
    var isScreen: Bool { snapshot?.you?.role == "screen" }
    var receives: Bool { snapshot?.you?.receives == true }

    var holdsAny: Bool {
        guard let snap = snapshot else { return false }
        return !ReadCore.mineIndexes(snap.room, cast: cast, member: snap.meMember).isEmpty
    }

    func send(_ message: [String: Any]) {
        Task { try? await session.send(message) }
    }

    /// Once, when the reader opens: relaunch keeps waiting takes, and an under-13 class records on one microphone.
    func begin() async {
        guard !started else { return }
        started = true
        recorder.resume()
        await openDoors()
        if let snap = snapshot, snap.kind == "class", let classID = snap.classID, let publishing,
           (try? await publishing.under13(classID: classID)) == true {
            recorder.setOneMic(true)
        }
    }

    /// DEBUG doors APP_START_READ_PART / APP_START_READ_RECORD: claim a part and arm Record without a person's taps (T7b).
    private func openDoors() async {
        #if DEBUG
        let doors = LaunchDoors.current
        if let part = doors.readPart {
            send(["type": "claim", "part": part.hasPrefix("role:") ? part : PartID.role(part).rawValue])
            try? await Task.sleep(for: .seconds(1))
        }
        if doors.readRecord { await recorder.arm { true } }
        #endif
    }

    func end() {
        recorder.detach()
        session.pause()
    }
}

// MARK: - The room bar

struct RoomBar: View {
    @Bindable var room: RoomReaderModel
    let pageLabel: String
    var pause: () -> Void = {}
    @Environment(AppStore.self) private var app
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif
    @State private var ending = false

    var body: some View {
        if let snap = room.snapshot {
            VStack(alignment: .leading, spacing: Spacing.s2) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s3) {
                    let text = RoomText.line(snap, status: ReadScreenText.status(room.session))
                    Text(verbatim: text).font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted).lineLimit(1)
                        .accessibilityIdentifier("room-fact")
                    Spacer(minLength: 0)
                    Text("\(snap.present) here").font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted).fixedSize()
                    Text(verbatim: pageLabel).font(TypeRamp.tabular).foregroundStyle(Color.brandTextMuted).fixedSize()
                }
                if let r = room.session.refusal {
                    Label(ReadCore.refusal(r), systemImage: "exclamationmark.triangle").font(TypeRamp.caption).foregroundStyle(Color.semanticError)
                }
                RoomRecordRow(room: room, snap: snap, pause: pause)
                controls(snap)
            }
            .padding(.horizontal, Spacing.s4)
            .padding(.vertical, Spacing.s2)
            .background(Color.brandSurface)
            .accessibilityIdentifier("room-bar")
            .sheet(item: $room.sheet) { which in
                switch which {
                case .parts: RoomPartsSheet(room: room)
                case .takes: ReadTakesSheet(room: room)
                case .screen: RoomScreenSheet(room: room)
                }
            }
        }
    }

    private func controls(_ snap: ReadSnapshot) -> some View {
        HStack(spacing: Spacing.s3) {
            if snap.mode == "rehearse" && !room.leads {
                Toggle(isOn: $room.hideMine) { Label("Hide My Lines", systemImage: "eye.slash") }
                    .toggleStyle(.button)
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("reader-hide")
            }
            if snap.kind == "adult" && !room.isScreen && !room.leads {
                Button("Parts") { room.sheet = .parts }
            }
            Spacer(minLength: 0)
            if room.leads {
                Button("Back") { move(snap, -1) }.keyboardShortcut(.leftArrow, modifiers: [])
                if snap.mode == "rehearse" { Button("Again") { again(snap) } }
                Button("Next") { move(snap, 1) }.keyboardShortcut(.rightArrow, modifiers: []).buttonStyle(.borderedProminent)
            }
            readingMenu(snap)
        }
        .buttonStyle(.bordered)
    }

    private func move(_ snap: ReadSnapshot, _ delta: Int) {
        guard let line = ReadCore.step(room.cast, cursor: snap.cursor, delta: delta) else { return }
        room.send(["type": "cursor", "line": line, "base": snap.cursorGen])
    }

    private func again(_ snap: ReadSnapshot) {
        let starts = ScriptReading.sectionsOf(room.script).filter { $0.level != .part }.map(\.index)
        if let line = ReadCore.sceneStart(room.cast, cursor: snap.cursor, starts: starts), line != snap.cursor {
            room.send(["type": "cursor", "line": line, "base": snap.cursorGen])
        }
    }

    private func readingMenu(_ snap: ReadSnapshot) -> some View {
        Menu {
            if room.leads {
                Picker("Mode", selection: Binding(get: { snap.mode }, set: { room.send(["type": "mode", "mode": $0]) })) {
                    Text("Table Read").tag("read")
                    Text("Rehearse").tag("rehearse")
                    Text("Record").tag("record")
                }
                if snap.mode == "record" {
                    Toggle("Record Every Line Here", isOn: Binding(get: { room.recorder.oneMic }, set: { room.recorder.setOneMic($0) }))
                }
                Toggle("Lock Joining", isOn: Binding(get: { snap.locked }, set: { room.send(["type": "lock", "locked": $0]) }))
                Toggle("Read Open Parts", isOn: Binding(get: { snap.readOpen == true }, set: { room.send(["type": "read-open", "open": $0]) }))
                Button("Add a Screen") { room.sheet = .screen }
                Button("Open the Screen") { openScreen(snap.code) }
                Button("End the Reading", role: .destructive) { ending = true }
            }
            Text(verbatim: ReadScreenText.grouped(snap.code))
        } label: {
            Label("Reading", systemImage: "ellipsis.circle")
        }
        .accessibilityIdentifier("reading-menu")
        .confirmationDialog("End the reading for everyone?", isPresented: $ending) {
            Button("End the Reading", role: .destructive) { room.send(["type": "end"]) }
        }
    }

    private func openScreen(_ code: String) {
        #if os(macOS)
        openWindow(id: ReadScreenWindow_macOS.id, value: code)
        #else
        app.push(Route.readScreen(code))
        #endif
    }
}

// MARK: - The Record row

/// Start Recording, Recording with Stop, who is reading, takes waiting on this device, and Takes (the receiver's sheet).
struct RoomRecordRow: View {
    @Bindable var room: RoomReaderModel
    let snap: ReadSnapshot
    var pause: () -> Void = {}

    var body: some View {
        let recorder = room.recorder
        let on = snap.mode == "record" && snap.you?.role == "reader"
        if on {
            let receives = room.receives
            let records = (room.holdsAny && !receives) || (receives && recorder.oneMic)
            HStack(spacing: Spacing.s3) {
                if recorder.recording != nil {
                    Circle().fill(StudioPalette.record).frame(width: 10, height: 10).accessibilityHidden(true)
                    Text("Recording").font(TypeRamp.bodyStrong).accessibilityAddTraits(.updatesFrequently)
                    Button("Stop") { recorder.stop() }.buttonStyle(.bordered)
                } else if case let .roomTone(left) = recorder.engine?.phase ?? .idle {
                    Text("Quiet for \(left) s").font(TypeRamp.bodyStrong)
                } else if records && !recorder.armed {
                    Button {
                        pause()
                        Task { await recorder.arm { await Self.microphone() } }
                    } label: { Label("Start Recording", systemImage: "mic.fill") }
                        .buttonStyle(.borderedProminent)
                        .tint(StudioPalette.record)
                        .accessibilityIdentifier("room-start-recording")
                    if let why = recorder.failed {
                        Text(verbatim: why == "microphone" ? "Allow the microphone." : "Recording did not start.")
                            .font(TypeRamp.caption).foregroundStyle(Color.semanticError)
                    }
                } else if let r = snap.readsNow, (snap.kind == "class" ? r.seat != nil : r.holder != nil),
                          snap.nextMine?.in != 0, !snap.done.contains(snap.cursor) {
                    Text("Quiet while others record").font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
                }
                if !recorder.outbox.isEmpty {
                    Text(recorder.outbox.count == 1 ? "1 take on this device" : "\(recorder.outbox.count) takes on this device")
                        .font(TypeRamp.caption).monospacedDigit().foregroundStyle(Color.brandTextMuted)
                }
                Spacer(minLength: 0)
                if receives { Button("Takes") { room.sheet = .takes }.buttonStyle(.bordered).accessibilityIdentifier("room-takes") }
            }
            .accessibilityIdentifier("room-record-row")
        }
    }

    static func microphone() async -> Bool {
        if StudioDoor.current.stub { return true }
        return await AVAudioApplication.requestRecordPermission()
    }
}

// MARK: - Parts, Add a Screen

struct RoomPartsSheet: View {
    @Bindable var room: RoomReaderModel

    var body: some View {
        NavigationStack {
            List {
                ForEach(room.script.roles, id: \.name) { role in
                    let id = PartID.role(role.name).rawValue
                    let holder = room.snapshot?.claims[id]
                    HStack {
                        Text(verbatim: role.name).font(TypeRamp.body)
                        Spacer()
                        if holder != nil, holder == room.snapshot?.you?.id {
                            Button("Release") { room.send(["type": "release", "part": id]) }
                        } else if holder == nil {
                            Button("Take") { room.send(["type": "claim", "part": id]) }
                        } else {
                            Text("Taken").font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
                        }
                    }
                }
            }
            .navigationTitle("Parts")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { room.sheet = nil } } }
        }
        #if os(macOS)
        .frame(width: 360, height: 420)
        #endif
    }
}

/// The leader's Add a Screen (PLAYS-DESIGN §12.10 item 9): the code a TV shows, typed here.
struct RoomScreenSheet: View {
    @Bindable var room: RoomReaderModel
    @State private var code = ""
    @State private var failure: String?
    @State private var added = false
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Code on the TV", text: $code)
                        #if os(iOS)
                        .textInputAutocapitalization(.characters)
                        #endif
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("room-pair-code")
                    Button("Add a Screen") { add() }.disabled(code.trimmingCharacters(in: .whitespaces).isEmpty || busy)
                }
                if let failure { Label(failure, systemImage: "exclamationmark.triangle").foregroundStyle(Color.semanticError) }
                else if added { Text("Screen added.").foregroundStyle(Color.brandTextMuted) }
            }
            .navigationTitle("Add a Screen")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { room.sheet = nil } } }
        }
        #if os(macOS)
        .frame(width: 360, height: 260)
        #endif
    }

    private func add() {
        busy = true
        failure = nil
        added = false
        Task {
            defer { busy = false }
            do {
                try await room.session.attachScreen(pairCode: code)
                code = ""
                added = true
            } catch let f as ReadFailure {
                failure = ReadCore.refusal(f.code)
            } catch {
                failure = ReadCore.refusal("error")
            }
        }
    }
}

// MARK: - Takes (the receiver's sheet)

struct ReadTakesSheet: View {
    @Bindable var room: RoomReaderModel
    @Environment(PlaysLibrary.self) private var plays

    var body: some View {
        NavigationStack {
            ReadTakesContent(room: room) {
                if let p = room.recorder.production { ListenThrough(production: p, script: room.script) }
            }
            .navigationTitle("Takes")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { room.sheet = nil } } }
        }
        #if os(macOS)
        .frame(width: 460, height: 560)
        #endif
    }
}

/// A head line of counts per reader, then each speaking line in script order with its state; Play and Again, and in a
/// class room with a production Approve and Again (which offers an optional note); Listen Through, Export and Publish at the foot. Counts,
/// never a ranking. Drawn without a List so it can be rendered (ImageRenderer cannot draw one).
struct ReadTakesContent<Foot: View>: View {
    @Bindable var room: RoomReaderModel
    /// False only in a render (ImageRenderer cannot draw a ScrollView).
    var scrolls = true
    @ViewBuilder var foot: () -> Foot
    @State private var player = SystemTakePlayer()
    @State private var failure: String?
    @State private var noteFor: String?
    @State private var note = ""
    @State private var under13: Bool?

    var body: some View {
        if let snap = room.snapshot {
            let table = ReadCore.takeRows(snap, cast: room.cast, arrived: room.recorder.arrivedLines) { PartID(rawValue: $0).isSpeaking }
            let content = VStack(alignment: .leading, spacing: Spacing.s3) {
                    Text(verbatim: table.counts.map { "\(label(snap, $0.seat, $0.holder) ?? "A reader") \($0.recorded) of \($0.lines)" }.joined(separator: " \u{00B7} "))
                        .font(TypeRamp.caption).monospacedDigit().foregroundStyle(Color.brandTextMuted)
                    ForEach(table.rows) { row in
                        takeRow(snap, row)
                        Divider()
                    }
                    if let failure { Label(failure, systemImage: "exclamationmark.triangle").font(TypeRamp.caption).foregroundStyle(Color.semanticError) }
                    foot()
                    publishing(snap)
                }
                .padding(Spacing.s4)
            Group {
                if scrolls { ScrollView { content } } else { content }
            }
            .task { await loadClass(snap) }
        }
    }

    private func label(_ snap: ReadSnapshot, _ seat: String?, _ holder: String?) -> String? {
        if let seat { return snap.seats.first { $0.id == seat }?.label }
        return holder.flatMap { id in snap.members.first { $0.id == id }?.name }
    }

    private func stateText(_ snap: ReadSnapshot, _ row: ReadCore.TakeRow) -> String {
        switch row.state {
        case .recorded: "Recorded"
        case .away: "On \(label(snap, row.seat, row.holder) ?? "a reader")\u{2019}s device"
        case .waiting: "Waiting"
        case .open: "Open"
        }
    }

    private func takeRow(_ snap: ReadSnapshot, _ row: ReadCore.TakeRow) -> some View {
        let line = room.script.lines.first { $0.id == row.line }
        let words = String((line?.spokenText ?? "").prefix(80))
        let take = room.recorder.production?.chosenTake(for: row.line)
        return VStack(alignment: .leading, spacing: Spacing.s1) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: PartID(rawValue: row.part).title).font(TypeRamp.bodyStrong)
                    Text(verbatim: words).font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted).lineLimit(1)
                }
                Spacer(minLength: Spacing.s2)
                Text(verbatim: stateText(snap, row)).font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
            }
            HStack(spacing: Spacing.s2) {
                if let take { Button("Play") { play(take) } }
                if let take, snap.productionID != nil, snap.kind == "class" {
                    Button("Approve") { review(snap.productionID ?? "", take, state: "approved", note: nil) }
                    Button("Again") { noteFor = noteFor == row.line ? nil : row.line; note = "" }
                } else if row.state != .open {
                    Button("Again") { again(snap, row.line) }
                }
            }
            .buttonStyle(.bordered)
            .font(TypeRamp.caption)
            if let take, noteFor == row.line, let pid = snap.productionID {
                HStack {
                    TextField("Note (optional)", text: $note).textFieldStyle(.roundedBorder)
                    Button("Send") {
                        let said = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
                        if !said.isEmpty { review(pid, take, state: "again", note: said) }
                        again(snap, row.line)
                        noteFor = nil
                    }
                }
            }
        }
    }

    private func play(_ take: Take) {
        guard let id = room.recorder.localID, let p = room.store.production(id) else { return }
        player.stop()
        let url = room.store.takeURL(p, take)
        Task { await player.play(url) }
    }

    private func again(_ snap: ReadSnapshot, _ line: String) {
        room.send(["type": "again", "line": line, "base": snap.cursorGen])
    }

    private func review(_ pid: String, _ take: Take, state: String, note: String?) {
        guard let publishing = room.publishing else { return }
        Task {
            do { try await publishing.review(pid, takeID: take.id, state: state, note: note); failure = nil } catch let r as PlaysRefusal {
                failure = ReadCore.refusal(r.code ?? "error")
            } catch { failure = ReadCore.refusal("error") }
        }
    }

    private func loadClass(_ snap: ReadSnapshot) async {
        guard snap.kind == "class", snap.productionID != nil, let classID = snap.classID, let publishing = room.publishing else { return }
        under13 = try? await publishing.under13(classID: classID)
    }

    @ViewBuilder private func publishing(_ snap: ReadSnapshot) -> some View {
        if snap.kind == "class", snap.productionID != nil, let production = room.recorder.production {
            if under13 == true {
                Text("An under-13 class never publishes.").font(TypeRamp.caption).foregroundStyle(Color.semanticError)
            } else if under13 == false, Relay.isComplete(production, room.script) {
                RoomPublishForm(room: room, pid: snap.productionID ?? "")
            }
        }
    }
}

/// Publish under my name (PLAYS-DESIGN §12.10 item 5): the credit name, the CC0 consent, then each line from this device.
struct RoomPublishForm: View {
    @Bindable var room: RoomReaderModel
    let pid: String
    @AppStorage("ed.readName") private var credit = ""
    @State private var consent: PlaysConsent?
    @State private var agreed = false
    @State private var performers = false
    @State private var release = false
    @State private var busy = false
    @State private var result: String?
    @State private var refusal: String?

    var body: some View {
        PublishFormFields(
            credit: $credit, performers: $performers, release: $release, agreed: $agreed,
            terms: consent.map { $0.publishes == true ? $0.text : "Publishing opens when the Ear Drama archive account is connected." },
            canPublish: agreed && consent?.publishes == true && !credit.trimmingCharacters(in: .whitespaces).isEmpty && !busy,
            refusal: refusal, result: result, publish: publish)
            .task { consent = try? await room.publishing?.consent() }
    }

    private func publish() {
        guard performers, release else { refusal = ReadCore.refusal("confirmations_required"); return }
        busy = true
        refusal = nil
        result = "Queued for archive.org"
        Task {
            defer { busy = false }
            if let code = await room.recorder.publish(creditName: String(credit.trimmingCharacters(in: .whitespaces).prefix(40)), pid: pid) {
                refusal = ReadCore.refusal(code)
                result = nil
            } else {
                result = "On archive.org"
            }
        }
    }
}
#endif
