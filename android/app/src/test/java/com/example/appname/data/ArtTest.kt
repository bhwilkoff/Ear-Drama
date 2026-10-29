package com.example.appname.data

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** Decision 069, contract §3.3a: served portraits reach rows, Detail, and the player; an older catalog has none. */
class ArtTest {
    @get:Rule val tmp = TemporaryFolder()

    @Test fun `the series face reaches series rows and every episode row of the series`() = runBlocking {
        val db = CatalogDatabase.open(CatalogFixture.build(tmp.root, withArt = true).path)!!
        try {
            assertEquals("Agnes Moorehead", db.series("suspense")?.face?.name)
            assertNull(db.series("commandperformance")?.face)
            val rows = db.seasonEpisodes("suspense", "1942-43")
            assertTrue(rows.all { it.seriesFace?.name == "Agnes Moorehead" && it.seriesGenre == "mystery" })
        } finally {
            db.close()
        }
    }

    @Test fun `Detail carries its star, each credit's portrait, and the credit a CC license owes`() = runBlocking {
        val db = CatalogDatabase.open(CatalogFixture.build(tmp.root, withArt = true).path)!!
        try {
            val d = db.episodeDetail("sus|1943-05-25")!!
            assertEquals("Agnes Moorehead", d.starFace?.name)
            assertEquals(listOf(true, true), d.credits.map { it.art != null })
            assertEquals(listOf("p2"), d.owedCredits.map { it.personId })
            assertEquals("Alan Light, CC BY 2.0", d.owedCredits.single().art?.credit)
            val other = db.episodeDetail("sus|1943-01-07")!!
            assertNull("no star of its own", other.starFace)
            assertEquals("the series' face", "Agnes Moorehead", other.face?.name)
        } finally {
            db.close()
        }
    }

    @Test fun `a catalog without the art columns still opens and shows none`() = runBlocking {
        val db = CatalogDatabase.open(CatalogFixture.build(tmp.root).path)!!
        try {
            assertNull(db.series("suspense")?.face)
            val d = db.episodeDetail("sus|1943-05-25")
            assertNotNull(d)
            assertTrue(d!!.credits.all { it.art == null } && d.star == null)
        } finally {
            db.close()
        }
    }

    @Test fun `one helper, Commons standard widths only`() {
        val art = Artwork("${CatalogFixture.ART_BASE}/A.jpg")
        assertEquals("${art.url}?width=120", art.url(80))
        assertEquals("${art.url}?width=330", art.url(224))
        assertEquals("${art.url}?width=500", art.url(384))
        assertEquals("${art.url}?width=960", art.url(512))
        assertEquals("${art.url}?width=960", art.url(4000))
        assertEquals(0.8f, art.aspect, 0f)
        assertEquals(0.75f, Artwork("x", width = 600, height = 800).aspect, 0f)
    }

    @Test fun `the shape decides the layout, from the published size`() {
        assertEquals("an unknown size is upright, never guessed wide", false, Artwork("x").isWide)
        assertEquals(null, Artwork("x").aspectRatio)
        assertEquals("a portrait is the print", false, Artwork("x", width = 600, height = 800).isWide)
        assertEquals("the threshold is still upright", false, Artwork("x", width = 1150, height = 1000).isWide)
        assertEquals("a wide picture is the plate", true, Artwork("x", width = 1830, height = 1000).isWide)
    }

    @Test fun `initials skip a leading article`() {
        assertEquals("W", artInitial("The Whistler"))
        assertEquals("A", artInitial("\"America First\""))
        assertEquals("", artInitial("..."))
    }
}
