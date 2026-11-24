package com.example.appname.playback

import com.example.appname.data.CatalogDatabase
import com.example.appname.data.CatalogFixture
import com.example.appname.data.EpisodeRow
import com.example.appname.data.UserStore
import java.io.File
import java.io.IOException
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * Android Auto's browse tree over the fixture catalog and a real listening
 * history. [problems] states the tree's rules (four tabs, every row a folder, a
 * playable item, or a plain message; titled; no folder past the page cap); the
 * control proves it sees a tree that breaks one.
 */
class CarLibraryTest {
    @get:Rule val tmp = TemporaryFolder()
    private lateinit var db: CatalogDatabase
    private lateinit var user: UserStore

    private val shelves = """[{"rule":"byLength","band":"about30","episodes":["sus|1943-01-07","sus|1943-02-04","cp|1944-01-07"]}]"""

    @Before fun open() {
        db = CatalogDatabase.open(CatalogFixture.build(tmp.root, listenShelves = shelves).path) ?: error("fixture did not open")
        user = UserStore.open(tmp.newFile("user.sqlite").path)
    }

    @After fun close() = db.close()

    private fun library(
        rows: suspend (List<String>) -> List<EpisodeRow> = { db.episodes(it) },
        budgetMs: Long = 8_000,
        downloaded: List<String> = emptyList(),
        catalog: CatalogDatabase? = db,
        followed: List<String> = emptyList(),
        stations: suspend () -> List<CarStation> = { emptyList() },
    ) = CarLibrary({ user.inProgress().map { it.episodeId } }, rows, { downloaded }, budgetMs, { catalog }, { followed }, stations)

    private val tabs = listOf("Continue", "Stations", "Browse", "Downloads")

    /** Each way the tree breaks its rules, walking every folder under the root to [depth], empty when it keeps them. */
    private suspend fun problems(lib: CarLibrary, parent: String = CarLibrary.ROOT, depth: Int = 5): List<String> {
        val out = mutableListOf<String>()
        val children = lib.children(parent) ?: return listOf("$parent lists nothing")
        if (parent == CarLibrary.ROOT && children.map { it.title } != tabs) out += "top level is ${children.map { it.title }}"
        if (children.size > CarLibrary.PAGE_MAX) out += "$parent holds ${children.size}"
        for (node in children) {
            val meta = node.toMediaItem().mediaMetadata
            if (meta.title.isNullOrBlank()) out += "${node.id} has no title"
            if (node.browsable && node.playable) out += "${node.id} is both a folder and playable"
            if (meta.isBrowsable != node.browsable || meta.isPlayable != node.playable) out += "${node.id} flags differ from the metadata"
            if (node.browsable && depth > 0) out += problems(lib, node.id, depth - 1)
        }
        return out
    }

