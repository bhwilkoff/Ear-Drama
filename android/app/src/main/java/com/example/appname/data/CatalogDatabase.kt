package com.example.appname.data

import androidx.sqlite.SQLiteConnection
import androidx.sqlite.SQLiteStatement
import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray

/**
 * The query verbs of docs/CATALOG-CONTRACT.md §5 over the served projection,
 * read in place through the bundled SQLite (FTS5 on every device). Nothing is
 * loaded whole: each verb decodes only the rows its screen shows, and only
 * Detail reads `detail_json`. Every filter clause lives here and nowhere else.
 */
class CatalogDatabase internal constructor(private val connection: SQLiteConnection) {

    private val mutex = Mutex()
    @Volatile private var closed = false

    /** A catalog published before §3.1's loudness columns reads them as NULL. */
    private val hasLoudness: Boolean by lazy {
        queryRaw("PRAGMA table_info(episodes)") { it.getText(1) }.containsAll(listOf("loudness_i", "loudness_tp"))
    }

    /** §3.1's transcript columns; an older catalog shows no transcript. */
    private val hasTranscript: Boolean by lazy {
        queryRaw("PRAGMA table_info(episodes)") { it.getText(1) }.containsAll(listOf("has_transcript", "transcript_url"))
    }

    /**
     * Contract §5.5: the rights words the catalog publishes in `meta.rightsLines`,
     * or the contract's own strings for a catalog that predates the key.
     */
    val rightsLines: Map<String, String> by lazy {
        queryRaw("SELECT value FROM meta WHERE key = 'rightsLines'") { it.getText(0) }.firstOrNull()
            ?.let { runCatching { Json.decodeFromString<Map<String, String>>(it) }.getOrNull() }
            ?: DisplayVocabulary.CONTRACT_RIGHTS_LINES
    }

    /** §3.1's `sponsor`; the served projection does not publish it yet, so it is probed (as Apple does). */
    private val hasSponsor: Boolean by lazy {
        "sponsor" in queryRaw("PRAGMA table_info(episodes)") { it.getText(1) }
    }

    /** Contract §3.3a: the projection carries portraits; an older catalog has none. */
    private val hasArt: Boolean by lazy {
        "portrait" in queryRaw("PRAGMA table_info(people)") { it.getText(1) } &&
            "url" in queryRaw("PRAGMA table_info(art)") { it.getText(1) }
    }
    /** The art columns a credit, person, or series query reads (§3.3a); `a.face` and `a.grade` are NULL in an older catalog. */
    private val artColumns: String by lazy {
        if (!hasArt) return@lazy "NULL, NULL, NULL, NULL, NULL, NULL, NULL"
        val cols = queryRaw("PRAGMA table_info(art)") { it.getText(1) }
        "a.url, a.width, a.height, a.credit, a.evidence_url, ${if ("face" in cols) "a.face" else "NULL"}, " +
            if ("grade" in cols) "a.grade" else "NULL"
    }
    private val hasEpisodeStar: Boolean by lazy {
        hasArt && "star" in queryRaw("PRAGMA table_info(episodes)") { it.getText(1) }
    }

    /** Contract §3.3: the pipeline's A-to-Z key; a catalog published before it sorts by `name`. */
    private val nameKey: String by lazy {
        if ("sort_name" in queryRaw("PRAGMA table_info(series)") { it.getText(1) }) "s.sort_name" else "s.name"
    }

    /** Contract §3.3 `series.downloads`, Browse's Popular key; without it Popular is A to Z. */
    private val hasDownloads: Boolean by lazy {
        "downloads" in queryRaw("PRAGMA table_info(series)") { it.getText(1) }
    }

    /** §3.1's `script` (Decision 068); an older catalog links none. */
    private val hasScript: Boolean by lazy {
        "script" in queryRaw("PRAGMA table_info(episodes)") { it.getText(1) }
    }

    /** §3.3's `arcs` and `arc_parts` (Decision 067); an older catalog has no arcs. */
    private val hasArcs: Boolean by lazy {
        "next_arc" in queryRaw("PRAGMA table_info(arcs)") { it.getText(1) } &&
            "part" in queryRaw("PRAGMA table_info(arc_parts)") { it.getText(1) }
    }

    /** Every series' genre, face and picture, read once: rows that mix series draw a tile from it. */
    private val seriesLook: Map<String, SeriesLook> by lazy {
        val cols = queryRaw("PRAGMA table_info(series)") { it.getText(1) }
        val faces = hasArt && "star" in cols
        // §3.3a series.picture: an art id; an older catalog has no column, and its picture is null.
        val pictures = hasArt && "picture" in cols
        val artCols = if (hasArt) queryRaw("PRAGMA table_info(art)") { it.getText(1) } else emptyList()
        val face = if ("face" in artCols) "ap.face" else "NULL"
        val grade = if ("grade" in artCols) "ap.grade" else "NULL"
        val sql = "SELECT s.key, s.genre, " +
            (if (faces) "p.name, $artColumns, " else "NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, ") +
            (if (pictures) "ap.url, ap.width, ap.height, ap.credit, ap.evidence_url, $face, $grade, s.picture_kind, " else
                "NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, ") +
            (if ("networks" in cols) "s.networks, " else "NULL, ") +
            (if ("year_counts" in cols) "s.year_counts, " else "NULL, ") +
            (if ("sort_name" in cols) "s.sort_name " else "NULL ") +
            "FROM series s " +
            (if (faces) "LEFT JOIN people p ON p.id = s.star AND p.portrait IS NOT NULL LEFT JOIN art a ON a.id = p.portrait " else "") +
            (if (pictures) "LEFT JOIN art ap ON ap.id = s.picture" else "")
        queryRaw(sql) { st ->
            val art = artwork(st, 3)
            val name = st.textOrNull(2)
            st.getText(0) to SeriesLook(
                genre = st.textOrNull(1),
                face = if (art != null && name != null) Face(name, art) else null,
                picture = artwork(st, 10),
                pictureKind = st.textOrNull(17),
                networks = networkList(st.textOrNull(18)),
                yearCounts = parseYearCounts(st.textOrNull(19)),
                sortName = st.textOrNull(20),
            )
        }.toMap()
    }

