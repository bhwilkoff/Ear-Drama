package com.example.appname.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.example.appname.ui.playButtonColors
import com.example.appname.plays.CastableLibrary
import com.example.appname.plays.PartID
import com.example.appname.plays.PartState
import com.example.appname.plays.PlayScript
import com.example.appname.plays.Production
import com.example.appname.plays.RecordingSession.Mode
import com.example.appname.plays.RecordingSession.Phase
import com.example.appname.plays.Take
import com.example.appname.ui.screens.CastRow
import com.example.appname.ui.screens.RecorderActions
import com.example.appname.ui.screens.RecorderUi
import com.example.appname.ui.screens.RecorderView
import com.example.appname.ui.screens.playPage
import com.example.appname.ui.theme.AppTheme
import com.github.takahirom.roborazzi.captureRoboImage
import java.io.File
import kotlin.math.abs
import kotlin.math.sin
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Renders the ear drama pages and the recorder in direction D (ANDROID-DESIGN §4.9a-b) to PNGs for a
 * human to read, light and dark: the play page, the cast sheet, and the recorder in Step ready,
 * recording and review, Run through playing, recording and review, and Line by line, idle and
 * recording. Runs only when GRAMMAR_RENDER_DIR names a directory (as GrammarRenderTest does). The
 * play is the bundled Caesar Rodney's Ride, as the prototype's; nothing plays or records.
 */
abstract class PlaysRenderBase {
    @get:Rule val compose = createComposeRule()

    private lateinit var out: File
    protected lateinit var script: PlayScript

    @Before fun setUp() {
        val dir = System.getenv("GRAMMAR_RENDER_DIR")
        assumeTrue("GRAMMAR_RENDER_DIR not set", !dir.isNullOrBlank())
        out = File(dir!!).apply { mkdirs() }
        System.setProperty("roborazzi.test.record", "true")
        val library = CastableLibrary.decode(File("../../catalog/plays/castable-scripts.json").readText())
        val found = library.scripts.firstOrNull { it.id == "gut-28051" }
        assumeTrue("the bundled Caesar Rodney's Ride is not in the file", found != null)
        script = found!!
    }

    protected val rodney = PartID.role("RODNEY")

    private var started = false
    private var dark by mutableStateOf(false)
    private var sceneName by mutableStateOf("")
    private var scene by mutableStateOf<(@Composable () -> Unit)?>(null)

    protected fun shoot(name: String, content: @Composable () -> Unit) {
        scene = content
        sceneName = name
        if (!started) {
            started = true
            compose.setContent {
                AppTheme(darkTheme = dark) {
                    Surface(color = MaterialTheme.colorScheme.background) { key(sceneName) { scene?.invoke() } }
                }
            }
        }
        listOf(false, true).forEach { d ->
            dark = d
            repeat(30) { compose.mainClock.advanceTimeBy(50); Thread.sleep(20) }
            compose.waitForIdle()
            compose.onRoot().captureRoboImage(File(out, "$name-${if (d) "dark" else "light"}.png").path)
        }
    }

    /** The prototype's production: Pat holds Uriah, Sam McKeen, Ada Franklin, Lou is recording Rodney, the rest are open. */
    protected fun production(takenBefore: Int = 5, extraTakes: Int = 0, bleedAt: Int = -1): Pair<Production, Int> {
        var p = Production.create(script)
        p = p.withPart(PartID.role("URIAH"), PartState(PartState.Status.Done, "Pat"))
            .withPart(PartID.role("MCKEEN"), PartState(PartState.Status.Done, "Sam"))
            .withPart(PartID.role("FRANKLIN"), PartState(PartState.Status.Done, "Ada"))
            .withPart(rodney, PartState(PartState.Status.Recording, "Lou"))
        val mine = script.lines(rodney)
        val here = mine.indexOfFirst { it.spokenText.startsWith("July first. Why") }.coerceAtLeast(takenBefore)
        mine.take(here).forEachIndexed { i, line -> p = p.add(take("t$i", line.id, i == bleedAt)) }
        repeat(extraTakes) { n -> p = p.add(take("x$n", mine[here].id, false, 2.4 + n)) }
        return p to here
    }

    private fun take(id: String, line: String, bleed: Boolean, seconds: Double = 3.1) =
        Take(id, line, rodney, "$id.wav", 0.0, (seconds * 48_000).toInt(), 48_000.0, Take.Capture.Direct, emptyMap(), -16.0, 0.5f, bleed)

    protected val wave: suspend (Take) -> FloatArray? = { t ->
        val phase = abs(t.id.hashCode() % 7).toDouble()
        FloatArray(72) { i -> (0.25 + 0.75 * abs(sin(i * 0.55 + phase))).toFloat() }
    }

    private val meter = List(30) { i -> (0.15 + 0.85 * abs(sin(i * 0.5))).toFloat() }

