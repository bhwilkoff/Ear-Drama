package com.example.appname.ui

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.unit.dp
import coil3.ImageLoader
import coil3.SingletonImageLoader
import coil3.annotation.DelicateCoilApi
import coil3.asImage
import coil3.intercept.Interceptor
import coil3.request.ImageRequest
import coil3.request.ImageResult
import coil3.request.SuccessResult
import coil3.decode.DataSource
import com.example.appname.data.Artwork
import com.example.appname.data.FaceBox
import com.example.appname.data.SeriesRow
import com.example.appname.ui.theme.AppTheme
import com.github.takahirom.roborazzi.captureRoboImage
import java.io.File
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Renders the grammar (ANDROID-DESIGN R11b) to PNGs for a human to read. Runs only when
 * GRAMMAR_RENDER_DIR names a directory, so the ordinary suite stays on the JVM alone:
 * `GRAMMAR_RENDER_DIR=/tmp/out ./gradlew testDebugUnitTest --tests '*GrammarRenderTest'`.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35], qualifiers = "w412dp-h1400dp-xhdpi")
class GrammarRenderTest {
    @get:Rule val compose = createComposeRule()

    private lateinit var out: File

    @OptIn(DelicateCoilApi::class)
    @Before fun setUp() {
        val dir = System.getenv("GRAMMAR_RENDER_DIR")
        assumeTrue("GRAMMAR_RENDER_DIR not set", !dir.isNullOrBlank())
        out = File(dir!!).apply { mkdirs() }
        System.setProperty("roborazzi.test.record", "true")
        SingletonImageLoader.setUnsafe(
            ImageLoader.Builder(androidx.test.core.app.ApplicationProvider.getApplicationContext())
                .components { add(FakePictures) }
                .build(),
        )
    }

    /** Stands in for the network: a colorful portrait or wide picture, so the grade's monochrome shows. */
    private object FakePictures : Interceptor {
        override suspend fun intercept(chain: Interceptor.Chain): ImageResult {
            val url = chain.request.data.toString()
            val (w, h) = if (url.contains("wide")) 960 to 480 else 500 to 667
            val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            val c = Canvas(bmp)
            val p = Paint(Paint.ANTI_ALIAS_FLAG)
            p.color = 0xFFC8553D.toInt(); c.drawRect(0f, 0f, w.toFloat(), h / 2f, p)
            p.color = 0xFF2E86AB.toInt(); c.drawRect(0f, h / 2f, w.toFloat(), h.toFloat(), p)
            p.color = 0xFFF1C453.toInt(); c.drawCircle(w * 0.5f, h * 0.35f, h * 0.11f, p)
            p.color = 0xFF222222.toInt(); c.drawRect(w * 0.3f, h * 0.5f, w * 0.7f, h * 0.9f, p)
            return SuccessResult(bmp.asImage(), chain.request, DataSource.MEMORY)
        }
    }

    private val portrait = Artwork("https://x/portrait.jpg", 500, 667, face = FaceBox(0.4f, 0.25f, 0.2f, 0.15f))
    private val wide = Artwork("https://x/wide.jpg", 960, 480)
    private val tiny = Artwork("https://x/portrait-tiny.jpg", 60, 80, face = FaceBox(0.4f, 0.25f, 0.2f, 0.15f))

    private fun series(key: String, name: String, genre: String?, first: String?, last: String?, n: Int, art: Artwork?) =
        SeriesRow(key, name, genre, first, last, n, picture = art)

