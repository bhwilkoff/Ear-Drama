package com.example.appname.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** WEB-DESIGN §6.4g: the same golden cases as js/api.test.js "item pages: the series lead, the pictures row, the play lead". */
class ItemLeadTest {
    private fun pic(name: String, w: Int? = 600, h: Int? = 800, evidence: Boolean = true) =
        Artwork("https://upload.example/$name.jpg", w, h, evidence = if (evidence) "https://commons.wikimedia.org/wiki/File:$name" else null)

    private fun urls(list: List<Artwork>) = list.map { it.url.substringAfterLast('/') }

    @Test fun aWideHeroLeadsAnUprightOneDoesNot() {
        assertEquals("h.jpg", ItemLead.seriesLead(pic("h", 1200, 600), pic("p"))?.url?.substringAfterLast('/'))
        assertEquals("p.jpg", ItemLead.seriesLead(pic("h", 600, 800), pic("p"))?.url?.substringAfterLast('/'))
        assertNull(ItemLead.seriesLead(null, null))
    }

    @Test fun theGalleryDrawsOnlyFromTwoEvidencedPictures() {
        val lead = pic("a")
        assertEquals(listOf("b.jpg", "c.jpg"), urls(ItemLead.gallery(listOf(pic("a"), pic("b"), pic("c")), lead)))
        assertTrue("one picture after the lead draws no row", ItemLead.gallery(listOf(pic("a"), pic("b")), lead).isEmpty())
        assertTrue("a repeat and a picture with no size do not count", ItemLead.gallery(listOf(pic("b"), pic("b"), pic("c", 0, 0)), null).isEmpty())
        assertTrue("a picture with no evidence does not count", ItemLead.gallery(listOf(pic("b", evidence = false), pic("c")), null).isEmpty())
    }

    @Test fun aPlayLeadsWithItsTitlePageThenItsAuthor() {
        assertEquals("t.jpg", ItemLead.playLead(pic("t"), pic("a"))?.url?.substringAfterLast('/'))
        assertEquals("a.jpg", ItemLead.playLead(null, pic("a", 1, 1))?.url?.substringAfterLast('/'))
        assertEquals("p.jpg", ItemLead.playLead(null, pic("a"), pic("p"))?.url?.substringAfterLast('/'))
        assertEquals("t.jpg", ItemLead.playLead(pic("t"), null, pic("p"))?.url?.substringAfterLast('/'))
        assertNull(ItemLead.playLead(null, null))
    }

    @Test fun aHeadPictureKeepsItsOwnShape() {
        val plate = ItemLead.window(pic("w", 1600, 800), 390f)
        assertTrue(plate.plate && plate.width <= 390f && Math.abs(plate.width / plate.height - 2f) < 0.01f)
        val tall = ItemLead.window(pic("u", 600, 900), 390f)
        assertTrue(!tall.plate && tall.height <= 400f && Math.abs(tall.width / tall.height - 600f / 900f) < 0.01f)
        assertTrue("beside the words an upright picture is at most 320 wide", ItemLead.window(pic("u", 600, 900), 900f).width <= 320f)
        assertEquals(ItemLead.Window(390f, 390f, false), ItemLead.window(null, 390f))
        assertEquals(ItemLead.Window(320f, 320f, false), ItemLead.window(null, 900f))
        assertEquals("a short side under 160 px is not shown", ItemLead.Window(390f, 390f, false), ItemLead.window(pic("s", 150, 150), 390f))
        assertNull("a picture with no published size is not shown", ItemLead.shown(pic("n", null, null)))
    }

    /** V8: on a TV a wide plate is capped so the name and the buttons stay on the first screen; the shape holds. */
    @Test fun aTvCapsTheWidePlateAndKeepsItsShape() {
        val tv = ItemLead.window(pic("w", 1600, 800), 960f, plateMax = 216f)
        assertEquals(216f, tv.height, 0.01f)
        assertEquals(432f, tv.width, 0.01f)
        assertEquals(440f, ItemLead.window(pic("w", 1600, 800), 960f).height, 0.01f)
    }

    /** V8 follow-up: a TV's capped plate stands beside the words; a full-width plate, and any phone's, stays over them. */
    @Test fun aCappedPlateStandsBesideTheWordsAndAFullOneDoesNot() {
        val capped = ItemLead.window(pic("w", 1600, 800), 960f, plateMax = 216f)
        assertTrue(ItemLead.cappedPlate(capped, 960f))
        assertTrue("an uncapped plate spans the board", !ItemLead.cappedPlate(ItemLead.window(pic("w", 1600, 800), 960f), 960f))
        assertTrue("a phone's plate spans the column", !ItemLead.cappedPlate(ItemLead.window(pic("w", 1600, 800), 390f), 390f))
        assertTrue("an upright picture is no plate", !ItemLead.cappedPlate(ItemLead.window(pic("u", 600, 900), 960f), 960f))
    }

    @Test fun anUploadTaggedTitleGivesWayToTheBroadcastDate() {
        fun ep(title: String?, date: String?, num: Int? = null) = EpisodeRow("s|${date ?: ""}", "s", "Suspense", date, null, num, title, null)
        val own = { r: EpisodeRow -> r.title ?: "" }
        val day = { d: String -> "on $d" }
        assertEquals("The Lodger", ItemLead.episodeTitle(ep("The Lodger", "1943-06-17"), own, day))
        assertEquals("on 1943-06-17", ItemLead.episodeTitle(ep("AbyM #026 The Telltale Bottle", "1943-06-17"), own, day))
        assertEquals("No. 7", ItemLead.episodeTitle(ep("AbyM #026 X", null, 7), own, day))
        assertEquals("Suspense", ItemLead.episodeTitle(ep("AbyM #026 X", null), own, day))
    }

    @Test fun theMarkedYearIsTheOnlyBarAtFullInk() {
        val n = (RUN_AXIS.second - RUN_AXIS.first + 1).toDouble()
        val from1942 = (1942 - RUN_AXIS.first) / n
        val from1943 = (1943 - RUN_AXIS.first) / n
        assertFalse(ItemLead.dimmed(from1942, 1942))
        assertTrue("the show's other years sit at 45 %", ItemLead.dimmed(from1943, 1942))
        assertFalse("no marked year dims nothing", ItemLead.dimmed(from1943, null))
    }
}
