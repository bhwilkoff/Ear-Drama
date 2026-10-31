package com.example.appname.playback

/**
 * Watches progress, not elapsed time (resilient-media-streaming): a load that wants data and has
 * gained no buffered bytes and not moved its position for [LIMIT_MS] never fails by itself, so it
 * is called failed and goes through [LoadRecovery]. A healthy slow load keeps buffering and is
 * never touched. The same machine as apple/Core/Player/StallWatchdog.swift and js/player.js.
 */
class StallWatchdog {
    private data class Mark(val buffered: Long, val position: Long)

    private var mark: Mark? = null
    private var since = 0L

    /**
     * One look at the player. [wantsData]: play-when-ready and buffering from the network.
     * [bufferedMs] is Media3's buffered position; [positionMs] the playhead.
     */
    fun stalled(nowMs: Long, wantsData: Boolean, bufferedMs: Long, positionMs: Long): Boolean {
        val seen = Mark(bufferedMs, positionMs)
        if (!wantsData || seen != mark) {
            mark = if (wantsData) seen else null
            since = nowMs
            return false
        }
        return nowMs - since >= LIMIT_MS
    }

    /** A new item was opened, or the stall was handled: start counting again. */
    fun reset() {
        mark = null
        since = 0
    }

    companion object {
        const val LIMIT_MS = 30_000L
    }
}
