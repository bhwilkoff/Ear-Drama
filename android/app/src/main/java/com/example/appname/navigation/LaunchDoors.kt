package com.example.appname.navigation

import androidx.compose.runtime.staticCompositionLocalOf

/**
 * External entry points (deep links, test doors) are POSTED here by
 * MainActivity and drained by AppRoot — they never mutate navigation directly.
 */
sealed interface InboxRequest {
    data class Tab(val tab: String) : InboxRequest
    data class Item(val id: String) : InboxRequest

    /** APP_DOOR_SECONDS elapsed: end the door's activity (stop playback, leave the room). */
    data object EndDoor : InboxRequest
}

/** Player-level mute. Every player reads it, so a harness run is silent unless it opts in. */
val LocalPlayerMuted = staticCompositionLocalOf { false }

/**
 * Test doors: intent extras that open a screen directly
 * (`adb shell am start -n <debug pkg>/.MainActivity --es appname_start_tab home`).
 * Names are tools/app_config.py's hooks via android_extra(): APP_START_TAB ->
 * appname_start_tab. Only honoured when [from] is told the build is DEBUG, and
 * a harness must install the DEBUG build — against release they do nothing.
 */
data class LaunchDoors(
    val startTab: String? = null,
    val startItem: String? = null,
    val mute: Boolean = false,
    val doorSeconds: Int? = null,
) {
    fun requests(): List<InboxRequest> =
        listOfNotNull(startTab?.let(InboxRequest::Tab), startItem?.let(InboxRequest::Item))

    companion object {
        const val EXTRA_START_TAB = "appname_start_tab"
        const val EXTRA_START_ITEM = "appname_start_item"
        const val EXTRA_MUTE = "appname_mute"
        const val EXTRA_DOOR_SECONDS = "appname_door_seconds"

        /** [extras] is the intent's extras as a map; `am start` sends --es/--ez/--ei types. */
        fun from(extras: Map<String, Any?>, debug: Boolean): LaunchDoors {
            if (!debug) return LaunchDoors()
            return LaunchDoors(
                startTab = extras[EXTRA_START_TAB]?.toString(),
                startItem = extras[EXTRA_START_ITEM]?.toString(),
                mute = extras[EXTRA_MUTE].let { it == true || it == "1" || it == "true" },
                doorSeconds = extras[EXTRA_DOOR_SECONDS].let { it as? Int ?: it?.toString()?.toIntOrNull() },
            )
        }
    }
}
