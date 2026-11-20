package com.example.appname.ui

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.outlined.Download
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
import coil3.decode.DataSource
import coil3.intercept.Interceptor
import coil3.request.ImageResult
import coil3.request.SuccessResult
import com.example.appname.data.Artwork
import com.example.appname.data.Credit
import com.example.appname.data.EpisodeDetail
import com.example.appname.data.EpisodeRow
import com.example.appname.data.LabelItem
import com.example.appname.data.LabelKind
import com.example.appname.data.SeriesRow
import com.example.appname.plays.CastableLibrary
import com.example.appname.ui.screens.episodeHead
import com.example.appname.ui.screens.seriesHead
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
 * V7: the item pages' heads rendered at a phone, a wide size and a Google TV's 960 x 540 dp, light and dark: a series (a
 * picture, the label, a wide hero stub, the pictures row), an episode, a person (portrait and label), a play (its opening drawn
 * as a page, then with a title page). Runs only when GRAMMAR_RENDER_DIR names a directory. The pictures are stubs (the
 * pipeline has not published a hero or a gallery yet): `GRAMMAR_RENDER_DIR=/tmp/out ./gradlew :app:testDebugUnitTest --tests '*ItemRenderTest'`.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35], qualifiers = "w412dp-h1400dp-xhdpi")
class ItemRenderTest {
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

    /** Stands in for the network: a gray studio backdrop with heads and shoulders, shaped by the url's name. */
    private object FakePictures : Interceptor {
        override suspend fun intercept(chain: Interceptor.Chain): ImageResult {
            val url = chain.request.data.toString()
            val (w, h) = when {
                url.contains("wide") -> 960 to 540
                url.contains("land") -> 600 to 400
                else -> 500 to 667
            }
            val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            val c = Canvas(bmp)
            val p = Paint(Paint.ANTI_ALIAS_FLAG)
            p.color = 0xFFC8C8C8.toInt(); c.drawRect(0f, 0f, w.toFloat(), h / 2f, p)
            p.color = 0xFF8A8A8A.toInt(); c.drawRect(0f, h / 2f, w.toFloat(), h.toFloat(), p)
            val figures = if (w > h) 2 else 1
            p.color = 0xFF222222.toInt()
            repeat(figures) { i ->
                val cx = w * (i + 0.5f) / figures
                val r = minOf(w / figures, h) * 0.17f
                c.drawOval(cx - r, h * 0.28f, cx + r, h * 0.28f + 2.3f * r, p)
                c.drawOval(cx - 2.4f * r, h * 0.6f, cx + 2.4f * r, h * 1.4f, p)
            }
            return SuccessResult(bmp.asImage(), chain.request, DataSource.MEMORY)
        }
    }

    private val upright = Artwork("https://x/upright.jpg", 500, 667, "Library of Congress", "https://commons.wikimedia.org/wiki/File:u.jpg")
    private val wideHero = Artwork("https://x/wide.jpg", 1600, 900, "NBC", "https://commons.wikimedia.org/wiki/File:w.jpg")
    private val gallery = listOf(
        Artwork("https://x/land1.jpg", 600, 400, "CBS", "https://commons.wikimedia.org/wiki/File:l1.jpg"),
        Artwork("https://x/upright2.jpg", 500, 667, null, "https://www.loc.gov/item/x"),
        Artwork("https://x/land3.jpg", 600, 400, "Wikimedia Commons", "https://commons.wikimedia.org/wiki/File:l3.jpg"),
    )

    private val years = listOf(1940, 6, 41, 52, 50, 52, 52, 48, 50, 52, 50, 47, 41, 35, 30, 22, 14, 6, 2, 2, 1, 1, 1)
    private fun suspense(picture: Artwork? = null, hero: Artwork? = null, pictures: List<Artwork> = emptyList()) = SeriesRow(
        "suspense", "Suspense", "mystery", "1940-06-17", "1962-09-30", 1077, picture = picture,
        networks = listOf("CBS"), yearCounts = years, hero = hero, gallery = pictures,
        aboutText = "Suspense is a radio drama series broadcast on CBS Radio from 1940 through 1962.", aboutSource = "Wikipedia",
    )

    private val episode = EpisodeDetail(
        episode = EpisodeRow("suspense|1942-12-22", "suspense", "Suspense", "1942-12-22", "1942-43", 22, "Two Sharp Knives", 1800.0, seriesGenre = "mystery", network = "CBS"),
        rights = "unclaimed", rightsBasis = null, network = "CBS", noRecommend = null,
        credits = listOf(Credit("agnes", "Stuart Erwin", "cast", null, upright)),
        recordings = List(6) { com.example.appname.data.Recording(it + 1, "sus-$it", "https://x/a.mp3", "mp3", 128, 1800.0, null, false) },
        detailJson = null, sponsor = null, star = "agnes",
    )

    @Composable private fun Frame(width: androidx.compose.ui.unit.Dp, height: androidx.compose.ui.unit.Dp, content: LazyListScope.() -> Unit) {
        Box(Modifier.padding(0.dp).then(Modifier.fillMaxWidth())) {
            LazyColumn(Modifier.width(width).height(height), content = content)
        }
    }

