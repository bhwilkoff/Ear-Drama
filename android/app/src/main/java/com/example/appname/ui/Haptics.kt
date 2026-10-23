package com.example.appname.ui

import android.os.Build
import android.view.HapticFeedbackConstants
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalView
import com.example.appname.data.DownloadRecord

/**
 * The one haptic taxonomy (AGENTS.md), mapped to Android in one place.
 * `selection` accompanies a page or segment change; `success` a finished
 * download; `error` a surfaced error line.
 */
enum class Haptic {
    Selection, Light, Medium, Heavy, Success, Warning, Error;

    /** The `HapticFeedbackConstants` value for this event on API [sdk]; the named ones arrived in API 30. */
    fun feedbackConstant(sdk: Int): Int = when (this) {
        Selection -> if (sdk >= Build.VERSION_CODES.R) HapticFeedbackConstants.SEGMENT_TICK else HapticFeedbackConstants.CLOCK_TICK
        Light -> HapticFeedbackConstants.KEYBOARD_TAP
        Medium -> HapticFeedbackConstants.VIRTUAL_KEY
        Heavy -> HapticFeedbackConstants.LONG_PRESS
        Success -> if (sdk >= Build.VERSION_CODES.R) HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.VIRTUAL_KEY
        Warning -> HapticFeedbackConstants.LONG_PRESS
        Error -> if (sdk >= Build.VERSION_CODES.R) HapticFeedbackConstants.REJECT else HapticFeedbackConstants.LONG_PRESS
    }

    companion object {
        /** A download that finished is `success`; one that failed shows "Download failed" and is `error`. */
        fun forDownloads(before: Map<String, DownloadRecord.State>, after: Map<String, DownloadRecord.State>): Haptic? {
            val changed = after.filter { (id, state) -> before[id] != state && before[id] != null }.values
            return when {
                DownloadRecord.State.Failed in changed -> Error
                DownloadRecord.State.Downloaded in changed -> Success
                else -> null
            }
        }

        /** The player's problem line appearing is `error`; it staying or clearing is nothing. */
        fun forProblem(before: String?, after: String?): Haptic? = if (before == null && after != null) Error else null
    }
}

/** Plays [Haptic]s through the view the composition is attached to. */
@Composable
fun rememberHaptics(): (Haptic) -> Unit {
    val view = LocalView.current
    return remember(view) { { haptic -> view.performHapticFeedback(haptic.feedbackConstant(Build.VERSION.SDK_INT)) } }
}

/** The app-wide events: a download's end and the player's problem line. Composed once, in AppRoot. */
@Composable
fun HapticEvents() {
    val container = LocalAppContainer.current
    val haptics = rememberHaptics()
    val records by container.downloads.records.collectAsState()
    val states = records.mapValues { it.value.state }
    val previous = remember { arrayOfNulls<Map<String, DownloadRecord.State>>(1) }
    LaunchedEffect(states) {
        previous[0]?.let { before -> Haptic.forDownloads(before, states)?.let(haptics) }
        previous[0] = states
    }
    val now by container.playback.state.collectAsState()
    val lastProblem = remember { arrayOfNulls<String>(1) }
    val problem = now.problem
    LaunchedEffect(problem) {
        Haptic.forProblem(lastProblem[0], problem)?.let(haptics)
        lastProblem[0] = problem
    }
}
