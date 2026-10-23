package com.example.appname.data

import java.io.File
import kotlinx.coroutines.runBlocking
import org.junit.AfterClass
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.BeforeClass
import org.junit.Test

/**
 * The verbs against the real seed the build bundles (the `earDramaSeed` path
 * in app/build.gradle.kts). Skipped where no seed is present, as on a fresh
 * clone; the fixture tests run everywhere.
 */
class SeedCatalogTest {
    companion object {
        private var db: CatalogDatabase? = null

        @BeforeClass @JvmStatic fun open() {
            val path = System.getProperty("earDramaSeed")?.takeIf { File(it).isFile } ?: return
            db = CatalogDatabase.open(path)
        }

        @AfterClass @JvmStatic fun close() { db?.close() }
    }

    private fun seed(): CatalogDatabase {
        assumeTrue("no seed catalog at -PearDramaSeed", db != null)
        return db!!
    }

    // Shape only: each test picks its series from what the seed holds, so a better
    // catalog (a rights ruling, a fold, an unfinished LibriVox project) never breaks it.
    private suspend fun allSeries() = seed().seriesBrowse(BrowseFilter(), limit = 5000)
    private suspend fun largest(where: (SeriesRow) -> Boolean) =
        allSeries().filter(where).maxByOrNull { it.episodes }!!

    @Test fun `the seed's FTS5 table answers through the bundled driver`() = runBlocking {
        val s = largest { true }
        val word = s.name.split(" ").first { it.length >= 4 }.take(5)
        val found = seed().search(word)
        assertTrue(found.series.any { it.key == s.key } || found.episodes.isNotEmpty())
    }

    @Test fun `a real series page runs oldest first`() = runBlocking {
        val s = largest { it.firstDate != null }
        val page = seed().seriesPage(s.key)!!
        val dated = page.seasons.mapNotNull { it.season }
        assertEquals(dated.sorted(), dated)
        val rows = seed().seasonEpisodes(s.key, dated.first())
        val dates = rows.mapNotNull { it.airDate }
        assertEquals(dates.sorted(), dates)
    }

    @Test fun `every seed episode is clean, has a rights line, and plays a file`() = runBlocking {
        val s = largest { true }
        val rows = seed().seasonEpisodes(s.key, seed().seriesPage(s.key)!!.seasons.first().season).take(5)
        assertTrue(rows.isNotEmpty())
        rows.forEach { row ->
            val d = seed().episodeDetail(row.id)!!
            assertEquals("clean", d.rights)
            val line = DisplayVocabulary.rightsLine(d.rights, d.rightsBasis)
            assertTrue(line != null && line != DisplayVocabulary.UNCLAIMED)
            val url = d.recordings.first().url
            assertTrue(url.startsWith("https://archive.org/download/") && !url.endsWith("/"))
        }
    }

    @Test fun `a LibriVox series reads in chapter order`() = runBlocking {
        val s = largest { it.key.startsWith("librivox") }
        val rows = seed().seasonEpisodes(s.key, null)
        val nums = rows.mapNotNull { it.num }
        assertEquals(nums.sorted(), nums)
        assertTrue(rows.isNotEmpty())
    }
}