    private val shelfA = listOf(
        series("sus", "Suspense", "mystery", "1942-06-17", "1962-09-30", 944, portrait),
        series("holmes", "The Adventures of Sherlock Holmes", "mystery", "1930-10-20", "1950-06-26", 215, wide),
        series("lux", "Lux Radio Theatre", "drama", "1934-10-14", "1955-06-07", 410, null),
        series("dx", "Dimension X", "scifi", null, null, 1, tiny),
    )
    private val shelfB = listOf(
        series("ext", "Extraordinary Entertainment Hour", "comedy", "1947-01-01", "1948-12-31", 12, null),
        series("counter", "Counterrevolutionary Hour", null, "1950-01-01", "1951-01-01", 3, wide),
        series("lone", "The Lone Ranger", "western", "1933-01-30", "1954-09-03", 2956, portrait),
        series("news", "X Minus One", "news", "1955-04-24", "1958-01-09", 125, null),
        series("doc", "Documentary", "documentary", "1945-01-01", "1946-01-01", 7, null),
        series("serial", "Serial Adventures", "serial", "1938-01-01", "1941-01-01", 40, null),
    )

    @Composable private fun Page(dark: Boolean, content: @Composable () -> Unit) {
        AppTheme(darkTheme = dark) {
            Surface(color = MaterialTheme.colorScheme.background) { Column(Modifier.fillMaxWidth().padding(vertical = 12.dp)) { content() } }
        }
    }

    private fun shoot(name: String, content: @Composable () -> Unit) {
        var dark by mutableStateOf(false)
        compose.setContent { Page(dark, content) }
        listOf(false, true).forEach { d ->
            dark = d
            repeat(30) { compose.mainClock.advanceTimeBy(50); Thread.sleep(20) }
            compose.waitForIdle()
            compose.onRoot().captureRoboImage(File(out, "$name-${if (dark) "dark" else "light"}.png").path)
        }
    }

    @Test fun shelves() = shoot("tiles-shelf") {
        SectionHeader("Shelf A")
        ShowShelf(shelfA, onOpen = {})
        SectionHeader("Shelf B")
        ShowShelf(shelfB, onOpen = {})
        SectionHeader("Shelf B, scrolled")
        ShowShelf(shelfB.drop(3), onOpen = {})
    }

    @Test fun television() = shoot("tile-tv") {
        CompositionLocalProvider(LocalIsTelevision provides true) {
            ShowShelf(listOf(shelfA[0], shelfA[1]), onOpen = {})
        }
    }

    @Composable private fun one(m: Modifier, date: String?, num: Int?, g: String?) = DateBlock(date, num, g, m)

    @Test fun rows() = shoot("rows") {
        GrammarRow("Sorry, Wrong Number", { m -> one(m, "1943-05-25", null, "mystery") }, {}, sub = listOf(null), length = "30 min", onPlay = {})
        GrammarRow("The Hitch-Hiker", { m -> one(m, "1942-09-02", null, "mystery") }, {}, sub = listOf("Orson Welles in the lead"), length = "29 min", onPlay = {})
        GrammarRow("Spring Offensive, a title long enough to take two full lines", { m -> one(m, "1950-02", null, "drama") }, {}, sub = listOf("Sponsored by Lux", "CBS", "Remastered"), length = "1 h", onPlay = {})
        GrammarRow("Year only", { m -> one(m, "1948", null, "scifi") }, {}, length = "30 min", onPlay = {})
        GrammarRow("Undated number", { m -> one(m, null, 14, null) }, {}, sub = listOf("Undated"), length = "28 min", onPlay = {})
        GrammarRow("Suspense: Sorry, Wrong Number", { m -> PictureWindow(portrait, "Suspense", "mystery", m) }, {}, sub = listOf("Suspense", "1943-05-25", "Cast as Mrs. Stevenson"), length = "30 min", onPlay = {})
        GrammarRow("Wide picture whole", { m -> PictureWindow(wide, "The Adventures of Sherlock Holmes", "mystery", m) }, {}, sub = listOf("The Adventures of Sherlock Holmes", "Undated"), length = "30 min", onPlay = {})
        GrammarRow("Title block", { m -> PictureWindow(null, "Lux Radio Theatre", "drama", m) }, {}, sub = listOf("Lux Radio Theatre", "1936-06-01"), length = "60 min", onPlay = {})
        GrammarRow("No genre block", { m -> PictureWindow(null, "Mr. and Mrs. North", null, m) }, {}, sub = listOf("Mr. and Mrs. North", "1943-01-07"), length = "30 min", onPlay = {})
        GrammarRow("Suspense", { m -> PictureWindow(portrait, "Suspense", "mystery", m) }, {}, sub = listOf("1942–1962", "944 episodes"), openLabel = "Open series")
        GrammarRow("Dimension X", { m -> PictureWindow(tiny, "Dimension X", "scifi", m) }, {}, sub = listOf("1950–1951", "50 episodes"), openLabel = "Open series")
    }

