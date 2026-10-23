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
