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

    @Test fun `forwarding reads every alias and tombstone`() = runBlocking {
        val f = db.forwarding()
        assertEquals("sus|1943-05-25", f.resolve("suspense|sorry-wrong-number"))
        assertTrue(f.isGone("sus|taken-down"))
        assertEquals("an unknown id is kept", "sus|1999-01-01", f.resolve("sus|1999-01-01"))
        assertFalse(f.isGone("suspense|sorry-wrong-number"))
        assertEquals("series keys forward too", "suspense", f.resolveSeries("suspence"))
        assertTrue(f.isSeriesGone("folkweave"))
        assertEquals("an unknown key is kept", "nope", f.resolveSeries("nope"))
    }

    @Test fun `a moved series key opens the series it now is`() = runBlocking {
        val page = db.seriesPage("suspence")
        assertEquals("suspense", page?.series?.key)
        assertTrue("with its seasons", page?.seasons?.isNotEmpty() == true)
        assertEquals("suspense", db.series("suspence")?.key)
        assertNull("control: a tombstoned key is not served", db.seriesPage("folkweave"))
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

    @Test fun `Surprise's random episode applies recommendAnd`() = runBlocking {
        // The control: the never-recommended broadcast is served and has recordings.
        assertNotNull(db.episodeDetail("sus|1943-02-04")?.recordings?.firstOrNull())
        val draws = (1..400).mapNotNull { db.randomEpisode()?.id }
        assertEquals(400, draws.size)
        assertFalse(draws.contains("sus|1943-02-04"))
        assertTrue(draws.toSet().size > 1)
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

    @Test fun `a catalog without meta rightsLines shows the contract's words`() = runBlocking {
        assertEquals(DisplayVocabulary.CONTRACT_RIGHTS_LINES, db.rightsLines)
        assertEquals("No rights claim known. Removed on request.", db.episodeDetail("sus|1943-03-11")!!.rightsLine)
        assertEquals("Government recording", db.episodeDetail("sus|1943-05-25")!!.rightsLine)
    }

    @Test fun `the rights words come from the published meta rightsLines`() = runBlocking {
        val json = """{"unclaimed": "Published words for unclaimed.", "rec_gov_work": "Published gov words"}"""
        val published = CatalogDatabase.open(CatalogFixture.build(tmp.newFolder(), rightsLines = json).path)!!
        try {
            assertEquals("Published words for unclaimed.", published.episodeDetail("sus|1943-03-11")!!.rightsLine)
            assertEquals("Published gov words", published.episodeDetail("sus|1943-05-25")!!.rightsLine)
        } finally {
            published.close()
        }
        // A basis the published table has no words for shows no line, never the unclaimed one.
        assertNull(DisplayVocabulary.rightsLine("clean", "rec_librivox", mapOf("unclaimed" to "x")))
    }

    @Test fun `seriesDecades are the decades the series span, against the genre picked`() = runBlocking {
        // Suspense 1942-43, Command Performance 1942-44: only the 1940s, whatever the genre.
        assertEquals(listOf(1940), db.seriesDecades())
        assertEquals(listOf(1940), db.seriesDecades(genre = "mystery"))
        assertTrue(db.seriesDecades(genre = "western").isEmpty())
        assertEquals(listOf("comedy", "mystery"), db.genres(decade = 1940))
        assertTrue(db.genres(decade = 1950).isEmpty())
        assertEquals(listOf(1930, 1940, 1950), CatalogDatabase.decadesSpanning(1938, 1951))
        assertEquals(listOf(1940), CatalogDatabase.decadesSpanning(1942, null))
        assertTrue(CatalogDatabase.decadesSpanning(null, 1950).isEmpty())
    }

    @Test fun `episodeDetail carries the transcript only past the gate`() = runBlocking {
        assertEquals(CatalogFixture.TRANSCRIPT_URL, db.episodeDetail("sus|1943-01-07")!!.transcriptUrl)
        // The control: a URL on a row that failed the gate is never shown.
        assertNull(db.episodeDetail("sus|1943-05-25")!!.transcriptUrl)
        assertNull(db.episodeDetail("sus|1942-06-17")!!.transcriptUrl)
        val older = CatalogDatabase.open(CatalogFixture.build(tmp.newFolder("pre-transcript"), withTranscript = false).path)!!
        try {
            assertNull(older.episodeDetail("sus|1943-01-07")!!.transcriptUrl)
            // A catalog published before the gate columns never searches what is said.
            assertTrue(older.search("lighthouse").isEmpty)
        } finally {
            older.close()
        }
    }

    @Test fun `search finds what is said in a shown transcript, in its own section`() = runBlocking {
        val keeper = db.search("lighthouse")
        assertTrue(keeper.episodes.isEmpty())
        assertEquals(listOf("sus|1943-01-07"), keeper.transcript.map { it.id })
        assertEquals(CatalogFixture.TRANSCRIPT_URL, keeper.transcript.single().transcriptUrl)
        // The control: a transcript that failed the gate is never searched, even where an older catalog indexed it.
        assertTrue(db.search("zeppelin").isEmpty)
        // "hitchhiker" is in the title AND the transcript: Episodes only, never twice.
        val title = db.search("hitchhiker")
        assertEquals(listOf("sus|1943-01-07"), title.episodes.map { it.id })
        assertTrue(title.transcript.isEmpty())
        assertTrue(db.search("moore").transcript.isEmpty())
        // Every word must be said; one in the title and one only spoken is a transcript match.
        assertEquals(listOf("sus|1943-01-07"), db.search("hitchhiker tuned").transcript.map { it.id })
        assertTrue(db.search("tuned police").transcript.isEmpty())
        // A word under three letters is never searched in a transcript.
        assertTrue(db.search("by").transcript.isEmpty())
    }

    @Test fun `search finds what aired on a date the query names`() = runBlocking {
        assertEquals(listOf("sus|1943-01-07", "sus|1943-02-04", "sus|1943-03-11", "sus|1943-05-25", "cp|1943-02-24")
            .sortedBy { it.substringAfter('|') }, db.search("1943").aired!!.episodes.map { it.id })
        assertEquals(listOf("sus|1943-02-04", "cp|1943-02-24"), db.search("February 1943").aired!!.episodes.map { it.id })
        assertEquals(listOf("sus|1942-06-17"), db.search("1942-06-17").aired!!.episodes.map { it.id })
        assertEquals(listOf("cp|1944-01-07"), db.search("jan 7, 1944").aired!!.episodes.map { it.id })
        assertEquals("Aired February 1943", db.search("February 1943").aired!!.title)
        assertEquals(listOf("sus|1943-02-04"), db.search("suspense feb 1943").aired!!.episodes.map { it.id })
        // The controls: a day nothing aired, and a query naming no date.
        assertTrue(db.search("1943-05-26").aired!!.episodes.isEmpty())
        assertTrue(db.search("1943-05-26").isEmpty)
        assertNull(db.search("sorry wrong").aired)
        assertFalse(db.search("1943").isEmpty)
    }

    @Test fun `series search never matches a word spoken in a transcript`() = runBlocking {
        // "Command Performance" is spoken in a Suspense episode's transcript, and
        // that episode IS found by it, so the words are in the index...
        val found = db.search("command perf")
        assertTrue(found.transcript.any { it.id == "sus|1943-01-07" })
        // ...yet the series list holds only the series that bears the name.
        assertEquals(listOf("commandperformance"), found.series.map { it.key })
        // A word only spoken lists no series at all.
        assertTrue(db.search("lighthouse").series.isEmpty())
    }

    @Test fun `transcript lines drop blanks and stray spaces`() {
        assertEquals(listOf("One.", "Two.", "Three."), Transcript.lines("One.\n\n  Two.  \r\nThree.\n"))
        assertEquals("Automatic transcript", Transcript.LABEL)
    }

    @Test fun `matchExpression quotes every word as a prefix`() {
        assertEquals("\"Sorry\"* \"wrong\"*", CatalogDatabase.matchExpression("Sorry, wrong"))
        assertEquals("series : \"a\"*", CatalogDatabase.matchExpression("a", column = "series"))
        assertEquals(
            "{title series people} : \"a\"*",
            CatalogDatabase.matchExpression("a", column = CatalogDatabase.NON_TRANSCRIPT_COLUMNS),
        )
        assertNull(CatalogDatabase.matchExpression("  ,. "))
    }
}
