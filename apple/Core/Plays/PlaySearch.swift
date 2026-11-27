#if os(iOS) || os(macOS)
import Foundation

// The play search's state (B31 §3.3, iOS-DESIGN §4.5), drawn by `PlaySearchSections`; the rules are FindCore's.

/// A play search's state: title and author hits, characters, and the lines found in the scripts the line shards name,
/// read a batch at a time within about 1.6 MB a press (the web's LINE_BUDGET).
@Observable
final class PlaySearchModel {
    enum Phase: Equatable { case idle, loading, done }

    private(set) var query = ""
    private(set) var phase: Phase = .idle
    private(set) var titled: [PlayRow] = []
    private(set) var characters: [FindCore.CharacterHit] = []
    private(set) var hits: [FindCore.LineHit] = []
    private(set) var reading = false
    @ObservationIgnored private var ordered: [FindCore.Ordered] = []
    @ObservationIgnored private var prefix = Set<String>()
    private(set) var from = 0
    private(set) var total = 0

    static let lineBudget = 1_600_000

    var shown: [FindCore.LineHit] { FindCore.shownHits(hits) }
    var left: Int { total - from }
    var foundAny: Bool { !titled.isEmpty || !characters.isEmpty || !shown.isEmpty }

    func run(_ q: String, plays: PlaysLibrary) async {
        query = q
        phase = .loading
        titled = []; characters = []; hits = []; ordered = []; from = 0; total = 0; prefix = []
        let rows = plays.rows
        titled = FindCore.titleHits(rows, q)
        async let names = try? plays.characterNames()
        let lined = (try? await FindCore.lineCandidates(q) { try await plays.shard("lines", $0) }) ?? nil
        var cands = lined?.cands ?? []
        if lined == nil {
            // A library built before the line shards: the plays that say every word (search/said).
            let said: (all: [Int], exact: [Int]) = (try? await FindCore.saidPlays(q) { try await plays.shard("said", $0) }) ?? ([], [])
            cands = (said.exact.isEmpty ? said.all : said.exact).map { FindCore.Candidate(play: $0, lines: nil) }
        }
        let found = await names
        guard query == q, !Task.isCancelled else { return }
        characters = FindCore.characterHits(rows, found ?? nil, q)
        prefix = lined?.prefix ?? []
        ordered = FindCore.orderCandidates(cands, rows, q)
        total = ordered.count
        phase = .done
        if !ordered.isEmpty { await more(plays: plays) }
    }

    /// Reads the next batch of scripts once, not keeping them, and keeps their best lines.
    func more(plays: PlaysLibrary) async {
        guard !reading, from < ordered.count else { return }
        reading = true
        defer { reading = false }
        let q = query, to = FindCore.nextBatch(ordered, from: from, budget: Self.lineBudget)
        let batch = Array(ordered[from..<to]), prefix = prefix
        let got = await withTaskGroup(of: (Int, FindCore.LineHit?).self) { group in
            for (i, c) in batch.enumerated() {
                group.addTask {
                    guard let script = try? await plays.scriptOnce(c.row) else { return (i, nil) }
                    return (i, FindCore.lineHit(script, row: c.row, q, places: c.lines, prefix: prefix))
                }
            }
            var out: [(Int, FindCore.LineHit?)] = []
            for await r in group { out.append(r) }
            return out.sorted { $0.0 < $1.0 }.compactMap(\.1)
        }
        guard query == q else { return }
        from = to
        hits += got
    }
}
#endif
