package com.example.appname.playback

import org.junit.Assert.assertEquals
import org.junit.Test

/** Decision 067: the leveler's numbers are every platform's, and only the person's queue plays next. */
class LevelingAndQueueTest {
    @Test fun `the leveler's numbers are the web's and Apple's`() {
        assertEquals(-24f, LevelNumbers.THRESHOLD_DB)
        assertEquals(4f, LevelNumbers.RATIO)
        assertEquals(12f, LevelNumbers.KNEE_DB)
        assertEquals(3f, LevelNumbers.ATTACK_MS)
        assertEquals(250f, LevelNumbers.RELEASE_MS)
        assertEquals("0.6 x 18 dB, the Web Audio makeup rule", 10.8f, LevelNumbers.MAKEUP_DB, 1e-4f)
        assertEquals(-1f, LevelNumbers.CEILING_DB)
    }

    @Test fun `one episode, then the queue whatever its series, then stop`() {
        assertEquals(
            "another series plays because the person queued it",
            listOf("gunsmoke|1952-04-26", "x|1"),
            PlaybackQueue.after("suspense|1942-06-17", listOf("gunsmoke|1952-04-26", "x|1")),
        )
        assertEquals("with nothing queued, nothing plays after", emptyList<String>(), PlaybackQueue.after("a|1", emptyList()))
        assertEquals("the episode itself is never queued behind itself", listOf("b|2"), PlaybackQueue.after("a|1", listOf("a|1", "b|2")))
    }
}
