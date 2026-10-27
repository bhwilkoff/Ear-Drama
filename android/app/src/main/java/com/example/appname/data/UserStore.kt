package com.example.appname.data

import androidx.sqlite.SQLiteConnection
import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import androidx.sqlite.execSQL
import com.example.appname.account.FollowRow
import com.example.appname.account.HistoryRow
import com.example.appname.account.QueueState
import com.example.appname.account.SyncAnswer
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlin.math.roundToLong

/** Where the listener left an episode. */
data class Progress(val episodeId: String, val positionMs: Long, val durationMs: Long, val finished: Boolean)

/** What sync sends: rows changed here since the last upload, or everything (the anonymous merge). */
data class LocalChanges(val history: List<HistoryRow>, val follows: List<FollowRow>, val queue: QueueState?) {
    val isEmpty get() = history.isEmpty() && follows.isEmpty() && queue == null
}

/**
 * The listener's own records: resume positions, what they finished, followed
 * series, and the queue. A separate file from the catalog, so a catalog swap
 * never touches it. [changes] bumps on every write; screens key their queries
 * on it.
 *
 * Signed out, this is all there is. Signed in (DECISIONS 063), every row
 * carries its `updated_at` and a `dirty` flag that a local write sets and an
 * upload clears; a removal is a marker (`deleted`, `following = 0`), never a
 * missing row, so it reaches the other devices. Rows from the Worker are
 * applied last-write-wins and leave the row clean, so applying a pull never
 * schedules the next push.
 */
class UserStore private constructor(private val connection: SQLiteConnection, private val now: () -> Long) {

    private val mutex = Mutex()
    private val _changes = MutableStateFlow(0)
    val changes: StateFlow<Int> = _changes

    companion object {
        /** An episode this close to its end counts as finished. */
        const val FINISHED_WITHIN_MS = 30_000L

        fun open(path: String, now: () -> Long = System::currentTimeMillis): UserStore {
            val connection = BundledSQLiteDriver().open(path)
            connection.execSQL(
                "CREATE TABLE IF NOT EXISTS progress (episode_id TEXT PRIMARY KEY, position_ms INTEGER NOT NULL, " +
                    "duration_ms INTEGER NOT NULL, finished INTEGER NOT NULL DEFAULT 0, updated_at INTEGER NOT NULL)",
            )
            val columns = connection.prepare("PRAGMA table_info(progress)").use { stmt ->
                buildSet { while (stmt.step()) add(stmt.getText(1)) }
            }
            // Rows from before sync are the signed-out history the merge sends, so they start dirty.
            if ("deleted" !in columns) connection.execSQL("ALTER TABLE progress ADD COLUMN deleted INTEGER NOT NULL DEFAULT 0")
            if ("dirty" !in columns) connection.execSQL("ALTER TABLE progress ADD COLUMN dirty INTEGER NOT NULL DEFAULT 1")
            connection.execSQL(
                "CREATE TABLE IF NOT EXISTS follows (series_id TEXT PRIMARY KEY, following INTEGER NOT NULL, " +
                    "updated_at INTEGER NOT NULL, dirty INTEGER NOT NULL DEFAULT 1)",
            )
            connection.execSQL(
                "CREATE TABLE IF NOT EXISTS queue_state (id INTEGER PRIMARY KEY CHECK (id = 1), items TEXT NOT NULL, " +
                    "updated_at INTEGER NOT NULL, dirty INTEGER NOT NULL DEFAULT 1)",
            )
            return UserStore(connection, now)
        }
    }

    suspend fun save(episodeId: String, positionMs: Long, durationMs: Long) = write {
        val finished = durationMs > 0 && positionMs >= durationMs - FINISHED_WITHIN_MS
        putProgress(episodeId, if (finished) 0 else positionMs, durationMs, finished, deleted = false, at = now(), dirty = true)
    }

    /** Removes an episode from this listener's history, as a marker that syncs. No Android verb calls it yet. */
    suspend fun forget(episodeId: String) = write {
        putProgress(episodeId, 0, 0, finished = false, deleted = true, at = now(), dirty = true)
    }

    /** Follow and Following on a series page (ANDROID-DESIGN §4.3); an unfollow is a marker, so it syncs. */
    suspend fun setFollowing(seriesId: String, following: Boolean) = write {
        putFollow(seriesId, following, now(), dirty = true)
    }

    suspend fun isFollowing(seriesId: String): Boolean = read {
        connection.prepare("SELECT following FROM follows WHERE series_id = ?").use { stmt ->
            stmt.bindText(1, seriesId)
            stmt.step() && stmt.getLong(0) != 0L
        }
    }

