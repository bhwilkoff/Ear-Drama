package com.example.appname.playback

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * R20 (docs/research/05-design-research.md §9). [r20Violations] states the
 * rules; the real timer must pass it, and each broken variant below (one rule
 * removed) must fail it, which proves the check can see each rule.
 */
class SleepTimerTest {

    /** Every R20 rule the policy breaks, in words. Empty means it keeps them all. */
    private fun r20Violations(make: () -> SleepPolicy): List<String> {
        val out = mutableListOf<String>()

        if (make().options.firstOrNull() != SleepMode.EndOfEpisode) out += "end of episode is not offered first"

        // Fade: full volume until the last stretch, then lower, never rising, before the pause.
        make().run {
            arm(SleepMode.Minutes(15), nowMs = 0)
            val end = 15 * 60_000L
            val early = tick(end - 60_000, null, 1f)
            val v8 = tick(end - 8_000, null, 1f)
            val v4 = tick(end - 4_000, null, 1f)
            val v1 = tick(end - 1_000, null, 1f)
            if (early.volume != 1f || early.pause) out += "changes volume a minute out"
            if (!(v8.volume < 1f && v4.volume < v8.volume && v1.volume < v4.volume && v1.volume > 0f)) {
                out += "does not fade over its last seconds (${v8.volume}, ${v4.volume}, ${v1.volume})"
            }
            if (v1.pause) out += "pauses before its time"
            val fire = tick(end, null, 1f)
            if (!fire.pause) out += "does not pause when the time is up"
            if (allowsAutoAdvance()) out += "lets the next episode start after firing (minutes)"
        }

        // End of this episode: fades against the episode's remaining time, pauses at its end, never advances.
        make().run {
            arm(SleepMode.EndOfEpisode, nowMs = 0)
            if (!pausesAtEndOfItem) out += "does not hold the player at the end of the item"
            if (allowsAutoAdvance()) out += "allows advancing while end of episode is armed"
            val fading = tick(1_000, remainingMediaMs = 5_000, speed = 1f)
            if (!(fading.volume < 1f && fading.volume > 0f)) out += "end of episode does not fade"
            val ended = onItemEnded()
            if (!ended.pause) out += "does not pause at the end of the episode"
            if (allowsAutoAdvance()) out += "lets the next episode start after firing (end of episode)"
            if (onItemEnded().pause.not()) out += "a second item end after firing would play on"
        }

        return out
    }

    @Test fun `the timer keeps every R20 rule`() {
        assertEquals(emptyList<String>(), r20Violations { SleepTimer() })
    }

    // --- controls: each removes one rule and must be caught ---

    private open class Delegating(private val inner: SleepPolicy = SleepTimer()) : SleepPolicy by inner

    @Test fun `control - a timer without a fade is caught`() {
        val v = r20Violations { SleepTimer(fadeMs = 0) }
        assertTrue(v.toString(), v.any { "fade" in it })
    }

    @Test fun `control - durations offered before end of episode are caught`() {
        val v = r20Violations {
            object : Delegating() {
                override val options = SleepTimer.OPTIONS.reversed()
            }
        }
        assertTrue(v.toString(), v.any { "first" in it })
    }

    @Test fun `control - a timer that lets the queue advance after firing is caught`() {
        val v = r20Violations {
            object : Delegating() {
                override fun allowsAutoAdvance() = true
            }
        }
        assertTrue(v.toString(), v.any { "next episode" in it })
    }

    @Test fun `control - an end of episode that does not pause is caught`() {
        val v = r20Violations {
            object : Delegating() {
                override fun onItemEnded() = SleepDecision(volume = 1f, pause = false)
            }
        }
        assertTrue(v.toString(), v.any { "end of the episode" in it })
    }

    // --- the state machine directly ---

    @Test fun `playing again after it fired stands the timer down`() {
        val t = SleepTimer()
        t.arm(SleepMode.EndOfEpisode, 0)
        t.onItemEnded()
        assertEquals(SleepState.Fired, t.state)
        assertFalse(t.allowsAutoAdvance())
        t.onUserPlay()
        assertEquals(SleepState.Off, t.state)
        assertTrue(t.allowsAutoAdvance())
    }

    @Test fun `end of episode counts real time at the playback speed`() {
        val t = SleepTimer()
        t.arm(SleepMode.EndOfEpisode, 0)
        // 16 s of media at 2x is 8 s of real time: inside the 10 s fade.
        assertTrue(t.tick(0, 16_000, 2f).volume < 1f)
        assertEquals(1f, t.tick(0, 16_000, 1f).volume)
    }

    @Test fun `an unknown length waits for the item to end`() {
        val t = SleepTimer()
        t.arm(SleepMode.EndOfEpisode, 0)
        assertEquals(SleepDecision(1f, false), t.tick(10_000, null, 1f))
        assertTrue(t.onItemEnded().pause)
    }

    @Test fun `off is full volume and lets the queue move on`() {
        val t = SleepTimer()
        assertEquals(SleepDecision(1f, false), t.tick(0, 1_000, 1f))
        assertTrue(t.allowsAutoAdvance())
        assertFalse(t.pausesAtEndOfItem)
        assertFalse(t.onItemEnded().pause)
    }

    @Test fun `cancel turns it off`() {
        val t = SleepTimer()
        t.arm(SleepMode.Minutes(30), 0)
        t.cancel()
        assertEquals(SleepState.Off, t.state)
    }
}
