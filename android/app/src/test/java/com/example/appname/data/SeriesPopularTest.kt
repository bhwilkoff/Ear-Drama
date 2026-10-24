package com.example.appname.data

import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import androidx.sqlite.execSQL
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * Contract §3.3 `series.downloads`: Popular lists counted series first, most
 * downloaded first, then the uncounted by name; an older catalog is A to Z.
 */
class SeriesPopularTest {
    @get:Rule val tmp = TemporaryFolder()

    private fun open(withDownloads: Boolean): CatalogDatabase {
        val file = CatalogFixture.build(tmp.newFolder())
        val c = BundledSQLiteDriver().open(file.path)
        try {
            c.execSQL("INSERT INTO series VALUES ('lux', 'Lux Radio Theatre', 'drama', NULL, '1934-10-14', '1955-06-07', NULL, 900)")
            if (withDownloads) {
                c.execSQL("ALTER TABLE series ADD COLUMN downloads INTEGER")
                c.execSQL("UPDATE series SET downloads = 500 WHERE key = 'suspense'")
                c.execSQL("UPDATE series SET downloads = 10 WHERE key = 'lux'")
            }
        } finally {
            c.close()
        }
        return CatalogDatabase.open(file.path) ?: error("fixture did not open")
    }

    @Test fun `Popular is counted series by count, then the rest A to Z`() = runBlocking {
        assertEquals(
            listOf("suspense", "lux", "commandperformance"),
            open(withDownloads = true).seriesBrowse(BrowseFilter(sort = SeriesSort.Popular)).map { it.key },
        )
    }

    @Test fun `a catalog without downloads sorts Popular A to Z`() = runBlocking {
        val db = open(withDownloads = false)
        assertEquals(listOf("commandperformance", "lux", "suspense"), db.seriesBrowse(BrowseFilter()).map { it.key })
        assertEquals(
            db.seriesBrowse(BrowseFilter(sort = SeriesSort.Name)).map { it.key },
            db.seriesBrowse(BrowseFilter(sort = SeriesSort.Popular)).map { it.key },
        )
    }
}
