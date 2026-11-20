package com.example.appname.plays

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

/**
 * Publish under my name from a room's local production (PLAYS-DESIGN §12.10 item 5): after the class's `publish` call the
 * receiver's device sends each line's chosen take to archive.org through the Worker, one at a time, in script order.
 * `not_ready` (the cron has not laid the item out) waits and tries again; `already_sent` is skipped; any other refusal stops.
 */
object RoomPublish {
    const val WAIT_MS = 60_000L
    const val TRIES = 30

    /** Codes that mean "later": the item is not laid out yet, the archive is busy, or the network dropped. */
    val LATER = setOf("not_ready", "archive_busy", "archive_unavailable", "offline", "error", "rate_limited")

    /** Sends every chosen take; null when all are on their way, else the Worker's code that stopped it. */
    suspend fun sendFiles(
        wire: ReadClassWire,
        store: ShareStore,
        production: Production,
        script: PlayScript,
        wait: suspend (Long) -> Unit = { delay(it) },
        pid: String = production.roomPid.orEmpty(),
    ): String? {
        for (line in script.lines) {
            val take = production.usableTake(line.id) ?: continue
            if (!line.part.isSpeaking) continue
            var sent = false
            for (attempt in 0 until TRIES) {
                try {
                    val bytes = withContext(Dispatchers.IO) { store.readTake(production.id, take.file) }
                    wire.sendFile(pid, line.id, bytes)
                    sent = true
                    break
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    val code = (e as? ReadFailure)?.code ?: "error"
                    if (code == "already_sent") { sent = true; break }
                    if (code !in LATER) return code
                    wait(WAIT_MS)
                }
            }
            if (!sent) return "not_ready"
        }
        return null
    }
}
