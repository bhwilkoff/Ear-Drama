#if os(iOS) || os(macOS)
import SwiftUI

// Your parts, and the teacher's receiving end (PLAYS-DESIGN §12.11, iOS-DESIGN §4.20, macOS-DESIGN §4.10): a seat at home.
// Its parts from the class, each line with its take's state on this device ("On this device · sends when Ms. Ortiz is in
// Ear Drama", "Sending", "Sent") and the teacher's review. The takes are the studio's own, recorded in a production kept on
// this device; the sender is RelayHub. Every word is a label, a fact, a warning or a refusal.

/// The lines of a part with each take's state. A plain stack (no List), so it draws in a screen and to a PNG.
struct RelayLinesView: View {
    let rows: [RelayCore.Row]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: row.text).font(TypeRamp.body)
                    if let state = row.state { Text(verbatim: state).font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted) }
                    if let review = row.review {
                        Text(verbatim: review).font(TypeRamp.caption).foregroundStyle(row.again ? Color.semanticError : Color.brandTextMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
                Divider()
            }
        }
    }
}

/// The classes this device holds a seat in (names only; the key is in the Keychain).
nonisolated enum HomeSeats {
    private static let key = "ed.homeSeats"
    static func load() -> [SeatLink] {
        guard let d = UserDefaults.standard.data(forKey: key), let l = try? JSONDecoder().decode([SeatLink].self, from: d) else { return [] }
        return l
    }
    static func add(_ s: SeatLink) {
        let l = load().filter { $0.classID != s.classID } + [s]
        if let d = try? JSONEncoder().encode(l) { UserDefaults.standard.set(d, forKey: key) }
    }
}

struct PartsScreen: View {
    @Environment(PlaysLibrary.self) private var plays
    @Environment(AppStore.self) private var app
    @State private var blocks: [Block] = []
    @State private var loaded = false
    @State private var failure: String?
    @State private var classCode = ""
    @State private var seatList: ReadSeatList?

    private let classWire = WorkerReadClass(api: .shared)
    private let vault: any SeatKeyVault = KeychainSeatVault()

    struct Block: Identifiable {
        var id: String { seat.classID + "/" + production.id }
        var seat: SeatLink
        var className: String
        var production: SeatHome.Production
        var script: PlayScript
        var key: String
    }

    var body: some View {
        List {
            if HomeSeats.load().isEmpty {
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
                            Button { Task { await claim(s, seatList.class.id) } } label: { Text(verbatim: s.label).font(TypeRamp.body) }
                        }
                    }
                }
            } else if loaded && blocks.isEmpty && failure == nil {
                Text("No parts yet.").font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
            }
            ForEach(blocks) { b in
                Section("\(b.seat.label) \u{00B7} \(b.className)") {
                    Text(verbatim: b.production.title).font(TypeRamp.bodyStrong)
                    ForEach(parts(b), id: \.self) { part in partBlock(b, part) }
                }
            }
            if let failure { Label(failure, systemImage: "exclamationmark.triangle").foregroundStyle(Color.semanticError) }
        }
        .navigationTitle("Your Parts")
        .task { await load() }
        .onChange(of: plays.relay.revision) { _, _ in rebuild() }
        .refreshable { await load() }
    }

    private func parts(_ b: Block) -> [String] {
        var seen = Set<String>()
        return b.production.assignments.map(\.part).filter { seen.insert($0).inserted }
    }

    @ViewBuilder
    private func partBlock(_ b: Block, _ part: String) -> some View {
        let lines = b.script.lines.filter { $0.part.rawValue == part && mine(b).contains($0.id) }
        HStack {
            Text(verbatim: "\(PartID(rawValue: part).title) \u{00B7} \(lines.count == 1 ? "1 line" : "\(lines.count) lines")").font(TypeRamp.bodyStrong)
            Spacer()
            Button("Record") { record(b, PartID(rawValue: part)) }.buttonStyle(.borderedProminent)
        }
        RelayLinesView(rows: rowsFor(b, lines))
    }

    private func mine(_ b: Block) -> Set<String> {
        Set(RelayCore.assignedLines(cast: b.script.lines.map { ($0.id, $0.part.rawValue) }, assignments: b.production.assignments))
    }

    private func rowsFor(_ b: Block, _ lines: [ScriptLine]) -> [RelayCore.Row] {
        let local = plays.store.findShared(b.production.id)
        let remote = Dictionary(b.production.takes.map { ($0.lineID, $0) }, uniquingKeysWith: { _, n in n })
        let link = local.flatMap { plays.store.share($0.id) }
        let sender = local.flatMap { plays.relay.sender(for: $0.id) }
        return RelayCore.rows(lines: lines, local: local, remote: remote, sentHere: Set(link?.sent ?? []), refused: link?.refused ?? [:],
                              sending: sender?.sending, name: sender?.name ?? receiverName[b.production.id])
    }

    @State private var receiverName: [String: String] = [:]

    private func rebuild() { blocks = blocks }

    private func load() async {
        failure = nil
        var out: [Block] = []
        for seat in HomeSeats.load() {
            guard let key = vault.key(forClass: seat.classID) else { continue }
            do {
                let home = try await WorkerSeat(api: .shared).home(key: key)
                for p in home.productions where !p.assignments.isEmpty {
                    guard let script = await plays.script(id: p.scriptID, revision: p.scriptRevision) else { failure = ReadCore.refusal("revision_mismatch"); continue }
                    out.append(Block(seat: seat, className: home.class.name, production: p, script: script, key: key))
                    if let r = try? await WorkerSeat(api: .shared).receiver(key: key, pid: p.id), let n = r.name { receiverName[p.id] = n }
                }
            } catch let f as ReadFailure { failure = ReadCore.refusal(f.code == "seat_key_required" ? "seat_key_required" : f.code) } catch { failure = ReadCore.refusal("error") }
        }
        blocks = out
        loaded = true
        for b in out { if let l = plays.store.findShared(b.production.id) { await plays.relay.kick(l.id) } }
    }

    private func loadSeats() async {
        failure = nil
        do { seatList = try await classWire.seatList(code: classCode) } catch let f as ReadFailure { failure = ReadCore.refusal(f.code) } catch { failure = ReadCore.refusal("error") }
    }

    private func claim(_ s: ReadSeatList.Seat, _ classID: String) async {
        failure = nil
        do {
            let r = try await classWire.seatClaim(code: classCode, seat: s.id, move: false)
            vault.set(r.seatKey, forClass: classID)
            HomeSeats.add(SeatLink(classID: classID, label: s.label))
            await load()
        } catch let f as ReadFailure { failure = ReadCore.refusal(f.code) } catch { failure = ReadCore.refusal("error") }
    }

    /// Opens the studio on a production kept on this device, linked to the seat; its takes then pass through whenever the teacher's app is open.
    private func record(_ b: Block, _ part: PartID) {
        do {
            let local = try plays.store.findShared(b.production.id) ?? plays.store.create(b.script)
            try plays.store.linkSeat(local.id, pid: b.production.id, classID: b.seat.classID, label: b.seat.label, key: b.key,
                                     assignments: b.production.assignments, vault: vault)
            Task { await plays.relay.kick(local.id) }
            app.push(PlayRoute.recording(production: local.id, part: part))
        } catch { failure = ReadCore.refusal("error") }
    }
}
#endif
