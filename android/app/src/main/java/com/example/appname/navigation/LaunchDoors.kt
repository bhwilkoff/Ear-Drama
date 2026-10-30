package com.example.appname.navigation

import androidx.compose.runtime.staticCompositionLocalOf

/**
 * External entry points (deep links, test doors) are POSTED here by
 * MainActivity and drained by AppRoot — they never mutate navigation directly.
 */
sealed interface InboxRequest {
    data class Tab(val tab: String) : InboxRequest
    data class Item(val id: String) : InboxRequest
    data class Series(val key: String) : InboxRequest
    data class Search(val query: String) : InboxRequest
    data class Person(val id: String) : InboxRequest

    /** A Listen Together invitation: the sheet opens with [code] filled in; joining waits for Join. */
    data class Room(val code: String) : InboxRequest

    /** A shared ear drama's invitation (PLAYS-DESIGN §11.7): its page opens with the token held, signed in or not. */
    data class Invite(val token: String) : InboxRequest

    /** A finished ear drama's page (DEEP_LINKS.md `drama/{pid}`). */
    data class Drama(val pid: String) : InboxRequest

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
    /** APP_FORCE_OFFLINE: render the offline state (fakes the state, never the network). */
    val forceOffline: Boolean = false,
) {
    fun requests(): List<InboxRequest> =
        listOfNotNull(startTab?.let(InboxRequest::Tab), startItem?.let(InboxRequest::Item))

    companion object {
        const val EXTRA_START_TAB = "appname_start_tab"
        const val EXTRA_START_ITEM = "appname_start_item"
        const val EXTRA_MUTE = "appname_mute"
        const val EXTRA_DOOR_SECONDS = "appname_door_seconds"
        const val EXTRA_FORCE_OFFLINE = "appname_force_offline"

        /** [extras] is the intent's extras as a map; `am start` sends --es/--ez/--ei types. */
        fun from(extras: Map<String, Any?>, debug: Boolean): LaunchDoors {
            if (!debug) return LaunchDoors()
            return LaunchDoors(
                startTab = extras[EXTRA_START_TAB]?.toString(),
                startItem = extras[EXTRA_START_ITEM]?.toString(),
                mute = extras[EXTRA_MUTE].let { it == true || it == "1" || it == "true" },
                doorSeconds = extras[EXTRA_DOOR_SECONDS].let { it as? Int ?: it?.toString()?.toIntOrNull() },
                forceOffline = extras[EXTRA_FORCE_OFFLINE].let { it == true || it == "1" || it == "true" },
            )
        }
    }
}