    private fun ui(
        p: Production,
        index: Int,
        phase: Phase,
        mode: Mode,
        runTakes: List<Take> = emptyList(),
        running: Boolean = false,
        seconds: Int = 0,
    ) = RecorderUi(script, rodney, p, phase, mode, runTakes, running, index, meter, seconds)

    private fun recorder(name: String, width: Dp, height: Dp, build: (Production, Int) -> RecorderUi) {
        val (p, here) = when {
            name.contains("review") && name.startsWith("recorder-step") -> production(extraTakes = 2)
            name.contains("run-review") -> production(takenBefore = 2, bleedAt = 3)
            else -> production()
        }
        shoot(name) {
            Box(Modifier.width(width).height(height)) {
                RecorderView(build(p, here), RecorderActions(loadWave = wave), Modifier.fillMaxSize())
            }
        }
    }

    fun recorderStates(suffix: String, width: Dp, height: Dp) {
        val cueLine = { p: Production, here: Int ->
            script.lines.let { all -> val mine = all.first { it.id == script.lines(rodney)[here].id }; all[all.indexOf(mine) - 1].id }
        }
        recorder("recorder-step-ready$suffix", width, height) { p, here -> ui(p, here, Phase.Idle, Mode.Step) }
        recorder("recorder-step-cue$suffix", width, height) { p, here -> ui(p, here, Phase.Cue(cueLine(p, here), true), Mode.Step) }
        recorder("recorder-step-recording$suffix", width, height) { p, here ->
            ui(p, here, Phase.Listening(script.lines(rodney)[here].id), Mode.Step, seconds = 2)
        }
        recorder("recorder-step-review$suffix", width, height) { p, here -> ui(p, here, Phase.Review(script.lines(rodney)[here].id), Mode.Step) }
        recorder("recorder-run-playing$suffix", width, height) { p, here ->
            ui(p, here, Phase.Cue(cueLine(p, here), true, run = true), Mode.Run, runTakes = p.takes.takeLast(2), running = true)
        }
        recorder("recorder-run-recording$suffix", width, height) { p, here ->
            ui(p, here, Phase.Listening(script.lines(rodney)[here].id, run = true), Mode.Run, runTakes = p.takes.takeLast(3), running = true, seconds = 2)
        }
        recorder("recorder-run-review$suffix", width, height) { p, _ ->
            ui(p, 3, Phase.RunReview, Mode.Run, runTakes = p.takes.takeLast(3), running = true)
        }
        recorder("recorder-lines$suffix", width, height) { p, here -> ui(p, here, Phase.Idle, Mode.Lines) }
        recorder("recorder-lines-recording$suffix", width, height) { p, here ->
            ui(p, here, Phase.Listening(script.lines(rodney)[here].id), Mode.Lines, seconds = 2)
        }
    }

    fun pages(suffix: String, width: Dp) {
        shoot("play-page$suffix") {
            Box(Modifier.width(width).height(1500.dp)) {
                LazyColumn(Modifier.fillMaxSize()) {
                    playPage(script, television = false, onOpenProduction = {}, start = { Button(onClick = {}, colors = playButtonColors()) { Text("Start an ear drama") } })
                }
            }
        }
        shoot("cast-sheet$suffix") {
            val (p, _) = production()
            Box(Modifier.width(width).height(1500.dp)) {
                LazyColumn(Modifier.fillMaxSize()) {
                    item { PlayHeadBoard(script, "Ear drama", title = script.title) }
                    item {
                        ActionRow(Modifier.padding(16.dp)) {
                            Button(onClick = {}, colors = playButtonColors()) { Text("Listen through") }
                            OutlinedButton(onClick = {}) { Text("Invite") }
                        }
                    }
                    item {
                        PartGrid(script.castParts) { part, m ->
                            CastRow(
                                script = script, part = part, production = p, modifier = m,
                                isNext = part.id == script.castParts.first { p.state(it.id).status == PartState.Status.Open }.id,
                                canTake = false, canReopen = true,
                                onRecord = {}, onTake = {}, onLeaveSilent = {}, onReopen = {},
                            )
                        }
                    }
                    item { Box(Modifier.fillMaxWidth().padding(16.dp)) { Text("Script: Project Gutenberg.", style = MaterialTheme.typography.labelMedium) } }
                }
            }
        }
    }
}

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35], qualifiers = "w412dp-h900dp-xhdpi")
class PlaysRenderTest : PlaysRenderBase() {
    @Test fun phonePages() = pages("-412", 412.dp)
    @Test fun phoneRecorder() = recorderStates("-412", 412.dp, 880.dp)
}

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35], qualifiers = "w840dp-h900dp-xhdpi")
class PlaysRender840Test : PlaysRenderBase() {
    @Test fun widePages() = pages("-840", 840.dp)
    @Test fun wideRecorder() = recorderStates("-840", 840.dp, 800.dp)
}
