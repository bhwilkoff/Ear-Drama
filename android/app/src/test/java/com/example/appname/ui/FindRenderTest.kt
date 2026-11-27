package com.example.appname.ui

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.unit.dp
import coil3.ImageLoader
import coil3.SingletonImageLoader
import coil3.annotation.DelicateCoilApi
import coil3.asImage
import coil3.decode.DataSource
import coil3.intercept.Interceptor
import coil3.request.ImageResult
import coil3.request.SuccessResult
import com.example.appname.plays.FindCore
import com.example.appname.plays.LibraryTransport
import com.example.appname.plays.PlayCollections
import com.example.appname.plays.PlayLibraryFeed
import com.example.appname.plays.PlayRow
import com.example.appname.plays.PlayScript
import com.example.appname.plays.PlaySearchModel
import com.example.appname.ui.screens.FACET_CHIPS
import com.example.appname.ui.screens.PlayFacetRow
import com.example.appname.ui.screens.PlayFiltersBody
import com.example.appname.ui.screens.PlayNeighbors
import com.example.appname.ui.screens.PlayQueryField
import com.example.appname.ui.screens.PlayRailSection
import com.example.appname.ui.screens.PlaySearchSections
import com.example.appname.ui.screens.PlayShelvesTv
import com.example.appname.ui.screens.RowProblem
import com.example.appname.ui.screens.RowSpinner
import com.example.appname.ui.screens.SceneCard
import com.example.appname.ui.screens.playPage
import com.example.appname.ui.theme.AppTheme
import com.github.takahirom.roborazzi.captureRoboImage
import java.io.File
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * B31 D1's frames: the play label and tiles, Record's Plays (facets, ways in, grid), Filters, the search's Plays, Characters and
 * Lines, the play page's neighbors, the four states and the TV's shelves, light and dark, over the REAL play library (nothing is
 * written for them). Runs only when GRAMMAR_RENDER_DIR and PLAY_LIBRARY_DIR (a built `plays-library` folder, e.g.
 * catalog/out/plays-library) name directories:
 * `GRAMMAR_RENDER_DIR=/tmp/out PLAY_LIBRARY_DIR=catalog/out/plays-library ./gradlew testDebugUnitTest --tests '*FindRenderTest'`.
 * Pictures stand in with a colorful fake (the grade's monochrome shows); nothing touches the network.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35], qualifiers = "w412dp-h2600dp-xhdpi")
class FindRenderTest {
    @get:Rule val compose = createComposeRule()

    private lateinit var out: File
    private lateinit var library: File
    private lateinit var feed: PlayLibraryFeed
    private lateinit var rows: List<PlayRow>
    private var collections: PlayCollections? = null
    private var facets: com.example.appname.plays.PlayFacetsIndex? = null

    private object FakePictures : Interceptor {
        override suspend fun intercept(chain: Interceptor.Chain): ImageResult {
            val (w, h) = 600 to 800
            val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            val c = Canvas(bmp)
            val p = Paint(Paint.ANTI_ALIAS_FLAG)
            p.color = 0xFFC8553D.toInt(); c.drawRect(0f, 0f, w.toFloat(), h / 2f, p)
            p.color = 0xFF2E86AB.toInt(); c.drawRect(0f, h / 2f, w.toFloat(), h.toFloat(), p)
            p.color = 0xFFF1C453.toInt(); c.drawCircle(w * 0.5f, h * 0.35f, h * 0.11f, p)
            return SuccessResult(bmp.asImage(), chain.request, DataSource.MEMORY)
        }
    }

    @OptIn(DelicateCoilApi::class)
    @Before fun setUp() {
        val dir = System.getenv("GRAMMAR_RENDER_DIR")
        val lib = System.getenv("PLAY_LIBRARY_DIR")
        assumeTrue("GRAMMAR_RENDER_DIR not set", !dir.isNullOrBlank())
        assumeTrue("PLAY_LIBRARY_DIR not set", !lib.isNullOrBlank())
        out = File(dir!!).apply { mkdirs() }
        library = File(lib!!)
        assumeTrue("no index.json in PLAY_LIBRARY_DIR", File(library, "index.json").exists())
        System.setProperty("roborazzi.test.record", "true")
        SingletonImageLoader.setUnsafe(
            ImageLoader.Builder(androidx.test.core.app.ApplicationProvider.getApplicationContext()).components { add(FakePictures) }.build(),
        )
        feed = PlayLibraryFeed(LibraryTransport { path -> File(library, path).takeIf { it.exists() }?.readText() }, null) { emptyList() }
        runBlocking { feed.loadRows() }
        val ready = feed.rows.value as PlayLibraryFeed.Rows.Ready
        rows = ready.rows
        facets = ready.facets
        collections = runBlocking { feed.collections() }
    }

    private val featured = listOf("gut-3544", "gut-4023", "gut-3790", "gut-59432-101", "gut-8500-3", "gut-7700", "gut-1521", "gut-78131", "gut-59421", "gut-68576", "gut-65920-109", "gut-31-101")
    private fun twelve() = featured.mapNotNull { id -> rows.firstOrNull { it.id == id } }

    @Composable private fun Page(dark: Boolean, content: @Composable () -> Unit) {
        AppTheme(darkTheme = dark) {
            Surface(color = MaterialTheme.colorScheme.background) { Column(Modifier.fillMaxWidth().padding(vertical = 12.dp)) { content() } }
        }
    }

    private var dark by mutableStateOf(false)
    private var television by mutableStateOf(false)
    private var current by mutableStateOf<(@Composable () -> Unit)?>(null)
    private var started = false

    /** One composition per test (the rule sets content once); each frame swaps what it holds. */
    private fun shoot(name: String, tv: Boolean = false, content: @Composable () -> Unit) {
        if (!started) {
            started = true
            compose.setContent { CompositionLocalProvider(LocalIsTelevision provides television) { Page(dark) { current?.invoke() } } }
        }
        television = tv
        current = content
        listOf(false, true).forEach { d ->
            dark = d
            repeat(20) { compose.mainClock.advanceTimeBy(50); Thread.sleep(20) }
            compose.waitForIdle()
            compose.onRoot().captureRoboImage(File(out, "$name-${if (dark) "dark" else "light"}.png").path)
        }
    }

    @OptIn(ExperimentalLayoutApi::class)
    @Test fun labelsAndTiles() {
        val plays = twelve()
        assertEquals(12, plays.size)
        shoot("find-labels") {
            FlowRow(Modifier.fillMaxWidth().padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                plays.take(1).forEach { LabelArt(it.labelItem, Modifier.size(320.dp).clip(RoundedCornerShape(4.dp))) }
                plays.drop(1).take(2).forEach { LabelArt(it.labelItem, Modifier.size(190.dp).clip(RoundedCornerShape(4.dp))) }
                plays.forEach { LabelArt(it.labelItem, Modifier.size(100.dp).clip(RoundedCornerShape(4.dp))) }
                plays.forEach { LabelArt(it.labelItem, Modifier.size(52.dp).clip(RoundedCornerShape(4.dp))) }
            }
        }
        shoot("find-tiles") {
            FlowRow(Modifier.fillMaxWidth().padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                plays.take(8).forEach { PlayTile(it, onOpen = {}, onRead = {}) }
            }
        }
    }

    @Test fun recordPlays() {
        val fs = FindCore.facets(facets)
        val state = FindCore.State()
        val rails = FindCore.rails(rows, collections)
        assertTrue("the library's ways in were not read", rails.isNotEmpty())
        shoot("find-record") {
            PlayQueryField("", {}, {}, Modifier.padding(horizontal = 16.dp, vertical = 8.dp))
            SectionHeader("Plays")
            PlayFacetRow(rows, fs, state, onState = {})
            rails.take(3).forEach { PlayRailSection(it, {}, { _, _ -> }, {}, {}) }
        }
        val picked = state.copy(picks = mapOf("voices" to "1-2", "form" to "comedy"))
        val list = FindCore.sorted(FindCore.filter(rows, fs, picked.picks), picked.sort)
        shoot("find-picked") {
            PlayQueryField("", {}, {}, Modifier.padding(horizontal = 16.dp, vertical = 8.dp))
            PlayFacetRow(rows, fs, picked, onState = {})
            Text(FindCore.sortTitle(picked.sort), style = MaterialTheme.typography.headlineSmall, modifier = Modifier.padding(16.dp))
            @OptIn(ExperimentalLayoutApi::class)
            FlowRow(Modifier.fillMaxWidth().padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                list.take(6).forEach { PlayTile(it, onOpen = {}, onRead = {}) }
            }
        }
        assertTrue(FACET_CHIPS.isNotEmpty())
    }

    @Test fun filters() {
        val fs = FindCore.facets(facets)
        val pending = mapOf("form" to "comedy")
        val counted = FindCore.counts(rows, fs, pending)
        shoot("find-filters") {
            PlayFiltersBody(counted, pending, FindCore.filter(rows, fs, pending).size, { _, _ -> }, {}, {}, Modifier.height(1500.dp))
        }
    }

    private fun searched(q: String): PlaySearchModel = PlaySearchModel(feed).also { runBlocking { it.run(q, rows) } }

    @Test fun search() {
        for ((name, q) in listOf("mercy" to "quality of mercy", "candida" to "candida")) {
            val model = searched(q)
            val s = model.state.value
            assertTrue("$q found nothing", s.foundAny)
            shoot("find-search-$name") {
                PlayQueryField(q, {}, {}, Modifier.padding(horizontal = 16.dp, vertical = 8.dp))
                PlaySearchSections(q, model, {}, { _, _ -> }, {}, offersAdd = true)
            }
        }
        val none = searched("zzzxqj")
        shoot("find-search-none") {
            PlayQueryField("zzzxqj", {}, {}, Modifier.padding(horizontal = 16.dp, vertical = 8.dp))
            PlaySearchSections("zzzxqj", none, {}, { _, _ -> }, {}, offersAdd = true)
        }
    }

    @Test fun playPageWithNeighbors() {
        val row = rows.first { it.id == "gut-4023" }
        val script: PlayScript = runBlocking { feed.script(row.id) }!!
        val sceneRow = rows.first { r -> r.scenes.any { it.voices == 2 } }
        shoot("find-play-page") {
            Column(Modifier.height(2300.dp)) {
                LazyColumn(Modifier.fillMaxSize()) {
                    playPage(
                        script, television = false, onOpenProduction = {}, start = { Button(onClick = {}, colors = playButtonColors()) { Text("Record this") } },
                        row = row, neighbors = { PlayNeighbors(row, rows, collections, false, {}, { _, _ -> }, {}) },
                    )
                }
            }
        }
        shoot("find-scenes") {
            Text("Scenes for two voices", style = MaterialTheme.typography.headlineSmall, modifier = Modifier.padding(16.dp))
            @OptIn(ExperimentalLayoutApi::class)
            FlowRow(Modifier.fillMaxWidth().padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                FindCore.sceneRows(rows, 2).take(4).forEach { SceneCard(it, onClick = {}) }
                SceneCard(FindCore.SceneHit(sceneRow, sceneRow.scenes.first { it.voices == 2 }), inPlay = true, onClick = {})
            }
        }
    }

    @Test fun states() = shoot("find-states") {
        SectionHeader("Loading")
        RowSpinner()
        SectionHeader("Did not load")
        RowProblem("This did not load.", onRetry = {})
        SectionHeader("Offline")
        RowProblem(OFFLINE_LINE, onRetry = {})
        SectionHeader("Nothing matches")
        EmptyMessage("Nothing matches these filters.", action = EmptyAction("Clear filters") {}, claimTvFocus = false)
        SectionHeader("No play matches")
        EmptyMessage("No plays match “zzzxqj”.", action = EmptyAction("Add a script") {}, claimTvFocus = false)
    }

    @Config(qualifiers = "w960dp-h540dp-xhdpi")
    @Test fun television() {
        val rails = FindCore.rails(rows, collections, per = 16, withScenes = false, ids = FindCore.tvIds(collections))
        assertTrue(rails.none { it.kind == FindCore.RailKind.Scenes })
        shoot("find-tv", tv = true) { PlayShelvesTv(rails.take(2), onOpenScript = {}, modifier = Modifier.height(500.dp)) }
    }

}
