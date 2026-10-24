package com.example.appname.data

import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import androidx.sqlite.execSQL
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** Contract §3.3 `series.sort_name`: A to Z follows the pipeline's key, and an older catalog falls back to `name`. */
class SeriesSortNameTest {
    @get:Rule val tmp = TemporaryFolder()

    private fun open(withSortName: Boolean): CatalogDatabase {
        val file = CatalogFixture.build(tmp.root)
        val c = BundledSQLiteDriver().open(file.path)
        try {
            if (withSortName) c.execSQL("ALTER TABLE series ADD COLUMN sort_name TEXT")
            c.execSQL("INSERT INTO series VALUES ('hour', 'The Fixture Hour', 'drama', NULL, NULL, NULL, NULL, 5" + (if (withSortName) ", 'fixture hour')" else ")"))
            c.execSQL("INSERT INTO series VALUES ('quoted', '\"Fixture Quoted\"', 'drama', NULL, NULL, NULL, NULL, 5" + (if (withSortName) ", 'fixture quoted\"')" else ")"))
            if (withSortName) {
                c.execSQL("UPDATE series SET sort_name = 'suspense' WHERE key = 'suspense'")
                c.execSQL("UPDATE series SET sort_name = 'command performance' WHERE key = 'commandperformance'")
            }
        } finally {
            c.close()
        }
        return CatalogDatabase.open(file.path) ?: error("fixture did not open")
    }

    @Test fun `A to Z follows sort_name, so quotes and articles do not lead`() = runBlocking {
        val keys = open(withSortName = true).seriesBrowse(BrowseFilter(sort = SeriesSort.Name)).map { it.key }
        assertEquals(listOf("commandperformance", "hour", "quoted", "suspense"), keys)
    }

    @Test fun `a catalog without sort_name still sorts, by name`() = runBlocking {
        val keys = open(withSortName = false).seriesBrowse(BrowseFilter(sort = SeriesSort.Name)).map { it.key }
        assertEquals(listOf("quoted", "commandperformance", "suspense", "hour"), keys)
    }
}
