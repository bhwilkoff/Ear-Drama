package com.example.appname.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.unit.dp
import com.example.appname.plays.LinePart
import com.example.appname.plays.OwnSounds
import com.example.appname.plays.PartID
import com.example.appname.plays.PartState
import com.example.appname.plays.PlayScript
import com.example.appname.plays.Production
import com.example.appname.plays.SoundBlock
import com.example.appname.plays.SoundSlot
import com.example.appname.ui.screens.partWho
import com.example.appname.plays.ScriptLine
import com.example.appname.plays.SoundCore
import com.example.appname.plays.SoundCue
import com.example.appname.plays.SoundSource
import com.example.appname.ui.screens.BoardActions
import com.example.appname.ui.screens.BoardModel
import com.example.appname.ui.screens.InCueRow
import com.example.appname.ui.screens.LineRow
import com.example.appname.ui.screens.MINE
import com.example.appname.ui.screens.PackUi
import com.example.appname.ui.screens.SoundBoard
import com.example.appname.ui.screens.SoundDock
import com.example.appname.ui.screens.StudioGate
import com.example.appname.ui.theme.AppTheme
import com.github.takahirom.roborazzi.captureRoboImage
import java.io.File
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Draws the sound board and the Sound part's page (B32 batch D, ANDROID-DESIGN §4.17) light and dark: the page of Caesar Rodney's
 * Ride (Gutenberg 28051, lines L0172 to L0191, the words of the real library through `b32-proto/data.js`) with its cue slots, a
 * bed's rule in the margin and the dock; the board over it with a chosen sound and a bed, the search seeded from the cue, the
 * pack's categories; Mine empty; a search with no match. The pack is the web's fixture manifest (`tools/fixtures/sounds`); the
 * real pack waits on its hosting. Runs only when GRAMMAR_RENDER_DIR names a directory:
 * `GRAMMAR_RENDER_DIR=/tmp/out ./gradlew :app:testDebugUnitTest --tests '*SoundRenderTest'`. Nothing records or plays.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35], qualifiers = "w412dp-h900dp-xhdpi")
class SoundRenderTest {
    @get:Rule val compose = createComposeRule()
    private lateinit var out: File

    @Before fun setUp() {
        val dir = System.getenv("GRAMMAR_RENDER_DIR")
        assumeTrue("GRAMMAR_RENDER_DIR not set", !dir.isNullOrBlank())
        out = File(dir!!).apply { mkdirs() }
        System.setProperty("roborazzi.test.record", "true")
    }

    private val lines: List<ScriptLine> = run {
        val text = File("../../docs/research/design/b32-proto/data.js").readText().substringAfter("const DATA = ").trimEnd().removeSuffix(";")
        val rodney = Json.parseToJsonElement(text).jsonObject.getValue("rodney").jsonObject.getValue("lines").jsonArray
        rodney.map { Json { ignoreUnknownKeys = true }.decodeFromJsonElement(ScriptLine.serializer(), it) }
            .dropWhile { it.id != "L0172" }.takeWhile { it.id != "L0192" }
    }

    private val script = PlayScript(
        id = "gut-28051", revision = "1", kind = "radio", title = "Caesar Rodney's Ride",
        source = PlayScript.Source("Project Gutenberg", "https://www.gutenberg.org/ebooks/28051"),
        rights = PlayScript.Rights("castable"), lines = lines,
    )

    private val pack = SoundCore.readManifest(Json.parseToJsonElement(File("../../tools/fixtures/sounds/sounds.json").readText()))
    private val packUi = PackUi.Ready(pack.cues, pack.categories, here = setOf("weather", "doors"))

    private fun shoot(name: String, content: @Composable () -> Unit) {
        var dark by mutableStateOf(false)
        compose.setContent { AppTheme(darkTheme = dark) { Surface(color = MaterialTheme.colorScheme.background) { content() } } }
        listOf(false, true).forEach { d ->
            dark = d
            compose.waitForIdle()
            compose.onRoot().captureRoboImage(File(out, "$name-${if (dark) "dark" else "light"}.png").path)
        }
    }

    private fun cue(id: String, src: SoundSource, at: String, until: String? = null, loop: Boolean = false, fadeIn: Double = 0.0, fadeOut: Double = 0.0) =
        SoundCue(id = id, src = src, at = at, until = until, loop = loop, fadeInMs = fadeIn, fadeOutMs = fadeOut)

