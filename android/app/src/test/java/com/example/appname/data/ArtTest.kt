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

    /** Contract §3.3a's golden cases, the same as js/api.test.js and Apple's CatalogQueryTests. */
    @Test fun `a small crop is the square around the published face`() {
        fun at(w: Int?, h: Int?, face: String?) = Artwork("x", width = w, height = h, face = FaceBox.parse(face)).cropRect()
        fun near(msg: String, got: CropRect?, x: Float, y: Float, w: Float, h: Float) {
            assertNotNull(msg, got)
            assertEquals(msg, x, got!!.x, 1e-5f)
            assertEquals(msg, y, got.y, 1e-5f)
            assertEquals(msg, w, got.w, 1e-5f)
            assertEquals(msg, h, got.h, 1e-5f)
        }
        near("wide, small face: zoomed onto it", at(1000, 500, "0.5,0.2,0.1,0.2"), 0.45f, 0.1f, 0.2f, 0.4f)
        near("wide, big face: the edge square", at(1000, 500, "0.85,0,0.15,0.6"), 0.5f, 0f, 0.5f, 1f)
        near("tall: around the face", at(500, 1000, "0.3,0.25,0.4,0.2"), 0.1f, 0.15f, 0.8f, 0.4f)
        near("square, big face: the whole", at(1000, 1000, "0.4,0.4,0.5,0.5"), 0f, 0f, 1f, 1f)
        near("a tiny face: at most 4x", at(1000, 1000, "0.5,0.5,0.01,0.01"), 0.38f, 0.38f, 0.25f, 0.25f)
        near("control: upright without a face keeps the top", at(500, 1000, null), 0f, 0.1f, 1f, 0.5f)
        near("control: a square without a face is whole", at(1000, 1000, null), 0f, 0f, 1f, 1f)
        assertNull("control: a wide picture without a face is not cropped", at(1000, 500, null))
        assertNull("control: an unknown size keeps the plain crop", at(null, null, "0.6,0.1,0.2,0.2"))
        assertNull("control: three numbers are no box", FaceBox.parse("0.1,0.2,0.3"))
    }

    @Test fun `the projection's face box reaches the art`() = runBlocking {
        val db = CatalogDatabase.open(CatalogFixture.build(tmp.root, withArt = true).path)!!
        try {
            assertEquals(FaceBox(0.3f, 0.1f, 0.4f, 0.3f), db.series("suspense")?.face?.art?.face)
            val d = db.episodeDetail("sus|1943-05-25")!!
            assertNull("NULL is no box", d.credits.first { it.personId == "p2" }.art?.face)
        } finally {
            db.close()
        }
    }

    @Test fun `the projection's grade and voices are read when published`() = runBlocking {
        val db = CatalogDatabase.open(CatalogFixture.build(tmp.root, withArt = true, withGrade = true).path)!!
        try {
            assertEquals(Grade(1.6, 0.148), gradeOf(db.series("suspense")?.face?.art))
            val d = db.episodeDetail("sus|1943-05-25")!!
            assertNull("NULL is the identity", d.credits.first { it.personId == "p2" }.art?.grade)
            val voices = db.voices()
            assertEquals(listOf("p2", "p1"), voices.map { it.person.id })
            assertEquals(listOf(9, 4), voices.map { it.episodes })
            assertEquals(listOf(1.6, 0.148), voices[1].person.art?.grade)
        } finally {
            db.close()
        }
        val older = CatalogDatabase.open(CatalogFixture.build(tmp.newFolder(), withArt = true).path)!!
        try {
            assertTrue("a catalog without the table has no voices", older.voices().isEmpty())
            assertEquals("a catalog without the column takes the identity", Grade(1.0, 0.0), gradeOf(older.series("suspense")?.face?.art))
        } finally {
            older.close()
        }
        assertEquals(listOf(1.6, 0.1), parseGrade("1.6, 0.1"))
        assertNull(parseGrade("1.6"))
        assertNull(parseGrade("a,b"))
        assertNull(parseGrade(null))
    }

    @Test fun `initials skip a leading article`() {
        assertEquals("W", artInitial("The Whistler"))
        assertEquals("A", artInitial("\"America First\""))
        assertEquals("", artInitial("..."))
    }
}
