package com.example.appname.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.isDialog
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.unit.dp
import com.example.appname.plays.AgeGate
import com.example.appname.plays.ClassRow
import com.example.appname.ui.screens.AgeQuestionDialog
import com.example.appname.ui.screens.AgeRefusalDialog
import com.example.appname.ui.screens.ClassDateDialog
import com.example.appname.ui.screens.ClassItemContent
import com.example.appname.ui.screens.ClassSection
import com.example.appname.ui.screens.DestructiveConfirm
import com.example.appname.ui.screens.PublishConfirmations
import com.example.appname.ui.screens.SchoolApproval
import com.example.appname.ui.theme.AppTheme
import com.github.takahirom.roborazzi.captureRoboImage
import java.io.File
import java.time.LocalDate
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Renders student privacy (PLAYS-DESIGN §12.12): the Class section, School approval, the publish confirmations, the class
 * list's idle notice, and the dialogs, light and dark. Runs only when GRAMMAR_RENDER_DIR names a directory.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35], qualifiers = "w412dp-h900dp-xhdpi")
class PrivacyRenderTest {
    @get:Rule val compose = createComposeRule()
    private lateinit var out: File

    @Before fun setUp() {
        val dir = System.getenv("GRAMMAR_RENDER_DIR")
        assumeTrue("GRAMMAR_RENDER_DIR not set", !dir.isNullOrBlank())
        out = File(dir!!).apply { mkdirs() }
        System.setProperty("roborazzi.test.record", "true")
    }

    private fun shoot(name: String, dialog: Boolean = false, content: @Composable () -> Unit) {
        var dark by mutableStateOf(false)
        compose.setContent { AppTheme(darkTheme = dark) { Surface(color = MaterialTheme.colorScheme.background) { content() } } }
        listOf(false, true).forEach { d ->
            dark = d
            repeat(20) { compose.mainClock.advanceTimeBy(50); Thread.sleep(10) }
            compose.waitForIdle()
            val target = if (dialog) compose.onNode(isDialog()) else compose.onRoot()
            target.captureRoboImage(File(out, "$name-${if (dark) "dark" else "light"}.png").path)
        }
    }

    @Composable private fun Page(content: @Composable () -> Unit) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(16.dp)) { content() }
    }

    @Test fun classSection() = shoot("android-class-section") {
        Page { ClassSection(endsOn = "2027-06-12", busy = false, onChangeDate = {}, onExport = {}, onDelete = {}) }
    }

    @Test fun schoolApproval() = shoot("android-school-approval") {
        Page { SchoolApproval(busy = false, error = null, onRecord = {}, initialChecked = true, initialReference = "Dr. Reyes, Westside District, approval 2026-114") }
    }

    @Test fun publishConfirmations() = shoot("android-publish-confirmations") {
        Page { PublishConfirmations(performers = true, onPerformers = {}, released = false, onReleased = {}) }
    }

    @Test fun classListRow() = shoot("android-class-list-row") {
        Page {
            ClassItemContent(ClassRow("c1", "Period 3 English", code = "ABCD2345", deletesOn = "2027-02-01"), listOf("ABCD 2345"))
            ClassItemContent(ClassRow("c2", "Drama Club", code = "WXYZ6789"), listOf("WXYZ 6789"))
        }
    }

    @Test fun ageQuestion() = shoot("android-age-question", dialog = true) {
        AgeQuestionDialog(AgeGate.years(2026), onContinue = {}, onCancel = {})
    }

    @Test fun ageRefusal() = shoot("android-age-refusal", dialog = true) { AgeRefusalDialog {} }

    @Test fun deleteClass() = shoot("android-delete-class", dialog = true) {
        DestructiveConfirm("Delete Period 3 English? Its names, casting and notes are deleted. Published plays stay.", "Delete class", {}, {})
    }

    @Test fun changeDate() = shoot("android-change-date", dialog = true) {
        ClassDateDialog(endsOn = "2027-06-12", today = LocalDate.of(2026, 11, 21), onPick = {}, onDismiss = {})
    }
}
