package com.example.appname.data

import androidx.sqlite.SQLiteConnection
import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import androidx.sqlite.execSQL
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/** Where the listener left an episode. */
data class Progress(val episodeId: String, val positionMs: Long, val durationMs: Long, val finished: Boolean)

/**
 * The listener's own records, on this device only: resume positions and what
 * they finished. A separate file from the catalog, so a catalog swap never
 * touches it. [changes] bumps on every write; screens key their queries on it.
 */
class UserStore private constructor(private val connection: SQLiteConnection) {

    private val mutex = Mutex()
    private val _changes = MutableStateFlow(0)
    val changes: StateFlow<Int> = _changes

    companion object {
        /** An episode this close to its end counts as finished. */
        const val FINISHED_WITHIN_MS = 30_000L

        fun open(path: String): UserStore {
            val connection = BundledSQLiteDriver().open(path)
            connection.execSQL(
                "CREATE TABLE IF NOT EXISTS progress (episode_id TEXT PRIMARY KEY, position_ms INTEGER NOT NULL, " +
                    "duration_ms INTEGER NOT NULL, finished INTEGER NOT NULL DEFAULT 0, updated_at INTEGER NOT NULL)",
            )
            return UserStore(connection)
        }
    }

    suspend fun save(episodeId: String, positionMs: Long, durationMs: Long) = write {
        val finished = durationMs > 0 && positionMs >= durationMs - FINISHED_WITHIN_MS
        val stmt = connection.prepare(
            "INSERT INTO progress (episode_id, position_ms, duration_ms, finished, updated_at) VALUES (?, ?, ?, ?, ?) " +
                "ON CONFLICT(episode_id) DO UPDATE SET position_ms = excluded.position_ms, " +
                "duration_ms = excluded.duration_ms, finished = excluded.finished, updated_at = excluded.updated_at",
        )
        try {
            stmt.bindText(1, episodeId)
            stmt.bindLong(2, if (finished) 0 else positionMs)
            stmt.bindLong(3, durationMs)
            stmt.bindLong(4, if (finished) 1 else 0)
            stmt.bindLong(5, System.currentTimeMillis())
            stmt.step()
        } finally {
            stmt.close()
        }
    }

    suspend fun progress(episodeId: String): Progress? = read {
        select("WHERE episode_id = ?", episodeId).firstOrNull()
    }

    /** §5 `continueListening`: in progress, most recent first. */
    suspend fun inProgress(limit: Int = 20): List<Progress> = read {
        select("WHERE finished = 0 AND position_ms > 0 ORDER BY updated_at DESC LIMIT $limit")
    }

    suspend fun finished(limit: Int = 100): List<Progress> = read {
        select("WHERE finished = 1 ORDER BY updated_at DESC LIMIT $limit")
    }

    private fun select(tail: String, bind: String? = null): List<Progress> {
        val stmt = connection.prepare("SELECT episode_id, position_ms, duration_ms, finished FROM progress $tail")
        try {
            bind?.let { stmt.bindText(1, it) }
            val out = mutableListOf<Progress>()
            while (stmt.step()) {
                out += Progress(stmt.getText(0), stmt.getLong(1), stmt.getLong(2), stmt.getLong(3) != 0L)
            }
            return out
        } finally {
            stmt.close()
        }
    }

    private suspend fun <T> read(block: () -> T): T = withContext(Dispatchers.IO) { mutex.withLock { block() } }

    private suspend fun write(block: () -> Unit) {
        withContext(Dispatchers.IO) { mutex.withLock { block() } }
        _changes.value += 1
    }
}
