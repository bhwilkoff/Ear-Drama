package com.example.appname.navigation

import com.example.appname.plays.ReadCore
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

    /** DEBUG door `appname_start_read`: the reader on a play, at [line] when given. */
    data class Read(val id: String, val line: String? = null, val studioPart: String? = null) : InboxRequest

    /** DEBUG door `appname_start_read_along`: a production's reader with its Read along started (PLAYS-DESIGN 2.11 rule 1). */
    data class ReadAlong(val pid: String) : InboxRequest

    /** DEBUG door `appname_start_along`: a finished drama's page with Listen pressed, so its read-along follows the files (a TV too). */
    data class Along(val pid: String) : InboxRequest

    /** A read room by code (DEEP_LINKS.md `read/{CODE}`); [screen] opens it as the shared screen; [seat] is the DEBUG seat door. */
    data class ReadRoom(val code: String, val screen: Boolean = false, val seat: String? = null) : InboxRequest

    /** `read/pair` or the DEBUG door `appname_start_read_pair`: a TV's pairing screen. */
    data object ReadPair : InboxRequest

    /** `parts` (`https://eardrama.org/parts`): the "Your parts" screen, a seat's parts at home. Not on a TV. */
    data object Parts : InboxRequest

    /** A text another app shared or opened here (ANDROID-DESIGN §4.23 item 1): Add a script, with it in the field. Not on a TV. */
    data class AddScript(val incoming: com.example.appname.ui.screens.OwnIncoming) : InboxRequest

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
    /** `play-id` or `play-id@L0042`. */
    val startRead: String? = null,
    /** `appname_start_studio`: a role name; with [startRead], presses Record in the reader for that part (the studio). */
    val startStudio: String? = null,
    /** `appname_studio_stub`: the studio's engine opens no microphone and plays nothing (DEBUG frames, never real room audio). */
    val studioStub: Boolean = false,
    /** `appname_studio_phase`: with the stub, `listening` starts a take on the current line, `takes` opens the take list. */
    val studioPhase: String? = null,
    /**
     * `appname_start_along`: a finished production's id; its drama page opens and Listen is pressed (muted with the mute door).
     * `rehearsal` or `rehearsal:<script id>` needs no finished drama (none is published yet): the page opens over a bundled
     * script and the panel steps through its lines on a timer, playing nothing.
     */
    val startAlong: String? = null,
    /** `appname_start_read_along`: a production's id; its reader opens and reads along at once (muted with the mute door). */
    val startReadAlong: String? = null,
    /** `appname_start_read_room`: a read room's code. `appname_start_seat` is `<class code>:<seat id or label>`; `appname_start_screen` opens it as the shared screen. */
    val startReadRoom: String? = null,
    val startSeat: String? = null,
    val startScreen: Boolean = false,
    /** `appname_start_read_part`: a role name (or `role:NAME`) claimed once the reader is in the room; `appname_start_read_record` then arms Record (use with `appname_studio_stub`). */
    val startReadPart: String? = null,
    val startReadRecord: Boolean = false,
    /** `appname_start_read_pair`: the TV's pairing screen (Show a reading). */
    val startReadPair: Boolean = false,
    /** `appname_empty_library`: Library drawn as a new listener's; draws only, never writes or deletes stored data. */
    val emptyLibrary: Boolean = false,
    /** APP_SKIP_ONBOARD (`appname_skip_onboard`): the Better voices step stays away (UI tests, harness frames). */
    val skipOnboard: Boolean = false,
    /** `appname_voices_step`: the Better voices step at launch, without reading or writing its record (§4.6b). */
    val voicesStep: Boolean = false,
    /** `appname_play_query` and `appname_play_picks` (`voices=1-2,form=comedy`): Record's Plays opens with that search and those facets; `appname_browse_scope` (`plays`): Browse opens on that scope. */
    val playQuery: String? = null,
    val playPicks: String? = null,
    val browseScope: String? = null,
) {
    fun requests(): List<InboxRequest> =
        listOfNotNull(
            startTab?.let(InboxRequest::Tab),
            // A series key has no `|`; an episode id always does (Apple's door reads it the same way).
            startItem?.let { if ('|' in it) InboxRequest.Item(it) else InboxRequest.Series(it) },
            startReadRoom?.let { ReadCore.normalizeCode(it) }?.let { InboxRequest.ReadRoom(it, startScreen, startSeat) },
            if (startReadPair) InboxRequest.ReadPair else null,
            startAlong?.takeIf { it.isNotBlank() }?.let { InboxRequest.Along(alongPid(it)) },
            startReadAlong?.takeIf { it.isNotBlank() }?.let { InboxRequest.ReadAlong(it) },
            startRead?.let {
                InboxRequest.Read(
                    it.substringBefore('@'), it.substringAfter('@', "").ifEmpty { null },
                    studioPart = startStudio?.takeIf { s -> s.isNotBlank() }?.let { s ->
                        if (s == com.example.appname.plays.PartID.DIRECTIONS.raw || s == com.example.appname.plays.PartID.SOUND.raw) s else com.example.appname.plays.PartID.role(s).raw
                    },
                )
            },
        )

    companion object {
        const val REHEARSAL_PREFIX = "door-along:"

        /** The drama id the door opens: a production's own, or the rehearsal's `door-along:auto` / `door-along:<script id>`. */
        fun alongPid(value: String): String =
            if (value.startsWith("rehearsal")) REHEARSAL_PREFIX + value.substringAfter(':', "auto").ifBlank { "auto" } else value

        const val EXTRA_START_TAB = "appname_start_tab"
        const val EXTRA_START_ITEM = "appname_start_item"
        const val EXTRA_MUTE = "appname_mute"
        const val EXTRA_DOOR_SECONDS = "appname_door_seconds"
        const val EXTRA_FORCE_OFFLINE = "appname_force_offline"
        const val EXTRA_START_READ = "appname_start_read"
        const val EXTRA_START_STUDIO = "appname_start_studio"
        const val EXTRA_STUDIO_STUB = "appname_studio_stub"
        const val EXTRA_STUDIO_PHASE = "appname_studio_phase"
        const val EXTRA_START_ALONG = "appname_start_along"
        const val EXTRA_START_READ_ALONG = "appname_start_read_along"
        const val EXTRA_START_READ_ROOM = "appname_start_read_room"
        const val EXTRA_START_SEAT = "appname_start_seat"
        const val EXTRA_START_SCREEN = "appname_start_screen"
        const val EXTRA_START_READ_PART = "appname_start_read_part"
        const val EXTRA_START_READ_RECORD = "appname_start_read_record"
        const val EXTRA_START_READ_PAIR = "appname_start_read_pair"
        const val EXTRA_EMPTY_LIBRARY = "appname_empty_library"
        const val EXTRA_SKIP_ONBOARD = "appname_skip_onboard"
        const val EXTRA_VOICES_STEP = "appname_voices_step"
        const val EXTRA_PLAY_QUERY = "appname_play_query"
        const val EXTRA_PLAY_PICKS = "appname_play_picks"
        const val EXTRA_BROWSE_SCOPE = "appname_browse_scope"
        const val EXTRA_READ_DIAG = "appname_read_diag"
        const val EXTRA_WORKER_URL = "appname_worker_url"
        private val BENCH_HOST = Regex("""^http://(10\.\d+\.\d+\.\d+|192\.168\.\d+\.\d+|172\.(1[6-9]|2\d|3[01])\.\d+\.\d+|localhost|127\.0\.0\.1):\d+$""")

        /**
         * DEBUG `appname_worker_url=http://<this Mac on the home network>:<port>`: the read bench's local `wrangler dev`
         * (tools/read_bench.py --base, tools/class_bench.py). Plain http to a private address only. Set once by MainActivity
         * before the Worker client is made; null in a release build.
         */
        @Volatile var workerUrl: String? = null

        /** DEBUG `appname_read_diag`: the read session prints its transport, cursor delay and clock offset. Set once by MainActivity. */
        @Volatile var diag = false

        /** [extras] is the intent's extras as a map; `am start` sends --es/--ez/--ei types. */
        fun from(extras: Map<String, Any?>, debug: Boolean): LaunchDoors {
            if (!debug) return LaunchDoors()
            diag = extras[EXTRA_READ_DIAG].let { it == true || it == "1" || it == "true" }
            workerUrl = extras[EXTRA_WORKER_URL]?.toString()?.takeIf { BENCH_HOST.matches(it) }
            return LaunchDoors(
                startTab = extras[EXTRA_START_TAB]?.toString(),
                startItem = extras[EXTRA_START_ITEM]?.toString(),
                mute = extras[EXTRA_MUTE].let { it == true || it == "1" || it == "true" },
                doorSeconds = extras[EXTRA_DOOR_SECONDS].let { it as? Int ?: it?.toString()?.toIntOrNull() },
                forceOffline = extras[EXTRA_FORCE_OFFLINE].let { it == true || it == "1" || it == "true" },
                startRead = extras[EXTRA_START_READ]?.toString(),
                startStudio = extras[EXTRA_START_STUDIO]?.toString(),
                studioStub = extras[EXTRA_STUDIO_STUB].let { it == true || it == "1" || it == "true" },
                studioPhase = extras[EXTRA_STUDIO_PHASE]?.toString(),
                startAlong = extras[EXTRA_START_ALONG]?.toString(),
                startReadAlong = extras[EXTRA_START_READ_ALONG]?.toString(),
                startReadRoom = extras[EXTRA_START_READ_ROOM]?.toString()?.takeIf { it.isNotBlank() },
                startSeat = extras[EXTRA_START_SEAT]?.toString()?.takeIf { it.isNotBlank() },
                startScreen = extras[EXTRA_START_SCREEN].let { it == true || it == "1" || it == "true" },
                startReadPart = extras[EXTRA_START_READ_PART]?.toString()?.takeIf { it.isNotBlank() },
                startReadRecord = extras[EXTRA_START_READ_RECORD].let { it == true || it == "1" || it == "true" },
                startReadPair = extras[EXTRA_START_READ_PAIR].let { it == true || it == "1" || it == "true" },
                emptyLibrary = extras[EXTRA_EMPTY_LIBRARY].let { it == true || it == "1" || it == "true" },
                skipOnboard = extras[EXTRA_SKIP_ONBOARD].let { it == true || it == "1" || it == "true" },
                voicesStep = extras[EXTRA_VOICES_STEP].let { it == true || it == "1" || it == "true" },
                playQuery = extras[EXTRA_PLAY_QUERY]?.toString()?.takeIf { it.isNotBlank() },
                playPicks = extras[EXTRA_PLAY_PICKS]?.toString()?.takeIf { it.isNotBlank() },
                browseScope = extras[EXTRA_BROWSE_SCOPE]?.toString()?.takeIf { it.isNotBlank() },
            )
        }
    }
}

