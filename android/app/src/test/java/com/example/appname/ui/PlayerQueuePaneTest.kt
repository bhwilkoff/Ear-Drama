package com.example.appname.ui

import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import com.example.appname.data.EpisodeRow
import com.example.appname.plays.ReaderMath
import com.example.appname.ui.screens.PLAYER_PANES_FROM
import com.example.appname.ui.screens.PlayerQueuePane
import com.example.appname.ui.theme.AppTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * B21 (ANDROID-DESIGN §5.3): at 860 dp the player has a second pane, the engine's own queue: each row names its episode and
 * show, a tap plays that row, an empty queue draws the heading alone. The switch is the reader's and the studio's own.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35], qualifiers = "w900dp-h700dp-xhdpi")
class PlayerQueuePaneTest {
    @get:Rule val compose = createComposeRule()

    private fun ep(id: String, show: String, title: String) = EpisodeRow(id, id, show, "1943-06-17", null, null, title, null)

    @Test fun theSwitchIsTheReadersAndTheStudios() {
        assertEquals(ReaderMath.SPREAD_MIN, PLAYER_PANES_FROM)
    }

    @Test fun eachQueuedRowNamesItsShowAndATapPlaysIt() {
        val played = mutableListOf<String>()
        val rows = listOf(ep("a", "Suspense", "The Lodger"), ep("b", "Lux Radio Theatre", "Rebecca"))
        compose.setContent { AppTheme(darkTheme = false) { PlayerQueuePane(rows, onPlay = { played += it.id }) } }
        compose.onNodeWithText("Up next").assertExists()
        compose.onNodeWithText("Suspense").assertExists()
        compose.onNodeWithText("Lux Radio Theatre").assertExists()
        compose.onNodeWithText("Rebecca").performClick()
        assertEquals(listOf("b"), played)
    }

    @Test fun anEmptyQueueDrawsTheHeadingAlone() {
        compose.setContent { AppTheme(darkTheme = false) { PlayerQueuePane(emptyList(), onPlay = {}) } }
        compose.onNodeWithText("Up next").assertExists()
        compose.onAllNodes(hasClickAction()).assertCountEquals(0)
    }
}