    suspend fun followed(): List<String> = read {
        connection.prepare("SELECT series_id FROM follows WHERE following = 1 ORDER BY updated_at DESC").use { stmt ->
            buildList { while (stmt.step()) add(stmt.getText(0)) }
        }
    }

    /** Replaces the queue. It syncs whole, by its own `updated_at`. */
    suspend fun setQueue(items: List<String>) = write { putQueue(items, now(), dirty = true) }

    /** Applies one [QueueEdit] to the stored queue in one step; an edit that leaves it as it was writes nothing. */
    private suspend fun editQueue(edit: (List<String>) -> List<String>) {
        var changed = false
        withContext(Dispatchers.IO) {
            mutex.withLock {
                val current = readQueue()?.items.orEmpty()
                val next = edit(current)
                if (next != current) { putQueue(next, now(), dirty = true); changed = true }
            }
        }
        if (changed) _changes.value += 1
    }

    suspend fun enqueue(id: String) = editQueue { QueueEdit.add(it, id) }
    suspend fun dequeue(id: String) = editQueue { QueueEdit.remove(it, id) }
    suspend fun moveInQueue(id: String, delta: Int) = editQueue { QueueEdit.move(it, id, delta) }
    suspend fun reorderQueue(ids: List<String>) = editQueue { QueueEdit.reorder(it, ids) }

    suspend fun queue(): List<String> = read { readQueue()?.items.orEmpty() }

    suspend fun progress(episodeId: String): Progress? = read {
        select("WHERE episode_id = ? AND deleted = 0", episodeId).firstOrNull()
    }

    /** §5 `continueListening`: in progress, most recent first. */
    suspend fun inProgress(limit: Int = 20): List<Progress> = read {
        select("WHERE finished = 0 AND position_ms > 0 AND deleted = 0 ORDER BY updated_at DESC LIMIT $limit")
    }

    suspend fun finished(limit: Int = 100): List<Progress> = read {
        select("WHERE finished = 1 AND deleted = 0 ORDER BY updated_at DESC LIMIT $limit")
    }

    /** The rows to upload: those changed here since the last upload, or every row when [all] (the merge). */
    suspend fun localChanges(all: Boolean): LocalChanges = read {
        val where = if (all) "" else " WHERE dirty = 1"
        val history = connection.prepare(
            "SELECT episode_id, position_ms, duration_ms, finished, deleted, updated_at FROM progress$where",
        ).use { stmt ->
            buildList {
                while (stmt.step()) {
                    val duration = stmt.getLong(2)
                    add(
                        HistoryRow(
                            episodeId = stmt.getText(0),
                            position = stmt.getLong(1) / 1000.0,
                            duration = if (duration > 0) duration / 1000.0 else null,
                            finished = stmt.getLong(3) != 0L,
                            deleted = stmt.getLong(4) != 0L,
                            updatedAt = stmt.getLong(5),
                        ),
                    )
                }
            }
        }
        val follows = connection.prepare("SELECT series_id, following, updated_at FROM follows$where").use { stmt ->
            buildList { while (stmt.step()) add(FollowRow(stmt.getText(0), stmt.getLong(1) != 0L, stmt.getLong(2))) }
        }
        val queue = readQueue()?.takeIf { all || it.dirty }?.let { QueueState(it.items, it.updatedAt) }
        LocalChanges(history, follows, queue)
    }

    /** After an upload: rows not written again since [sent] was read are clean. */
    suspend fun markUploaded(sent: LocalChanges) = read {
        connection.prepare("UPDATE progress SET dirty = 0 WHERE episode_id = ? AND updated_at = ?").use { stmt ->
            for (h in sent.history) {
                stmt.bindText(1, h.episodeId)
                stmt.bindLong(2, h.updatedAt)
                stmt.step()
                stmt.reset()
            }
        }
        connection.prepare("UPDATE follows SET dirty = 0 WHERE series_id = ? AND updated_at = ?").use { stmt ->
            for (f in sent.follows) {
                stmt.bindText(1, f.seriesId)
                stmt.bindLong(2, f.updatedAt)
                stmt.step()
                stmt.reset()
            }
        }
        sent.queue?.let { q ->
            connection.prepare("UPDATE queue_state SET dirty = 0 WHERE id = 1 AND updated_at = ?").use { stmt ->
                stmt.bindLong(1, q.updatedAt)
                stmt.step()
            }
        }
    }