/** DEBUG doors for finding a play (B31): Record's initial search and facet picks, Browse's initial scope. Set once by MainActivity; never set in release. */
object FindDoor {
    @Volatile var query: String? = null
    @Volatile var picks: String? = null
    @Volatile var scope: String? = null

    /** `voices=1-2,form=comedy` as picks. */
    fun picksOf(text: String?): Map<String, String> =
        text.orEmpty().split(',').mapNotNull { p -> p.split('=', limit = 2).takeIf { it.size == 2 && it[0].isNotBlank() }?.let { it[0].trim() to it[1].trim() } }.toMap()
}

/**
 * What the DEBUG doors say about the studio's engine, set once by MainActivity and read where the studio is built. Never set
 * in a release build, so the microphone is always the real one there.
 */
object StudioDoor {
    @Volatile var stub = false
    @Volatile var phase: String? = null
}

/** DEBUG doors `appname_start_read_part` / `_read_record`, set once by MainActivity; the room bar reads them once. Never set in release. */
object ReadRoomDoor {
    @Volatile var part: String? = null
    @Volatile var record = false
}

/** Set by the Along door when it opens a drama: the page presses Listen once, then clears it. Never set in release. */
object AlongDoor {
    @Volatile var autoplay: String? = null
}

/** DEBUG door `appname_empty_library`, set once by MainActivity; Library only reads it to draw. Never set in release. */
object LibraryDoor {
    @Volatile var empty = false
}

/** DEBUG doors `appname_skip_onboard` and `appname_voices_step`, set once by MainActivity; the root reads them. Never set in release. */
object VoicesStepDoor {
    @Volatile var skip = false
    @Volatile var force = false
}
