package com.example.appname.playback

import com.example.appname.data.CatalogDatabase
import com.example.appname.data.CatalogFixture
import com.example.appname.data.EpisodeRow
import com.example.appname.data.UserStore
import kotlinx.coroutines.awaitCancellation
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
 * Android Auto's browse tree over the fixture catalog and a real listening
 * history. [problems] states the tree's rules (R17's four tabs, every playable
 * item titled and art-less); the control proves it sees a tree that breaks one.
 */
class CarLibraryTest {
    @get:Rule val tmp = TemporaryFolder()
    private lateinit var db: CatalogDatabase
    private lateinit var user: UserStore

    @Before fun open() {
        db = CatalogDatabase.open(CatalogFixture.build(tmp.root).path) ?: error("fixture did not open")
        user = UserStore.open(tmp.newFile("user.sqlite").path)
    }

    @After fun close() = db.close()

    private fun library(rows: suspend (List<String>) -> List<EpisodeRow> = { db.episodes(it) }, budgetMs: Long = 8_000) =
        CarLibrary({ user.inProgress().map { it.episodeId } }, rows, budgetMs)

    /** Each way the tree breaks its rules, empty when it keeps them. */
    private suspend fun problems(lib: CarLibrary): List<String> {
        val out = mutableListOf<String>()
        val top = lib.children(CarLibrary.ROOT) ?: return listOf("the root has no children")
        val titles = top.map { it.title }
        if (titles != listOf("Continue", "Stations", "Browse", "Downloads")) out += "top level is $titles"
        for (tab in top) {
            val tabMeta = tab.toMediaItem().mediaMetadata
            if (tabMeta.isBrowsable != true || tabMeta.isPlayable == true) out += "${tab.title} is not a folder"
            val children = lib.children(tab.id)
            if (children == null) {
                out += "${tab.title} lists nothing"
                continue
            }
            for (node in children) {
                val meta = node.toMediaItem().mediaMetadata
                if (meta.isPlayable != true || meta.isBrowsable == true) out += "${node.id} is not playable"
                if (meta.title.isNullOrBlank()) out += "${node.id} has no title"
                if (meta.artworkUri != null || meta.artworkData != null) out += "${node.id} carries art"
            }
        }
        return out
    }

    @Test fun `the tree keeps its rules with an episode in progress`() = runBlocking {
        user.save("sus|1943-01-07", 600_000, 1_800_000)
        assertEquals(emptyList<String>(), problems(library()))
    }

    @Test fun `control - an untitled episode is caught`() = runBlocking {
        user.save("sus|1943-01-07", 600_000, 1_800_000)
        val untitled = EpisodeRow("x|1", "x", "", null, null, null, null, null)
        val found = problems(library(rows = { listOf(untitled) }))
        assertTrue(found.toString(), found.any { it.contains("has no title") })
    }

    @Test fun `Continue lists only what is in progress and in the catalog`() = runBlocking {
        user.save("sus|1943-01-07", 600_000, 1_800_000)
        user.save("cp|1944-01-07", 300_000, 1_800_000)
        user.save("sus|1943-05-25", 1_790_000, 1_800_000) // within 30 s of the end: finished
        user.save("gone|1950-01-01", 300_000, 1_800_000) // not in this catalog
        val ids = library().children(CarLibrary.CONTINUE)!!.map { it.id }.toSet()
        assertEquals(setOf("sus|1943-01-07", "cp|1944-01-07"), ids)
    }

    @Test fun `a playable item carries title and subtitle and no art`() = runBlocking {
        user.save("sus|1943-01-07", 600_000, 1_800_000)
        val node = library().children(CarLibrary.CONTINUE)!!.single()
        val meta = node.toMediaItem().mediaMetadata
        assertEquals("The Hitchhiker", meta.title.toString())
        assertTrue(meta.subtitle.toString(), meta.subtitle.toString().startsWith("Suspense"))
        assertNull(meta.artworkUri)
        assertNull(meta.artworkData)
    }

    @Test fun `Radio, Series and Downloads are empty in the stub`() = runBlocking {
        val lib = library()
        listOf(CarLibrary.RADIO, CarLibrary.SERIES, CarLibrary.DOWNLOADS).forEach {
            assertEquals(it, emptyList<CarNode>(), lib.children(it))
        }
    }

    @Test fun `an unknown folder is an error, not an empty list`() = runBlocking {
        assertNull(library().children("tab:nowhere"))
    }

    @Test fun `children page`() = runBlocking {
        val lib = library()
        assertEquals(listOf("Browse", "Downloads"), lib.children(CarLibrary.ROOT, page = 1, pageSize = 2)!!.map { it.title })
        assertEquals(emptyList<CarNode>(), lib.children(CarLibrary.ROOT, page = 2, pageSize = 2))
    }

    @Test fun `a catalog that never answers yields an empty Continue within the budget`() = runBlocking {
        user.save("sus|1943-01-07", 600_000, 1_800_000)
        val started = System.nanoTime()
        val children = library(rows = { awaitCancellation() }, budgetMs = 200).children(CarLibrary.CONTINUE)
        assertEquals(emptyList<CarNode>(), children)
        assertTrue((System.nanoTime() - started) / 1_000_000 < 5_000)
    }

    @Test fun `item finds tabs and episodes by id`() = runBlocking {
        val lib = library()
        assertEquals("Continue", lib.item(CarLibrary.CONTINUE)?.title)
        assertEquals("The Hitchhiker", lib.item("sus|1943-01-07")?.title)
        assertNull(lib.item("gone|1950-01-01"))
    }
}
