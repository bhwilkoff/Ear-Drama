package com.example.appname.data

import java.io.File
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * Listen draws `meta.listenShelves` (docs/CATALOG-CONTRACT.md §5.1): the published
 * order, each genre's ids as published, This day in radio held to the golden cases
 * every client shares, and the older-catalog fallback.
 */
class ListenShelvesTest {
    @get:Rule val tmp = TemporaryFolder()

    private val published = """
        [{"rule": "genreFirsts", "genre": "comedy", "episodes": ["cp|1945-02-04", "cp|1943-02-24"]},
         {"rule": "onThisDay"},
         {"rule": "genreFirsts", "genre": "mystery", "episodes": ["sus|1943-05-25", "gone|1900-01-01", "sus|1942-06-17"]},
         {"rule": "mostEpisodes"},
         {"rule": "genreFirsts", "genre": "western", "episodes": []}]
    """.trimIndent()

    private fun open(file: File) = CatalogDatabase.open(file.path) ?: error("fixture did not open")

    private fun golden(): JsonObject {
        var dir: File? = File("").absoluteFile
        while (dir != null) {
            val f = File(dir, "catalog/tests/golden/on_this_day.json")
            if (f.exists()) return Json.parseToJsonElement(f.readText()).jsonObject
            dir = dir.parentFile
        }
        error("catalog/tests/golden/on_this_day.json not found")
    }

    @Test fun `this day in radio returns the golden cases`() = runBlocking {
        val g = golden()
        val rows = g["episodes"]!!.jsonArray.map { r ->
            val a = r.jsonArray
            listOf(0, 1, 2, 4).map { i -> (a[i] as? JsonPrimitive)?.contentOrNull }
        }
        val db = open(CatalogFixture.buildRows(tmp.root, rows))
        val cases = g["cases"]!!.jsonArray
        assertTrue(cases.size >= 7)
        cases.forEach { c ->
            val o = c.jsonObject
            val md = "%02d-%02d".format(o["month"]!!.jsonPrimitive.int, o["day"]!!.jsonPrimitive.int)
            val limit = o["limit"]?.jsonPrimitive?.int ?: CatalogDatabase.SHELF_LIMIT
            val want = o["want"]!!.jsonArray.map { it.jsonPrimitive.content }
            assertEquals(md, want, db.shelf(ShelfRule.ThisDay(md), limit).map { it.id })
        }
        db.close()
    }

    @Test fun `the published order and ids are drawn as given`() = runBlocking {
        val db = open(CatalogFixture.build(tmp.root, listenShelves = published))
        val shelves = db.listenShelves("05-25")
        // An unknown rule is ignored and an empty shelf dropped.
        assertEquals(listOf("genre:comedy", "thisday", "genre:mystery"), shelves.map { it.key })
        assertEquals(listOf("comedy", null, "mystery"), shelves.map { it.genre })
        // Ids in published order, not broadcast order; an unserved id dropped.
        assertEquals(listOf("cp|1945-02-04", "cp|1943-02-24"), shelves[0].rows.map { it.id })
        assertEquals(listOf("sus|1943-05-25"), shelves[1].rows.map { it.id })
        assertEquals(listOf("sus|1943-05-25", "sus|1942-06-17"), shelves[2].rows.map { it.id })
        db.close()
    }

    @Test fun `an older catalog falls back to the rules run here`() = runBlocking {
        val db = open(CatalogFixture.build(tmp.root))
        assertNull(db.publishedShelves)
        val shelves = db.listenShelves("05-25")
        assertEquals(listOf("thisday", "genre:comedy", "genre:mystery"), shelves.map { it.key })
        // Control: the fallback's own mystery rule starts elsewhere than the published list did.
        assertEquals("sus|1942-06-17", shelves[2].rows.first().id)
        db.close()
        // A value that is not a list is an older catalog too.
        val odd = open(CatalogFixture.build(tmp.newFolder(), listenShelves = "{}"))
        assertNull(odd.publishedShelves)
        odd.close()
    }

    @Test fun `parse keeps only known rules`() {
        assertEquals(
            listOf(
                PublishedShelf.GenreFirsts("comedy", listOf("cp|1945-02-04", "cp|1943-02-24")),
                PublishedShelf.OnThisDay,
                PublishedShelf.GenreFirsts("mystery", listOf("sus|1943-05-25", "gone|1900-01-01", "sus|1942-06-17")),
                PublishedShelf.GenreFirsts("western", emptyList()),
            ),
            PublishedShelf.parse(published),
        )
        assertNull(PublishedShelf.parse("not json"))
        assertEquals(emptyList<PublishedShelf>(), PublishedShelf.parse("[]"))
    }
}