    private class SeriesLook(
        val genre: String?,
        val face: Face?,
        val picture: Artwork?,
        val pictureKind: String?,
        val networks: List<String>,
        val yearCounts: List<Int>?,
        val sortName: String?,
    )

    private fun artwork(st: SQLiteStatement, at: Int): Artwork? = st.textOrNull(at)?.let {
        Artwork(
            url = it,
            width = if (st.isNull(at + 1)) null else st.getLong(at + 1).toInt(),
            height = if (st.isNull(at + 2)) null else st.getLong(at + 2).toInt(),
            credit = st.textOrNull(at + 3),
            evidence = st.textOrNull(at + 4),
            face = FaceBox.parse(st.textOrNull(at + 5)),
            grade = parseGrade(st.textOrNull(at + 6)),
        )
    }

    /** §3.4: the index carries transcript words, so a match can be told apart as transcript-only. */
    private val ftsHasTranscript: Boolean by lazy {
        "transcript" in queryRaw("PRAGMA table_info(episodes_fts)") { it.getText(1) }
    }

    companion object {
        /** Every FTS column but `transcript` (§3.4), as an FTS5 column filter. */
        const val NON_TRANSCRIPT_COLUMNS = "{title series people}"

        /** The lowest `meta.schemaVersion` this build reads. */
        const val MIN_SCHEMA_VERSION = 1

        /** §5 `recommendAnd`: every surface that chooses for the listener applies it. */
        const val RECOMMEND_AND = " AND e.no_recommend IS NULL"

        /** §5.1's shelf limit, and the full-date pattern onThisDay matches. */
        const val SHELF_LIMIT = 20
        private const val FULL_DATE = "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]"

        private const val EPISODE_COLUMNS =
            "e.id, e.series_key, s.name, e.air_date, e.season, e.num, e.title, e.length_s, e.network"
        private const val EPISODE_FROM = " FROM episodes e JOIN series s ON s.key = e.series_key"
        private const val SERIES_COLUMNS = "s.key, s.name, s.genre, s.first_date, s.last_date, s.episodes"

        /** `series.networks` as JSON SQLite can walk; a NULL or malformed value is no network. */
        private const val NETWORKS_JSON = "CASE WHEN json_valid(s.networks) THEN s.networks ELSE '[]' END"

        /** `series.networks` (a JSON array of names); a NULL or malformed value is none. */
        fun networkList(json: String?): List<String> = runCatching {
            Json.parseToJsonElement(json ?: return emptyList()).jsonArray
                .mapNotNull { (it as? JsonPrimitive)?.contentOrNull?.takeIf(String::isNotBlank) }
        }.getOrDefault(emptyList())

        /** R1: oldest first, undated last, then the log number, then the title. */
        private const val OLDEST_FIRST = "e.air_date IS NULL, COALESCE(e.air_date, ''), " +
            "e.num IS NULL, COALESCE(e.num, 0), COALESCE(e.title, ''), e.id"
        private const val CURRENT_ORDER = "cur.air_date IS NULL, COALESCE(cur.air_date, ''), " +
            "cur.num IS NULL, COALESCE(cur.num, 0), COALESCE(cur.title, ''), cur.id"

        /** unicode61's words, as the builder and the web tokenize (`API.tokens`). */
        fun nameWords(text: String): List<String> =
            java.text.Normalizer.normalize(text, java.text.Normalizer.Form.NFD)
                .replace(Regex("\\p{M}+"), "").lowercase()
                .split(Regex("[^\\p{L}\\p{N}]+")).filter { it.isNotEmpty() }

        /** Opens and probes; null when the file is not a catalog this build can read. */
        fun open(path: String): CatalogDatabase? = try {
            val db = CatalogDatabase(BundledSQLiteDriver().open(path))
            val version = db.schemaVersionBlocking()
            if (version == null || version < MIN_SCHEMA_VERSION) {
                db.close()
                null
            } else db
        } catch (_: Throwable) {
            null
        }

        /**
         * The full validation a downloaded file passes before it may replace
         * the live one (§2): `PRAGMA integrity_check`, the schema floor, and a
         * known row to read.
         */
        fun validate(path: String): Boolean = try {
            val connection = BundledSQLiteDriver().open(path)
            try {
                val db = CatalogDatabase(connection)
                val integrity = db.queryRaw("PRAGMA integrity_check") { it.getText(0) }
                val version = db.schemaVersionBlocking()
                val episodes = db.queryRaw("SELECT id FROM episodes LIMIT 1") { it.getText(0) }
                integrity == listOf("ok") && version != null && version >= MIN_SCHEMA_VERSION &&
                    episodes.isNotEmpty()
            } finally {
                connection.close()
            }
        } catch (_: Throwable) {
            false
        }

        /** The first year of every decade from [firstYear] through [lastYear]: 1938 to 1951 is 1930, 1940, 1950. */
        fun decadesSpanning(firstYear: Int?, lastYear: Int?): List<Int> {
            val first = firstYear ?: return emptyList()
            val last = (lastYear ?: first).coerceAtLeast(first)
            return (first / 10 * 10..last / 10 * 10 step 10).toList()
        }

        /**
         * §3.4: word-prefix matching, never substring. Each word of the query
         * becomes a quoted prefix term, so "sorr" finds "Sorry, Wrong Number"
         * and FTS syntax typed by a listener is treated as words.
         */
        fun matchExpression(query: String, column: String? = null): String? {
            val words = query.split(Regex("[^\\p{L}\\p{N}]+")).filter { it.isNotEmpty() }
            if (words.isEmpty()) return null
            val prefix = column?.let { "$it : " } ?: ""
            return words.joinToString(" ") { "$prefix\"$it\"*" }
        }
    }

