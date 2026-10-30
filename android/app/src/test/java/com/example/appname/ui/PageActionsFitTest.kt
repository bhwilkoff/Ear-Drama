package com.example.appname.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.example.appname.ui.theme.AppTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * R11d: a page's button row never wraps apart. At every phone width the buttons share one line,
 * stay inside the row and keep a touch target; the same check fails a row that is allowed to wrap
 * (the negative control).
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35], qualifiers = "w700dp-h900dp-xhdpi")
class PageActionsFitTest {
    @get:Rule val compose = createComposeRule()

    private var shown by mutableStateOf(320.dp)
    private var started = false

    private fun show(width: Dp, content: @Composable () -> Unit) {
        shown = width
        if (!started) {
            started = true
            compose.setContent { AppTheme(darkTheme = false) { Box(Modifier.width(shown).padding(16.dp)) { content() } } }
        }
        compose.waitForIdle()
    }

    private fun problems(width: Dp): List<String> {
        val px = with(compose.density) { width.toPx() }
        val floor = with(compose.density) { 40.dp.toPx() - 1 }
        val rects = compose.onAllNodes(hasClickAction()).fetchSemanticsNodes().map { it.boundsInRoot }
        val out = mutableListOf<String>()
        if (rects.size < 2) out += "only ${rects.size} buttons found"
        val centers = rects.map { (it.top + it.bottom) / 2 }
        if (centers.max() - centers.min() > 4) out += "not on one line: $centers"
        rects.forEach {
            if (it.right > px + 1) out += "pushed past the row: $it"
            if (it.width < floor || it.height < floor) out += "under a touch target: $it"
        }
        return out
    }

    @Composable private fun EpisodeRowOf() {
        ActionRow(foldBelow = 600.dp) { fit ->
            Button(onClick = {}, modifier = Modifier.weight(1f)) {
                Icon(Icons.Filled.PlayArrow, contentDescription = null)
                Text(if (fit.tight) "Resume" else "Resume at 12:34", maxLines = 1)
            }
            FoldButton(Icons.Filled.Add, "Add to queue", fit.folded, {})
            FoldButton(Icons.Filled.Share, "Share", fit.folded, {}, description = "Share Sorry, Wrong Number")
            FoldButton(Icons.Outlined.Download, "Download", fit.folded, {})
        }
    }

    @Composable private fun SeriesRowOf() {
        ActionRow { fit ->
            Button(onClick = {}, modifier = Modifier.weight(1f)) {
                Icon(Icons.Filled.Add, contentDescription = null)
                Text("Following", maxLines = 1)
            }
            FoldButton(Icons.Filled.Share, "Share", fit.folded, {}, description = "Share Counterrevolutionary Hour")
        }
    }

    @Test fun `the episode row holds one line from 320 to 599 dp`() {
        listOf(320, 360, 375, 412, 480, 599).forEach { w ->
            show(w.dp) { EpisodeRowOf() }
            assertEquals("episode row at $w dp", emptyList<String>(), problems(w.dp))
        }
    }

    @Test fun `the series row holds one line from 320 to 479 dp`() {
        listOf(320, 360, 412, 479).forEach { w ->
            show(w.dp) { SeriesRowOf() }
            assertEquals("series row at $w dp", emptyList<String>(), problems(w.dp))
        }
    }

    @OptIn(ExperimentalLayoutApi::class)
    @Test fun `control - a row allowed to wrap fails the check at 320 dp`() {
        show(320.dp) {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = {}) { Text("Resume at 12:34") }
                FoldButton(Icons.Filled.Add, "Add to queue", false, {})
                FoldButton(Icons.Filled.Share, "Share", false, {})
                FoldButton(Icons.Outlined.Download, "Download", false, {})
            }
        }
        assertTrue("the check must catch a wrapped row", problems(320.dp).any { it.startsWith("not on one line") })
    }
}