    private data class Bc(val date: String, val genre: String)

    private val dayRows: List<Bc> = buildList {
        val per = mapOf(
            1930 to listOf("drama"), 1934 to listOf("mystery", "drama"), 1938 to listOf("comedy", "comedy", "drama"),
            1941 to listOf("western", "scifi", "serial", "news"),
            1944 to List(9) { "drama" } + List(6) { "mystery" } + List(4) { "comedy" } + listOf("documentary", "serial", ""),
            1947 to listOf("mystery", "scifi", "", "drama"), 1952 to listOf("drama", "western"), 1958 to listOf("news"),
        )
        per.forEach { (y, gs) -> gs.forEach { add(Bc("$y-10-29", it)) } }
    }

    @Test fun dayBoard() = shoot("home-day") {
        val years = com.example.appname.data.dayYears(dayRows, { it.date }, { it.genre })
        DayBoard("October 29", years, years.peak, onSelect = {})
        SectionHeading("October 29, 1944") {
            androidx.compose.material3.Text("12 single recordings", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        TileGrid(
            listOf(shelfA[0], shelfA[2], shelfB[0], shelfB[3], shelfB[4], shelfB[5]).mapIndexed { i, s ->
                TileSpec("n$i", s, facts = listOf("Sorry, Wrong Number", "30 min"), openLabel = "Open episode", onOpen = {})
            },
        )
        TextLink("All 14 shows that night", onClick = {}, modifier = Modifier.padding(horizontal = 16.dp))
    }

    @Test fun browseField() = shoot("browse-field") {
        val shows = buildList {
            fun n(g: String?, y: String?, k: Int) = repeat(k) { add(com.example.appname.data.FieldShow(g, y)) }
            n("drama", "1925", 3); n("drama", "1934", 40); n("drama", "1946", 98); n("drama", "1953", 20); n("drama", "1962", 5)
            n("mystery", "1936", 12); n("mystery", "1947", 60); n("comedy", "1938", 30); n("comedy", "1948", 55)
            n("western", "1950", 25); n("scifi", "1951", 9); n("news", "1942", 1); n(null, "1945", 7)
        }
        val field = com.example.appname.data.decadeField(shows)
        androidx.compose.foundation.layout.Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
            androidx.compose.material3.Text("2,036 shows", style = MaterialTheme.typography.titleMedium)
            androidx.compose.foundation.layout.Spacer(Modifier.weight(1f))
            TextLink("7,189 single recordings", onClick = {})
        }
        SectionHeading("By decade and genre") {
            androidx.compose.material3.Text("7 with no genre", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        DecadeFieldView(field, "drama", 1940, onCell = { _, _ -> }, modifier = Modifier.padding(horizontal = 16.dp))
        androidx.compose.material3.Text("A to Z", style = MaterialTheme.typography.headlineSmall, modifier = Modifier.padding(16.dp))
        TileGrid(
            (shelfA + shelfB).mapIndexed { i, s -> TileSpec("g$i", s, onOpen = {}) } +
                TileSpec("p", SeriesRow("play:x", "The Importance of Being Earnest", null, null, null, 0), facts = listOf("Oscar Wilde", "6 parts"), onOpen = {}),
        )
    }

    @Test fun head() = shoot("headboard") {
        HeadBoard("Suspense", "mystery", portrait, "Series", listOf("1942–1962", "CBS", "944 episodes"), "1942-06-17", "1962-09-30")
        HeadBoard("Counterrevolutionary Hour", null, null, "Series", listOf("1950"), "1950-01-01", "1951-01-01", Modifier.padding(top = 12.dp))
    }
}
