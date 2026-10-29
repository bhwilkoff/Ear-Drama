package com.example.appname.account

import com.example.appname.data.IdForwarding
import com.example.appname.data.LocalChanges
import com.example.appname.data.UserStore
import java.io.IOException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * History, queue, and follows between [UserStore] and the Worker (DECISIONS
 * 063): one pass is push, then pull.
 *
 * - The first pass after a sign-in sends everything this device kept signed
 *   out to `/v1/sync/merge`, once; the flag that says so clears only when the
 *   merge succeeded, and the pull after it starts from `since=0`.
 * - Later passes `PUT` only rows changed here since the last upload.
 * - The pull reads `?since=` the last answer's `server_time` and applies it
 *   last-write-wins ([UserStore.applyRemote]).
 *
 * One pass runs at a time. The outcome is kept on the account: `lastSyncAt`
 * on success, `lastError` (a sentence for the status row) on failure.
 */
class SyncEngine(
    private val worker: WorkerApi,
    private val user: UserStore,
    private val device: String,
    /** The open catalog's (contract §3.5): another device's rows may name an id it moved. */
    private val forwarding: suspend () -> IdForwarding? = { null },
    private val now: () -> Long = System::currentTimeMillis,
) {
    private val lock = Mutex()
    private val _running = MutableStateFlow(false)
    val running: StateFlow<Boolean> = _running

    private companion object {
        /** The Worker's per-upload limit for each part. */
        const val MAX_ROWS = 500
    }

    /** One push-and-pull. False when signed out or it failed (the reason is on the account). */
    suspend fun sync(): Boolean = lock.withLock {
        val start = worker.account.value ?: return@withLock false
        _running.value = true
        try {
            if (start.mergePending) {
                val everything = user.localChanges(all = true)
                send(everything, worker::merge)
                worker.update(start.userId) { it.copy(mergePending = false, cursor = 0) }
            } else {
                val changed = user.localChanges(all = false)
                if (!changed.isEmpty) send(changed, worker::upload)
            }
            val since = worker.account.value?.takeIf { it.userId == start.userId }?.cursor ?: return@withLock false
            val answer = worker.read(since)
            user.applyRemote(answer, device)
            forwarding()?.let { user.forward(it) }
            worker.update(start.userId) { it.copy(cursor = answer.serverTime, lastSyncAt = now(), lastError = null) }
            true
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            println("SyncEngine: ${e.javaClass.simpleName}: ${e.message}")
            worker.update(start.userId) { it.copy(lastError = describe(e)) }
            false
        } finally {
            _running.value = false
        }
    }

    /** In parts of at most [MAX_ROWS]; the queue rides the first. Each part sent is marked clean. */
    private suspend fun send(changes: LocalChanges, call: suspend (SyncUpload) -> Long) {
        val history = changes.history.chunked(MAX_ROWS)
        val follows = changes.follows.chunked(MAX_ROWS)
        val parts = maxOf(1, history.size, follows.size)
        for (i in 0 until parts) {
            val part = LocalChanges(
                history = history.getOrElse(i) { emptyList() },
                follows = follows.getOrElse(i) { emptyList() },
                queue = changes.queue.takeIf { i == 0 },
            )
            call(
                SyncUpload(
                    device = device,
                    history = part.history.takeIf { it.isNotEmpty() },
                    follows = part.follows.takeIf { it.isNotEmpty() },
                    queue = part.queue,
                ),
            )
            user.markUploaded(part)
        }
    }

    private fun describe(e: Exception): String = when (e) {
        is SignedOutException -> "Signed out. Sign in again to sync."
        is WorkerException -> "Sync failed: the server answered ${e.status}."
        is IOException -> "Sync failed: no connection to the server."
        else -> "Sync failed."
    }
}
