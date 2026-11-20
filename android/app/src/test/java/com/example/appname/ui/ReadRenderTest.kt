package com.example.appname.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.height
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import io.mockk.coEvery
import io.mockk.mockk
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import com.example.appname.app.AppContainer
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
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
import com.example.appname.plays.MarkDao
import com.example.appname.plays.MarkEntity
import com.example.appname.plays.ProductionStore
import com.example.appname.plays.ReadClassWire
import com.example.appname.plays.ReadJoined
import com.example.appname.plays.ReadRecord
import com.example.appname.plays.ReadSession
import com.example.appname.plays.ReadSnapshot
import com.example.appname.plays.ReadWire
import com.example.appname.plays.Take
import com.example.appname.plays.PartID
import com.example.appname.plays.temporaryRoot
import com.example.appname.plays.ReadState
import com.example.appname.plays.ScriptLine
import com.example.appname.plays.ShareJson
import com.example.appname.ui.screens.CastingBoardContent
import com.example.appname.ui.LocalAppContainer
import com.example.appname.ui.LocalIsTelevision
import com.example.appname.ui.screens.PairContent
import com.example.appname.ui.screens.ReaderBody
import com.example.appname.ui.screens.RoomSeam
import com.example.appname.ui.screens.TakesContent
import com.example.appname.ui.screens.ClassReviewRow
import com.example.appname.plays.ClassReviewItem
import com.example.appname.plays.SharedTake
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

    private fun shoot(name: String, settle: Int = 20, content: @Composable () -> Unit) {
        var dark by mutableStateOf(false)
        compose.setContent { AppTheme(darkTheme = dark) { Surface(color = MaterialTheme.colorScheme.background) { content() } } }
        listOf(false, true).forEach { d ->
            dark = d
            repeat(settle) { compose.mainClock.advanceTimeBy(50); Thread.sleep(if (settle > 20) 40 else 10) }
            compose.waitForIdle()
            compose.onRoot().captureRoboImage(File(out, "$name-${if (dark) "dark" else "light"}.png").path)
        }
    }

    /** Composed in the dark from the first frame, so a theme that is not rebuilt on toggle cannot hide a defect. */
    private fun shootDark(name: String, settle: Int, content: @Composable () -> Unit) {
        compose.setContent { AppTheme(darkTheme = true) { Surface(color = MaterialTheme.colorScheme.background) { content() } } }
        repeat(settle) { compose.mainClock.advanceTimeBy(50); Thread.sleep(40) }
        compose.waitForIdle()
        compose.onRoot().captureRoboImage(File(out, "$name-dark-fresh.png").path)
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

    private class NoMarks : MarkDao() {
        override suspend fun marksFor(scriptId: String): List<MarkEntity> = emptyList()
        override suspend fun all(): List<MarkEntity> = emptyList()
        override suspend fun deleteFor(scriptId: String) {}
        override suspend fun insertAll(rows: List<MarkEntity>) {}
    }

    /** An adult room as Ann sees it in Record mode: Lucy is hers; Ben holds Tom and is the receiver. */
    private fun adult(cursor: String, you: String, next: String, mode: String = "record", reads: String = """{"part":"role:TOM","holder":"host","members":["host"]}""") = ShareJson.decodeFromString(
        ReadSnapshot.serializer(),
        """{"type":"snapshot","code":"ABC123","kind":"adult","mode":"$mode","script_id":"fixture","script_revision":"r1","cursor":"$cursor","cursor_gen":2,"generation":4,
        "locked":false,"ended":false,"leader":"host","leader_name":"Ben","read_open":false,"waiting_for_leader":false,"you":$you,"next_mine":$next,
        "reads_now":$reads,"members":[{"id":"host","role":"reader","name":"Ben"},{"id":"ann","role":"reader","name":"Ann"}],
        "receiver":"host","present":2,"claims":{"role:LUCY":"ann","role:TOM":"host"},"seats":[],"assignments":[],"done":["l1"],"server_time":1763500000000}""",
    )

    private val ann = """{"id":"ann","role":"reader","name":"Ann","leads":false,"owner":false,"receives":false}"""
    private val ben = """{"id":"host","role":"reader","name":"Ben","leads":true,"owner":true,"receives":true}"""

    private fun seamFor(snap: ReadSnapshot, scope: CoroutineScope): RoomSeam {
        val wire = mockk<ReadWire>(relaxed = true)
        coEvery { wire.poll(any(), any()) } returns snap
        val session = ReadSession(wire, scope)
        session.adopt(ReadJoined(snap, "key", "poll"))
        session.pause()
        val record = ReadRecord(wire, session, ProductionStore(temporaryRoot()), script, scope, engineFor = { error("no microphone in a render") })
        return RoomSeam(session, record, mockk<ReadClassWire>(relaxed = true), scope, {}, {})
    }

    private fun theReader(name: String, snap: ReadSnapshot) = shoot(name, settle = 120) {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        val seam = remember { seamFor(snap, scope) }
        CompositionLocalProvider(LocalAppContainer provides mockk<AppContainer>(relaxed = true)) {
            ReaderBody(script, snap.cursor, null, {}, { _, _, _ -> }, room = seam, marksDao = NoMarks())
        }
    }

    /** The room inside the real reader: pages, the lit line, my lines tinted, the fact, and the Record row's Start recording. */
    @Test fun theReaderFollowsTheLitLine() = theReader("read-reader", adult("l2", ann, """{"line":"l3","in":1}"""))

    @Test fun theReaderInTheDark() = shootDark("read-reader", 120) {
        val snap = adult("l2", ann, """{"line":"l3","in":1}""")
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        val seam = remember { seamFor(snap, scope) }
        CompositionLocalProvider(LocalAppContainer provides mockk<AppContainer>(relaxed = true)) {
            ReaderBody(script, snap.cursor, null, {}, { _, _, _ -> }, room = seam, marksDao = NoMarks())
        }
    }

    @Test fun theLeaderMovesIt() = theReader("read-leader", adult("l3", ben, """{"line":"l5","in":2}""", reads = """{"part":"role:LUCY","holder":"ann","members":["ann"]}"""))

    /** The receiver's Takes: counts per reader, each line's state, Play and Again. */
    @Test fun theTakesSheet() = shoot("read-takes", settle = 40) {
        val snap = adult("l5", ben, """{"line":"l5","in":0}""")
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        val seam = remember { seamFor(snap, scope) }
        val store = remember { ProductionStore(temporaryRoot()) }
        val local = remember {
            var p = store.create(script).copy(room = "ABC123")
            p = p.add(Take("a1", "l1", PartID.role("LUCY"), "a1.wav", 0.0, 4_800, 48_000.0, Take.Capture.Room, emptyMap(), null, 0.1f, false, member = "ann"))
            p = p.add(Take("a2", "l2", PartID.role("TOM"), "a2.wav", 0.0, 4_800, 48_000.0, Take.Capture.Room, emptyMap(), null, 0.1f, false, member = "host"))
            p
        }
        CompositionLocalProvider(LocalAppContainer provides mockk<AppContainer>(relaxed = true)) {
            Column(Modifier.height(900.dp)) { TakesContent(seam, snap, script, script.lines.map { it.id to it.part.raw }, local, null, store, {}) }
        }
    }

    /** The receiver's Takes in a class production: Approve and one Again that offers an optional note. */
    @Test fun theTakesSheetInAClass() = shoot("read-takes-class", settle = 40) {
        val leader = """{"id":"teacher","role":"reader","name":"Ms. Ortiz","leads":true,"owner":true,"receives":true}"""
        val snap = snap("l5", leader, """{"line":"l5","in":0}""").copy(productionId = "P1")
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        val seam = remember { seamFor(snap, scope) }
        val store = remember { ProductionStore(temporaryRoot()) }
        val local = remember {
            var p = store.create(script).copy(room = "KLS456")
            p = p.add(Take("a1", "l1", PartID.role("LUCY"), "a1.wav", 0.0, 4_800, 48_000.0, Take.Capture.Room, emptyMap(), null, 0.1f, false, member = "d1"))
            p = p.add(Take("a2", "l2", PartID.role("TOM"), "a2.wav", 0.0, 4_800, 48_000.0, Take.Capture.Room, emptyMap(), null, 0.1f, false, member = "d2"))
            p
        }
        CompositionLocalProvider(LocalAppContainer provides mockk<AppContainer>(relaxed = true)) {
            Column(Modifier.height(900.dp)) { TakesContent(seam, snap, script, script.lines.map { it.id to it.part.raw }, local, null, store, {}) }
        }
    }

    /** The class page's review queue: takes recorded at home that reached the teacher's app, each waiting for Approve or Again. */
    @Test fun theClassReviewQueue() = shoot("class-review") {
        fun item(id: String, line: String, part: String, seat: String) =
            ClassReviewItem("p1", "The Lost Lady", SharedTake(id, line, part, "$id.wav", seat = seat))
        Column(Modifier.padding(16.dp)) {
            Text("Review", style = MaterialTheme.typography.titleMedium)
            ClassReviewRow(item("r1", "l1", "role:LUCY", "s1"), "Ada", PartID("role:LUCY").title, script.lines[0].spokenText, canPlay = true)
            ClassReviewRow(item("r2", "l2", "role:TOM", "s2"), "Ben", PartID("role:TOM").title, script.lines[1].spokenText, canPlay = false)
        }
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

    /** A Google TV before a leader has added it: the code large, split 3 + 3, one line, one Leave. */
    @Config(sdk = [35], qualifiers = "w960dp-h540dp-xhdpi")
    @Test fun theTvPairingScreen() = shoot("read-pair-tv") {
        CompositionLocalProvider(LocalIsTelevision provides true) { PairContent("K7M4PD", null, {}) }
    }
}