    fun close() {
        closed = true
        runCatching { connection.close() }
    }

    /** Closes after any query already holding the lock has finished (the swap's old file). */
    suspend fun closeWhenIdle() = mutex.withLock { close() }

    private fun schemaVersionBlocking(): Int? =
        queryRaw("SELECT value FROM meta WHERE key = 'schemaVersion'") { it.getText(0) }
            .firstOrNull()?.trim('"')?.toIntOrNull()

    // --- Series ---

    /**
     * The genres the catalog names; with [decade] or [network], only those
     * with a series under that selection (web §10.5).
     */
    suspend fun genres(decade: Int? = null, network: String? = null): List<String> = read {
        val (clause, binds) = facetClause(BrowseFilter(decade = decade, network = network))
        queryRaw(
            "SELECT DISTINCT s.genre FROM series s WHERE s.genre IS NOT NULL AND s.genre <> ''$clause ORDER BY s.genre",
            binds,
        ) { it.getText(0) }
    }

    /**
     * The decades the catalog's series were on the air, from the data, never
     * a fixed list; with [genre] or [network], only that selection's (each
     * facet counted against the others, so no chip offered yields zero rows).
     */
    suspend fun seriesDecades(genre: String? = null, network: String? = null): List<Int> = read {
        val (clause, binds) = facetClause(BrowseFilter(genre = genre, network = network))
        queryRaw(
            "SELECT DISTINCT substr(s.first_date, 1, 4), substr(COALESCE(s.last_date, s.first_date), 1, 4) " +
                "FROM series s WHERE s.first_date IS NOT NULL$clause",
            binds,
        ) { decadesSpanning(it.getText(0).toIntOrNull(), it.getText(1).toIntOrNull()) }
            .flatten().distinct().sorted()
    }

    /**
     * The networks the series name (`series.networks`, a JSON array), each
     * with the series it would list against the genre and decade picked,
     * most first, at most [limit] (the web's 40).
     */
    suspend fun networks(genre: String? = null, decade: Int? = null, limit: Int = 40): List<FacetCount<String>> = read {
        val (clause, binds) = facetClause(BrowseFilter(genre = genre, decade = decade))
        queryRaw(
            "SELECT j.value, COUNT(DISTINCT s.key) FROM series s, json_each($NETWORKS_JSON) j " +
                "WHERE j.type = 'text' AND j.value <> ''$clause " +
                "GROUP BY j.value ORDER BY COUNT(DISTINCT s.key) DESC, j.value LIMIT ?",
            binds + limit,
        ) { FacetCount(it.getText(0), it.getLong(1).toInt()) }
    }

    /** The WHERE tail every facet and the browse list share, so a count and its list never disagree. */
    private fun facetClause(filter: BrowseFilter): Pair<String, List<Any?>> {
        val where = StringBuilder()
        val binds = mutableListOf<Any?>()
        filter.genre?.let { where.append(" AND s.genre = ?"); binds += it }
        filter.network?.let {
            where.append(" AND EXISTS (SELECT 1 FROM json_each($NETWORKS_JSON) n WHERE n.value = ?)")
            binds += it
        }
        filter.decade?.let {
            where.append(" AND s.first_date <= ? AND COALESCE(s.last_date, s.first_date) >= ?")
            binds += "${it + 9}-12-31"
            binds += "$it-01-01"
        }
        filter.showLine?.let { where.append(if (it) " AND s.episodes >= $SHOW_MIN" else " AND s.episodes < $SHOW_MIN") }
        return where.toString() to binds
    }

    /** How many shows and how many single recordings the filter's genre, decade and network select. */
    suspend fun seriesCounts(filter: BrowseFilter): Pair<Int, Int> = read {
        val (clause, binds) = facetClause(filter.copy(showLine = null))
        queryRaw(
            "SELECT COALESCE(SUM(s.episodes >= $SHOW_MIN), 0), COALESCE(SUM(s.episodes < $SHOW_MIN), 0) " +
                "FROM series s WHERE 1 = 1$clause",
            binds,
        ) { it.getLong(0).toInt() to it.getLong(1).toInt() }.first()
    }