    private fun shoot(name: String, content: @Composable () -> Unit) {
        var dark by mutableStateOf(false)
        compose.setContent {
            AppTheme(darkTheme = dark) { Surface(color = MaterialTheme.colorScheme.background) { Column(Modifier.fillMaxWidth().padding(vertical = 12.dp)) { content() } } }
        }
        listOf(false, true).forEach { d ->
            dark = d
            repeat(30) { compose.mainClock.advanceTimeBy(50); Thread.sleep(20) }
            compose.waitForIdle()
            compose.onRoot().captureRoboImage(File(out, "$name-${if (dark) "dark" else "light"}.png").path)
        }
    }

    private fun seriesPage(name: String, s: SeriesRow, width: Int, height: Int) = shoot(name) {
        Frame(width.dp, height.dp) { seriesHead(s, following = false) {} }
    }

    @Test fun seriesLabelPhone() = seriesPage("android-series-label-phone", suspense(), 412, 760)

    @Test fun seriesPicturePhone() = seriesPage("android-series-picture-phone", suspense(picture = upright, pictures = gallery), 412, 1150)

    @Test fun seriesHeroPhone() = seriesPage("android-series-hero-phone", suspense(picture = upright, hero = wideHero, pictures = gallery), 412, 1000)

    @Test @Config(sdk = [35], qualifiers = "w1000dp-h1000dp-xhdpi")
    fun seriesLabelWide() = seriesPage("android-series-label-wide", suspense(), 720, 640)

    @Test @Config(sdk = [35], qualifiers = "w1000dp-h1000dp-xhdpi")
    fun seriesHeroWide() = seriesPage("android-series-hero-wide", suspense(picture = upright, hero = wideHero, pictures = gallery), 720, 1000)

    /** A Google TV's viewport: 960 x 540 dp. The head is one item with its buttons, and the page keeps its top in view. */
    @Test @Config(sdk = [35], qualifiers = "w960dp-h540dp-xhdpi")
    fun seriesGoogleTv() = shoot("android-series-googletv") {
        CompositionLocalProvider(LocalIsTelevision provides true) { Frame(720.dp, 540.dp) { seriesHead(suspense(picture = upright), following = false) {} } }
    }

    @Test @Config(sdk = [35], qualifiers = "w960dp-h540dp-xhdpi")
    fun seriesHeroGoogleTv() = shoot("android-series-hero-googletv") {
        CompositionLocalProvider(LocalIsTelevision provides true) { Frame(720.dp, 540.dp) { seriesHead(suspense(picture = upright, hero = wideHero), following = false) {} } }
    }

    private fun episodePage(name: String, width: Int, height: Int) = shoot(name) {
        Frame(width.dp, height.dp) {
            episodeHead(
                d = episode, series = suspense(picture = upright), progress = null,
                playFocus = androidx.compose.ui.focus.FocusRequester(),
                onPlay = {}, onOpenSeries = {}, onOpenPerson = {}, onOpenTranscript = {},
                queue = { f -> FoldButton(Icons.Filled.Add, "Add to queue", f, {}) },
                share = { f -> ShareButton("Two Sharp Knives", "https://eardrama.org/x", f) },
                download = { f -> FoldButton(Icons.Outlined.Download, "Download", f, {}) },
                earDrama = null,
            )
        }
    }

    @Test fun episodePhone() = episodePage("android-episode-phone", 412, 980)

    @Test @Config(sdk = [35], qualifiers = "w1000dp-h1000dp-xhdpi")
    fun episodeWide() = episodePage("android-episode-wide", 720, 900)

    private fun person(name: String, art: Artwork?, width: Int, height: Int) = shoot(name) {
        Frame(width.dp, height.dp) {
            item {
                ItemHeadBoard(
                    name = "Jack Webb", genre = null, art = art, round = true,
                    label = LabelItem(LabelKind.Person, "Jack Webb", first = "1946", last = "1962"),
                    facts = listOf("1920–1982", "406 episodes", "17 shows"),
                    first = "1946", last = "1962", years = listOf(1946, 4, 0, 0, 2, 12, 20, 18, 5),
                )
                HeadCredit(art, Modifier.padding(horizontal = 16.dp))
            }
        }
    }

    @Test fun personPortraitPhone() = person("android-person-portrait-phone", upright, 412, 700)

    @Test fun personLabelPhone() = person("android-person-label-phone", null, 412, 700)

    @Test @Config(sdk = [35], qualifiers = "w1000dp-h1000dp-xhdpi")
    fun personLabelWide() = person("android-person-label-wide", null, 720, 420)

    private fun play(name: String, titlePage: Artwork?, width: Int, height: Int) {
        val library = CastableLibrary.decode(File("../../catalog/plays/castable-scripts.json").readText())
        val script = library.scripts.first { it.id == "gut-28051" }
        shoot(name) {
            Frame(width.dp, height.dp) { item { PlayPageHead(script, "Radio play", titlePage = titlePage) } }
        }
    }

    @Test fun playOpeningPhone() = play("android-play-phone", null, 412, 760)

    @Test fun playTitlePagePhone() = play("android-play-titlepage-phone", upright, 412, 1000)

    @Test @Config(sdk = [35], qualifiers = "w1000dp-h1000dp-xhdpi")
    fun playOpeningWide() = play("android-play-wide", null, 720, 460)
}
