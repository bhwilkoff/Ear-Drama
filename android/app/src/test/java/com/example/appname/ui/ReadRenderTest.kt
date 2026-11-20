package com.example.appname.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.height
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
import com.example.appname.plays.PlayScript
import com.example.appname.plays.ReadClass
import com.example.appname.plays.ReadCore
import com.example.appname.plays.ReadSnapshot
import com.example.appname.plays.ReadState
import com.example.appname.plays.ScriptLine
import com.example.appname.plays.ShareJson
import com.example.appname.ui.screens.CastingBoardContent
import com.example.appname.ui.screens.ReadRoomContent
import com.example.appname.ui.screens.ReadScreenContent
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
 * Renders reading together (T4): a reader following a class room, the casting board, and the shared screen a TV pairs as,
 * light and dark. Runs only when GRAMMAR_RENDER_DIR names a directory:
 * `GRAMMAR_RENDER_DIR=/tmp/out ./gradlew testDebugUnitTest --tests '*ReadRenderTest'`.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35], qualifiers = "w412dp-h900dp-xhdpi")
class ReadRenderTest {
    @get:Rule val compose = createComposeRule()
    private lateinit var out: File

    @Before fun setUp() {
        val dir = System.getenv("GRAMMAR_RENDER_DIR")
        assumeTrue("GRAMMAR_RENDER_DIR not set", !dir.isNullOrBlank())
        out = File(dir!!).apply { mkdirs() }
        System.setProperty("roborazzi.test.record", "true")
    }

    private fun shoot(name: String, content: @Composable () -> Unit) {
        var dark by mutableStateOf(false)
        compose.setContent { AppTheme(darkTheme = dark) { Surface(color = MaterialTheme.colorScheme.background) { content() } } }
        listOf(false, true).forEach { d ->
            dark = d
            repeat(20) { compose.mainClock.advanceTimeBy(50); Thread.sleep(10) }
            compose.waitForIdle()
            compose.onRoot().captureRoboImage(File(out, "$name-${if (dark) "dark" else "light"}.png").path)
        }
    }

    private fun say(id: String, role: String, text: String) = ScriptLine(id, ScriptLine.Kind.Speech, role, listOf(LinePart.Say(text)))

    private val script = PlayScript(
        id = "fixture", revision = "r1", kind = "radio", title = "The Lost Lady",
        source = PlayScript.Source("Fixture", "https://example.org"), rights = PlayScript.Rights("script_source_cleared"),
        roles = listOf(PlayScript.Role("LUCY", 3, 21), PlayScript.Role("TOM", 3, 18), PlayScript.Role("NURSE", 1, 6)),
        lines = listOf(
            say("l1", "LUCY", "I thought you had gone out to the garden."),
            say("l2", "TOM", "The rain turned me back at the gate."),
            say("l3", "LUCY", "Then sit with me, and we will read the letter together."),
            say("l4", "NURSE", "Supper is on the table, if you please."),
            say("l5", "TOM", "Lucy, wait. Listen to that."),
            say("l6", "LUCY", "It is only the wind in the chimney."),
            say("l7", "TOM", "No. Someone is at the door."),
        ),
    )

    private fun snap(cursor: String, you: String = """{"id":"d1","role":"reader","seat":"s1","leads":false,"owner":false}""", next: String = """{"line":"l3","in":1}""") =
        ShareJson.decodeFromString(
            ReadSnapshot.serializer(),
            """{"type":"snapshot","code":"KLS456","kind":"class","mode":"read","script_id":"fixture","script_revision":"r1","cursor":"$cursor","cursor_gen":2,"generation":4,
            "locked":false,"ended":false,"leader":"teacher","leader_name":"Ms. Ortiz","read_open":false,"waiting_for_leader":false,"you":$you,"next_mine":$next,
            "reads_now":{"part":"role:TOM","seat":"s2","members":["d2"]},"members":[{"id":"teacher","role":"reader"},{"id":"d1","role":"reader","seat":"s1"},{"id":"d2","role":"reader","seat":"s2"}],
            "present":9,"claims":{},"seats":[{"id":"s1","label":"Ada"},{"id":"s2","label":"Ben"}],
            "assignments":[{"part":"role:LUCY","seat":"s1"},{"part":"role:TOM","seat":"s2"}],"done":[],"server_time":1763500000000}""",
        )

    @Test fun theReaderFollowsTheLitLine() = shoot("read-reader") {
        Column(Modifier.height(900.dp)) { ReadRoomContent(snap("l2"), ReadState(snapshot = snap("l2")), script, null) {} }
    }

    @Test fun theLeaderMovesIt() = shoot("read-leader") {
        val you = """{"id":"teacher","role":"reader","leads":true,"owner":true}"""
        Column(Modifier.height(900.dp)) { ReadRoomContent(snap("l2", you, "null"), ReadState(snapshot = snap("l2", you, "null")), script, null) {} }
    }

    @Test fun theSharedScreenAPaired_TvShows() = shoot("read-screen") {
        val you = """{"id":"tv","role":"screen","leads":false,"owner":false}"""
        Column(Modifier.height(900.dp)) { ReadScreenContent(ReadState(snapshot = snap("l3", you, "null")), script) }
    }

    @Test fun theCastingBoard() = shoot("read-casting") {
        val facts = ReadClass.Facts(script)
        val seats = listOf(ReadCore.Seat("s1", "Ada"), ReadCore.Seat("s2", "Ben"), ReadCore.Seat("s3", "Cleo"))
        val filled = ReadCore.fillEvenly(facts.facts, seats, listOf(ReadCore.Assignment("role:NURSE", "s3")), facts.cast, facts.words)
        Column(Modifier.height(900.dp)) {
            CastingBoardContent(facts, seats, filled, null, true, {}, { _, _ -> }, { _, _, _ -> }, {}, {}, {})
        }
    }
}