    /** Every show under [network], as the decade field counts it (genre and decade are the field's own axes). */
    suspend fun fieldShows(network: String? = null): List<FieldShow> = read {
        val (clause, binds) = facetClause(BrowseFilter(network = network, showLine = true))
        queryRaw("SELECT s.genre, s.first_date FROM series s WHERE 1 = 1$clause", binds) {
            FieldShow(it.textOrNull(0), it.textOrNull(1))
        }
    }

    /** Every dated broadcast that aired on this month and day, any year, oldest first, with no limit (Home's day board). */
    suspend fun dayRows(monthDay: String): List<EpisodeRow> = read {
        queryRaw(
            "SELECT $EPISODE_COLUMNS$EPISODE_FROM WHERE e.air_date GLOB '$FULL_DATE' " +
                "AND substr(e.air_date, 6, 5) = ?$RECOMMEND_AND ORDER BY e.air_date, e.id",
            listOf(monthDay),
            ::episodeRow,
        )
    }

    /** §5 `seriesBrowse`: the listener drives it, so no `recommendAnd`. */
    suspend fun seriesBrowse(filter: BrowseFilter, limit: Int = 200, offset: Int = 0): List<SeriesRow> = read {
        val (clause, binds) = facetClause(filter)
        val order = when (filter.sort) {
            SeriesSort.Popular -> if (hasDownloads) {
                "COALESCE(s.downloads, 0) <= 0, s.downloads DESC, $nameKey COLLATE NOCASE, s.key"
            } else "$nameKey COLLATE NOCASE, s.key"
            SeriesSort.Name -> "$nameKey COLLATE NOCASE, s.key"
            SeriesSort.Episodes -> "s.episodes DESC, $nameKey COLLATE NOCASE, s.key"
            SeriesSort.FirstAired -> "s.first_date IS NULL, s.first_date, $nameKey COLLATE NOCASE, s.key"
        }
        queryRaw(
            "SELECT $SERIES_COLUMNS FROM series s WHERE 1 = 1$clause ORDER BY $order LIMIT ? OFFSET ?",
            binds + limit + offset,
            ::seriesRow,
        )
    }

    /** The series [key] names, or the one it now is when a later catalog moved the key (§3.5). */
    suspend fun series(key: String): SeriesRow? = read { seriesRowFor(key) }

    /** §5 `seriesPage`: the series and its broadcast seasons, oldest first, undated last; a moved key opens the series it now is. */
    suspend fun seriesPage(key: String): SeriesPage? = read {
        val series = seriesRowFor(key) ?: return@read null
        val seasons = queryRaw(
            "SELECT season, COUNT(*) FROM episodes WHERE series_key = ? " +
                "GROUP BY season ORDER BY season IS NULL, season",
            listOf(series.key),
        ) { SeasonRow(it.textOrNull(0), it.getLong(1).toInt()) }
        SeriesPage(series, seasons)
    }

    /** One season of a series page, oldest first (R1). A null [season] is the undated episodes. */
    suspend fun seasonEpisodes(seriesKey: String, season: String?): List<EpisodeRow> = read {
        queryRaw(
            "SELECT $EPISODE_COLUMNS$EPISODE_FROM WHERE e.series_key = ? AND e.season IS ? ORDER BY $OLDEST_FIRST",
            listOf(seriesKey, season),
            ::episodeRow,
        )
    }

    /**
     * What may follow [episodeId] when it ends: the rest of its season of the
     * same series, oldest first, with `recommendAnd` (autoplay chooses for the
     * listener). It never crosses into another season or series (R3).
     */
    suspend fun followingInSeason(episodeId: String, limit: Int = 50): List<EpisodeRow> = read {
        queryRaw(
            "SELECT $EPISODE_COLUMNS$EPISODE_FROM, episodes cur " +
                "WHERE cur.id = ? AND e.series_key = cur.series_key AND e.season IS cur.season " +
                "AND e.id <> cur.id " +
                "AND ($OLDEST_FIRST) > ($CURRENT_ORDER)" +
                RECOMMEND_AND +
                " ORDER BY $OLDEST_FIRST LIMIT ?",
            listOf(episodeId, limit),
            ::episodeRow,
        )
    }

    // --- Episodes ---

    /**
     * §3.5: every alias and tombstone, episode and series, for the stores that rewrite kept ids
     * and keys; a catalog older than tombstones or series forwarding has none of them.
     */
    suspend fun forwarding(): IdForwarding = read {
        val aliases = queryRaw("SELECT old_id, new_id FROM episode_aliases") { it.getText(0) to it.getText(1) }.toMap()
        val tombstones = if (hasColumn("episode_tombstones", "id")) {
            queryRaw("SELECT id FROM episode_tombstones") { it.getText(0) }.toSet()
        } else {
            emptySet()
        }
        val seriesAliases = if (hasColumn("series_key_aliases", "old_key")) {
            queryRaw("SELECT old_key, new_key FROM series_key_aliases") { it.getText(0) to it.getText(1) }.toMap()
        } else {
            emptyMap()
        }
        val seriesTombstones = if (hasColumn("series_key_tombstones", "key")) {
            queryRaw("SELECT key FROM series_key_tombstones") { it.getText(0) }.toSet()
        } else {
            emptySet()
        }
        IdForwarding(aliases, tombstones, seriesAliases, seriesTombstones)
    }

