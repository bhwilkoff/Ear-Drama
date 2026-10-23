package com.example.appname.data

import androidx.sqlite.SQLiteConnection
import androidx.sqlite.SQLiteStatement
import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json

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

        private const val EPISODE_COLUMNS =
            "e.id, e.series_key, s.name, e.air_date, e.season, e.num, e.title, e.length_s"
        private const val EPISODE_FROM = " FROM episodes e JOIN series s ON s.key = e.series_key"
        private const val SERIES_COLUMNS = "s.key, s.name, s.genre, s.first_date, s.last_date, s.episodes"

        /** R1: oldest first, undated last, then the log number, then the title. */
        private const val OLDEST_FIRST = "e.air_date IS NULL, COALESCE(e.air_date, ''), " +
            "e.num IS NULL, COALESCE(e.num, 0), COALESCE(e.title, ''), e.id"
        private const val CURRENT_ORDER = "cur.air_date IS NULL, COALESCE(cur.air_date, ''), " +
            "cur.num IS NULL, COALESCE(cur.num, 0), COALESCE(cur.title, ''), cur.id"

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

    /** The genres the catalog names; with [decade], only those with a series on the air then (web §10.5). */
    suspend fun genres(decade: Int? = null): List<String> = read {
        val (clause, binds) = decadeClause(decade)
        queryRaw(
            "SELECT DISTINCT s.genre FROM series s WHERE s.genre IS NOT NULL AND s.genre <> ''$clause ORDER BY s.genre",
            binds,
        ) { it.getText(0) }
    }

    /**
     * The decades the catalog's series were on the air, from the data, never
     * a fixed list; with [genre], only that genre's (each facet counted
     * against the other, so no chip offered yields zero rows).
     */
    suspend fun seriesDecades(genre: String? = null): List<Int> = read {
        val where = if (genre == null) "" else " AND s.genre = ?"
        queryRaw(
            "SELECT DISTINCT substr(s.first_date, 1, 4), substr(COALESCE(s.last_date, s.first_date), 1, 4) " +
                "FROM series s WHERE s.first_date IS NOT NULL$where",
            listOfNotNull(genre),
        ) { decadesSpanning(it.getText(0).toIntOrNull(), it.getText(1).toIntOrNull()) }
            .flatten().distinct().sorted()
    }

    private fun decadeClause(decade: Int?): Pair<String, List<Any?>> =
        if (decade == null) "" to emptyList()
        else " AND s.first_date <= ? AND COALESCE(s.last_date, s.first_date) >= ?" to listOf("${decade + 9}-12-31", "$decade-01-01")

    /** §5 `seriesBrowse`: the listener drives it, so no `recommendAnd`. */
    suspend fun seriesBrowse(filter: BrowseFilter, limit: Int = 200, offset: Int = 0): List<SeriesRow> = read {
        val where = StringBuilder(" WHERE 1 = 1")
        val binds = mutableListOf<Any?>()
        filter.genre?.let { where.append(" AND s.genre = ?"); binds += it }
        filter.network?.let { where.append(" AND s.networks LIKE ?"); binds += "%\"$it\"%" }
        decadeClause(filter.decade).let { (clause, values) ->
            where.append(clause)
            binds.addAll(values)
        }
        binds += limit
        binds += offset
        queryRaw(
            "SELECT $SERIES_COLUMNS FROM series s$where ORDER BY s.name COLLATE NOCASE, s.key LIMIT ? OFFSET ?",
            binds,
            ::seriesRow,
        )
    }

    suspend fun series(key: String): SeriesRow? = read {
        queryRaw("SELECT $SERIES_COLUMNS FROM series s WHERE s.key = ?", listOf(key), ::seriesRow).firstOrNull()
    }

    /** §5 `seriesPage`: the series and its broadcast seasons, oldest first, undated last. */
    suspend fun seriesPage(key: String): SeriesPage? = read {
        val series = queryRaw("SELECT $SERIES_COLUMNS FROM series s WHERE s.key = ?", listOf(key), ::seriesRow)
            .firstOrNull() ?: return@read null
        val seasons = queryRaw(
            "SELECT season, COUNT(*) FROM episodes WHERE series_key = ? " +
                "GROUP BY season ORDER BY season IS NULL, season",
            listOf(key),
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

    /** §3.5: an id that changed forwards to its new one. */
    private fun resolve(id: String): String =
        if (queryRaw("SELECT 1 FROM episodes WHERE id = ?", listOf(id)) { 1 }.isNotEmpty()) id
        else queryRaw("SELECT new_id FROM episode_aliases WHERE old_id = ?", listOf(id)) { it.getText(0) }
            .firstOrNull() ?: id

    /** §5 `episodeDetail`: the row, its credits, and its recordings in rank order. */
    suspend fun episodeDetail(id: String): EpisodeDetail? = read {
        val resolved = resolve(id)
        val loudness = if (hasLoudness) "e.loudness_i, e.loudness_tp" else "NULL, NULL"
        // Shown only where the gate passed, whatever else the row carries.
        val transcript = if (hasTranscript) "CASE WHEN e.has_transcript = 1 THEN e.transcript_url END" else "NULL"
        val head = queryRaw(
            "SELECT $EPISODE_COLUMNS, e.rights, e.rights_basis, e.network, e.no_recommend, e.detail_json, " +
                "$loudness, $transcript$EPISODE_FROM WHERE e.id = ?",
            listOf(resolved),
        ) { st ->
            EpisodeDetail(
                episode = episodeRow(st),
                rights = st.getText(8),
                rightsBasis = st.textOrNull(9),
                network = st.textOrNull(10),
                noRecommend = st.textOrNull(11),
                credits = emptyList(),
                recordings = emptyList(),
                detailJson = st.textOrNull(12),
                loudnessI = if (st.isNull(13)) null else st.getDouble(13),
                loudnessTp = if (st.isNull(14)) null else st.getDouble(14),
                transcriptUrl = st.textOrNull(15),
            )
        }.firstOrNull() ?: return@read null
        val credits = queryRaw(
            "SELECT c.person_id, p.name, c.role, c.character FROM credits c " +
                "JOIN people p ON p.id = c.person_id WHERE c.episode_id = ? ORDER BY c.rowid",
            listOf(resolved),
        ) { Credit(it.getText(0), it.getText(1), it.textOrNull(2), it.textOrNull(3)) }
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
     * in a transcript never lists a series.
     */
    suspend fun search(query: String, limit: Int = 100): SearchResults = read {
        val all = matchExpression(query) ?: return@read SearchResults(emptyList(), emptyList())
        val seriesOnly = matchExpression(query, column = "series")!!
        // The same terms without the transcript column: a row the full match
        // finds and this one does not was found by its transcript alone.
        val elsewhere = if (ftsHasTranscript) matchExpression(query, column = NON_TRANSCRIPT_COLUMNS) else null
        val flag = if (elsewhere == null) "0"
        else "e.rowid NOT IN (SELECT rowid FROM episodes_fts WHERE episodes_fts MATCH ?)"
        val series = queryRaw(
            "SELECT $SERIES_COLUMNS FROM series s WHERE s.key IN (" +
                "SELECT e.series_key FROM episodes_fts f JOIN episodes e ON e.rowid = f.rowid " +
                "WHERE episodes_fts MATCH ?) ORDER BY s.episodes DESC, s.name COLLATE NOCASE LIMIT 20",
            listOf(seriesOnly),
            ::seriesRow,
        )
        val found = queryRaw(
            "SELECT $EPISODE_COLUMNS, $flag FROM episodes_fts f JOIN episodes e ON e.rowid = f.rowid " +
                "JOIN series s ON s.key = e.series_key WHERE episodes_fts MATCH ? " +
                "ORDER BY f.rank, $OLDEST_FIRST LIMIT ?",
            listOfNotNull(elsewhere) + listOf(all, limit),
        ) { episodeRow(it) to (it.getLong(8) != 0L) }
        SearchResults(series, found.map { it.first }, found.filter { it.second }.map { it.first.id }.toSet())
    }

    // --- Shelves ---

    /** §5 `shelf`: a Listen shelf, always with `recommendAnd`. */
    suspend fun shelf(rule: ShelfRule, limit: Int = 30): List<EpisodeRow> = read {
        when (rule) {
            is ShelfRule.ThisDay -> queryRaw(
                "SELECT $EPISODE_COLUMNS$EPISODE_FROM WHERE substr(e.air_date, 6, 5) = ?$RECOMMEND_AND " +
                    "ORDER BY $OLDEST_FIRST LIMIT ?",
                listOf(rule.monthDay, limit),
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
