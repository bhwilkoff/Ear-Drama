package com.example.appname.ui

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
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
import com.example.appname.data.FaceBox
import com.example.appname.data.SeriesRow
import com.example.appname.data.dayYears
import com.example.appname.radio.DialEntry
import com.example.appname.radio.HomeLive
import com.example.appname.radio.RadioSlot
import com.example.appname.radio.Station
import com.example.appname.ui.screens.HomeDial
import com.example.appname.ui.screens.OnAirHero
import com.example.appname.ui.theme.AppTheme
import com.github.takahirom.roborazzi.captureRoboImage
import java.io.File
import java.time.Instant
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Renders Home's first screen (V6: the On the air hero, the dial, the doors, the one-ink day chart) at a phone and a
 * wide size, light and dark. Runs only when GRAMMAR_RENDER_DIR names a directory:
 * `GRAMMAR_RENDER_DIR=/tmp/out ./gradlew testDebugUnitTest --tests '*HomeRenderTest'`.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35], qualifiers = "w412dp-h1400dp-xhdpi")
class HomeRenderTest {
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

    private object FakePictures : Interceptor {
        override suspend fun intercept(chain: Interceptor.Chain): ImageResult {
            val (w, h) = 500 to 667
            val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            val c = Canvas(bmp)
            val p = Paint(Paint.ANTI_ALIAS_FLAG)
            p.color = 0xFFC8553D.toInt(); c.drawRect(0f, 0f, w.toFloat(), h / 2f, p)
            p.color = 0xFF2E86AB.toInt(); c.drawRect(0f, h / 2f, w.toFloat(), h.toFloat(), p)
            p.color = 0xFFF1C453.toInt(); c.drawCircle(w * 0.5f, h * 0.35f, h * 0.11f, p)
            return SuccessResult(bmp.asImage(), chain.request, DataSource.MEMORY)
        }
    }

    private val portrait = Artwork("https://x/portrait.jpg", 500, 667, face = FaceBox(0.4f, 0.25f, 0.2f, 0.15f))
    private val start = Instant.parse("2026-11-19T20:00:00Z")
    private val now = start.plusSeconds(300)

    private fun slot(id: String, series: String, title: String) = RadioSlot(
        etStart = "", etEnd = "", lengthMin = 30, utcStart = start, utcEnd = start.plusSeconds(1800),
        episode = RadioSlot.Episode(id, series, title, 1800.0), gap = false, withheld = false,
    )

    private val stations = listOf(
        Station("drama", "Drama", listOf(slot("sol|1948-03-02", "Soldiers of the Press", "Ep"))),
        Station("mystery", "Mystery", listOf(slot("whistler|1944-05-01", "The Whistler", "Ep"))),
        Station("scifi", "Science fiction", listOf(slot("gl|1951-02-02", "Gregory Lyons", "Ep"))),
        Station("western", "Western", listOf(slot("ga|1949-07-07", "Gene Autry's Melody Ranch", "Ep"))),
        Station("comedy", "Comedy", listOf(slot("dr|1946-10-10", "Dr I Q the Mental Banker", "Ep"))),
        Station("news", "News", listOf(slot("cbs|1941-12-08", "CBS World News", "Ep"))),
        Station("documentary", "Documentary", listOf(slot("js|1947-11-11", "The Jean Shepherd Show", "Ep"))),
        Station("serial", "Serials", listOf(slot("jc|1945-01-15", "Jerry of the Circus", "Ep"))),
    )

    @Composable private fun Home(dark: Boolean, picture: Boolean, rawTitle: Boolean) {
        val ellery = SeriesRow(
            "ellery", "The Adventures of Ellery Queen", "mystery", "1939-06-18", "1948-05-30", 120,
            picture = portrait.takeIf { picture },
        )
        val on = HomeLive("Tonight in 1939", slot("ellery|1939-04-02", ellery.name, if (rawTitle) "AbyM #026 The Telltale Bottle" else "The Telltale Bottle"), null, null)
        AppTheme(darkTheme = dark) {
            Surface(color = MaterialTheme.colorScheme.background) {
                Column(Modifier.fillMaxWidth().padding(vertical = 12.dp)) {
                    OnAirHero(on, now, ellery, tuned = false, onTune = {}, onOpenStations = {}, onOpenEpisode = {}, liveFocus = FocusRequester())
                    HomeDial(DialEntry.entries(stations, now), liveStation = null, onTune = {})
                    val rows = listOf(
                        row("a", "1938-04-02", "drama"), row("b", "1938-04-02", "mystery"), row("c", "1939-04-02", "western"),
                        row("d", "1941-04-02", "comedy"), row("e", "1941-04-02", "drama"), row("f", "1944-04-02", "news"),
                    )
                    DayBoard("April 2", dayYears(rows, { it.airDate }, { it.seriesGenre }), 1941, onSelect = {})
                }
            }
        }
    }

    private fun row(key: String, date: String, genre: String) =
        com.example.appname.data.EpisodeRow("$key|$date", key, key, date, null, null, null, 1800.0, seriesGenre = genre)

    private fun shoot(name: String, picture: Boolean = true, rawTitle: Boolean = false) {
        var dark by mutableStateOf(false)
        compose.setContent { Home(dark, picture, rawTitle) }
        listOf(false, true).forEach { d ->
            dark = d
            repeat(30) { compose.mainClock.advanceTimeBy(50); Thread.sleep(20) }
            compose.waitForIdle()
            compose.onRoot().captureRoboImage(File(out, "$name-${if (dark) "dark" else "light"}.png").path)
        }
    }

    @Test fun phone() = shoot("android-home-phone")

    @Test fun phoneLabelHero() = shoot("android-home-phone-label", picture = false, rawTitle = true)

    @Test @Config(sdk = [35], qualifiers = "w1000dp-h1000dp-xhdpi")
    fun wide() = shoot("android-home-wide")
}
