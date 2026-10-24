package com.example.appname.data

import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import androidx.sqlite.execSQL
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

/** `withPerson` and `searchPeople` (contract §5) against the fixture, plus credits added here. */
class PersonTest {
    @get:Rule val tmp = TemporaryFolder()

    private fun open(withArt: Boolean = false): CatalogDatabase {
        val file: File = CatalogFixture.build(tmp.newFolder(), withArt = withArt)
        val c = BundledSQLiteDriver().open(file.path)
        try {
            // Agnes Moorehead also wrote the 1943 broadcast, hosted a later one, and is in an undated one.
            c.execSQL("INSERT INTO credits VALUES ('sus|1943-05-25', 'p1', 'writer', NULL)")
            c.execSQL("INSERT INTO credits VALUES ('cp|1944-01-07', 'p1', 'host', NULL)")
            c.execSQL("INSERT INTO credits VALUES ('sus|u1', 'p1', 'cast', NULL)")
            c.execSQL("UPDATE people SET birth = '1900-12-06', death = '1974-04-30' WHERE id = 'p1'")
            c.execSQL("INSERT INTO people (id, name) VALUES ('p3', 'José Ferrer')")
            c.execSQL("INSERT INTO people (id, name) VALUES ('p4', 'Nobody Credited')")
            c.execSQL("INSERT INTO credits VALUES ('cp|1945-02-04', 'p3', 'cast', NULL)")
        } finally {
            c.close()
        }
        return CatalogDatabase.open(file.path) ?: error("fixture did not open")
    }

    @Test fun `a person's page lists every served credit oldest first, one row per episode`() = runBlocking {
        val db = open()
        try {
            val page = db.personPage("p1")!!
            assertEquals("1900–1974", page.person.years)
            assertEquals(listOf("sus|1943-05-25", "cp|1944-01-07", "sus|u1"), page.episodes.map { it.episode.id })
            assertEquals("Cast as Mrs. Stevenson, Writer", page.episodes.first().rolesLine)
            assertEquals("Host", page.episodes[1].rolesLine)
            assertNull("control: no credits, no page", db.personPage("p4"))
            assertNull(db.personPage("nobody"))
        } finally {
            db.close()
        }
    }

    @Test fun `groups by series in either order, undated last`() = runBlocking {
        val db = open()
        try {
            val page = db.personPage("p1")!!
            val oldest = page.groups(newestFirst = false)
            assertEquals(listOf("suspense", "commandperformance"), oldest.map { it.seriesKey })
            assertEquals(listOf("sus|1943-05-25", "sus|u1"), oldest.first().episodes.map { it.episode.id })
            val newest = page.groups(newestFirst = true)
            assertEquals(listOf("commandperformance", "suspense"), newest.map { it.seriesKey })
            assertEquals(listOf("sus|1943-05-25", "sus|u1"), newest.last().episodes.map { it.episode.id })
            assertEquals("Command Performance", newest.first().seriesName)
        } finally {
            db.close()
        }
    }

    @Test fun `people search is word prefix, folded, most episodes first`() = runBlocking {
        val db = open()
        try {
            assertEquals(listOf("p1"), db.searchPeople("moore").map { it.person.id })
            assertEquals(3, db.searchPeople("agnes moore").single().episodes)
            assertEquals(listOf("p3"), db.searchPeople("jose fer").map { it.person.id })
            assertTrue("control: never a substring", db.searchPeople("oore").isEmpty())
            assertTrue("control: a person with no served credit is not listed", db.searchPeople("nobody").isEmpty())
            assertEquals(listOf("p1"), db.search("moorehead").people.map { it.person.id })
        } finally {
            db.close()
        }
    }

    @Test fun `the served portrait rides the page and the search row`() = runBlocking {
        val db = open(withArt = true)
        try {
            assertNotNull(db.personPage("p1")?.person?.face)
            assertNotNull(db.searchPeople("moore").single().person.art)
        } finally {
            db.close()
        }
    }

    @Test fun `years come from the people row only`() {
        assertEquals("Born 1915", Person.years("1915", null))
        assertEquals("Died 1985", Person.years(null, "1985"))
        assertNull(Person.years(null, null))
    }
}
