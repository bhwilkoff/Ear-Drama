import Foundation
import SQLite3
import Synchronization

// Read-only query layer over the served projection (docs/CATALOG-CONTRACT.md
// §3, §5). The database stays on disk and a screen decodes only the rows it
// shows, so resident memory is the visible rows, never the catalog. Ported
// from Archive Watch's CatalogDB: the checked step loop and the corruption
// report carry over; the schema and the verbs are Ear Drama's.
//
// Opened FULLMUTEX so a query may run off the main actor (the full catalog is
// 133 MB and 121,907 episodes); the handle is never written.

nonisolated(unsafe) private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

nonisolated final class CatalogDatabase: @unchecked Sendable {
    /// The lowest `meta.schemaVersion` this build reads.
    static let minimumSchemaVersion = 1

    let path: String
    private let handle: OpaquePointer
    private let hasSponsor: Bool
    private let hasNoRecommend: Bool
    private let hasLoudness: Bool
    private let hasTranscript: Bool
    /// The index carries the transcript column (contract §3.4), so a match can
    /// be told apart as transcript-only.
    private let ftsHasTranscript: Bool
    /// `meta.rightsLines` (contract §5.5), or the contract's strings when absent.
    let rightsLines: [String: String]
    private let sawCorruption = Mutex(false)
    /// Called once when a read proves the FILE is bad (not merely busy), so the
    /// owner can discard a torn download and its ETag.
    private let onCorruption: @Sendable () -> Void

    init?(path: String, onCorruption: @escaping @Sendable () -> Void = {}) {
        var h: OpaquePointer?
        guard sqlite3_open_v2(path, &h, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let h else {
            if let h { sqlite3_close(h) }
            return nil
        }
        // mmap off: a torn file faults the process under mmap instead of
        // returning a recoverable SQLITE_CORRUPT.
        sqlite3_exec(h, "PRAGMA mmap_size=0;", nil, nil, nil)
        self.path = path
        self.handle = h
        self.onCorruption = onCorruption
        hasSponsor = Self.columnExists(h, table: "episodes", column: "sponsor")
        hasNoRecommend = Self.columnExists(h, table: "episodes", column: "no_recommend")
        hasLoudness = Self.columnExists(h, table: "episodes", column: "loudness_i")
            && Self.columnExists(h, table: "episodes", column: "loudness_tp")
        hasTranscript = Self.columnExists(h, table: "episodes", column: "transcript_url")
            && Self.columnExists(h, table: "episodes", column: "has_transcript")
        ftsHasTranscript = Self.columnExists(h, table: "episodes_fts", column: "transcript")
        rightsLines = Self.publishedRightsLines(h) ?? RightsDisplay.contract
        guard let version = Self.schemaVersion(h), version >= Self.minimumSchemaVersion else {
            sqlite3_close(h)
            return nil
        }
    }

    deinit { sqlite3_close(handle) }

    // MARK: - Validation (before a downloaded file becomes the live one)

    /// The contract's swap gate (§2): `PRAGMA integrity_check` is ok, the
    /// schema is one this build reads, and the catalog is not empty.
    static func validate(path: String) -> Bool {
        var h: OpaquePointer?
        guard sqlite3_open_v2(path, &h, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let h else {
            if let h { sqlite3_close(h) }
            return false
        }
        defer { sqlite3_close(h) }
        guard let version = schemaVersion(h), version >= minimumSchemaVersion else { return false }
        var ok = false
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(h, "PRAGMA integrity_check;", -1, &stmt, nil) == SQLITE_OK,
           sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0) {
            ok = String(cString: c) == "ok"
        }
        sqlite3_finalize(stmt)
        guard ok else { return false }
        if sqlite3_prepare_v2(h, "SELECT count(*) FROM episodes;", -1, &stmt, nil) == SQLITE_OK,
           sqlite3_step(stmt) == SQLITE_ROW {
            ok = sqlite3_column_int64(stmt, 0) > 0
        } else {
            ok = false
        }
        sqlite3_finalize(stmt)
        return ok
    }

    private static func schemaVersion(_ h: OpaquePointer) -> Int? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(h, "SELECT value FROM meta WHERE key = 'schemaVersion';", -1, &stmt, nil) == SQLITE_OK
        else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0) else { return nil }
        return Int(String(cString: c).trimmingCharacters(in: CharacterSet(charactersIn: "\" ")))
    }

    private static func publishedRightsLines(_ h: OpaquePointer) -> [String: String]? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(h, "SELECT value FROM meta WHERE key = 'rightsLines';", -1, &stmt, nil) == SQLITE_OK
        else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0),
              let data = String(cString: c).data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([String: String].self, from: data)
    }

    private static func columnExists(_ h: OpaquePointer, table: String, column: String) -> Bool {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(h, "PRAGMA table_info(\(table));", -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let c = sqlite3_column_text(stmt, 1), String(cString: c) == column { return true }
        }
        return false
    }

    var metaCounts: String? {
        rows("SELECT value FROM meta WHERE key = 'counts'") { $0.text(0) }.first ?? nil
    }

    // MARK: - Named filter clauses (contract §5)

    /// `recommendAnd`: every surface that CHOOSES for the listener applies it;
    /// every surface the listener drives does not.
    private var recommendAnd: String { hasNoRecommend ? "AND e.no_recommend IS NULL" : "" }

    // MARK: - Verbs

    private static let seriesColumns = "s.key, s.name, s.genre, s.first_date, s.last_date, s.networks, s.episodes"
    private static let episodeColumns = """
        e.id, e.series_key, s.name, e.air_date, e.season, e.num, e.title, e.length_s, \
        e.rights, e.rights_basis, e.network
        """
    /// R1: oldest first, everywhere. SQLite sorts NULL first on ASC, so the
    /// undated rows are pushed to the end explicitly.
    private static let oldestFirst = "e.air_date IS NULL, e.air_date, e.num IS NULL, e.num, e.rowid"

    /// `seriesBrowse(genre, network, decade, kind)`. `kind` waits on the
    /// `runs` table, which the served projection does not carry yet.
    /// `recommendAnd` applies only when a shelf asks (`forShelf`).
    func seriesBrowse(genre: String? = nil, network: String? = nil, decade: Int? = nil,
                      forShelf: Bool = false, limit: Int = 20_000) -> [SeriesRow] {
        var clauses = ["s.episodes > 0"]
        var binds: [Bind] = []
        if let genre { clauses.append("s.genre = ?"); binds.append(.text(genre)) }
        if let network {
            clauses.append("EXISTS (SELECT 1 FROM json_each(s.networks) j WHERE j.value = ?)")
            binds.append(.text(network))
        }
        if let decade {
            clauses.append("s.first_date <= ? AND s.last_date >= ?")
            binds.append(.text("\(decade + 9)-12-31"))
            binds.append(.text("\(decade)-01-01"))
        }
        if forShelf, hasNoRecommend {
            clauses.append("EXISTS (SELECT 1 FROM episodes e WHERE e.series_key = s.key \(recommendAnd))")
        }
        let sql = """
            SELECT \(Self.seriesColumns) FROM series s WHERE \(clauses.joined(separator: " AND "))
            ORDER BY s.name COLLATE NOCASE LIMIT \(limit)
            """
        return rows(sql, binds, Self.series)
    }

    /// The genres present, most series first, for the browse filter.
    func genres() -> [String] {
        rows("SELECT genre FROM series WHERE genre IS NOT NULL AND episodes > 0 GROUP BY genre ORDER BY count(*) DESC") {
            $0.text(0)
        }.compactMap { $0 }
    }

    /// The networks present, most series first, for the browse filter.
    func networks(limit: Int = 24) -> [String] {
        rows("""
            SELECT j.value FROM series s, json_each(s.networks) j WHERE s.episodes > 0
            GROUP BY j.value ORDER BY count(*) DESC LIMIT \(limit)
            """) { $0.text(0) }.compactMap { $0 }
    }

    /// The decades any series spans, oldest first.
    func decades() -> [Int] {
        let span = rows("SELECT min(first_date), max(last_date) FROM series WHERE episodes > 0") {
            ($0.text(0).flatMap { Int($0.prefix(4)) }, $0.text(1).flatMap { Int($0.prefix(4)) })
        }.first
        guard let first = span?.0, let last = span?.1 else { return [] }
        return Array(stride(from: first / 10 * 10, through: last / 10 * 10, by: 10))
    }

    func series(key: String) -> SeriesRow? {
        rows("SELECT \(Self.seriesColumns) FROM series s WHERE s.key = ?", [.text(key)], Self.series).first
    }

    /// `seriesPage(key)`: its episodes by broadcast season, oldest first (R1).
    func seriesPage(key: String) -> SeriesPage? {
        guard let series = series(key: key) else { return nil }
        let episodes = rows("""
            SELECT \(Self.episodeColumns) FROM episodes e JOIN series s ON s.key = e.series_key
            WHERE e.series_key = ? ORDER BY \(Self.oldestFirst)
            """, [.text(key)], Self.episode)
        var groups: [SeasonGroup] = []
        var current: [EpisodeRow] = []
        var currentSeason: String?? = .none
        for episode in episodes {
            if currentSeason != .some(episode.season), !current.isEmpty {
                groups.append(SeasonGroup(season: currentSeason ?? nil, episodes: current))
                current = []
            }
            currentSeason = .some(episode.season)
            current.append(episode)
        }
        if !current.isEmpty { groups.append(SeasonGroup(season: currentSeason ?? nil, episodes: current)) }
        return SeriesPage(series: series, seasons: groups)
    }

    /// Resolves a forwarded id (§3.5) so a saved position or link never breaks.
    func resolve(_ id: String) -> String {
        (rows("SELECT new_id FROM episode_aliases WHERE old_id = ?", [.text(id)]) { $0.text(0) }.first ?? nil) ?? id
    }

    /// `episodeDetail(id)`: the row, its credits joined to people, and every
    /// recording in rank order (rank 0 is the default copy).
    func episodeDetail(id rawID: String) -> EpisodeDetail? {
        let id = resolve(rawID)
        let sponsorColumn = hasSponsor ? "e.sponsor" : "NULL"
        let loudnessColumns = hasLoudness ? "e.loudness_i, e.loudness_tp" : "NULL, NULL"
        // §3.1: shown only where the gate passed, whatever else the row carries.
        let transcriptColumn = hasTranscript ? "CASE WHEN e.has_transcript = 1 THEN e.transcript_url END" : "NULL"
        let found = rows("""
            SELECT \(Self.episodeColumns), \(sponsorColumn), \(loudnessColumns), \(transcriptColumn)
            FROM episodes e JOIN series s ON s.key = e.series_key WHERE e.id = ?
            """, [.text(id)]) { row -> (EpisodeRow, String?) in
            var episode = Self.episode(row)
            episode.loudnessI = row.double(12)
            episode.loudnessTP = row.double(13)
            episode.transcriptURL = row.text(14).flatMap { URL(string: $0) }
            return (episode, row.text(11))
        }.first
        guard let (episode, sponsor) = found else { return nil }
        let credits = rows("""
            SELECT c.person_id, p.name, c.role, c.character FROM credits c JOIN people p ON p.id = c.person_id
            WHERE c.episode_id = ? ORDER BY c.rowid
            """, [.text(id)]) { row in
            Credit(personID: row.text(0) ?? "", name: row.text(1) ?? "", role: row.text(2), character: row.text(3))
        }
        let recordings = rows("""
            SELECT rank, archive_id, url, format, kbps, length_s, variant, partial FROM recordings
            WHERE episode_id = ? ORDER BY rank
            """, [.text(id)]) { row -> Recording? in
            guard let raw = row.text(2), let url = URL(string: raw) else { return nil }
            return Recording(rank: row.int(0) ?? 0, archiveID: row.text(1) ?? "", url: url, format: row.text(3),
                             kbps: row.int(4), lengthSeconds: row.double(5), variant: row.text(6),
                             partial: (row.int(7) ?? 0) != 0)
        }.compactMap { $0 }
        let rightsLine = RightsDisplay.line(rights: episode.rights, basis: episode.rightsBasis, lines: rightsLines)
        return EpisodeDetail(episode: episode, sponsor: sponsor, credits: credits, recordings: recordings,
                             rightsLine: rightsLine)
    }

    /// Episodes by id, in the order asked (the person's own history).
    func episodes(ids: [String]) -> [EpisodeRow] {
        guard !ids.isEmpty else { return [] }
        let resolved = ids.map(resolve)
        let marks = Array(repeating: "?", count: resolved.count).joined(separator: ",")
        let found = rows("""
            SELECT \(Self.episodeColumns) FROM episodes e JOIN series s ON s.key = e.series_key
            WHERE e.id IN (\(marks))
            """, resolved.map { .text($0) }, Self.episode)
        let byID = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return resolved.compactMap { byID[$0] }
    }

    /// `search(q)`: word-prefix, never substring, on every platform (§3.4).
    /// "sorr" finds "Sorry, Wrong Number" and never "Mr. Sorrowful".
    func search(_ query: String, limit: Int = 100) -> SearchResults {
        guard let match = Self.ftsQuery(query) else { return SearchResults() }
        // The same terms without the transcript column: a row the full match
        // finds and this one does not was found by its transcript alone.
        let elsewhere = ftsHasTranscript ? Self.ftsQuery(query, columns: Self.nonTranscriptColumns) : nil
        let flag = elsewhere == nil ? "0"
            : "e.rowid NOT IN (SELECT rowid FROM episodes_fts WHERE episodes_fts MATCH ?)"
        var binds: [Bind] = elsewhere.map { [.text($0)] } ?? []
        binds.append(.text(match))
        let found = rows("""
            SELECT \(Self.episodeColumns), \(flag) FROM episodes_fts f JOIN episodes e ON e.rowid = f.rowid
            JOIN series s ON s.key = e.series_key
            WHERE episodes_fts MATCH ? ORDER BY f.rank LIMIT \(limit)
            """, binds) { row in (Self.episode(row), (row.int(11) ?? 0) != 0) }
        let episodes = found.map(\.0)
        let transcriptOnly = Set(found.filter(\.1).map(\.0.id))
        let phrase = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "%", with: "").replacingOccurrences(of: "_", with: "")
        let series = rows("""
            SELECT \(Self.seriesColumns) FROM series s
            WHERE s.episodes > 0 AND (s.name LIKE ? OR s.name LIKE ?)
            ORDER BY s.episodes DESC LIMIT 20
            """, [.text("\(phrase)%"), .text("% \(phrase)%")], Self.series)
        return SearchResults(series: series, episodes: episodes, transcriptOnly: transcriptOnly)
    }

    /// Every FTS column but `transcript` (contract §3.4).
    static let nonTranscriptColumns = ["title", "series", "people"]

    /// Each word becomes a quoted prefix term (`"sorr"*`), so FTS5 syntax in
    /// what someone types is never interpreted. `columns` limits every term
    /// to those columns (`{title series people} : "sorr"*`).
    static func ftsQuery(_ query: String, columns: [String]? = nil) -> String? {
        let words = query.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" })
            .map { $0.replacingOccurrences(of: "'", with: "") }
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return nil }
        let filter = columns.map { "{\($0.joined(separator: " "))} : " } ?? ""
        return words.map { "\(filter)\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"*" }
            .joined(separator: " ")
    }

    /// `shelf(rule)`: a Listen shelf. Always `recommendAnd`.
    func shelf(_ rule: ShelfRule, limit: Int = 20) -> [EpisodeRow] {
        switch rule {
        case let .onThisDay(month, day):
            let suffix = String(format: "-%02d-%02d", month, day)
            return rows("""
                SELECT \(Self.episodeColumns) FROM episodes e JOIN series s ON s.key = e.series_key
                WHERE e.air_date LIKE ? \(recommendAnd) ORDER BY e.air_date, e.rowid LIMIT \(limit)
                """, [.text("%\(suffix)")], Self.episode)
        case let .genreFirsts(genre):
            return rows("""
                SELECT \(Self.episodeColumns) FROM series s
                JOIN episodes e ON e.id = (
                    SELECT e.id FROM episodes e WHERE e.series_key = s.key \(recommendAnd)
                    ORDER BY \(Self.oldestFirst) LIMIT 1)
                WHERE s.genre = ? ORDER BY s.episodes DESC, s.key LIMIT \(limit)
                """, [.text(genre)], Self.episode)
        }
    }

    /// `withPerson(id)`: every episode crediting a person, oldest first.
    func withPerson(_ personID: String, limit: Int = 500) -> [EpisodeRow] {
        rows("""
            SELECT DISTINCT \(Self.episodeColumns) FROM credits c JOIN episodes e ON e.id = c.episode_id
            JOIN series s ON s.key = e.series_key WHERE c.person_id = ? ORDER BY \(Self.oldestFirst) LIMIT \(limit)
            """, [.text(personID)], Self.episode)
    }

    // MARK: - Row decoding

    private static func series(_ row: Row) -> SeriesRow {
        let networks = row.text(5).flatMap { $0.data(using: .utf8) }
            .flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        return SeriesRow(key: row.text(0) ?? "", name: row.text(1) ?? "", genre: row.text(2),
                         firstDate: row.text(3), lastDate: row.text(4), networks: networks,
                         episodeCount: row.int(6) ?? 0)
    }

    private static func episode(_ row: Row) -> EpisodeRow {
        EpisodeRow(id: row.text(0) ?? "", seriesKey: row.text(1) ?? "", seriesName: row.text(2) ?? "",
                   airDate: row.text(3), season: row.text(4), number: row.int(5), title: row.text(6),
                   lengthSeconds: row.double(7), rights: row.text(8) ?? "unclaimed",
                   rightsBasis: row.text(9), network: row.text(10))
    }

    // MARK: - Statement plumbing

    enum Bind { case text(String), int(Int) }

    struct Row {
        fileprivate let stmt: OpaquePointer
        func text(_ i: Int32) -> String? {
            sqlite3_column_text(stmt, i).map { String(cString: $0) }
        }
        func int(_ i: Int32) -> Int? {
            sqlite3_column_type(stmt, i) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(stmt, i))
        }
        func double(_ i: Int32) -> Double? {
            sqlite3_column_type(stmt, i) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, i)
        }
    }

    private func rows<T>(_ sql: String, _ binds: [Bind] = [], _ map: (Row) -> T) -> [T] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            print("[CatalogDatabase] prepare failed: \(String(cString: sqlite3_errmsg(handle)))")
            return []
        }
        defer { sqlite3_finalize(stmt) }
        for (i, bind) in binds.enumerated() {
            switch bind {
            case let .text(s): sqlite3_bind_text(stmt, Int32(i + 1), s, -1, SQLITE_TRANSIENT)
            case let .int(n): sqlite3_bind_int64(stmt, Int32(i + 1), Int64(n))
            }
        }
        var out: [T] = []
        // The step result is CHECKED: a torn file opens cleanly and fails only
        // here, and treating every non-row answer as "done" would show empty
        // shelves that look like a filter matching nothing.
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW { out.append(map(Row(stmt: stmt))); continue }
            if rc != SQLITE_DONE { noteBadRead(rc) }
            break
        }
        return out
    }

    private func noteBadRead(_ rc: Int32) {
        let fatal = [SQLITE_CORRUPT, SQLITE_NOTADB, SQLITE_IOERR, SQLITE_CANTOPEN]
        guard fatal.contains(rc & 0xFF) else {
            print("[CatalogDatabase] read ended rc=\(rc) (transient; catalog kept)")
            return
        }
        let first = sawCorruption.withLock { seen in
            defer { seen = true }
            return !seen
        }
        guard first else { return }
        print("[CatalogDatabase] corrupt catalog (rc=\(rc))")
        onCorruption()
    }
}
