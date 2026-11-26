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
import com.example.appname.kokoro.Kokoro
import com.example.appname.plays.CastVoice
import com.example.appname.plays.VoiceCasting
import com.example.appname.plays.VoiceDefaults
import com.example.appname.ui.screens.KokoroUi
import com.example.appname.ui.screens.VoiceSettingsActions
import com.example.appname.ui.screens.voicesItems
import androidx.compose.foundation.lazy.LazyColumn
import com.example.appname.ui.screens.VoiceSettingsUi
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
 * Renders Library's Voices section (Decision 086) in each state of the Kokoro download, and the
 * picker's Default row, light and dark. Runs only when GRAMMAR_RENDER_DIR names a directory:
 * `GRAMMAR_RENDER_DIR=/tmp/out ./gradlew :app:testDebugUnitTest --tests '*SettingsRenderTest'`. Nothing speaks or downloads.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35], qualifiers = "w412dp-h900dp-xhdpi")
class SettingsRenderTest {
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
            compose.waitForIdle()
            compose.onRoot().captureRoboImage(File(out, "$name-${if (dark) "dark" else "light"}.png").path)
        }
    }

    private val device = listOf(
        CastVoice("en-us-x-tpd-local", "English (United States) 1", "en-US", 400),
        CastVoice("en-gb-x-rjs-local", "English (United Kingdom)", "en-GB", 300),
        CastVoice("en-us-x-sfg-local", "English (United States) 2", "en-US", 300),
    )
    private val kokoro = Kokoro.castable(true).let { all -> all.take(4) + all.filter { it.offByDefault }.take(1) }

    private fun ui(k: KokoroUi, here: Boolean) = VoiceSettingsUi(
        k, VoiceDefaults(), VoiceCasting.ordered((if (here) kokoro else emptyList()) + device, VoiceDefaults()),
        hearing = if (here) "kokoro:af_heart" else null,
    )

    @Test fun absent() = shoot("android-settings-absent") { LazyColumn { voicesItems(ui(KokoroUi.Absent(126_000_000), false), VoiceSettingsActions()) } }

    @Test fun downloading() = shoot("android-settings-downloading") {
        LazyColumn { voicesItems(ui(KokoroUi.Progress(48_000_000, 126_000_000), false), VoiceSettingsActions()) }
    }

    @Test fun ready() = shoot("android-settings-ready") { LazyColumn { voicesItems(ui(KokoroUi.Ready(107_000_000), true), VoiceSettingsActions()) } }

    @Test fun unsupported() = shoot("android-settings-unsupported") { LazyColumn { voicesItems(ui(KokoroUi.Unsupported, false), VoiceSettingsActions()) } }

    // The Better voices step (§4.6b): the sheet's content as the ModalBottomSheet draws it.
    @Test fun voicesStep() = shoot("android-voices-step") {
        VoicesStepContent(KokoroUi.Absent(126_000_000), VoiceSettingsActions(), freeBytes = 20_000_000_000, systemVoicesLine = true, onOpenSettings = {}, onClose = {})
    }

    @Test fun voicesStepLowSpace() = shoot("android-voices-step-low") {
        VoicesStepContent(KokoroUi.Absent(126_000_000), VoiceSettingsActions(), freeBytes = 98_000_000, systemVoicesLine = false, onOpenSettings = {}, onClose = {})
    }

    @Test fun voicesStepDownloading() = shoot("android-voices-step-downloading") {
        VoicesStepContent(KokoroUi.Progress(34_000_000, 126_000_000), VoiceSettingsActions(), freeBytes = 20_000_000_000, systemVoicesLine = false, onOpenSettings = {}, onClose = {})
    }

    @Test fun voicesStepReady() = shoot("android-voices-step-ready") {
        VoicesStepContent(KokoroUi.Ready(107_000_000), VoiceSettingsActions(), freeBytes = 20_000_000_000, systemVoicesLine = false, onOpenSettings = {}, onClose = {})
    }

    @Test fun pickerDefaultRow() = shoot("android-picker-default") {
        Column(Modifier.padding(top = 16.dp)) {
            Text("LUCY", Modifier.padding(horizontal = 16.dp), style = MaterialTheme.typography.headlineSmall)
            VoiceRow("Default", "Heart (Kokoro)", true, "default", false, "Default", onHear = null) {}
            VoiceRow("Heart (Kokoro)", null, false, "af_heart", false, "af_heart", onHear = {}) {}
            VoiceRow("English (United States) 1", "High quality", false, "tpd", false, "tpd", onHear = {}) {}
        }
    }
}
