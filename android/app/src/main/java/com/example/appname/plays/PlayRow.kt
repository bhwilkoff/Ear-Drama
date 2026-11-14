package com.example.appname.plays

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * One play of the published library's index (contract §4.1, `<site>/data/plays/library/index.json`): enough to
 * list, filter and draw a play without its script, which is fetched only to read or cast it.
 */
@Serializable
data class PlayRow(
    override val id: String,
    val revision: String = "",
    override val title: String,
    @SerialName("sort_name") override val sortName: String? = null,
    override val kind: String = "radio",
    val authors: List<String> = emptyList(),
    override val year: Int? = null,
    val collection: String? = null,
    override val voices: Int = 0,
    val roles: Int = 0,
    override val cast: List<Int> = emptyList(),
    val lines: Int = 0,
    val words: Int = 0,
    override val minutes: Int = 1,
    val rights: PlayScript.Rights? = null,
    val source: PlayScript.Source? = null,
    val path: String = "",
) : PlayListing {
    override val authorLine: String get() = authors.filter { it.isNotBlank() }.joinToString(", ")
    override val authorWithYears: String get() = authorLine
    override val speechCount: Int get() = lines

    companion object {
        /** A bundled script as the row it would be in the index (the offline floor). */
        fun of(script: PlayScript): PlayRow = PlayRow(
            id = script.id, revision = script.revision, title = script.title, sortName = script.sortName, kind = script.kind,
            authors = script.authors.mapNotNull { it.shown }, year = script.year, voices = script.voices,
            roles = script.roles.size, cast = script.cast, lines = script.speechCount,
            words = script.roles.sumOf { it.words }, minutes = script.minutes, rights = script.rights, source = script.source,
        )
    }
}

/** `index.json`: `{format, plays: [...]}`. */
@Serializable
data class PlayIndex(val format: Int = 1, val count: Int = 0, val plays: List<PlayRow> = emptyList()) {
    companion object {
        val json = Json { ignoreUnknownKeys = true }
        fun decode(text: String): PlayIndex = json.decodeFromString(serializer(), text)
    }
}

/** `scripts/<id>.json`: `{format, scripts: [<one entry>]}`, the shape of the bundled file. */
@Serializable
data class PlayScriptFile(val format: Int = 1, val scripts: List<PlayScript> = emptyList()) {
    companion object {
        fun decode(text: String): PlayScriptFile = PlayIndex.json.decodeFromString(serializer(), text)
    }
}
