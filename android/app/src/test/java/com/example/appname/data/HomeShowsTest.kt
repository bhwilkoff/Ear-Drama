package com.example.appname.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** WEB-DESIGN §4.2r rule 5: the same cases as js/api.test.js "homeShows" and "uploadTagged". */
class HomeShowsTest {
    private fun id(n: Int, series: String) = "$series|$n"

    @Test
    fun aShowAppearsAtMostOncePerHome() {
        val seen = mutableSetOf("gunsmoke")
        val start = homeShows(listOf(id(1, "gunsmoke"), id(2, "dragnet"), id(3, "dragnet"), id(4, "suspense")), seen)
        assertEquals(listOf("dragnet|2", "suspense|4"), start)
        val length = homeShows(listOf(id(5, "dragnet"), id(6, "suspense"), id(7, "xminusone"), id(8, "gunsmoke")), seen)
        assertEquals("By length never opens on Start a show's shows", listOf("xminusone|7"), length)
        assertEquals(setOf("gunsmoke", "dragnet", "suspense", "xminusone"), seen)
    }

    @Test
    fun chipsSkipOnlyWhatIsAboveAndTheFirstFeedsTheRowsBelow() {
        val a = HomeShelf("a", "A", listOf(id(1, "x"), id(2, "y")))
        val b = HomeShelf("b", "B", listOf(id(3, "x")))
        val c = HomeShelf("c", "C", listOf(id(4, "hero")))
        val out = homeChips(listOf(c, a, b), setOf("hero"))
        assertEquals("a chip left empty is dropped", listOf("a", "b"), out.shelves.map { it.key })
        assertEquals("a later chip is not filtered by the first chip's shows", listOf("x|3"), out.shelves[1].ids)
        assertEquals(setOf("hero", "x", "y"), out.seen)
    }

    @Test
    fun anUploadTagOrIdentifierIsRawText() {
        assertTrue(uploadTagged("AbyM #026 The Girl on Shipwreck Island Pt 03 More About Gracie"))
        assertTrue(uploadTagged("OTRR_Suspense_420622"))
        for (t in listOf("The Telltale Bottle", "Sorry, Wrong Number", "The Case of the 13 Keys", "")) {
            assertFalse("$t is a title", uploadTagged(t))
        }
    }

    /** js/api.test.js "placeholderTitle": the same cases. */
    @Test
    fun aPlaceholderIsNeverATitle() {
        for (t in listOf("Title Unknown", "?? Title Unknown ??", "Ceiling Unlimited Title Unknown", "Unknown Title", "No Title Given", "Untitled", "Unknown")) {
            assertTrue("$t is a placeholder", placeholderTitle(t) && uploadTagged(t))
        }
        for (t in listOf("Murderer Unknown", "The Unknown Voice", "Mission to the Unknown", "The Case of the Unknown Source", "Untitled Love", "")) {
            assertFalse("$t is a title", placeholderTitle(t))
        }
        assertEquals("On the air shows the broadcast's date", "1945-04-11", heroTitle("Title Unknown", "amannamedjordan|1945-04-11") { it })
    }

    @Test
    fun aRawTitleGivesWayToTheBroadcastDate() {
        assertEquals("The Telltale Bottle", heroTitle("The Telltale Bottle", "ellery|1939-04-02") { it })
        assertEquals("1946-03-04", heroTitle("AbyM #026 Gracie", "abym|1946-03-04") { it })
        assertNull("control: no date, no line", heroTitle("AbyM #026 Gracie", "abym|") { it })
    }
}
