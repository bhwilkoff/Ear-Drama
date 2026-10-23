package com.example.appname.data

import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** The §5 verbs against a fixture in the served schema, through the same bundled SQLite the app ships. */
class CatalogQueriesTest {
    @get:Rule val tmp = TemporaryFolder()
    private lateinit var db: CatalogDatabase

    @Before fun open() {
        db = CatalogDatabase.open(CatalogFixture.build(tmp.root).path) ?: error("fixture did not open")
    }

    @After fun close() = db.close()

    @Test fun `a file without the schema floor does not open`() {
        val bogus = tmp.newFile("bogus.sqlite")
        bogus.writeText("not a database")
        assertNull(CatalogDatabase.open(bogus.path))
        assertFalse(CatalogDatabase.validate(bogus.path))
    }

    @Test fun `the fixture passes the swap validation`() {
        assertTrue(CatalogDatabase.validate(CatalogFixture.build(tmp.newFolder()).path))
    }

    @Test fun `seriesPage lists seasons oldest first with the undated last`() = runBlocking {
        val page = db.seriesPage("suspense")!!
        assertEquals(listOf("1941-42", "1942-43", null), page.seasons.map { it.season })
        assertEquals(listOf(1, 4, 2), page.seasons.map { it.episodes })
    }

    @Test fun `a season's episodes run oldest first (R1)`() = runBlocking {
        val rows = db.seasonEpisodes("suspense", "1942-43")
        assertEquals(
            listOf("sus|1943-01-07", "sus|1943-02-04", "sus|1943-03-11", "sus|1943-05-25"),
            rows.map { it.id },
        )
        assertEquals(listOf("sus|u1", "sus|u2"), db.seasonEpisodes("suspense", null).map { it.id })
    }

    @Test fun `episodeDetail joins credits and lists recordings in rank order`() = runBlocking {
        val d = db.episodeDetail("sus|1943-05-25")!!
        assertEquals(listOf("Agnes Moorehead", "Orson Welles"), d.credits.map { it.name })
        assertEquals("Mrs. Stevenson", d.credits.first().character)
        assertEquals(listOf(0, 1), d.recordings.map { it.rank })
        assertEquals("https://archive.org/download/main/a%20b.mp3", d.recordings.first().url)
        assertTrue(d.recordings[1].partial)
        assertEquals("AFRS", d.recordings[1].variant)
    }

    @Test fun `episodeDetail carries loudness and tolerates its absence`() = runBlocking {
        val measured = db.episodeDetail("sus|1943-05-25")!!
        assertEquals(-15.0, measured.loudnessI!!, 0.0)
        assertEquals(-6.0, measured.loudnessTp!!, 0.0)
        assertNull(db.episodeDetail("sus|1943-01-07")!!.loudnessI)
        assertNull(db.episodeDetail("sus|1943-01-07")!!.loudnessTp)
        val dir = tmp.newFolder("older")
        val older = CatalogDatabase.open(CatalogFixture.build(dir, withLoudness = false).path)!!
        try {
            val d = older.episodeDetail("sus|1943-05-25")!!
            assertNull(d.loudnessI)
            assertEquals(2, d.credits.size)
        } finally {
            older.close()
        }
    }

    @Test fun `episodeDetail forwards an alias`() = runBlocking {
        assertEquals("sus|1943-05-25", db.episodeDetail("suspense|sorry-wrong-number")?.episode?.id)
    }

    @Test fun `search matches word prefixes`() = runBlocking {
        val found = db.search("wrong numb")
        assertEquals(listOf("sus|1943-05-25"), found.episodes.map { it.id })
        // A credited name is searchable.
        assertEquals(listOf("sus|1943-05-25"), db.search("moore").episodes.map { it.id })
    }

    @Test fun `search never matches inside a word`() = runBlocking {
        assertTrue(db.search("orry").isEmpty)
        assertTrue(db.search("rowful").isEmpty)
    }

    @Test fun `search finds series by their name`() = runBlocking {
        assertEquals(listOf("commandperformance"), db.search("command perf").series.map { it.key })
    }

    @Test fun `search treats FTS syntax as words`() = runBlocking {
        db.search("\"NEAR(\" OR *")
        db.search("sorry AND")
        Unit
    }

    @Test fun `shelves apply recommendAnd and search does not`() = runBlocking {
        val shelf = db.shelf(ShelfRule.ThisDay("02-04"))
        assertEquals(listOf("cp|1945-02-04"), shelf.map { it.id })
        // The control: the never-recommended broadcast is in the catalog and findable.
        assertEquals(listOf("sus|1943-02-04"), db.search("banquo").episodes.map { it.id })
        assertNotNull(db.episodeDetail("sus|1943-02-04")?.noRecommend)
        val genre = db.shelf(ShelfRule.Genre("mystery"))
        assertFalse(genre.any { it.id == "sus|1943-02-04" })
        assertEquals("sus|1942-06-17", genre.first().id)
    }

    @Test fun `the queue stays inside the season and skips the never-recommended`() = runBlocking {
        val next = db.followingInSeason("sus|1943-01-07")
        assertEquals(listOf("sus|1943-03-11", "sus|1943-05-25"), next.map { it.id })
        assertTrue(db.followingInSeason("sus|1943-05-25").isEmpty())
        assertEquals(listOf("sus|u2"), db.followingInSeason("sus|u1").map { it.id })
    }

    @Test fun `seriesBrowse filters by genre and decade`() = runBlocking {
        assertEquals(listOf("commandperformance", "suspense"), db.seriesBrowse(BrowseFilter()).map { it.key })
        assertEquals(listOf("suspense"), db.seriesBrowse(BrowseFilter(genre = "mystery")).map { it.key })
        assertEquals(2, db.seriesBrowse(BrowseFilter(decade = 1940)).size)
        assertTrue(db.seriesBrowse(BrowseFilter(decade = 1950)).isEmpty())
        assertEquals(listOf("commandperformance"), db.seriesBrowse(BrowseFilter(network = "AFRS")).map { it.key })
    }

    @Test fun `the unclaimed broadcast's rights line is the contract's`() = runBlocking {
        val d = db.episodeDetail("sus|1943-03-11")!!
        assertEquals("No rights claim known. Removed on request.", DisplayVocabulary.rightsLine(d.rights, d.rightsBasis))
    }

    @Test fun `matchExpression quotes every word as a prefix`() {
        assertEquals("\"Sorry\"* \"wrong\"*", CatalogDatabase.matchExpression("Sorry, wrong"))
        assertEquals("series : \"a\"*", CatalogDatabase.matchExpression("a", column = "series"))
        assertNull(CatalogDatabase.matchExpression("  ,. "))
    }
}
