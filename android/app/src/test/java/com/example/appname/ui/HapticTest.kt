package com.example.appname.ui

import android.view.HapticFeedbackConstants
import com.example.appname.data.DownloadRecord.State
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** AGENTS.md's one haptic taxonomy, at the places it names. */
class HapticTest {
    @Test fun `the semantic events use Android's own constants from API 30`() {
        assertEquals(HapticFeedbackConstants.SEGMENT_TICK, Haptic.Selection.feedbackConstant(30))
        assertEquals(HapticFeedbackConstants.CONFIRM, Haptic.Success.feedbackConstant(30))
        assertEquals(HapticFeedbackConstants.REJECT, Haptic.Error.feedbackConstant(30))
        // API 29 has none of the three; each falls back to a constant it has.
        assertEquals(HapticFeedbackConstants.CLOCK_TICK, Haptic.Selection.feedbackConstant(29))
        Haptic.entries.forEach { it.feedbackConstant(29) }
    }

    @Test fun `a finished download is success and a failed one is error`() {
        assertEquals(Haptic.Success, Haptic.forDownloads(mapOf("a" to State.Downloading), mapOf("a" to State.Downloaded)))
        assertEquals(Haptic.Error, Haptic.forDownloads(mapOf("a" to State.Downloading), mapOf("a" to State.Failed)))
        // Nothing for progress, a record already done at launch, or one just added.
        assertNull(Haptic.forDownloads(mapOf("a" to State.Queued), mapOf("a" to State.Downloading)))
        assertNull(Haptic.forDownloads(mapOf("a" to State.Downloaded), mapOf("a" to State.Downloaded)))
        assertNull(Haptic.forDownloads(emptyMap(), mapOf("a" to State.Queued)))
    }

    @Test fun `error accompanies the player's problem line once`() {
        assertEquals(Haptic.Error, Haptic.forProblem(null, "No connection."))
        assertNull(Haptic.forProblem("No connection.", "No connection."))
        assertNull(Haptic.forProblem("No connection.", null))
    }
}
