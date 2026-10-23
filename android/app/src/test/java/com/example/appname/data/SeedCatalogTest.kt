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

    @Test fun `the seed's FTS5 table answers through the bundled driver`() = runBlocking {
        val found = seed().search("command perf")
        assertTrue(found.series.any { it.key == "commandperformance" })
        assertTrue(found.episodes.isNotEmpty())
    }

    @Test fun `a real series page runs oldest first`() = runBlocking {
        val page = seed().seriesPage("commandperformance")!!
        val dated = page.seasons.mapNotNull { it.season }
        assertEquals(dated.sorted(), dated)
        val rows = seed().seasonEpisodes("commandperformance", dated.first())
        val dates = rows.mapNotNull { it.airDate }
        assertEquals(dates.sorted(), dates)
    }

    @Test fun `every seed episode is clean and has a rights line`() = runBlocking {
        val rows = seed().seasonEpisodes("commandperformance", "1942-43").take(5)
        rows.forEach { row ->
            val d = seed().episodeDetail(row.id)!!
            assertEquals("clean", d.rights)
            assertEquals("Government recording", DisplayVocabulary.rightsLine(d.rights, d.rightsBasis))
            assertTrue(d.recordings.first().url.startsWith("https://archive.org/download/"))
        }
    }

    @Test fun `a LibriVox series reads in chapter order`() = runBlocking {
        val rows = seed().seasonEpisodes("librivox19977", null)
        val nums = rows.mapNotNull { it.num }
        assertEquals(nums.sorted(), nums)
        assertTrue(rows.size > 100)
    }
}