    private val thunder = cue("C1", SoundSource("eardrama-sounds-1", "thunder-close"), "after")
    private val rain = cue("C2", SoundSource("eardrama-sounds-1", "rain-steady"), "bed", until = "L0191", loop = true, fadeIn = 1500.0, fadeOut = 2000.0)

    private val slot13 = SoundCore.Slot("S1", "S1", "L0180", 1, false, "another peal of thunder closer", false, listOf(thunder, rain))
    private val slot14 = SoundCore.Slot("S2", "S2", "L0180", 2, false, "sound of rain and wind", false, emptyList())
    private val first = SoundCore.Slot("S0", "S0", "L0172", 1, false, "sound of horses' hoofs and thunder", false, emptyList())

    @Composable
    private fun Page() {
        val slots = listOf(first, slot13, slot14)
        val bed = (lines.indexOfFirst { it.id == "L0180" }..lines.indexOfFirst { it.id == "L0191" }).toSet()
        Column(Modifier.fillMaxSize()) {
            Column(Modifier.weight(1f)) {
                lines.take(11).forEachIndexed { i, line ->
                    LineRow(
                        line = line, mine = slots.filter { it.line == line.id }, bed = i in bed, currentKey = "S1", picking = false,
                        numberOf = { k -> slots.indexOfFirst { it.key == k } + 1 }, menu = false, onMenu = {}, onTap = {}, onSlot = {}, onAdd = {},
                    )
                }
            }
            SoundDock(
                headline = "Cue 2 of 3 · Thunder, close · After", hasCue = true, recording = false, gate = StudioGate.Ready, started = false,
                roomTone = false, roomToneLeft = 0, failure = null, onBoard = {}, onPrevious = {}, onNext = {}, onRecord = {},
                onSettings = {}, onCheckHeadphones = {}, onWithout = {},
            )
        }
    }

    private val rows = listOf(
        InCueRow("C1", "Thunder, close", "0:01 · ${SoundCore.placeLine(thunder)}", selected = false),
        InCueRow("C2", "Steady rain", "0:02 · ${SoundCore.placeLine(rain, "line 20")}", selected = true),
    )

    private fun board(query: String, category: String?, mine: List<OwnSounds.Sound> = emptyList(), selected: SoundCue? = rain, inCue: List<InCueRow> = rows, pack: PackUi = packUi) = BoardModel(
        headline = "Cue 2 of 3 · URIAH", words = "another peal of thunder closer", silent = false, inCue = inCue, selected = selected,
        untilLabel = "line 20", laneDuckDb = -12.0, query = query, category = category, pack = pack,
        inCueIds = setOf("thunder-close", "rain-steady"), mine = mine,
    )

    @Composable
    private fun Sheet(model: BoardModel) {
        Surface(color = MaterialTheme.colorScheme.surfaceContainerLow, modifier = Modifier.fillMaxWidth()) {
            Column(Modifier.padding(top = 12.dp), verticalArrangement = Arrangement.spacedBy(0.dp)) {
                SoundBoard(model, BoardActions())
            }
        }
    }

    @Test fun page() = shoot("android-page") { Page() }

    /** The cast sheet's last cards: Sound with its cue rows and what is chosen, then Stage directions. */
    @Test fun castSheet() = shoot("android-cast") {
        val block = SoundBlock(1, slots = listOf(SoundSlot("S1", "L0180", 1, false, false, listOf(thunder, rain))))
        val made = Production.create(script, "P").copy(
            parts = script.castParts.associate { it.id to PartState() } + (PartID.SOUND to PartState(PartState.Status.Recording)),
            sound = block,
        )
        Column(Modifier.padding(top = 16.dp)) {
            PartGrid(script.castParts.takeLast(4)) { part, modifier ->
                PartCard(
                    script, part, Holder.DeviceVoice, recorded = false, modifier = modifier, who = partWho(part, made, script),
                    highlight = part.id == PartID.SOUND,
                )
            }
        }
    }

    @Test fun boardWithSounds() = shoot("android-board") { Sheet(board("thunder", null)) }

    @Test fun boardMineEmpty() = shoot("android-board-mine") { Sheet(board("", MINE, selected = null, inCue = emptyList())) }

    @Test fun boardNoMatch() = shoot("android-board-nomatch") { Sheet(board("zeppelin", null, selected = null, inCue = emptyList())) }

    @Test fun boardLoading() = shoot("android-board-loading") { Sheet(board("", null, selected = null, inCue = emptyList(), pack = PackUi.Loading)) }

    @Test fun boardAbsent() = shoot("android-board-absent") { Sheet(board("", null, selected = null, inCue = emptyList(), pack = PackUi.Absent)) }
}
