package com.example.appname.playback

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * resilient-media-streaming: a load that wants data, gains no bytes, and does not move for 30 s is
 * a failed load; a slow trickle and a pause never are. The same cases as
 * apple/Tests/StallWatchdogTests.swift.
 */
class StallWatchdogTest {
    /** A fake clock (every 500 ms) over a fake loader: buffered and position as functions of time. */
    private fun firstStall(
        endMs: Long,
        wantsData: (Long) -> Boolean = { true },
        buffered: (Long) -> Long,
        position: (Long) -> Long = { 0 },
    ): Long? {
        val watch = StallWatchdog()
        var t = 0L
        while (t <= endMs) {
            if (watch.stalled(t, wantsData(t), buffered(t), position(t))) return t
            t += 500
        }
        return null
    }

    @Test fun `no bytes for 30 seconds while waiting is a stall`() {
        assertEquals(30_000L, firstStall(60_000, buffered = { 0 }))
    }

    @Test fun `a slow trickle of bytes is never a stall`() {
        assertNull(firstStall(3_600_000, buffered = { it / 20_000 * 1024 }))
    }

    @Test fun `a moving position is never a stall`() {
        assertNull(firstStall(600_000, buffered = { 5 }, position = { it }))
    }

    @Test fun `a pause is never a stall`() {
        assertNull(firstStall(3_600_000, wantsData = { false }, buffered = { 0 }))
    }

    @Test fun `a pause then play counts from the play`() {
        assertEquals(130_000L, firstStall(200_000, wantsData = { it >= 100_000 }, buffered = { 0 }))
    }

    @Test fun `reset starts the count again`() {
        val watch = StallWatchdog()
        watch.stalled(0, true, 0, 0)
        watch.reset()
        assertEquals(false, watch.stalled(40_000, true, 0, 0))
        assertEquals(true, watch.stalled(70_000, true, 0, 0))
    }
}
