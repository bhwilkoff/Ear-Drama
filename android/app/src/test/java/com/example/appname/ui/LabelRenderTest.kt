package com.example.appname.ui

import android.graphics.Bitmap
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.example.appname.data.LabelItem
import com.example.appname.data.LabelKind
import com.example.appname.data.LabelPart
import com.example.appname.ui.theme.AppTheme
import com.github.takahirom.roborazzi.captureRoboImage
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The label (Decision 081) drawn to PNG so a person can look at it against the web's sheet
 * (docs/research/design/img/v3/label-sheet-*.png). Runs only when GRAMMAR_RENDER_DIR names a directory:
 * `GRAMMAR_RENDER_DIR=/tmp/out ./gradlew testDebugUnitTest --tests '*LabelRenderTest'`.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35], qualifiers = "w1100dp-h1000dp-xhdpi")
class LabelRenderTest {
    @get:Rule val compose = createComposeRule()

    private val suspense = LabelItem(LabelKind.Series, "Suspense", "mystery", "1942-06-17", "1962-09-30", "CBS")
    private val gunsmoke = LabelItem(LabelKind.Series, "Gunsmoke", "western", "1952", "1961", "CBS")
    private val xminus = LabelItem(LabelKind.Series, "X Minus One", "scifi", "1955", "1958", "NBC")
    private val ranger = LabelItem(LabelKind.Series, "Ranger Bill", "drama")
    private val plain = LabelItem(LabelKind.Series, "The Case Closed")
    private val episode = LabelItem(LabelKind.Episode, "Suspense", "mystery", "1942-06-17", "1962-09-30", "CBS", date = "1949-03-03")
    private val numbered = LabelItem(LabelKind.Episode, "Ranger Bill", "drama", num = "7")
    private val station = LabelItem(LabelKind.Station, genre = "comedy", tickYear = "1939")
    private val lady = LabelItem(
        LabelKind.Drama, "The Lost Lady", parts = listOf(LabelPart(50, "mystery"), LabelPart(42, "scifi"), LabelPart(20, "western")),
        finished = "2026-11-03",
    )
    private val person = LabelItem(LabelKind.Person, "Orson Welles", first = "1934", last = "1946")
    private val cast = LabelItem(LabelKind.Play, cast = listOf(120, 80, 40, 30, 10, 5, 5, 3, 2))

    @androidx.compose.runtime.Composable
    private fun Tile(item: LabelItem, side: Dp) {
        val shape = if (item.kind == LabelKind.Person) CircleShape else RoundedCornerShape(4.dp)
        LabelArt(item, Modifier.size(side).clip(shape))
    }

    @OptIn(ExperimentalLayoutApi::class)
    @Test fun labelSheet() {
        val dir = System.getenv("GRAMMAR_RENDER_DIR")
        assumeTrue("GRAMMAR_RENDER_DIR not set", !dir.isNullOrBlank())
        val out = File(dir!!).apply { mkdirs() }
        System.setProperty("roborazzi.test.record", "true")
        var dark by mutableStateOf(false)
        val row = listOf(suspense, xminus, ranger, plain, episode, numbered, station, lady, person, cast)
        compose.setContent {
            AppTheme(darkTheme = dark) {
                Surface(color = MaterialTheme.colorScheme.background) {
                    FlowRow(
                        Modifier.fillMaxWidth().padding(24.dp),
                        horizontalArrangement = Arrangement.spacedBy(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp),
                    ) {
                        Tile(suspense, 320.dp); Tile(episode, 320.dp)
                        listOf(gunsmoke, lady, person, cast).forEach { Tile(it, 200.dp) }
                        row.forEach { Tile(it, 128.dp) }
                        row.forEach { Tile(it, 56.dp) }
                        Tile(suspense, 40.dp)
                    }
                }
            }
        }
        listOf(false, true).forEach { d ->
            dark = d
            compose.waitForIdle()
            compose.onRoot().captureRoboImage(File(out, "label-sheet-android${if (d) "-dark" else ""}.png").path)
        }
        val lock = labelBitmap(androidx.test.core.app.ApplicationProvider.getApplicationContext(), episode, 512).asAndroidBitmap()
        File(out, "lock-screen-android.png").outputStream().use { lock.compress(Bitmap.CompressFormat.PNG, 100, it) }
        assertEquals(512, lock.width)
    }
}
