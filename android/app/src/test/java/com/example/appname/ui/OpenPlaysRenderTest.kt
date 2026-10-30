package com.example.appname.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.height
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
import com.example.appname.plays.FinishedCredit
import com.example.appname.plays.FinishedList
import com.example.appname.plays.FinishedPlay
import com.example.appname.plays.OpenInvite
import com.example.appname.plays.OpenMember
import com.example.appname.plays.OpenPart
import com.example.appname.plays.OpenTake
import com.example.appname.ui.screens.DramaContent
import com.example.appname.ui.screens.EarDramasList
import com.example.appname.ui.screens.InviteContent
import com.example.appname.ui.screens.tile
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
 * Renders the invitation, the finished ear dramas and a drama's page (D3-7) to PNGs, light and dark. Runs only
 * when GRAMMAR_RENDER_DIR names a directory: `GRAMMAR_RENDER_DIR=/tmp/out ./gradlew testDebugUnitTest --tests '*OpenPlaysRenderTest'`.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35], qualifiers = "w412dp-h1000dp-xhdpi")
class OpenPlaysRenderTest {
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
        compose.setContent {
            AppTheme(darkTheme = dark) { Surface(color = MaterialTheme.colorScheme.background) { content() } }
        }
        listOf(false, true).forEach { d ->
            dark = d
            repeat(20) { compose.mainClock.advanceTimeBy(50); Thread.sleep(10) }
            compose.waitForIdle()
            compose.onRoot().captureRoboImage(File(out, "$name-${if (dark) "dark" else "light"}.png").path)
        }
    }

    private val invite = OpenInvite(
        id = "P1", scriptID = "hamlet", scriptRevision = "r1", title = "The Tell-Tale Heart",
        parts = listOf(
            OpenPart("role:NARRATOR", 24, "done", "Pat"),
            OpenPart("role:OLD MAN", 6, "recording", "Sam"),
            OpenPart("role:OFFICER", 9, "open"),
            OpenPart("directions", 4, "open"),
        ),
        members = listOf(OpenMember("Pat", true), OpenMember("Sam")),
        takes = listOf(OpenTake("t1", "L1", "role:NARRATOR", 4800, 48000.0, "/x")),
        next = "role:OFFICER",
    )

    private val idle = invite.copy(parts = invite.parts.map { if (it.status == "recording") it.copy(status = "done") else it })

    private fun page(signedIn: Boolean, member: Boolean = false, inv: OpenInvite = idle) = @Composable {
        Column(Modifier.height(900.dp)) {
            InviteContent(
                inv, script = null, signedIn = signedIn, member = member, playing = null, hearing = false, error = null,
                name = "", onName = {}, onPlayPart = {}, onListenAll = {}, onTake = {}, onOpen = {},
                contentPadding = PaddingValues(0.dp),
            )
        }
    }

    @Test fun inviteSignedOut() = shoot("invite-signed-out", page(false))
    @Test fun inviteSignedIn() = shoot("invite-signed-in", page(true))
    @Test fun inviteMember() = shoot("invite-member", page(true, member = true))
    @Test fun inviteSomeoneRecording() = shoot("invite-recording", page(false, inv = invite))

    private val dramas = listOf(
        FinishedPlay("d1", "s1", "The Tell-Tale Heart", null, listOf(FinishedCredit("role:NARRATOR", "Pat"), FinishedCredit("role:OLD MAN", "Sam"), FinishedCredit("role:OFFICER", "Ada"), FinishedCredit("role:CLERK", "Lee")), "https://archive.org/details/d1", 1_793_000_000_000),
        FinishedPlay("d2", "s2", "Hamlet", null, listOf(FinishedCredit("role:HAMLET", "Ada"), FinishedCredit("role:OPHELIA", "")), "https://archive.org/details/d2", 1_792_000_000_000),
        FinishedPlay("d3", "s3", "Sorry, Wrong Number", null, emptyList(), "https://archive.org/details/d3", 1_790_000_000_000),
    )

    @Test fun dramasScope() = shoot("dramas-scope") {
        Column(Modifier.height(900.dp)) { EarDramasList(FinishedList.State.Ready(dramas), {}, {}) }
    }

    @Test fun dramasStates() = shoot("dramas-states") {
        Column(Modifier.height(900.dp)) {
            Column(Modifier.height(200.dp)) { EarDramasList(FinishedList.State.Ready(emptyList()), {}, {}) }
            Column(Modifier.height(200.dp)) { EarDramasList(FinishedList.State.Failed(true), {}, {}) }
            Column(Modifier.height(200.dp)) { EarDramasList(FinishedList.State.Failed(false), {}, {}) }
        }
    }

    @Test fun homeShelf() = shoot("home-new-dramas") {
        Column(Modifier.padding(vertical = 12.dp)) {
            SectionHeading("New ear dramas") { TextLink("All 3", onClick = {}) }
            TileGrid(dramas.map { p -> p.tile {} })
        }
    }

    @Test fun dramaPage() = shoot("drama-page") {
        Column(Modifier.height(900.dp)) { DramaContent(dramas[0], PaddingValues(0.dp)) }
    }

    @Test fun dramaAudioStates() = shoot("drama-audio-states") {
        Column {
            Column(Modifier.height(560.dp)) { DramaContent(dramas[1], PaddingValues(0.dp), com.example.appname.plays.DramaAudio.Ready("https://x/a.mp3")) }
            Column(Modifier.height(300.dp)) { DramaContent(dramas[1].copy(credits = emptyList()), PaddingValues(0.dp), com.example.appname.plays.DramaAudio.Deriving) }
        }
    }
}
