import Foundation
import Testing

/// The free plan (2026-11-23 audit), the mirror of the three "free plan" tests in js/relay.test.js: what an open page costs the
/// one Worker account every app shares. These COUNT asks. The clock is a number the test turns; a pickup that returns nothing
/// is the Worker's 25 s wait, so each ask moves it 25 s.

private nonisolated final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var t = 0
    var now: Int { lock.withLock { t } }
    func advance(_ ms: Int) { lock.withLock { t += ms } }
}

/// A sleep the test opens by hand, so a timer comes due only when the test says.
private nonisolated final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async { await withCheckedContinuation { c in lock.withLock { waiters.append(c) } } }
    func open() { let w = lock.withLock { () -> [CheckedContinuation<Void, Never>] in let x = waiters; waiters = []; return x }; w.forEach { $0.resume() } }
}

private struct Enough: Error {}

private func settle() async { for _ in 0..<60 { await Task.yield() } }

@MainActor
struct RelayFreePlanTests {
    /// A loop whose inbox counts its asks; `cap` ends a loop that would otherwise run on (a mutant), as a refusal.
    private func make(_ clock: Clock, active: Bool, cap: Int = 400, takeAt: Set<Int> = [], onAsk: @escaping @MainActor (Int) -> Void = { _ in },
                      idle: @escaping @MainActor () -> Void) -> (PickupLoop, () -> Int) {
        var calls = 0
        let loop = PickupLoop(active: active, now: { clock.now }, sleep: { _ in }, inbox: {
            calls += 1
            onAsk(calls)
            if calls >= cap { throw Enough() }
            clock.advance(25_000)
            return takeAt.contains(calls)
        }, stopOn: { $0 is Enough }, onIdle: idle)
        return (loop, { calls })
    }

    @Test func aHiddenReceiverHoldsNoPickupAndStopsAfterThirtyIdleMinutes() async {
        let clock = Clock()
        var idle = 0
        let (loop, calls) = make(clock, active: false) { idle += 1 }
        loop.start()
        clock.advance(10 * 60 * 1000)
        await settle()
        #expect(calls() == 0, "no pickup in 10 hidden minutes")
        loop.setActive(true)
        await loop.finished()
        #expect(calls() >= 1, "shown again: it asks")
        #expect(idle == 1, "thirty minutes with no take: it stops and says so once")
        #expect(loop.stopped)
        #expect(calls() <= 74, "pickups in those 30 minutes: \(calls())")
        let at = calls()
        clock.advance(10 * 60 * 1000)
        await settle()
        #expect(calls() == at, "stopped means no more pickups")
    }

    @Test func aTakeResetsTheIdleClock() async {
        let clock = Clock()
        var idle = 0
        let (loop, calls) = make(clock, active: true, takeAt: [40]) { idle += 1 }
        loop.start()
        await loop.finished()
        #expect(idle == 1)
        #expect(calls() >= 100, "a take at 16 minutes keeps it receiving past 30: \(calls()) asks")
    }

    @Test func aPageHiddenMidWaitAsksNoMoreUntilItIsBack() async {
        let clock = Clock()
        var loopRef: PickupLoop?
        let (loop, calls) = make(clock, active: true, onAsk: { n in if n == 5 { loopRef?.setActive(false) } }) {}
        loopRef = loop
        loop.start()
        await settle()
        #expect(calls() == 5, "hidden after the fifth ask: \(calls())")
        clock.advance(20 * 60 * 1000)
        await settle()
        #expect(calls() == 5)
        loop.stop()
    }

    @Test func aBackgroundedAppAsksNothingWhenARetryComesDue() async throws {
        for foreground in [false, true] {
            let gate = Gate()
            let wire = StubWatch()
            let r = try watchRig(wire: wire, gate: gate)
            r.hub.setActive(foreground)
            await r.hub.kick(r.id)
            #expect(wire.probes == 1, "a kick asks once")
            for _ in 0..<12 {
                await settle()
                gate.open()
            }
            await settle()
            if foreground { #expect(wire.probes > 1, "shown: the retries keep asking (control)") }
            else { #expect(wire.probes == 1, "backgrounded: 12 retries came due and none asked, \(wire.probes) asks") }
            if !foreground {
                r.hub.setActive(true)
                await settle()
                #expect(wire.probes == 2, "coming forward asks at once")
            }
            r.hub.stop()
        }
    }
}

@MainActor
private final class StubWatch: SeatWire, @unchecked Sendable {
    var probes = 0
    nonisolated func home(key: String) async throws -> SeatHome {
        SeatHome(seat: .init(id: "s1", label: "Lucy"), class: .init(id: "c1", name: "Room 7"),
                 productions: [.init(id: "pid-1", title: "T", scriptID: "gut-1", scriptRevision: "r1",
                                     assignments: [ReadSnapshot.Assignment(part: "role:LUCY", seat: "s1", from: nil, to: nil)], takes: [])])
    }
    nonisolated func receiver(key: String, pid: String) async throws -> RelayReceiver {
        await MainActor.run { probes += 1; return RelayReceiver(receiving: false, name: nil) }
    }
    nonisolated func send(key: String, pid: String, takeID: String, audio: Data, meta: TakeMeta) async throws { throw ReadFailure(code: "nobody_receiving") }
}

@MainActor
private func watchRig(wire: StubWatch, gate: Gate) throws -> (store: ProductionStore, id: String, hub: RelayHub) {
    let store = ProductionStore(root: FileManager.default.temporaryDirectory.appending(path: "relay-free-\(UUID().uuidString)"))
    let lines = [ScriptLine(id: "l2", kind: .speech, role: "LUCY", parts: [.say("Words of l2 and a few more besides these.")])]
    let script = PlayScript(id: "gut-1", revision: "r1", kind: "radio", title: "T", authors: [],
                            source: .init(name: "Fixture", url: "https://example.org"), rights: .init(bucket: "script_source_cleared", evidence: []),
                            roles: [PlayScript.Role(name: "LUCY", lines: 1, words: 3)], lines: lines)
    var p = try store.create(script)
    let vault = MemorySeatVault()
    try store.linkSeat(p.id, pid: "pid-1", classID: "c1", label: "Lucy", key: String(repeating: "k", count: 24),
                       assignments: [ReadSnapshot.Assignment(part: "role:LUCY", seat: "s1", from: nil, to: nil)], vault: vault)
    let capture = MicrophoneCapture(samples: [Float](repeating: 0.01, count: 4_800), sampleRate: 48_000)
    let file = try store.writeTake(capture, production: p, lineID: "l2")
    p.add(Take(id: "T-l2", lineID: "l2", part: script.lines[0].part, file: file, created: Date(), frames: 4_800, sampleRate: 48_000, capture: .direct,
               heard: [:], loudness: nil, peak: 0.1, bleed: false))
    try store.save(p)
    let hub = RelayHub(store: store, seatWire: wire, vault: vault, sleep: { _ in await gate.wait() })
    return (store, p.id, hub)
}
