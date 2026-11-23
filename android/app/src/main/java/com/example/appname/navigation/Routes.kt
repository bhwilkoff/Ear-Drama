package com.example.appname.navigation

import androidx.navigation3.runtime.NavKey
import kotlinx.serialization.Serializable

/** Every pushable destination; each tab keeps its own back stack of these. */
@Serializable
sealed interface Route : NavKey {
    /** Home (ANDROID-DESIGN §4.1; was Listen). */
    @Serializable data object Listen : Route
    /** Browse: series and plays together (§4.2; was Series). */
    @Serializable data object SeriesBrowse : Route
    /** Stations: Tonight in 19xx (§4.10), pushed from Home's On the air and Listen door (§3.1). */
    @Serializable data object Radio : Route
    /** Record (§4.9a, Decision 075): your productions, today's play, the plays. Not on a TV. */
    @Serializable data object Record : Route
    @Serializable data object Search : Route
    @Serializable data object Library : Route
    /** Library's Downloads place (§4.6), by series. */
    @Serializable data object Downloads : Route
    /** A full list from Library (direction B): [kind] is `upnext` or `history`. */
    @Serializable data class LibraryList(val kind: String) : Route
    /** One play's productions, opened from Library's Making side (one row per play). */
    @Serializable data class PlayProductions(val scriptId: String) : Route
    @Serializable data class Series(val key: String) : Route
    @Serializable data class Episode(val id: String) : Route
    /** A person's page (`withPerson`, §4.15), pushed from Detail's credits or Search. */
    @Serializable data class Person(val id: String) : Route
    @Serializable data class Transcript(val id: String) : Route
    /** Surprise, pushed from Home's top bar (§4.14). */
    @Serializable data object Surprise : Route
    /** A castable script: its rights line, its parts, and "Start an ear drama". */
    @Serializable data class Script(val id: String) : Route
    /**
     * The script reader (ANDROID-DESIGN §4.17), full screen over the tab bar; [lineId] opens at that line, else where this
     * device left off. With [productionId] and [part] (a raw `PartID`) the studio is attached (PLAYS-DESIGN §2.9): the script
     * is the production's own copy, and the part's lines record in the page.
     */
    @Serializable data class Reader(
        val scriptId: String,
        val lineId: String? = null,
        val productionId: String? = null,
        val part: String? = null,
        /** Read along (PLAYS-DESIGN §2.11): with [productionId] and no [part], the reader follows the production's listen-through. */
        val along: Boolean = false,
        /** With [along] and no [productionId]: a finished drama's production id; the reader follows its line files (§2.11 rule 11). */
        val drama: String? = null,
    ) : Route
    /** A production's cast sheet. */
    @Serializable data class Production(val id: String) : Route
    /** The invitation page for the token the session holds (never in the key: a token is not saved state). */
    @Serializable data object Invitation : Route
    /** A finished ear drama's page. */
    @Serializable data class Drama(val id: String) : Route
    /** A read room (DEEP_LINKS.md `read/{CODE}`): a reader on a phone or tablet; the shared screen on a TV or with [screen]. */
    @Serializable data class ReadRoom(val code: String, val screen: Boolean = false, val seat: String? = null) : Route
    /** A Google TV's Show a reading: it shows a pairing code and becomes the room's screen once a leader adds it (ANDROID-DESIGN §4.19). */
    @Serializable data object ReadPair : Route
    /** The teacher's class page and its casting board (PLAYS-DESIGN §12.4). Not on a TV. */
    @Serializable data class ClassPage(val id: String) : Route
    @Serializable data class ClassCasting(val classId: String, val productionId: String) : Route
    /** A seat's parts at home and each take's state (PLAYS-DESIGN §12.11). Not on a TV. */
    @Serializable data object Parts : Route
    /** The recorder before the studio moved into the reader (S3): no door opens it any more; [part] is the raw `PartID`. */
    @Serializable data class Recording(val production: String, val part: String, val line: String? = null) : Route
}

/**
 * The tabs, in order (Decision 068: sections are actions, as Archive Watch);
 * [name] is what the `appname_start_tab` door names. Surprise is not a tab: Home's
 * top bar opens it (ANDROID-DESIGN §3.1).
 */
enum class Tab(val label: String, val root: Route) {
    Home("Home", Route.Listen),
    Browse("Browse", Route.SeriesBrowse),
    Record("Record", Route.Record),
    Search("Search", Route.Search),
    Library("Library", Route.Library),
    ;

    companion object {
        /** The names before Decision 075 still open: listen, series, plays (now Record). */
        private val RENAMED = mapOf("listen" to Home, "series" to Browse, "plays" to Record)

        /** Doors that open Home and then push a screen that is no longer a tab (Decision 075). */
        fun pushedFromHome(name: String): Route? = when (name.lowercase()) {
            "radio", "stations" -> Route.Radio
            "surprise" -> Route.Surprise
            else -> null
        }

        fun named(name: String): Tab? =
            entries.firstOrNull { it.name.equals(name, ignoreCase = true) } ?: RENAMED[name.lowercase()]
    }
}