    private fun hasColumn(table: String, column: String): Boolean =
        column in queryRaw("PRAGMA table_info($table)") { it.getText(1) }

    private fun seriesRowFor(key: String): SeriesRow? {
        val row = { k: String ->
            queryRaw("SELECT $SERIES_COLUMNS FROM series s WHERE s.key = ?", listOf(k), ::seriesRow).firstOrNull()
        }
        return row(key) ?: resolveSeries(key).takeIf { it != key }?.let(row)
    }

    /** §3.5: a series key that changed forwards to its new one; a catalog before series forwarding has none. */
    private fun resolveSeries(key: String): String =
        if (!hasColumn("series_key_aliases", "old_key")) key
        else queryRaw("SELECT new_key FROM series_key_aliases WHERE old_key = ?", listOf(key)) { it.getText(0) }
            .firstOrNull() ?: key

    /** §3.5: an id that changed forwards to its new one. */
    private fun resolve(id: String): String =
        if (queryRaw("SELECT 1 FROM episodes WHERE id = ?", listOf(id)) { 1 }.isNotEmpty()) id
        else queryRaw("SELECT new_id FROM episode_aliases WHERE old_id = ?", listOf(id)) { it.getText(0) }
            .firstOrNull() ?: id

    /**
     * The story arc [id] is a part of (§3.3, Decision 067): the parts after it, in order, and the
     * series' next story's first part (`next_arc` already applies recommendAnd), offered, never
     * started. Null outside an arc and for a catalog that predates arcs.
     */
    suspend fun arcAhead(id: String): ArcAhead? = read {
        if (!hasArcs) return@read null
        val resolved = resolve(id)
        val head = queryRaw(
            "SELECT p.arc_id, p.part, a.next_arc FROM arc_parts p JOIN arcs a ON a.id = p.arc_id WHERE p.episode_id = ?",
            listOf(resolved),
        ) { Triple(it.getText(0), it.getLong(1), it.textOrNull(2)) }.firstOrNull() ?: return@read null
        val rest = queryRaw(
            "SELECT episode_id FROM arc_parts WHERE arc_id = ? AND part > ? ORDER BY part",
            listOf(head.first, head.second),
        ) { it.getText(0) }
        val story = head.third?.let { next ->
            queryRaw("SELECT episode_id FROM arc_parts WHERE arc_id = ? AND part = 1", listOf(next)) { it.getText(0) }
                .firstOrNull()
        }
        ArcAhead(rest, story)
    }

    /** Each series' linked script ids (§3.1), for Browse's "Has a script". */
    suspend fun scriptedSeries(): Map<String, List<String>> = read {
        if (!hasScript) emptyMap()
        else queryRaw("SELECT series_key, script FROM episodes WHERE script IS NOT NULL") { it.getText(0) to it.getText(1) }
            .groupBy({ it.first }, { it.second })
    }

    /** §5 `episodeDetail`: the row, its credits, and its recordings in rank order. */
    suspend fun episodeDetail(id: String): EpisodeDetail? = read {
        val resolved = resolve(id)
        val loudness = if (hasLoudness) "e.loudness_i, e.loudness_tp" else "NULL, NULL"
        // Shown only where the gate passed, whatever else the row carries.
        val transcript = if (hasTranscript) "CASE WHEN e.has_transcript = 1 THEN e.transcript_url END" else "NULL"
        val sponsor = if (hasSponsor) "e.sponsor" else "NULL"
        val star = if (hasEpisodeStar) "e.star" else "NULL"
        val script = if (hasScript) "e.script" else "NULL"
        val head = queryRaw(
            "SELECT $EPISODE_COLUMNS, e.rights, e.rights_basis, e.network, e.no_recommend, e.detail_json, " +
                "$loudness, $transcript, $sponsor, $star, $script$EPISODE_FROM WHERE e.id = ?",
            listOf(resolved),
        ) { st ->
            EpisodeDetail(
                episode = episodeRow(st),
                rights = st.getText(9),
                rightsBasis = st.textOrNull(10),
                network = st.textOrNull(11),
                noRecommend = st.textOrNull(12),
                credits = emptyList(),
                recordings = emptyList(),
                detailJson = st.textOrNull(13),
                loudnessI = if (st.isNull(14)) null else st.getDouble(14),
                loudnessTp = if (st.isNull(15)) null else st.getDouble(15),
                transcriptUrl = st.textOrNull(16),
                sponsor = st.textOrNull(17)?.takeIf { it.isNotBlank() },
                star = st.textOrNull(18),
                script = st.textOrNull(19),
            )
        }.firstOrNull() ?: return@read null
        val artJoin = if (hasArt) " LEFT JOIN art a ON a.id = p.portrait" else ""
        val credits = queryRaw(
            "SELECT c.person_id, p.name, c.role, c.character, $artColumns FROM credits c " +
                "JOIN people p ON p.id = c.person_id$artJoin WHERE c.episode_id = ? ORDER BY c.rowid",
            listOf(resolved),
        ) { Credit(it.getText(0), it.getText(1), it.textOrNull(2), it.textOrNull(3), artwork(it, 4)) }
        val recordings = queryRaw(
            "SELECT rank, archive_id, url, format, kbps, length_s, variant, partial FROM recordings " +
                "WHERE episode_id = ? ORDER BY rank",
            listOf(resolved),
        ) {
            Recording(
                rank = it.getLong(0).toInt(),
                archiveId = it.getText(1),
                url = it.getText(2),
                format = it.textOrNull(3),
                kbps = if (it.isNull(4)) null else it.getLong(4).toInt(),
                lengthSeconds = if (it.isNull(5)) null else it.getDouble(5),
                variant = it.textOrNull(6),
                partial = it.getLong(7) != 0L,
            )
        }
        head.copy(
            credits = credits,
            recordings = recordings,
            rightsLine = DisplayVocabulary.rightsLine(head.rights, head.rightsBasis, rightsLines),
        )
    }

