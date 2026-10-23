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
}

/** The four tabs, in order; [name] is what the `appname_start_tab` door names. */
enum class Tab(val label: String, val root: Route) {
    Listen("Listen", Route.Listen),
    Series("Series", Route.SeriesBrowse),
    Search("Search", Route.Search),
    Library("Library", Route.Library),
    ;

    companion object {
        fun named(name: String): Tab? = entries.firstOrNull { it.name.equals(name, ignoreCase = true) }
    }
}
