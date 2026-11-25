#if os(iOS) || os(macOS)
import Foundation
import Observation

/// A run of calls collapsed into one, a moment after the last (a script is kept as it is corrected, not once a key).
@MainActor
final class OwnLater {
    private let wait: Duration
    private let act: () async -> Void
    private var task: Task<Void, Never>?

    init(_ wait: Duration, _ act: @escaping () async -> Void) {
        self.wait = wait
        self.act = act
    }

    var pending: Bool { task != nil }

    func callAsFunction() {
        task?.cancel()
        task = Task { [weak self, wait] in
            guard (try? await Task.sleep(for: wait)) != nil, let self else { return }
            self.task = nil
            await self.act()
        }
    }

    /// Takes back a waiting call; whether there was one.
    func take() -> Bool {
        guard task != nil else { return false }
        task?.cancel()
        task = nil
        return true
    }

    /// Now, when one is waiting.
    func flush() {
        if take() { Task { await act() } }
    }
}

/// The parts page (PLAYS-DESIGN §13 item 3, iOS-DESIGN §4.21): one script being corrected. Every change is
/// `OwnScript.apply`'s; every step is kept as it is made. No view and no word of its own.
@Observable
final class OwnPartsModel {
    private(set) var rec: OwnRecord
    /// The parts, largest first, then those named but not yet given a line.
    private(set) var parts: [OwnPart] = []
    private(set) var near: [Int: [String]] = [:]
    private(set) var open = 0
    /// The last write that failed, in essential words; the page keeps the work.
    private(set) var problem: String?
    /// A change refused outside a sheet.
    var refusal: String?
    /// The line Next goes on from.
    var current = 0
    private(set) var finished = false
    /// Moves on every change, for the haptic.
    private(set) var changes = 0
    @ObservationIgnored weak var undoManager: UndoManager?
    @ObservationIgnored private let store: OwnScripts
    @ObservationIgnored private var started = false
    @ObservationIgnored private lazy var save = OwnLater(.milliseconds(350)) { [weak self] in _ = await self?.write() }

    init(_ rec: OwnRecord, store: OwnScripts) {
        self.rec = rec
        self.store = store
        // A casting by ear is corrected as any script: its marks are its lines' own parts, its left-out lines gone.
        if rec.ear != nil { self.rec.doc = OwnScript.settle(rec.doc) }
        refresh()
    }

    var lines: [OwnLine] { rec.doc.lines }
    var takes: Set<String> { store.takes(rec.id) }
    var canUndo: Bool { !rec.doc.undo.isEmpty }
    var isEar: Bool { rec.ear != nil }
    /// The parts with a line, as a row counts them.
    var partCount: Int { parts.filter { $0.lines > 0 }.count }

    func line(_ k: Int) -> OwnLine? { lines.first { $0.k == k } }
    func index(_ k: Int) -> Int? { lines.firstIndex { $0.k == k } }
    func isLocked(_ line: OwnLine) -> Bool { line.id.map(takes.contains) ?? false }
    func hasTake(part: String) -> Bool {
        let taken = takes
        return lines.contains { $0.kind == "speech" && $0.role == part && ($0.id.map(taken.contains) ?? false) }
    }

    /// The first seven parts' hues, largest first, as the cast sheet gives them.
    func hue(_ name: String?) -> String? {
        guard let name, let i = parts.firstIndex(where: { $0.name == name && $0.lines > 0 }), i < PlayScript.partHues.count else { return nil }
        return PlayScript.partHues[i]
    }

    private func refresh() {
        let order = OwnScript.partsOf(lines)
        let first = Dictionary(order.enumerated().map { ($1.name, $0) }, uniquingKeysWith: { a, _ in a })
        parts = order.sorted { $0.lines != $1.lines ? $0.lines > $1.lines : first[$0.name]! < first[$1.name]! }
            + rec.extras.filter { first[$0] == nil }.map { OwnPart(name: $0, lines: 0) }
        near = OwnBuild.nearest(lines)
        open = lines.reduce(0) { $1.kind == "open" ? $0 + 1 : $0 }
        if !lines.contains(where: { $0.k == current }) { current = lines.first?.k ?? 0 }
    }

    // MARK: Changes

    /// One change, drawn and kept; its refusal when it is not allowed.
    @discardableResult
    func change(_ op: OwnOp) -> OwnRefusal? {
        let before = rec.doc
        let r = OwnScript.apply(before, op, OwnEnv(takes: takes))
        if let why = r.refusal { return why }
        guard r.doc != before else { return nil }
        rec.doc = r.doc
        refusal = nil
        started = true
        changes += 1
        refresh()
        save()
        if op.op != .undo { registerUndo() }
        return nil
    }

    private func registerUndo() {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { model in MainActor.assumeIsolated { model.undo(fromManager: true) } }
    }

    /// The toolbar's Undo takes its step off the system's stack too, so shake and Command-Z never take back a second.
    func undo(fromManager: Bool = false) {
        if !fromManager, let undoManager, undoManager.canUndo {
            undoManager.undo()
            return
        }
        change(OwnOp(op: .undo))
    }

    func give(_ k: Int, _ to: OwnTarget) {
        current = k
        refusal = change(OwnOp(op: .assign, line: k, to: to)).map(OwnText.say)
    }

    func rename(title raw: String) -> OwnRefusal? {
        let title = OwnScript.trim(OwnScript.normalize(raw))
        if title.isEmpty { return .no_title }
        if title.utf16.count > OwnScript.maxTitle { return .title_too_long }
        rec.title = title
        save()
        return nil
    }

    /// A part named before any line is given to it: it waits in the lists until one is.
    func addPart(_ raw: String) -> (name: String, refusal: OwnRefusal?) {
        let name = OwnScript.partName(OwnScript.normalize(raw))
        if let why = OwnScript.partNameRefusal(name) { return (name, why) }
        if !parts.contains(where: { $0.name == name }) {
            rec.extras.append(name)
            refresh()
            save()
        }
        return (name, nil)
    }

    func dropPart(_ name: String) {
        rec.extras.removeAll { $0 == name }
        refresh()
        save()
    }

    /// The next line with no part after the current one, around the end.
    func nextOpen() -> Int? {
        guard open > 0 else { return nil }
        let from = started || current != lines.first?.k ? (index(current) ?? -1) : -1
        let n = lines.count
        for i in 0..<n {
            let line = lines[(from + 1 + i + n) % n]
            if line.kind == "open" {
                current = line.k
                started = true
                return line.k
            }
        }
        return nil
    }

    // MARK: What is kept

    @discardableResult
    func write() async -> Bool {
        do {
            try await store.keep(rec)
            problem = nil
            return true
        } catch {
            problem = OwnText.notKept(error)
            return false
        }
    }

    /// What is waiting, now. The write holds the model: the page that had it may already be gone.
    func flush() {
        if save.take() { Task { await self.write() } }
    }

    /// Done: lines with no part become directions and each line gets its id, once. True when it is a script.
    func finish() async -> Bool {
        var next = rec
        next.doc = OwnScript.done(rec.doc)
        next.done = true
        if let why = OwnBuild.refusal(next) {
            problem = why == .too_long || why == .too_many_lines ? "This script is too long." : OwnText.say(why)
            return false
        }
        let before = rec
        rec = next
        _ = save.take()
        guard await write() else {
            rec = before
            refresh()
            return false
        }
        finished = true
        undoManager?.removeAllActions(withTarget: self)
        refresh()
        return true
    }

    func leave() {
        undoManager?.removeAllActions(withTarget: self)
        if !finished { flush() }
    }
}
#endif