    /** The rows for ids the listener already holds (Continue, Library); order follows [ids]. */
    suspend fun episodes(ids: List<String>): List<EpisodeRow> = read {
        ids.mapNotNull { id ->
            queryRaw("SELECT $EPISODE_COLUMNS$EPISODE_FROM WHERE e.id = ?", listOf(resolve(id)), ::episodeRow)
                .firstOrNull()
        }
    }

    // --- Search ---

    /**
     * §5 `search`: episodes and series, word-prefix, through the contentless
     * FTS5 table. Series match on the `series` column alone, so a word spoken
     * in a transcript never lists a series. Episodes match titles, series, and
     * people; a date the query names lists what aired then; what is said in a
     * shown transcript is its own section.
     */
    suspend fun search(query: String, limit: Int = 100): SearchResults = read {
        val aired = airedBlocking(query, limit)
        val all = matchExpression(query, column = if (ftsHasTranscript) NON_TRANSCRIPT_COLUMNS else null)
            ?: return@read SearchResults(emptyList(), emptyList(), aired = aired)
        val seriesOnly = matchExpression(query, column = "series")!!
        val series = queryRaw(
            "SELECT $SERIES_COLUMNS FROM series s WHERE s.key IN (" +
                "SELECT e.series_key FROM episodes_fts f JOIN episodes e ON e.rowid = f.rowid " +
                "WHERE episodes_fts MATCH ?) ORDER BY s.episodes DESC, s.name COLLATE NOCASE LIMIT 20",
            listOf(seriesOnly),
            ::seriesRow,
        )
        val episodes = queryRaw(
            "SELECT $EPISODE_COLUMNS FROM episodes_fts f JOIN episodes e ON e.rowid = f.rowid " +
                "JOIN series s ON s.key = e.series_key WHERE episodes_fts MATCH ? " +
                "ORDER BY f.rank, $OLDEST_FIRST LIMIT ?",
            listOf(all, limit),
            ::episodeRow,
        )
        SearchResults(series, episodes, searchPeopleBlocking(query), aired, transcriptBlocking(query, all))
    }

    /**
     * Search's transcript section: episodes whose shown automatic transcript
     * (`has_transcript = 1`, Decision 058) says every query word of three
     * letters or more as a word prefix, oldest first, less those [excluding]
     * (the titles, series, and people match) already finds.
     */
    private fun transcriptBlocking(query: String, excluding: String?, limit: Int = 50): List<EpisodeRow> {
        if (!ftsHasTranscript || !hasTranscript) return emptyList()
        val words = Transcript.searchWords(query)
        if (words.isEmpty()) return emptyList()
        val match = words.joinToString(" ") { "{transcript} : \"$it\"*" }
        val not = if (excluding == null) "" else
            " AND e.rowid NOT IN (SELECT rowid FROM episodes_fts WHERE episodes_fts MATCH ?)"
        return queryRaw(
            "SELECT $EPISODE_COLUMNS, e.transcript_url FROM episodes_fts f JOIN episodes e ON e.rowid = f.rowid " +
                "JOIN series s ON s.key = e.series_key WHERE episodes_fts MATCH ? AND e.has_transcript = 1 " +
                "AND e.transcript_url IS NOT NULL$not ORDER BY $OLDEST_FIRST LIMIT ?",
            listOfNotNull(match, excluding) + listOf(limit),
        ) { episodeRow(it).copy(transcriptUrl = it.textOrNull(9)) }
    }

    /**
     * The episodes that aired on the date the query names ([DateQuery]), oldest
     * first, narrowed by its other words in titles, series, and people; null
     * when the query names no date.
     */
    private fun airedBlocking(query: String, limit: Int): AiredResults? {
        val date = DateQuery.parse(query) ?: return null
        val narrow = if (Transcript.tokens(date.rest).any { it.length >= 2 })
            matchExpression(date.rest, column = if (ftsHasTranscript) NON_TRANSCRIPT_COLUMNS else null) else null
        val clause = if (narrow == null) "" else
            " AND e.rowid IN (SELECT rowid FROM episodes_fts WHERE episodes_fts MATCH ?)"
        val rows = queryRaw(
            "SELECT $EPISODE_COLUMNS$EPISODE_FROM WHERE e.air_date LIKE ?$clause ORDER BY e.air_date, e.id LIMIT ?",
            listOfNotNull(date.prefix + "%", narrow) + listOf(limit),
            ::episodeRow,
        )
        return AiredResults(date.prefix, rows)
    }