    /**
     * Applies a pull, last write wins per row. A clean local row always takes
     * the server's (the server already chose); a row changed here and not yet
     * uploaded is kept when it is newer, or equal and this device's name sorts
     * after the writer's (the Worker's own tie-break), and goes up next push.
     */
    suspend fun applyRemote(answer: SyncAnswer, device: String) = write {
        for (h in answer.history) {
            val local = localStamp("SELECT updated_at, dirty FROM progress WHERE episode_id = ?", h.episodeId)
            if (keepLocal(local, h.updatedAt, h.device, device)) continue
            val positionMs = if (h.finished || h.deleted) 0 else (h.position * 1000).roundToLong()
            val durationMs = ((h.duration ?: 0.0) * 1000).roundToLong()
            putProgress(h.episodeId, positionMs, durationMs, h.finished, h.deleted, h.updatedAt, dirty = false)
        }
        for (f in answer.follows) {
            val local = localStamp("SELECT updated_at, dirty FROM follows WHERE series_id = ?", f.seriesId)
            if (keepLocal(local, f.updatedAt, f.device, device)) continue
            putFollow(f.seriesId, f.following, f.updatedAt, dirty = false)
        }
        answer.queue?.let { q ->
            val local = readQueue()?.let { it.updatedAt to it.dirty }
            if (!keepLocal(local, q.updatedAt, q.device, device)) putQueue(q.items, q.updatedAt, dirty = false)
        }
    }

    private fun keepLocal(local: Pair<Long, Boolean>?, remoteAt: Long, remoteDevice: String?, device: String): Boolean {
        val (localAt, dirty) = local ?: return false
        if (!dirty) return false
        return localAt > remoteAt || (localAt == remoteAt && device >= remoteDevice.orEmpty())
    }

    private fun localStamp(sql: String, id: String): Pair<Long, Boolean>? = connection.prepare(sql).use { stmt ->
        stmt.bindText(1, id)
        if (stmt.step()) stmt.getLong(0) to (stmt.getLong(1) != 0L) else null
    }

    private fun putProgress(
        episodeId: String,
        positionMs: Long,
        durationMs: Long,
        finished: Boolean,
        deleted: Boolean,
        at: Long,
        dirty: Boolean,
    ) {
        connection.prepare(
            "INSERT INTO progress (episode_id, position_ms, duration_ms, finished, updated_at, deleted, dirty) " +
                "VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT(episode_id) DO UPDATE SET position_ms = excluded.position_ms, " +
                "duration_ms = excluded.duration_ms, finished = excluded.finished, updated_at = excluded.updated_at, " +
                "deleted = excluded.deleted, dirty = excluded.dirty",
        ).use { stmt ->
            stmt.bindText(1, episodeId)
            stmt.bindLong(2, positionMs)
            stmt.bindLong(3, durationMs)
            stmt.bindLong(4, if (finished) 1 else 0)
            stmt.bindLong(5, at)
            stmt.bindLong(6, if (deleted) 1 else 0)
            stmt.bindLong(7, if (dirty) 1 else 0)
            stmt.step()
        }
    }

    private fun putFollow(seriesId: String, following: Boolean, at: Long, dirty: Boolean) {
        connection.prepare(
            "INSERT INTO follows (series_id, following, updated_at, dirty) VALUES (?, ?, ?, ?) " +
                "ON CONFLICT(series_id) DO UPDATE SET following = excluded.following, " +
                "updated_at = excluded.updated_at, dirty = excluded.dirty",
        ).use { stmt ->
            stmt.bindText(1, seriesId)
            stmt.bindLong(2, if (following) 1 else 0)
            stmt.bindLong(3, at)
            stmt.bindLong(4, if (dirty) 1 else 0)
            stmt.step()
        }
    }

    private class StoredQueue(val items: List<String>, val updatedAt: Long, val dirty: Boolean)

    private fun readQueue(): StoredQueue? =
        connection.prepare("SELECT items, updated_at, dirty FROM queue_state WHERE id = 1").use { stmt ->
            if (!stmt.step()) return@use null
            StoredQueue(stmt.getText(0).split('\n').filter { it.isNotEmpty() }, stmt.getLong(1), stmt.getLong(2) != 0L)
        }

    private fun putQueue(items: List<String>, at: Long, dirty: Boolean) {
        connection.prepare(
            "INSERT INTO queue_state (id, items, updated_at, dirty) VALUES (1, ?, ?, ?) " +
                "ON CONFLICT(id) DO UPDATE SET items = excluded.items, updated_at = excluded.updated_at, dirty = excluded.dirty",
        ).use { stmt ->
            // Episode ids never hold a newline (the Worker refuses control characters).
            stmt.bindText(1, items.joinToString("\n"))
            stmt.bindLong(2, at)
            stmt.bindLong(3, if (dirty) 1 else 0)
            stmt.step()
        }
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
