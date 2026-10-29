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
    /// Contract §3.3: the pipeline's A-to-Z key; a catalog published before it sorts by `name`.
    private let hasSortName: Bool
    /// Contract §3.3 `series.downloads`, Browse's Popular key; a catalog without it sorts Popular A to Z.
    private let hasDownloads: Bool
    private let hasLoudness: Bool
    private let hasTranscript: Bool
    /// The index carries the transcript column (contract §3.4), so a match can
    /// be told apart as transcript-only.
    private let ftsHasTranscript: Bool
    /// The projection carries portraits (contract §3.3a).
    private let hasArt: Bool
    /// The art columns a credit or person query reads, `a.face` NULL in an older catalog.
    private let artColumnsSQL: String
    private let hasEpisodeStar: Bool
    /// The projection links episodes to castable scripts (contract §3.1, Decision 068).
    private let hasScript: Bool
    private let hasArcs: Bool
    /// Every series' genre and face, read once: rows that mix series draw a tile from it.
    private let seriesLook: [String: (genre: String?, face: Face?)]
    /// `meta.rightsLines` (contract §5.5), or the contract's strings when absent.
    let rightsLines: [String: String]
    /// `meta.listenShelves` (contract §5.1), or nil for a catalog that predates it.
    let publishedShelves: [PublishedShelf]?
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
        hasSortName = Self.columnExists(h, table: "series", column: "sort_name")
        hasDownloads = Self.columnExists(h, table: "series", column: "downloads")
        hasLoudness = Self.columnExists(h, table: "episodes", column: "loudness_i")
            && Self.columnExists(h, table: "episodes", column: "loudness_tp")
        hasTranscript = Self.columnExists(h, table: "episodes", column: "transcript_url")
            && Self.columnExists(h, table: "episodes", column: "has_transcript")
        ftsHasTranscript = Self.columnExists(h, table: "episodes_fts", column: "transcript")
        let art = Self.columnExists(h, table: "people", column: "portrait")
            && Self.columnExists(h, table: "art", column: "url")
        hasArt = art
        let face = art && Self.columnExists(h, table: "art", column: "face")
        artColumnsSQL = art ? "a.url, a.width, a.height, a.credit, a.evidence_url, \(face ? "a.face" : "NULL")"
            : "NULL, NULL, NULL, NULL, NULL, NULL"
        hasEpisodeStar = art && Self.columnExists(h, table: "episodes", column: "star")
        hasScript = Self.columnExists(h, table: "episodes", column: "script")
        hasArcs = Self.columnExists(h, table: "arcs", column: "next_arc")
            && Self.columnExists(h, table: "arc_parts", column: "part")
        seriesLook = Self.loadSeriesLook(h, withFaces: art && Self.columnExists(h, table: "series", column: "star"),
                                         faceColumn: face)
        rightsLines = Self.publishedRightsLines(h) ?? RightsDisplay.contract
        publishedShelves = Self.metaText(h, key: "listenShelves").flatMap(PublishedShelf.parse)
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

    private static func metaText(_ h: OpaquePointer, key: String) -> String? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(h, "SELECT value FROM meta WHERE key = ?;", -1, &stmt, nil) == SQLITE_OK
        else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: c)
    }

    private static func loadSeriesLook(_ h: OpaquePointer, withFaces: Bool,
                                       faceColumn: Bool) -> [String: (genre: String?, face: Face?)] {
        let sql = withFaces ? """
            SELECT s.key, s.genre, p.name, a.url, a.width, a.height, a.credit, a.evidence_url,
            \(faceColumn ? "a.face" : "NULL") FROM series s
            LEFT JOIN people p ON p.id = s.star AND p.portrait IS NOT NULL LEFT JOIN art a ON a.id = p.portrait
            """ : "SELECT key, genre, NULL, NULL, NULL, NULL, NULL, NULL, NULL FROM series"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(h, sql, -1, &stmt, nil) == SQLITE_OK else { return [:] }
        defer { sqlite3_finalize(stmt) }
        var out: [String: (genre: String?, face: Face?)] = [:]
        let text = { (i: Int32) in sqlite3_column_text(stmt, i).map { String(cString: $0) } }
        let int = { (i: Int32) in sqlite3_column_type(stmt, i) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(stmt, i)) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let key = text(0) else { continue }
            var face: Face?
            if let name = text(2), let art = artwork(url: text(3), width: int(4), height: int(5), credit: text(6),
                                                    evidence: text(7), face: text(8)) {
                face = Face(name: name, art: art)
            }
            out[key] = (text(1), face)
        }
        return out
    }

    static func artwork(url: String?, width: Int?, height: Int?, credit: String?, evidence: String?,
                        face: String? = nil) -> Artwork? {
        guard let url = url.flatMap(URL.init(string:)) else { return nil }
        return Artwork(url: url, width: width, height: height, credit: credit, evidence: evidence.flatMap(URL.init(string:)),
                       face: Artwork.FaceBox(face))
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
                      sort: SeriesSort = .name, forShelf: Bool = false, limit: Int = 20_000) -> [SeriesRow] {
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
            ORDER BY \(order(sort)) LIMIT \(limit)
            """
        return rows(sql, binds, decodeSeries)
    }

    /// Popular: counted series first, most downloaded first, then the uncounted by name.
    private func order(_ sort: SeriesSort) -> String {
        let name = "\(hasSortName ? "s.sort_name" : "s.name") COLLATE NOCASE, s.key"
        switch sort {
        case .popular where hasDownloads: return "COALESCE(s.downloads, 0) <= 0, s.downloads DESC, \(name)"
        case .popular, .name: return name
        case .episodes: return "s.episodes DESC, \(name)"
        case .firstAired: return "s.first_date IS NULL, s.first_date, \(name)"
        }
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

    /// The series `key` names, or the one it now is when a later catalog moved
    /// the key (§3.5), so a follow or a series link never breaks.
    func series(key: String) -> SeriesRow? {
        if let hit = seriesRow(key) { return hit }
        let moved = resolveSeries(key)
        return moved == key ? nil : seriesRow(moved)
    }

    private func seriesRow(_ key: String) -> SeriesRow? {
        rows("SELECT \(Self.seriesColumns) FROM series s WHERE s.key = ?", [.text(key)], decodeSeries).first
    }

    /// Resolves a forwarded series key (§3.5); a catalog published before series
    /// forwarding has none.
    func resolveSeries(_ key: String) -> String {
        guard Self.columnExists(handle, table: "series_key_aliases", column: "old_key") else { return key }
        return (rows("SELECT new_key FROM series_key_aliases WHERE old_key = ?", [.text(key)]) { $0.text(0) }.first ?? nil) ?? key
    }

    /// The series for `keys`, in the order given; a key this catalog does not
    /// serve is skipped (a follow made elsewhere is kept for sync, not listed).
    func series(keys: [String]) -> [SeriesRow] {
        keys.compactMap { series(key: $0) }
    }

    /// `seriesPage(key)`: its episodes by broadcast season, oldest first (R1).
    func seriesPage(key: String) -> SeriesPage? {
        guard let series = series(key: key) else { return nil }
        let episodes = rows("""
            SELECT \(Self.episodeColumns) FROM episodes e JOIN series s ON s.key = e.series_key
            WHERE e.series_key = ? ORDER BY \(Self.oldestFirst)
            """, [.text(series.key)], decodeEpisode)
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

    /// Every alias and tombstone (§3.5), episode and series, for the stores that
    /// rewrite kept ids and keys. A catalog published before tombstones, or before
    /// series forwarding, has none of them.
    func forwarding() -> IDForwarding {
        var f = IDForwarding()
        for (old, new) in rows("SELECT old_id, new_id FROM episode_aliases", [], { ($0.text(0), $0.text(1)) }) {
            if let old, let new { f.aliases[old] = new }
        }
        if Self.columnExists(handle, table: "episode_tombstones", column: "id") {
            f.tombstones = Set(rows("SELECT id FROM episode_tombstones", [], { $0.text(0) }).compactMap { $0 })
        }
        if Self.columnExists(handle, table: "series_key_aliases", column: "old_key") {
            for (old, new) in rows("SELECT old_key, new_key FROM series_key_aliases", [], { ($0.text(0), $0.text(1)) }) {
                if let old, let new { f.seriesAliases[old] = new }
            }
        }
        if Self.columnExists(handle, table: "series_key_tombstones", column: "key") {
            f.seriesTombstones = Set(rows("SELECT key FROM series_key_tombstones", [], { $0.text(0) }).compactMap { $0 })
        }
        return f
    }

    /// `episodeDetail(id)`: the row, its credits joined to people, and every
    /// recording in rank order (rank 0 is the default copy).
    func episodeDetail(id rawID: String) -> EpisodeDetail? {
        let id = resolve(rawID)
        let sponsorColumn = hasSponsor ? "e.sponsor" : "NULL"
        let loudnessColumns = hasLoudness ? "e.loudness_i, e.loudness_tp" : "NULL, NULL"
        // §3.1: shown only where the gate passed, whatever else the row carries.
        let transcriptColumn = hasTranscript ? "CASE WHEN e.has_transcript = 1 THEN e.transcript_url END" : "NULL"
        let starColumn = hasEpisodeStar ? "e.star" : "NULL"
        let scriptColumn = hasScript ? "e.script" : "NULL"
        let found = rows("""
            SELECT \(Self.episodeColumns), \(sponsorColumn), \(loudnessColumns), \(transcriptColumn), \(starColumn),
            \(scriptColumn)
            FROM episodes e JOIN series s ON s.key = e.series_key WHERE e.id = ?
            """, [.text(id)]) { row -> (EpisodeRow, String?, String?, String?) in
            var episode = decodeEpisode(row)
            episode.loudnessI = row.double(12)
            episode.loudnessTP = row.double(13)
            episode.transcriptURL = row.text(14).flatMap { URL(string: $0) }
            return (episode, row.text(11), row.text(15), row.text(16))
        }.first
        guard let (episode, sponsor, star, script) = found else { return nil }
        let artColumns = artColumnsSQL
        let artJoin = hasArt ? "LEFT JOIN art a ON a.id = p.portrait" : ""
        let credits = rows("""
            SELECT c.person_id, p.name, c.role, c.character, \(artColumns) FROM credits c
            JOIN people p ON p.id = c.person_id \(artJoin)
            WHERE c.episode_id = ? ORDER BY c.rowid
            """, [.text(id)]) { row in
            Credit(personID: row.text(0) ?? "", name: row.text(1) ?? "", role: row.text(2), character: row.text(3),
                   art: Self.artwork(url: row.text(4), width: row.int(5), height: row.int(6), credit: row.text(7),
                                     evidence: row.text(8), face: row.text(9)))
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
                             rightsLine: rightsLine, star: star, script: script)
    }

    /// The story arc an episode is a part of (contract §3.3, Decision 067), or
    /// nil outside an arc and for a catalog that predates arcs. The next story
    /// is named only on the last part (`next_arc` already applies recommendAnd).
    func arc(of rawID: String) -> ArcPosition? {
        guard hasArcs else { return nil }
        let id = resolve(rawID)
        return rows("""
            SELECT p.arc_id, p.part, a.parts,
                (SELECT n.episode_id FROM arc_parts n WHERE n.arc_id = p.arc_id AND n.part = p.part + 1),
                (SELECT f.episode_id FROM arc_parts f WHERE f.arc_id = a.next_arc AND f.part = 1)
            FROM arc_parts p JOIN arcs a ON a.id = p.arc_id WHERE p.episode_id = ?
            """, [.text(id)]) { row -> ArcPosition? in
            guard let arcID = row.text(0), let part = row.int(1), let parts = row.int(2) else { return nil }
            let nextPart = row.text(3)
            return ArcPosition(arcID: arcID, part: part, parts: parts, nextPart: nextPart,
                               nextStory: nextPart == nil ? row.text(4) : nil)
        }.first ?? nil
    }

    /// Each series' linked script ids (contract §3.1), for Browse's "Has a script".
    func scriptedSeries() -> [String: [String]] {
        guard hasScript else { return [:] }
        var out: [String: [String]] = [:]
        for (key, script) in rows("SELECT series_key, script FROM episodes WHERE script IS NOT NULL", [], {
            ($0.text(0) ?? "", $0.text(1) ?? "")
        }) {
            out[key, default: []].append(script)
        }
        return out
    }

    /// Episodes by id, in the order asked (the person's own history).
    func episodes(ids: [String]) -> [EpisodeRow] {
        guard !ids.isEmpty else { return [] }
        let resolved = ids.map(resolve)
        let marks = Array(repeating: "?", count: resolved.count).joined(separator: ",")
        let found = rows("""
            SELECT \(Self.episodeColumns) FROM episodes e JOIN series s ON s.key = e.series_key
            WHERE e.id IN (\(marks))
            """, resolved.map { .text($0) }, decodeEpisode)
        let byID = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return resolved.compactMap { byID[$0] }
    }

    /// Surprise's episode (iOS-DESIGN §4.11): one served episode with a
    /// recording, at random. It chooses for the listener, so `recommendAnd`.
    /// SQLite's own random(): nothing needs to match another device.
    func randomEpisode() -> EpisodeRow? {
        rows("""
            SELECT \(Self.episodeColumns) FROM episodes e JOIN series s ON s.key = e.series_key
            WHERE EXISTS (SELECT 1 FROM recordings r WHERE r.episode_id = e.id) \(recommendAnd)
            ORDER BY random() LIMIT 1
            """, [], decodeEpisode).first
    }

    /// `search(q)`: word-prefix, never substring, on every platform (§3.4).
    /// "sorr" finds "Sorry, Wrong Number" and never "Mr. Sorrowful". Episodes
    /// match titles, series, and people; a date the query names lists what
    /// aired then; what is said in a shown transcript is its own section.
    func search(_ query: String, limit: Int = 100) -> SearchResults {
        let aired = searchAired(query, limit: limit)
        let columns = ftsHasTranscript ? Self.nonTranscriptColumns : nil
        guard let match = Self.ftsQuery(query, columns: columns) else { return SearchResults(aired: aired) }
        let episodes = rows("""
            SELECT \(Self.episodeColumns) FROM episodes_fts f JOIN episodes e ON e.rowid = f.rowid
            JOIN series s ON s.key = e.series_key
            WHERE episodes_fts MATCH ? ORDER BY f.rank LIMIT \(limit)
            """, [.text(match)], decodeEpisode)
        let phrase = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "%", with: "").replacingOccurrences(of: "_", with: "")
        let series = rows("""
            SELECT \(Self.seriesColumns) FROM series s
            WHERE s.episodes > 0 AND (s.name LIKE ? OR s.name LIKE ?)
            ORDER BY s.episodes DESC LIMIT 20
            """, [.text("\(phrase)%"), .text("% \(phrase)%")], decodeSeries)
        return SearchResults(series: series, episodes: episodes, people: searchPeople(query), aired: aired,
                             transcript: searchTranscripts(query, excluding: match))
    }

    /// Search's transcript section: episodes whose shown automatic transcript
    /// (`has_transcript = 1`, Decision 058) says every query word of three
    /// letters or more as a word prefix, oldest first, less those `excluding`
    /// (the titles, series, and people match) already finds. Each row carries
    /// its `transcriptURL`, where its snippet is read.
    func searchTranscripts(_ query: String, excluding: String? = nil, limit: Int = 50) -> [EpisodeRow] {
        guard ftsHasTranscript, hasTranscript else { return [] }
        let words = Transcript.searchWords(query)
        guard !words.isEmpty else { return [] }
        let match = words.map { "{transcript} : \"\($0)\"*" }.joined(separator: " ")
        var binds: [Bind] = [.text(match)]
        var excluded = ""
        if let excluding {
            excluded = "AND e.rowid NOT IN (SELECT rowid FROM episodes_fts WHERE episodes_fts MATCH ?)"
            binds.append(.text(excluding))
        }
        return rows("""
            SELECT \(Self.episodeColumns), e.transcript_url FROM episodes_fts f JOIN episodes e ON e.rowid = f.rowid
            JOIN series s ON s.key = e.series_key
            WHERE episodes_fts MATCH ? AND e.has_transcript = 1 AND e.transcript_url IS NOT NULL \(excluded)
            ORDER BY \(Self.oldestFirst) LIMIT \(limit)
            """, binds) { row in
            var episode = decodeEpisode(row)
            episode.transcriptURL = row.text(11).flatMap { URL(string: $0) }
            return episode
        }
    }

    /// The episodes that aired on the date the query names (`DateQuery`),
    /// oldest first, narrowed by its other words in titles, series, and
    /// people; nil when the query names no date.
    func searchAired(_ query: String, limit: Int = 100) -> AiredResults? {
        guard let date = DateQuery.parse(query) else { return nil }
        var binds: [Bind] = [.text(date.prefix + "%")]
        var narrow = ""
        let columns = ftsHasTranscript ? Self.nonTranscriptColumns : nil
        if Transcript.tokens(date.rest).contains(where: { $0.count >= 2 }),
           let match = Self.ftsQuery(date.rest, columns: columns) {
            narrow = "AND e.rowid IN (SELECT rowid FROM episodes_fts WHERE episodes_fts MATCH ?)"
            binds.append(.text(match))
        }
        let found = rows("""
            SELECT \(Self.episodeColumns) FROM episodes e JOIN series s ON s.key = e.series_key
            WHERE e.air_date LIKE ? \(narrow) ORDER BY e.air_date, e.id LIMIT \(limit)
            """, binds, decodeEpisode)
        return AiredResults(prefix: date.prefix, episodes: found)
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
            // §5.1: a full YYYY-MM-DD only, oldest first, ties by id.
            let suffix = String(format: "-%02d-%02d", month, day)
            return rows("""
                SELECT \(Self.episodeColumns) FROM episodes e JOIN series s ON s.key = e.series_key
                WHERE e.air_date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' AND e.air_date LIKE ?
                \(recommendAnd) ORDER BY e.air_date, e.id LIMIT \(limit)
                """, [.text("%\(suffix)")], decodeEpisode)
        case let .genreFirsts(genre):
            return rows("""
                SELECT \(Self.episodeColumns) FROM series s
                JOIN episodes e ON e.id = (
                    SELECT e.id FROM episodes e WHERE e.series_key = s.key \(recommendAnd)
                    ORDER BY \(Self.oldestFirst) LIMIT 1)
                WHERE s.genre = ? ORDER BY s.episodes DESC, s.key LIMIT \(limit)
                """, [.text(genre)], decodeEpisode)
        case .mostDownloaded:
            // Precomputed by the pipeline from archive.org's counts, which
            // the served projection carries per item, not per episode.
            return []
        }
    }

    /// The Listen tab's shelves (contract §5.1): `meta.listenShelves` in its
    /// order, onThisDay on the person's own month and day, each genreFirsts
    /// from its published ids. A catalog without the key falls back to the
    /// rules run here (onThisDay, then each genre's firsts). Empty shelves
    /// are dropped, never shown as a heading over nothing.
    func listenShelves(month: Int, day: Int) -> [Shelf] {
        let shelves: [Shelf]
        if let published = publishedShelves {
            shelves = published.map { entry in
                switch entry {
                case .onThisDay:
                    let rule = ShelfRule.onThisDay(month: month, day: day)
                    return Shelf(rule: rule, episodes: shelf(rule))
                case let .genreFirsts(genre, ids):
                    return Shelf(rule: .genreFirsts(genre), episodes: episodes(ids: ids))
                case let .mostDownloaded(ids):
                    return Shelf(rule: .mostDownloaded, episodes: episodes(ids: ids))
                }
            }
        } else {
            let rules = [ShelfRule.onThisDay(month: month, day: day)] + genres().map { ShelfRule.genreFirsts($0) }
            shelves = rules.map { Shelf(rule: $0, episodes: shelf($0)) }
        }
        return shelves.filter { !$0.episodes.isEmpty }
    }

    /// `withPerson(id)`: every episode crediting a person, oldest first.
    func withPerson(_ personID: String, limit: Int = 500) -> [EpisodeRow] {
        rows("""
            SELECT DISTINCT \(Self.episodeColumns) FROM credits c JOIN episodes e ON e.id = c.episode_id
            JOIN series s ON s.key = e.series_key WHERE c.person_id = ? ORDER BY \(Self.oldestFirst) LIMIT \(limit)
            """, [.text(personID)], decodeEpisode)
    }

    /// `withPerson(id)` as a page: the person's facts and every served episode
    /// crediting them, oldest first, one row per episode with all its roles.
    /// Nil when the catalog serves none of their credits.
    func personPage(id personID: String) -> PersonPage? {
        let artColumns = artColumnsSQL
        let artJoin = hasArt ? "LEFT JOIN art a ON a.id = p.portrait" : ""
        guard let person = rows("""
            SELECT p.id, p.name, p.birth, p.death, \(artColumns) FROM people p \(artJoin) WHERE p.id = ?
            """, [.text(personID)], { row in
            Person(id: row.text(0) ?? "", name: row.text(1) ?? "", birth: row.text(2), death: row.text(3),
                   art: Self.artwork(url: row.text(4), width: row.int(5), height: row.int(6), credit: row.text(7),
                                     evidence: row.text(8), face: row.text(9)))
        }).first else { return nil }
        let credits = rows("""
            SELECT \(Self.episodeColumns), c.role, c.character FROM credits c JOIN episodes e ON e.id = c.episode_id
            JOIN series s ON s.key = e.series_key WHERE c.person_id = ?
            ORDER BY \(Self.oldestFirst), c.role, c.character
            """, [.text(personID)]) { row in
            (decodeEpisode(row), PersonRole(role: row.text(11), character: row.text(12)))
        }
        var episodes: [PersonEpisode] = []
        var at: [String: Int] = [:]
        for (episode, role) in credits {
            if let i = at[episode.id] {
                episodes[i].roles.append(role)
            } else {
                at[episode.id] = episodes.count
                episodes.append(PersonEpisode(episode: episode, roles: [role]))
            }
        }
        guard !episodes.isEmpty else { return nil }
        return PersonPage(person: person, episodes: episodes)
    }

    /// `searchPeople(q)`: people whose name has every typed word (two
    /// characters or more) as a word prefix, never a substring, diacritics
    /// and case folded; most served episodes first, then by name.
    func searchPeople(_ query: String, limit: Int = 8) -> [PersonRow] {
        let words = Self.nameWords(query).filter { $0.count >= 2 }
        guard !words.isEmpty else { return [] }
        let hits = rows("SELECT id, name FROM people") { ($0.text(0) ?? "", $0.text(1) ?? "") }.filter { _, name in
            let have = Self.nameWords(name)
            return words.allSatisfy { w in have.contains { $0.hasPrefix(w) } }
        }
        let artColumns = artColumnsSQL
        let artJoin = hasArt ? "LEFT JOIN art a ON a.id = p.portrait" : ""
        let ranked = hits.map { id, name in
            (id, name, rows("SELECT COUNT(DISTINCT episode_id) FROM credits WHERE person_id = ?", [.text(id)]) {
                $0.int(0) ?? 0
            }.first ?? 0)
        }
        .filter { $0.2 > 0 }
        .sorted { ($0.2, $1.1.lowercased(), $1.0) > ($1.2, $0.1.lowercased(), $0.0) }
        return ranked.prefix(limit).compactMap { id, _, count in
            rows("""
                SELECT p.id, p.name, p.birth, p.death, \(artColumns) FROM people p \(artJoin) WHERE p.id = ?
                """, [.text(id)]) { row in
                PersonRow(person: Person(id: row.text(0) ?? "", name: row.text(1) ?? "", birth: row.text(2),
                                         death: row.text(3),
                                         art: Self.artwork(url: row.text(4), width: row.int(5), height: row.int(6),
                                                           credit: row.text(7), evidence: row.text(8),
                                                           face: row.text(9))),
                          episodes: count)
            }.first
        }
    }

    /// unicode61's words, as the builder and the web tokenize (`API.tokens`).
    static func nameWords(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    // MARK: - Row decoding

    private func decodeSeries(_ row: Row) -> SeriesRow {
        let networks = row.text(5).flatMap { $0.data(using: .utf8) }
            .flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        let key = row.text(0) ?? ""
        return SeriesRow(key: key, name: row.text(1) ?? "", genre: row.text(2),
                         firstDate: row.text(3), lastDate: row.text(4), networks: networks,
                         episodeCount: row.int(6) ?? 0, face: seriesLook[key]?.face)
    }

    private func decodeEpisode(_ row: Row) -> EpisodeRow {
        let key = row.text(1) ?? ""
        let look = seriesLook[key]
        return EpisodeRow(id: row.text(0) ?? "", seriesKey: key, seriesName: row.text(2) ?? "",
                          airDate: row.text(3), season: row.text(4), number: row.int(5), title: row.text(6),
                          lengthSeconds: row.double(7), rights: row.text(8) ?? "unclaimed",
                          rightsBasis: row.text(9), network: row.text(10),
                          seriesGenre: look?.genre, seriesFace: look?.face)
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
