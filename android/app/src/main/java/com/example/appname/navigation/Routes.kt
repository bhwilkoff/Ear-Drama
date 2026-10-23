package com.example.appname.navigation

import androidx.navigation3.runtime.NavKey
import kotlinx.serialization.Serializable

/** Every pushable destination; each tab keeps its own back stack of these. */
@Serializable
sealed interface Route : NavKey {
    @Serializable data object Listen : Route
    @Serializable data object SeriesBrowse : Route
    @Serializable data object Search : Route
    @Serializable data object Library : Route
    @Serializable data class Series(val key: String) : Route
    @Serializable data class Episode(val id: String) : Route
    @Serializable data class Transcript(val id: String) : Route
    @Serializable data object Plays : Route
    /** A castable script: its rights line, its parts, and "Cast this play". */
    @Serializable data class Script(val id: String) : Route
    /** A production's cast sheet. */
    @Serializable data class Production(val id: String) : Route
    /** One part being recorded, line by line; [part] is the raw `PartID`. */
    @Serializable data class Recording(val production: String, val part: String) : Route
}

/**
 * The tabs, in order; [name] is what the `appname_start_tab` door names. Plays
 * records, so it is not offered on a TV (ANDROID-DESIGN §3.1).
 */
enum class Tab(val label: String, val root: Route, val onTelevision: Boolean = true) {
    Listen("Listen", Route.Listen),
    Series("Series", Route.SeriesBrowse),
    Plays("Plays", Route.Plays, onTelevision = false),
    Search("Search", Route.Search),
    Library("Library", Route.Library),
    ;

    companion object {
        fun named(name: String): Tab? = entries.firstOrNull { it.name.equals(name, ignoreCase = true) }
    }
}
