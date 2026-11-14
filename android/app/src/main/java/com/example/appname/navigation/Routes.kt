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
    @Serializable data class Series(val key: String) : Route
    @Serializable data class Episode(val id: String) : Route
    /** A person's page (`withPerson`, §4.15), pushed from Detail's credits or Search. */
    @Serializable data class Person(val id: String) : Route
    @Serializable data class Transcript(val id: String) : Route
    /** Surprise, pushed from Home's top bar (§4.14). */
    @Serializable data object Surprise : Route
    /** A castable script: its rights line, its parts, and "Start an ear drama". */
    @Serializable data class Script(val id: String) : Route
    /** The script reader (ANDROID-DESIGN §4.17), full screen over the tab bar; [lineId] opens at that line, else where this device left off. */
    @Serializable data class Reader(val scriptId: String, val lineId: String? = null) : Route
    /** A production's cast sheet. */
    @Serializable data class Production(val id: String) : Route
    /** The invitation page for the token the session holds (never in the key: a token is not saved state). */
    @Serializable data object Invitation : Route
    /** A finished ear drama's page. */
    @Serializable data class Drama(val id: String) : Route
    /** One part being recorded, line by line; [part] is the raw `PartID`. [line] set: replacing that one line on a published play (P12). */
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
