package com.example.appname.playback

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** DECISIONS 062: one set of player numbers, here and in the web player. */
class PlayerNumbersTest {
    @Test fun `the numbers are Decision 062's`() {
        assertEquals(10_000L, PlayerNumbers.SLEEP_FADE_MS)
        assertEquals(listOf(0.75f, 1f, 1.25f, 1.5f, 2f), PlayerNumbers.SPEEDS)
        assertEquals(5_000L, PlayerNumbers.SAVE_EVERY_MS)
        assertEquals(3_000L, PlayerNumbers.RESUME_REWIND_MS)
        assertEquals(PlayerNumbers.SLEEP_FADE_MS, SleepTimer.FADE_MS)
    }

    /** Play on the episode already on the player resumes it in place (2026-11-14: it reloaded). */
    @Test fun `Play on the loaded episode resumes in place, anything else loads`() {
        val ready = androidx.media3.common.Player.STATE_READY
        val url = "https://archive.org/download/x/a.mp3"
        assertTrue(PlayerNumbers.resumesInPlace("x|1", "x|1", url, null, null, ready))
        assertTrue(PlayerNumbers.resumesInPlace("x|1", "x|1", url, url, null, androidx.media3.common.Player.STATE_BUFFERING))
        assertFalse("another episode", PlayerNumbers.resumesInPlace("x|1", "x|2", url, null, null, ready))
        assertFalse("another copy", PlayerNumbers.resumesInPlace("x|1", "x|1", url, "https://archive.org/download/x/b.mp3", null, ready))
        assertFalse("a start of its own", PlayerNumbers.resumesInPlace("x|1", "x|1", url, null, 0L, ready))
        assertFalse("a failed load", PlayerNumbers.resumesInPlace("x|1", "x|1", url, null, null, androidx.media3.common.Player.STATE_IDLE))
        assertFalse("an ended one", PlayerNumbers.resumesInPlace("x|1", "x|1", url, null, null, androidx.media3.common.Player.STATE_ENDED))
        assertFalse("nothing loaded", PlayerNumbers.resumesInPlace(null, "x|1", null, null, null, null))
        val engine = File("src/main/java/com/example/appname/playback/PlaybackEngine.kt").readText()
        val play = engine.substringAfter("fun play(episode: EpisodeRow").substringBefore("scope.launch")
        assertTrue("the engine's play asks first", "resumesInPlace" in play)
    }

    /** A retry after a failure keeps the person's pause (2026-11-14: it always played). */
    @Test fun `a recovery keeps play-when-ready, never starts what was paused`() {
        val engine = File("src/main/java/com/example/appname/playback/PlaybackEngine.kt").readText()
        val recover = engine.substringAfter("private suspend fun recover(").substringBefore("\n    }")
        assertTrue("the retry sets play-when-ready from the person's", "playWhenReady = play" in recover)
        assertFalse("never an unconditional play", "p.play()" in recover)
        val error = engine.substringAfter("override fun onPlayerError").substringBefore("\n        }")
        assertTrue("an error passes the paused state on", "recover(play = playerOrNull?.playWhenReady == true)" in error)
    }

    @Test fun `resuming rewinds 3 s and never before the start`() {
        assertEquals(597_000L, PlayerNumbers.rewound(600_000L))
        assertEquals(0L, PlayerNumbers.rewound(2_000L))
    }

    /**
     * A saved position resumes exactly; only an interruption rewinds (062). The
     * control: the old Android behavior, a rewind from a saved position, is caught.
     */
    @Test fun `a saved position resumes exactly, only an interruption rewinds`() {
        assertEquals(600_000L, PlayerNumbers.fromSaved(600_000L, finished = false))
        assertEquals("a finished episode starts over", 0L, PlayerNumbers.fromSaved(600_000L, finished = true))
        assertNotEquals(PlayerNumbers.rewound(600_000L), PlayerNumbers.fromSaved(600_000L, finished = false))
        val engine = File("src/main/java/com/example/appname/playback/PlaybackEngine.kt").readText()
        val start = engine.substringAfter("private suspend fun startPositionFor").substringBefore("\n    }")
        assertTrue("the saved start goes through fromSaved", "fromSaved" in start)
        assertFalse("the saved start never rewinds", "rewound" in start)
    }

    /**
     * A duration once misread as longer than the recording saved a place past its
     * real end; the catalog length, less the finished slack, starts it over.
     */
    @Test fun `a saved place at or past the catalog length less the slack starts over`() {
        val length = 1_421_600L
        val slack = com.example.appname.data.UserStore.FINISHED_WITHIN_MS
        assertEquals(600_000L, PlayerNumbers.fromSaved(600_000L, finished = false, lengthMs = length))
        assertEquals(length - slack - 1, PlayerNumbers.fromSaved(length - slack - 1, finished = false, lengthMs = length))
        assertEquals(0L, PlayerNumbers.fromSaved(length - slack, finished = false, lengthMs = length))
        assertEquals(0L, PlayerNumbers.fromSaved(3_000_000L, finished = false, lengthMs = length))
        assertEquals("no known length: the place stands", 3_000_000L, PlayerNumbers.fromSaved(3_000_000L, finished = false, lengthMs = null))
    }

    private fun webNumbers(source: String): List<String> = listOf(
        Regex("""const FADE_S = (\d+);""").find(source)?.groupValues?.get(1)?.let { (it.toLong() * 1000).toString() }
            ?: "missing",
        Regex("""const SPEEDS = \[([^\]]*)\];""").find(source)?.groupValues?.get(1)
            ?.split(",")?.joinToString(",") { it.trim().toFloat().toString() } ?: "missing",
        Regex("""const SAVE_EVERY_MS = (\d+);""").find(source)?.groupValues?.get(1) ?: "missing",
        Regex("""const REWIND_S = (\d+);""").find(source)?.groupValues?.get(1)?.let { (it.toLong() * 1000).toString() }
            ?: "missing",
    )

    private val androidNumbers = listOf(
        PlayerNumbers.SLEEP_FADE_MS.toString(),
        PlayerNumbers.SPEEDS.joinToString(","),
        PlayerNumbers.SAVE_EVERY_MS.toString(),
        PlayerNumbers.RESUME_REWIND_MS.toString(),
    )

    @Test fun `the web player carries the same numbers`() {
        val web = File("../../js/player.js").readText()
        assertEquals(androidNumbers, webNumbers(web))
        // The control: the web's numbers before Decision 062 are caught.
        val before = "const FADE_S = 20;\nconst SPEEDS = [0.8, 1, 1.2, 1.5, 2];\nconst SAVE_EVERY_MS = 10000;"
        assertNotEquals(androidNumbers, webNumbers(before))
    }
}