    // --- People (withPerson, contract §5) ---

    private val personColumns: String
        get() = "p.id, p.name, p.birth, p.death, " +
            artColumns
    private val personJoin: String get() = if (hasArt) " LEFT JOIN art a ON a.id = p.portrait" else ""

    private fun person(st: SQLiteStatement) =
        Person(st.getText(0), st.getText(1), st.textOrNull(2), st.textOrNull(3), artwork(st, 4))

    /**
     * `withPerson(id)` as a page: the person's facts and every served episode
     * crediting them, oldest first, one row per episode with all its roles.
     * Null when the catalog serves none of their credits.
     */
    suspend fun personPage(id: String): PersonPage? = read {
        val person = queryRaw("SELECT $personColumns FROM people p$personJoin WHERE p.id = ?", listOf(id), ::person)
            .firstOrNull() ?: return@read null
        val credits = queryRaw(
            "SELECT $EPISODE_COLUMNS, c.role, c.character FROM credits c JOIN episodes e ON e.id = c.episode_id " +
                "JOIN series s ON s.key = e.series_key WHERE c.person_id = ? " +
                "ORDER BY $OLDEST_FIRST, COALESCE(c.role, ''), COALESCE(c.character, '')",
            listOf(id),
        ) { episodeRow(it) to PersonRole(it.textOrNull(9), it.textOrNull(10)) }
        val episodes = LinkedHashMap<String, PersonEpisode>()
        for ((episode, role) in credits) {
            val held = episodes[episode.id]
            episodes[episode.id] = held?.copy(roles = held.roles + role) ?: PersonEpisode(episode, listOf(role))
        }
        if (episodes.isEmpty()) null else PersonPage(person, episodes.values.toList())
    }

    /**
     * `searchPeople(q)`: people whose name has every typed word (two characters
     * or more) as a word prefix, never a substring, diacritics and case folded;
     * most served episodes first, then by name.
     */
    suspend fun searchPeople(query: String, limit: Int = 8): List<PersonRow> = read { searchPeopleBlocking(query, limit) }

    private fun searchPeopleBlocking(query: String, limit: Int = 8): List<PersonRow> {
        val words = nameWords(query).filter { it.length >= 2 }
        if (words.isEmpty()) return emptyList()
        val hits = queryRaw("SELECT id, name FROM people") { it.getText(0) to it.getText(1) }.filter { (_, name) ->
            val have = nameWords(name)
            words.all { w -> have.any { it.startsWith(w) } }
        }
        return hits.map { (pid, name) ->
            Triple(pid, name, queryRaw("SELECT COUNT(DISTINCT episode_id) FROM credits WHERE person_id = ?", listOf(pid)) {
                it.getLong(0).toInt()
            }.firstOrNull() ?: 0)
        }
            .filter { it.third > 0 }
            .sortedWith(compareByDescending<Triple<String, String, Int>> { it.third }
                .thenBy { it.second.lowercase() }.thenBy { it.first })
            .take(limit)
            .mapNotNull { (pid, _, count) ->
                queryRaw("SELECT $personColumns FROM people p$personJoin WHERE p.id = ?", listOf(pid), ::person)
                    .firstOrNull()?.let { PersonRow(it, count) }
            }
    }

    /** Contract §3.3 `voices`, the most heard voices; a catalog without the table has none. */
    private val hasVoices: Boolean by lazy {
        "episodes" in queryRaw("PRAGMA table_info(voices)") { it.getText(1) }
    }

    /**
     * "That night on the radio" (§3.3b): the other surviving broadcasts on an air date, capped, by
     * network (unknown last), then series, then id. Only a full YYYY-MM-DD has a day; it rides
     * `episodes_date`.
     */
    suspend fun sameDay(date: String?, excluding: String, limit: Int = 12): List<EpisodeRow> = read {
        if (date == null || date.length != 10) return@read emptyList()
        queryRaw(
            "SELECT $EPISODE_COLUMNS$EPISODE_FROM WHERE e.air_date = ? AND e.id != ? " +
                "ORDER BY e.network IS NULL, e.network, e.series_key, e.id LIMIT ?",
            listOf(date, resolve(excluding), limit),
            ::episodeRow,
        )
    }

    /** The most heard voices (§3.3 `voices`), most episodes first; empty for a catalog without them. */
    suspend fun voices(limit: Int = 300): List<PersonRow> = read {
        if (!hasVoices) return@read emptyList()
        queryRaw(
            "SELECT $personColumns, v.episodes FROM voices v JOIN people p ON p.id = v.person_id$personJoin " +
                "ORDER BY v.rank LIMIT ?",
            listOf(limit),
        ) { PersonRow(person(it), it.getLong(11).toInt()) }
    }

    // --- Shelves ---

    /** `meta.listenShelves` (contract §5.1), or null for a catalog that predates it. */
    val publishedShelves: List<PublishedShelf>? by lazy {
        queryRaw("SELECT value FROM meta WHERE key = 'listenShelves'") { it.getText(0) }.firstOrNull()
            ?.let(PublishedShelf::parse)
    }

