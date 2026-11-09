package com.example.appname.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** The Recordings list names a copy from data or by position; an archive.org identifier never shows. */
class RecordingLabelTest {
    private fun copy(rank: Int, id: String, label: String? = null) =
        Recording(rank, id, "https://archive.org/download/$id/a.mp3", "MP3", 128, 1790.0, null, false, label)

    @Test fun `no identifier-shaped text renders in the list`() {
        val ids = listOf("OTRR_Suspense_Singles", "Suspense420617TheBurningCourt", "AnthonyBerkeleyThePoisonedChocolatesCaseBBCSNT198")
        ids.forEach { assertTrue("control: $it is identifier-shaped", RecordingLabel.looksLikeIdentifier(it)) }
        ids.forEachIndexed { i, id ->
            val rec = copy(i, id, label = if (i == 0) id else null)
            val drawn = RecordingLabel.title(rec, "30 min") + " " + RecordingLabel.facts(rec, i == 0, "30 min", emptyList())
            assertFalse(drawn, RecordingLabel.looksLikeIdentifier(drawn))
            assertFalse(drawn.contains(id))
        }
    }

    @Test fun `a clean label wins, else the distinguishing facts, never Recording N`() {
        assertEquals("128 kbps · 30 min", RecordingLabel.title(copy(0, "x"), "30 min"))
        assertEquals("Old Time Radio Researchers", RecordingLabel.title(copy(1, "x", "Old Time Radio Researchers"), "30 min"))
        assertEquals("Best copy", RecordingLabel.facts(copy(0, "x"), true, "30 min", emptyList()))
        assertEquals("Best copy · 128 kbps · 30 min", RecordingLabel.facts(copy(0, "x", "Old Time Radio Researchers"), true, "30 min", emptyList()))
        val bare = Recording(0, "x", "u", "MP3", null, null, null, false, null)
        assertEquals("MP3", RecordingLabel.title(bare, null))
        assertEquals("Another copy", RecordingLabel.title(bare.copy(format = null), null))
        listOf(copy(0, "x"), copy(1, "x", "OTRR_Suspense_Singles"), bare).forEach {
            assertFalse(RecordingLabel.title(it, null).startsWith("Recording"))
        }
    }
}
