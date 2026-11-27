package com.example.appname.plays

import com.example.appname.data.Artwork
import com.example.appname.data.FaceBox
import com.example.appname.data.LabelItem
import com.example.appname.data.LabelKind
import com.example.appname.data.LabelLife

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
    /** `phonemes/<id>.json` when the catalog published the play's phonemes (Decision 078); absent for a held play. */
    val phonemes: String? = null,
    /** The first speeches as the index cuts them (contract §4.1), for a play drawn without its script. */
    val opening: List<Opening>? = null,
    /** Finding a play (contract §4.1, B31 C3), each absent in a library built before it: computed once by the catalog, never by a client. */
    @Serializable(with = LenientString::class) val form: String? = null,
    @Serializable(with = LenientString::class) val hue: String? = null,
    @Serializable(with = LenientString::class) val era: String? = null,
    @Serializable(with = LenientLife::class) val life: Life? = null,
    @Serializable(with = LenientBool::class) val oneAct: Boolean = false,
    @Serializable(with = LenientString::class) val balance: String? = null,
    @Serializable(with = LenientStrings::class) val subjects: List<String> = emptyList(),
    @Serializable(with = LenientString::class) val locc: String? = null,
    @Serializable(with = LenientBool::class) val attributed: Boolean = false,
    @Serializable(with = LenientScenes::class) val scenes: List<Scene> = emptyList(),
    /** The play's pictures (contract §4.1 `picture.kind`): `picture` leads a window only when it is of the play itself. */
    @Serializable(with = LenientArt::class) val picture: PlayArt? = null,
    @Serializable(with = LenientArt::class) val titlePage: PlayArt? = null,
    @Serializable(with = LenientArt::class) val production: PlayArt? = null,
    @Serializable(with = LenientArt::class) val authorArt: PlayArt? = null,
) : PlayListing {
    @Serializable data class Opening(val role: String = "", val text: String = "")

    @Serializable data class Life(val born: Int? = null, val died: Int? = null)

    /** A scene for N voices (B31 §3.4): its first line, its heading as printed, the voices, the minutes, its parts. */
    @Serializable data class Scene(
        val line: String,
        val heading: String? = null,
        val voices: Int,
        val minutes: Int = 0,
        val parts: List<String> = emptyList(),
        /** The last line before the next section (contract 4.1); absent in a library built before it, which keeps the old door. */
        val to: String? = null,
    ) {
        val range: ProductionRange? get() = to?.takeIf { it.isNotEmpty() && line.isNotEmpty() }?.let { ProductionRange(line, it) }
    }

    /** The first author's display name, or "". */
    val firstAuthor: String get() = authors.firstOrNull { it.isNotBlank() }.orEmpty()

    /** The play's label (B31 2.1): its name, first author, form's board, era, life and cast, all from the row. */
    val labelItem: LabelItem
        get() = LabelItem(
            LabelKind.Play, name = title, cast = cast, author = firstAuthor.ifEmpty { null }, hue = hue, era = era,
            life = life?.let { LabelLife(it.born, it.died) },
        )

    /** What a play's window leads with outside its own page (B31 §1.4): a picture of the play itself (`work`, `production` or `book`), never its title page or its author's face; null is the label. */
    val windowPicture: Artwork? get() = picture?.takeIf { it.kind in PlayArt.WINDOW_KINDS }?.artwork

    /** What leads the play's own page header: a picture of the play, else its title page, else a photograph of its production, else its author's portrait; null is the label. */
    val pageLead: Artwork? get() = windowPicture ?: titlePage?.artwork ?: production?.artwork ?: authorArt?.artwork

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

/** A picture as the play library publishes it (contract §4.1): the URL, its size, credit, evidence, face box and, on `picture`, what it shows. */
@Serializable
data class PlayArt(
    val url: String,
    val width: Int? = null,
    val height: Int? = null,
    val credit: String? = null,
    val evidence: String? = null,
    val face: String? = null,
    val kind: String? = null,
) {
    val artwork: Artwork get() = Artwork(url, width, height, credit, evidence, FaceBox.parse(face))

    companion object {
        /** The kinds a tile, row, rail or TV window may lead with (`play_art.WINDOW_KINDS`). */
        val WINDOW_KINDS = setOf("work", "production", "book")
    }
}

/**
 * The facets the catalog counted over the whole library (contract §4.1): the voice and minute bins, the form, era and
 * balance values (`value` null for "Not named" or undated), subjects and LoCC most first, the one-act count.
 */
@Serializable
data class PlayFacetsIndex(
    @Serializable(with = LenientBins::class) val voices: List<Bin>? = null,
    @Serializable(with = LenientBins::class) val minutes: List<Bin>? = null,
    @Serializable(with = LenientFacetValues::class) val form: List<Value>? = null,
    @Serializable(with = LenientFacetValues::class) val era: List<Value>? = null,
    @Serializable(with = LenientFacetValues::class) val balance: List<Value>? = null,
    @Serializable(with = LenientFacetValues::class) val subjects: List<Value>? = null,
    @Serializable(with = LenientFacetValues::class) val locc: List<Value>? = null,
    @Serializable(with = LenientInt::class) val oneAct: Int? = null,
) {
    @Serializable data class Bin(val min: Int, val max: Int? = null)
    @Serializable data class Value(val value: String? = null, val count: Int = 0)
}

/** `index.json`: `{format, plays: [...], facets}`. */
@Serializable
data class PlayIndex(
    val format: Int = 1,
    val count: Int = 0,
    val plays: List<PlayRow> = emptyList(),
    @Serializable(with = LenientFacets::class) val facets: PlayFacetsIndex? = null,
) {
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
