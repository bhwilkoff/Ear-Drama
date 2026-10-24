package com.example.appname.data

import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import androidx.sqlite.execSQL
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * ANDROID-DESIGN §4.2: Series browse's network, decade, and genre facets and
 * its three orders. The fixture gains series that share a network, carry two,
 * carry none, and carry a value that is not JSON.
 */
class SeriesFacetsTest {
    @get:Rule val tmp = TemporaryFolder()
    private lateinit var db: CatalogDatabase

    @Before fun open() {
        val file = CatalogFixture.build(tmp.root)
        val c = BundledSQLiteDriver().open(file.path)
        try {
            c.execSQL("INSERT INTO series VALUES ('lux', 'Lux Radio Theatre', 'drama', NULL, '1934-10-14', '1955-06-07', '[\"CBS\",\"NBC\"]', 900)")
            c.execSQL("INSERT INTO series VALUES ('gunsmoke', 'Gunsmoke', 'western', NULL, '1952-04-26', '1961-06-18', '[\"CBS\"]', 400)")
            c.execSQL("INSERT INTO series VALUES ('oddity', 'Oddity', NULL, NULL, NULL, NULL, 'not json', 3)")
            c.execSQL("INSERT INTO series VALUES ('none', 'No Network', 'mystery', NULL, '1950-01-01', '1950-12-31', NULL, 1)")
        } finally {
            c.close()
        }
        db = CatalogDatabase.open(file.path) ?: error("fixture did not open")
    }

    @After fun close() = db.close()

    @Test fun `networks are counted per series, most first, against the other facets`() = runBlocking {
        assertEquals(
            listOf(FacetCount("CBS", 3), FacetCount("AFRS", 1), FacetCount("NBC", 1)),
            db.networks(),
        )
        assertEquals(listOf(FacetCount("CBS", 1)), db.networks(genre = "western"))
        assertEquals(listOf(FacetCount("CBS", 1), FacetCount("NBC", 1)), db.networks(decade = 1930))
        assertEquals(listOf("CBS"), db.networks(limit = 1).map { it.value })
    }

    @Test fun `a network narrows the list and the other facets`() = runBlocking {
        assertEquals(listOf("gunsmoke", "lux", "suspense"), db.seriesBrowse(BrowseFilter(network = "CBS")).map { it.key })
        assertEquals(listOf("drama"), db.genres(network = "NBC"))
        assertEquals(listOf(1940), db.seriesDecades(network = "AFRS"))
        assertEquals(listOf(1930, 1940, 1950), db.seriesDecades(network = "NBC"))
        assertTrue(db.seriesBrowse(BrowseFilter(network = "not json")).isEmpty())
    }

    @Test fun `no choice offered yields zero rows, and each network's count is its list`() = runBlocking {
        for (network in db.networks().map { it.value } + listOf<String?>(null)) {
            for (decade in db.seriesDecades(network = network) + listOf<Int?>(null)) {
                for (genre in db.genres(decade, network) + listOf<String?>(null)) {
                    val rows = db.seriesBrowse(BrowseFilter(genre = genre, network = network, decade = decade))
                    if (genre != null || network != null || decade != null) {
                        assertTrue("$genre $network $decade lists nothing", rows.isNotEmpty())
                    }
                }
                for (n in db.networks(decade = decade)) {
                    assertEquals(n.series, db.seriesBrowse(BrowseFilter(network = n.value, decade = decade)).size)
                }
            }
        }
    }

    @Test fun `the orders are the web's, Popular first`() = runBlocking {
        assertEquals(
            listOf("commandperformance", "gunsmoke", "lux", "none", "oddity", "suspense"),
            db.seriesBrowse(BrowseFilter(sort = SeriesSort.Name)).map { it.key },
        )
        assertEquals(
            listOf("lux", "gunsmoke", "suspense", "oddity", "commandperformance", "none"),
            db.seriesBrowse(BrowseFilter(sort = SeriesSort.Episodes)).map { it.key },
        )
        // Undated last.
        assertEquals(
            listOf("lux", "commandperformance", "suspense", "none", "gunsmoke", "oddity"),
            db.seriesBrowse(BrowseFilter(sort = SeriesSort.FirstAired)).map { it.key },
        )
        assertEquals(listOf("Popular", "A to Z", "Most episodes", "Oldest first"), SeriesSort.entries.map { it.label })
    }

    @Test fun `the sponsor is read where the catalog carries it`() = runBlocking {
        assertNull("the served projection has no sponsor column", db.episodeDetail("sus|1943-05-25")!!.sponsor)
        val withSponsor = CatalogDatabase.open(CatalogFixture.build(tmp.newFolder(), withSponsor = true).path)!!
        try {
            assertEquals("Roma Wines", withSponsor.episodeDetail("sus|1943-05-25")!!.sponsor)
            assertNull("a blank sponsor is no sponsor", withSponsor.episodeDetail("sus|1943-01-07")!!.sponsor)
            assertNull(withSponsor.episodeDetail("sus|1943-03-11")!!.sponsor)
        } finally {
            withSponsor.close()
        }
    }
}
