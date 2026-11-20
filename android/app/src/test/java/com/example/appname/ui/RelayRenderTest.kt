package com.example.appname.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
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
import com.example.appname.plays.LinePart
import com.example.appname.plays.PartID
import com.example.appname.plays.RelayCore
import com.example.appname.plays.ScriptLine
import com.example.appname.ui.screens.RelayLines
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
 * Renders a seat's parts at home (T6, PLAYS-DESIGN §12.11): the lines with each take's state, waiting on this device,
 * then sent with the teacher's review, light and dark. Runs only when GRAMMAR_RENDER_DIR names a directory:
 * `GRAMMAR_RENDER_DIR=/tmp/out ./gradlew :app:testDebugUnitTest --tests '*RelayRenderTest'`. Nothing records or plays.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35], qualifiers = "w412dp-h700dp-xhdpi")
class RelayRenderTest {
    @get:Rule val compose = createComposeRule()
    private lateinit var out: File

    @Before fun setUp() {
        val dir = System.getenv("GRAMMAR_RENDER_DIR")
        assumeTrue("GRAMMAR_RENDER_DIR not set", !dir.isNullOrBlank())
        out = File(dir!!).apply { mkdirs() }
        System.setProperty("roborazzi.test.record", "true")
    }

    private fun say(id: String, text: String) = ScriptLine(id, ScriptLine.Kind.Speech, "LUCY", listOf(LinePart.Say(text)))

    private val lines = listOf(
        say("l1", "I thought you had gone out to the garden, Tom."),
        say("l3", "Then sit with me, and we will read the letter together."),
        say("l6", "It is only the wind in the chimney, nothing more."),
        say("l8", "Come, sit. The tea is still warm in the pot."),
    )

    private fun rows(sent: Boolean) = lines.mapIndexed { i, l ->
        when {
            sent && i == 0 -> RelayCore.Row(l.id, RelayCore.excerpt(l), "Sent", "Approved")
            sent && i == 1 -> RelayCore.Row(l.id, RelayCore.excerpt(l), "Sent", "Again · Slower at the end.", true)
            sent && i == 2 -> RelayCore.Row(l.id, RelayCore.excerpt(l), "Sent")
            !sent && i < 3 -> RelayCore.Row(l.id, RelayCore.excerpt(l), RelayCore.wording(RelayCore.State.Waiting, "Ms. Ortiz", "your teacher"))
            else -> RelayCore.Row(l.id, RelayCore.excerpt(l))
        }
    }

    private fun shoot(name: String, content: @Composable () -> Unit) {
        var dark by mutableStateOf(false)
        compose.setContent { AppTheme(darkTheme = dark) { Surface(color = MaterialTheme.colorScheme.background) { content() } } }
        listOf(false, true).forEach { d ->
            dark = d
            compose.waitForIdle()
            compose.onRoot().captureRoboImage(File(out, "$name-${if (dark) "dark" else "light"}.png").path)
        }
    }

    @Composable
    private fun Page(rows: List<RelayCore.Row>) {
        Column(Modifier.padding(16.dp)) {
            Text("Lucy · Room 7", style = MaterialTheme.typography.titleMedium)
            Text("The Lost Lady", style = MaterialTheme.typography.titleSmall)
            Text("${PartID.role("LUCY").title} · 4 lines", style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(top = 8.dp))
            RelayLines(rows)
        }
    }

    @Test fun waiting() = shoot("android-relay-waiting") { Page(rows(sent = false)) }

    @Test fun sentAndReviewed() = shoot("android-relay-sent") { Page(rows(sent = true)) }
}