    /**
     * The Listen tab's shelves (§5.1): `meta.listenShelves` in its order, This day
     * in radio on the person's own [monthDay] (`MM-dd`), each genre from its
     * published ids. A catalog without the key falls back to the rules run here.
     * Empty shelves are dropped.
     */
    suspend fun listenShelves(monthDay: String): List<ListenShelf> {
        val published = read { publishedShelves }
        val shelves = if (published != null) {
            published.map {
                when (it) {
                    PublishedShelf.OnThisDay -> ListenShelf("thisday", null, shelf(ShelfRule.ThisDay(monthDay)))
                    is PublishedShelf.GenreFirsts -> ListenShelf("genre:${it.genre}", it.genre, episodes(it.episodes))
                    is PublishedShelf.MostDownloaded ->
                        ListenShelf("mostdownloaded", null, episodes(it.episodes), heading = "Most downloaded")
                }
            }
        } else {
            listOf(ListenShelf("thisday", null, shelf(ShelfRule.ThisDay(monthDay)))) +
                genres().filter { DisplayVocabulary.genreName(it) != null }
                    .map { ListenShelf("genre:$it", it, shelf(ShelfRule.Genre(it))) }
        }
        return shelves.filter { it.rows.isNotEmpty() }
    }

    /**
     * Surprise's episode (ANDROID-DESIGN §4.14): one served episode with a
     * recording, at random. It chooses for the listener, so `recommendAnd`.
     * SQLite's own random(): nothing needs to match another device.
     */
    suspend fun randomEpisode(): EpisodeRow? = read {
        queryRaw(
            "SELECT $EPISODE_COLUMNS$EPISODE_FROM WHERE EXISTS " +
                "(SELECT 1 FROM recordings r WHERE r.episode_id = e.id)$RECOMMEND_AND ORDER BY random() LIMIT 1",
            emptyList(),
            ::episodeRow,
        ).firstOrNull()
    }

    /** §5 `shelf`: a Listen shelf, always with `recommendAnd`. */
    suspend fun shelf(rule: ShelfRule, limit: Int = 30): List<EpisodeRow> = read {
        when (rule) {
            // §5.1: a full YYYY-MM-DD only, oldest first, ties by id, at most 20.
            is ShelfRule.ThisDay -> queryRaw(
                "SELECT $EPISODE_COLUMNS$EPISODE_FROM WHERE e.air_date GLOB '$FULL_DATE' " +
                    "AND substr(e.air_date, 6, 5) = ?$RECOMMEND_AND ORDER BY e.air_date, e.id LIMIT ?",
                listOf(rule.monthDay, minOf(limit, SHELF_LIMIT)),
                ::episodeRow,
            )
            is ShelfRule.Genre -> queryRaw(
                "SELECT $EPISODE_COLUMNS$EPISODE_FROM WHERE s.genre = ? AND e.air_date IS NOT NULL" +
                    "$RECOMMEND_AND ORDER BY $OLDEST_FIRST LIMIT ?",
                listOf(rule.genre, limit),
                ::episodeRow,
            )
        }
    }

    // --- plumbing ---

    private fun seriesRow(st: SQLiteStatement) = SeriesRow(
        key = st.getText(0),
        name = st.getText(1),
        genre = st.textOrNull(2),
        firstDate = st.textOrNull(3),
        lastDate = st.textOrNull(4),
        episodes = st.getLong(5).toInt(),
        face = seriesLook[st.getText(0)]?.face,
        picture = seriesLook[st.getText(0)]?.picture,
        pictureKind = seriesLook[st.getText(0)]?.pictureKind,
        networks = seriesLook[st.getText(0)]?.networks.orEmpty(),
        yearCounts = seriesLook[st.getText(0)]?.yearCounts,
        sortName = seriesLook[st.getText(0)]?.sortName,
    )

    private fun episodeRow(st: SQLiteStatement) = EpisodeRow(
        id = st.getText(0),
        seriesKey = st.getText(1),
        seriesName = st.getText(2),
        airDate = st.textOrNull(3),
        season = st.textOrNull(4),
        num = if (st.isNull(5)) null else st.getLong(5).toInt(),
        title = st.textOrNull(6),
        lengthSeconds = if (st.isNull(7)) null else st.getDouble(7),
        network = st.textOrNull(8),
        seriesGenre = seriesLook[st.getText(1)]?.genre,
        seriesFace = seriesLook[st.getText(1)]?.face,
        seriesPicture = seriesLook[st.getText(1)]?.picture,
    )

    private fun SQLiteStatement.textOrNull(i: Int): String? = if (isNull(i)) null else getText(i)

    private suspend fun <T> read(block: () -> T): T =
        withContext(Dispatchers.IO) { mutex.withLock { block() } }

    private fun <T> queryRaw(sql: String, binds: List<Any?> = emptyList(), map: (SQLiteStatement) -> T): List<T> {
        if (closed) return emptyList()
        val out = mutableListOf<T>()
        val stmt = connection.prepare(sql)
        try {
            binds.forEachIndexed { i, value ->
                val idx = i + 1
                when (value) {
                    null -> stmt.bindNull(idx)
                    is String -> stmt.bindText(idx, value)
                    is Int -> stmt.bindLong(idx, value.toLong())
                    is Long -> stmt.bindLong(idx, value)
                    is Double -> stmt.bindDouble(idx, value)
                    else -> stmt.bindText(idx, value.toString())
                }
            }
            while (stmt.step()) out.add(map(stmt))
        } finally {
            stmt.close()
        }
        return out
    }
}
