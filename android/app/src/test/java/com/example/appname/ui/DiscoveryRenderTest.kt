package com.example.appname.ui

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
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
 * Renders Stations, Surprise, Search's people and a person's page (D3-8) to PNGs for a human to
 * read. Runs only when GRAMMAR_RENDER_DIR names a directory:
 * `GRAMMAR_RENDER_DIR=/tmp/out ./gradlew testDebugUnitTest --tests '*DiscoveryRenderTest'`.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35], qualifiers = "w412dp-h1400dp-xhdpi")
class DiscoveryRenderTest {
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

    /** Stands in for the network: a colorful portrait, so the grade's monochrome shows. */
    private object FakePictures : Interceptor {
        override suspend fun intercept(chain: Interceptor.Chain): ImageResult {
            val (w, h) = 500 to 667
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

    private fun series(key: String, name: String, genre: String?, first: String?, last: String?, n: Int, art: Artwork?) =
        SeriesRow(key, name, genre, first, last, n, picture = art)

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

    @Test fun stations() = shoot("stations") {
        val sus = series("sus", "Suspense", "mystery", "1942-06-17", "1962-09-30", 944, portrait)
        GrammarRow(
            "Tonight in 1952", { m -> PictureWindow(null, "Tonight in 1952", null, m) }, {}, opens = false,
            sub = listOf("Starts at 7:00 PM"),
        )
        GrammarRow(
            "Mystery", { m -> PictureWindow(sus.windowArt, sus.name, sus.genre, m) }, {}, opens = false,
            sub = listOf("Suspense", "Cabin B-13"),
            trailing = { OutlinedButton(onClick = {}) { Text("Listening live", maxLines = 1) } },
        )
        GrammarRow(
            "Science fiction", { m -> PictureWindow(null, "Science fiction", "scifi", m) }, {}, opens = false,
            sub = listOf("Dimension X", "Mars Is Heaven"),
            trailing = { Button(onClick = {}, colors = playButtonColors()) { Text("Listen live", maxLines = 1) } },
        )
        GrammarRow(
            "Lux Radio Theatre", { m -> PictureWindow(null, "Lux Radio Theatre", null, m) }, {}, opens = false,
            sub = listOf("7:00 PM ET", "Not surviving", "30 min"), length = "30 min", badge = "Now",
        )
        GrammarRow(
            "Suspense", { m -> PictureWindow(portrait, "Suspense", "mystery", m) }, {},
            sub = listOf("7:30 PM ET", "Cabin B-13"), length = "30 min", onPlay = {},
        )
    }

    @Test fun surprise() = shoot("surprise") {
        val sus = series("sus", "Suspense", "mystery", "1942-06-17", "1962-09-30", 944, portrait)
        SectionHeader("An episode")
        HeadBoard(
            name = sus.name, genre = sus.genre, art = sus.windowArt, kicker = null,
            facts = listOf("Cabin B-13", "1943-05-25"), first = sus.firstDate, last = sus.lastDate,
            years = listOf(1942, 20, 40, 52, 60, 48, 40, 33, 30, 28, 26, 20, 18, 22, 25, 30, 18, 14, 12, 10, 9),
        )
        SectionHeader("An evening")
        HeadBoard(
            name = "Tuesday, November 10, 1942", genre = "mystery", art = null, kicker = null,
            facts = listOf("CBS", "WJSV", "Lights Out"), first = null, last = null,
        )
    }

    @Test fun person() = shoot("person") {
        HeadBoard(
            name = "Jack Webb", genre = null, art = portrait, kicker = null,
            facts = listOf("1920–1982", "405 episodes", "17 shows"), first = "1946", last = "1957",
            years = listOf(1946, 4, 7, 6, 0, 0, 3, 5, 9, 1, 2, 1),
        )
        ShowShelf(
            listOf(
                series("a", "One Out of Seven", "drama", "1946-02-06", "1946-04-10", 4, null),
                series("b", "Dragnet", "drama", "1949-06-03", "1957-02-21", 312, portrait),
            ),
            onOpen = {},
        )
        GrammarRow("Senator Theodore Bilbo", { m -> DateBlock("1946-02-06", null, "drama", m) }, {}, sub = listOf("Host"), length = "30 min", onPlay = {})
        GrammarRow("Orson Welles", { m -> PersonWindow(null, "Orson Welles", m) }, {}, sub = listOf("225 episodes"), openLabel = "Open person")
        GrammarRow("Jack Webb", { m -> PersonWindow(portrait, "Jack Webb", m) }, {}, sub = listOf("405 episodes"), openLabel = "Open person")
    }
}