    @Test fun `the whole tree keeps its rules with a history, downloads and a followed show`() = runBlocking {
        user.save("sus|1943-01-07", 600_000, 1_800_000)
        val lib = library(
            downloaded = listOf("sus|1943-05-25"),
            followed = listOf("suspense"),
            stations = { listOf(CarStation("station:mystery", "Mystery", "Suspense · The Hitchhiker", "sus|1943-01-07")) },
        )
        assertEquals(emptyList<String>(), problems(lib))
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

    @Test fun `a playable item carries title, subtitle and its art path`() = runBlocking {
        user.save("sus|1943-01-07", 600_000, 1_800_000)
        val node = library().children(CarLibrary.CONTINUE)!!.single()
        val meta = node.toMediaItem().mediaMetadata
        assertEquals("The Hitchhiker", meta.title.toString())
        assertTrue(meta.subtitle.toString(), meta.subtitle.toString().startsWith("Suspense"))
        assertEquals("e/sus%7C1943-01-07", node.art)
    }

    @Test fun `empty folders say so in a message row that is neither a folder nor playable`() = runBlocking {
        val lib = library()
        for (tab in listOf(CarLibrary.CONTINUE, CarLibrary.DOWNLOADS, CarLibrary.RADIO)) {
            val only = lib.children(tab)!!.single()
            assertTrue(tab, !only.browsable && !only.playable)
        }
        assertEquals("No downloads yet", lib.children(CarLibrary.DOWNLOADS)!!.single().title)
    }

    @Test fun `Downloads lists the finished downloads in order`() = runBlocking {
        val lib = library(downloaded = listOf("sus|1943-05-25", "gone|1950-01-01", "sus|1943-01-07"))
        assertEquals(listOf("sus|1943-05-25", "sus|1943-01-07"), lib.children(CarLibrary.DOWNLOADS)!!.map { it.id })
    }

    @Test fun `an unknown folder is an error, not an empty list`() = runBlocking {
        assertNull(library().children("tab:nowhere"))
        assertNull(library().children("series/nope"))
    }

    @Test fun `children page, and no page passes the cap`() = runBlocking {
        val lib = library()
        assertEquals(listOf("Browse", "Downloads"), lib.children(CarLibrary.ROOT, page = 1, pageSize = 2)!!.map { it.title })
        assertEquals(emptyList<CarNode>(), lib.children(CarLibrary.ROOT, page = 2, pageSize = 2))
        assertTrue(lib.children(CarLibrary.SERIES, pageSize = 10_000)!!.size <= CarLibrary.PAGE_MAX)
    }

    @Test fun `a catalog that never answers gives a car-legible message within the budget`() = runBlocking {
        user.save("sus|1943-01-07", 600_000, 1_800_000)
        val started = System.nanoTime()
        val children = library(rows = { awaitCancellation() }, budgetMs = 200).children(CarLibrary.CONTINUE)
        assertEquals(CarLibrary.SLOW, children!!.single().title)
        assertTrue((System.nanoTime() - started) / 1_000_000 < 5_000)
    }

    @Test fun `item finds tabs and episodes by id`() = runBlocking {
        val lib = library()
        assertEquals("Continue", lib.item(CarLibrary.CONTINUE)?.title)
        assertEquals("The Hitchhiker", lib.item("sus|1943-01-07")?.title)
        assertNull(lib.item("gone|1950-01-01"))
    }

    // --- Stations ---

    @Test fun `Stations lists what is on air, each playable with its art`() = runBlocking {
        val on = CarStation("station:mystery", "Mystery", "Suspense · The Hitchhiker", "sus|1943-01-07")
        val nodes = library(stations = { listOf(on) }).children(CarLibrary.RADIO)!!
        assertEquals(listOf("station:mystery"), nodes.map { it.id })
        assertTrue(nodes.single().playable && !nodes.single().browsable)
        assertEquals("Suspense · The Hitchhiker", nodes.single().subtitle)
        assertNotNull(nodes.single().art)
    }

    @Test fun `Stations offline says it needs a connection, and a slow lookup says it is slow`() = runBlocking {
        val offline = library(stations = { throw IOException("no route") }).children(CarLibrary.RADIO)!!.single()
        assertEquals(CarLibrary.OFFLINE_STATIONS, offline.title)
        val slow = library(budgetMs = 200, stations = { awaitCancellation() }).children(CarLibrary.RADIO)!!.single()
        assertEquals(CarLibrary.SLOW, slow.title)
    }

    // --- Browse ---

    @Test fun `Browse has the four driver-safe doors`() = runBlocking {
        assertEquals(
            listOf("Shows you follow", "Popular shows", "Genres", "By length"),
            library().children(CarLibrary.SERIES)!!.map { it.title },
        )
    }

    @Test fun `Popular lists shows, not single recordings, and a show opens on its episodes oldest first`() = runBlocking {
        val lib = library()
        val shows = lib.children(CarLibrary.POPULAR)!!
        assertEquals(listOf("Suspense"), shows.map { it.title })
        assertTrue(shows.single().browsable)
        val eps = lib.children(shows.single().id)!!
        assertEquals(7, eps.size)
        assertEquals("The Burning Court", eps.first().title)
        assertTrue(eps.all { it.playable })
    }

    @Test fun `Genres lists the genres present by name and each opens its shows`() = runBlocking {
        val lib = library()
        val genres = lib.children(CarLibrary.GENRES)!!
        assertEquals(listOf("Mystery"), genres.map { it.title })
        assertEquals(listOf("Suspense"), lib.children(genres.single().id)!!.map { it.title })
    }

    @Test fun `By length lists the published band and leaves out no_recommend broadcasts`() = runBlocking {
        val lib = library()
        val bands = lib.children(CarLibrary.LENGTHS)!!
        assertEquals(listOf("About 30 min"), bands.map { it.title })
        val ids = lib.children(bands.single().id)!!.map { it.id }
        assertEquals(listOf("sus|1943-01-07", "cp|1944-01-07"), ids)
    }

    @Test fun `Shows you follow lists the followed shows, or says how`() = runBlocking {
        assertEquals(listOf("Suspense"), library(followed = listOf("suspense")).children(CarLibrary.FOLLOWING)!!.map { it.title })
        val none = library().children(CarLibrary.FOLLOWING)!!.single()
        assertTrue(!none.browsable && !none.playable)
    }

    @Test fun `Browse with no catalog says to open the phone`() = runBlocking {
        assertEquals(CarLibrary.NO_CATALOG, library(catalog = null).children(CarLibrary.POPULAR)!!.single().title)
    }

    // --- Search and voice ---

    @Test fun `search finds shows first then episodes, and says when nothing matches`() = runBlocking {
        val lib = library()
        val found = lib.search("suspense")
        assertTrue(found.first().browsable)
        assertEquals("Suspense", found.first().title)
        assertTrue(found.drop(1).all { it.playable })
        assertEquals(listOf("The Hitchhiker"), lib.search("hitchhiker").filter { it.playable }.map { it.title })
        assertEquals("Nothing found for zzzzqx", lib.search("zzzzqx").single().title)
        assertEquals(emptyList<CarNode>(), lib.search("   "))
    }

    @Test fun `search pages and stays within its caps`() = runBlocking {
        val lib = library()
        val all = lib.search("suspense")
        assertTrue(all.size <= CarLibrary.SEARCH_SERIES + CarLibrary.SEARCH_EPISODES)
        assertEquals(all.drop(2).take(2), lib.search("suspense", page = 1, pageSize = 2))
    }

    @Test fun `a spoken request plays a match, a station named, else where the listener left off, never nothing`() = runBlocking {
        val lib = library(stations = { listOf(CarStation("station:mystery", "Mystery", null, null)) })
        assertEquals("sus|1943-01-07", lib.voiceTarget("hitchhiker"))
        assertEquals("station:mystery", lib.voiceTarget("Mystery"))
        user.save("cp|1944-01-07", 300_000, 1_800_000)
        assertEquals("cp|1944-01-07", lib.voiceTarget("zzzzqx"))
        assertEquals("cp|1944-01-07", lib.voiceTarget(null))
        assertEquals("cp|1944-01-07", lib.resumeTarget())
    }

    @Test fun `a show spoken with nothing in progress plays its first episode`() = runBlocking {
        val lib = library(rows = { db.episodes(it) })
        // "Suspense" matches episodes too; the show's episode in progress is preferred when there is one.
        user.save("sus|1943-05-25", 300_000, 1_800_000)
        assertEquals("sus|1943-05-25", lib.voiceTarget("suspense"))
    }
}
