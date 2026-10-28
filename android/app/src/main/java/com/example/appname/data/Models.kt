package com.example.appname.data

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull

/**
 * A served image (contract §3.3a, Decision 069): a Commons file with its
 * evidence. [url] takes a width; [credit] is set only where the license asks.
 */
data class Artwork(
    val url: String,
    val width: Int? = null,
    val height: Int? = null,
    val credit: String? = null,
    val evidence: String? = null,
) {
    /** The one image helper: the smallest Commons standard width covering [pixels]. */
    fun url(pixels: Int): String = "$url?width=${STEPS.firstOrNull { it >= pixels } ?: STEPS.last()}"

    companion object {
        /** Commons' standard thumbnail steps; any other width is refused upstream. */
        val STEPS = listOf(120, 330, 500)
    }
}

/** Whose face a series or episode wears: a person's name and served portrait. */
data class Face(val name: String, val art: Artwork)

/** The first letter or digit of a name, skipping a leading article (a row's tile). */
fun artInitial(name: String): String {
    var rest = name.dropWhile { !it.isLetterOrDigit() }
    for (article in listOf("The ", "A ", "An ")) {
        if (rest.startsWith(article, ignoreCase = true)) { rest = rest.drop(article.length); break }
    }
    return rest.firstOrNull { it.isLetterOrDigit() }?.uppercase() ?: ""
}

/** A row of `series` (docs/CATALOG-CONTRACT.md §3.3). */
data class SeriesRow(
    val key: String,
    val name: String,
    val genre: String?,
    val firstDate: String?,
    val lastDate: String?,
    val episodes: Int,
    /** The series' star and portrait (§3.3a), or null: its art is then the typographic card. */
    val face: Face? = null,
)

/** The light columns of `episodes` a list row shows; never `detail_json`. */
data class EpisodeRow(
    val id: String,
    val seriesKey: String,
    val seriesName: String,
    val airDate: String?,
    val season: String?,
    val num: Int?,
    val title: String?,
    val lengthSeconds: Double?,
    /** The series' genre and face, so a row that mixes series can draw its tile. */
    val seriesGenre: String? = null,
    val seriesFace: Face? = null,
    /** Set only on Search's transcript matches: the shown transcript's own URL, where the snippet is read. */
    val transcriptUrl: String? = null,
)

/** One broadcast season of a series page; [season] is null for undated episodes. */
data class SeasonRow(val season: String?, val episodes: Int)

data class SeriesPage(
    val series: SeriesRow,
    val seasons: List<SeasonRow>,
)

data class Credit(
    val personId: String,
    val name: String,
    val role: String?,
    val character: String?,
    /** The person's served portrait (§3.3a), or null. */
    val art: Artwork? = null,
)

data class Recording(
    val rank: Int,
    val archiveId: String,
    val url: String,
    val format: String?,
    val kbps: Int?,
    val lengthSeconds: Double?,
    val variant: String?,
    val partial: Boolean,
)

/** An arc part's view ahead (contract §3.3): the parts after it, in order, and the next story's first part. */
data class ArcAhead(val rest: List<String>, val nextStory: String?)

data class EpisodeDetail(
    val episode: EpisodeRow,
    val rights: String,
    val rightsBasis: String?,
    val network: String?,
    val noRecommend: String?,
    val credits: List<Credit>,
    val recordings: List<Recording>,
    /** Decoded only on Detail, and only when a field here needs it. */
    val detailJson: String?,
    /** The default copy's integrated loudness (LUFS) and true peak (dBTP), §3.1; null until measured. */
    val loudnessI: Double? = null,
    val loudnessTp: Double? = null,
    /**
     * archive.org's automatic transcript (§3.1), set only where the quality
     * gate passed (`has_transcript = 1`); fetched when opened, never bundled.
     */
    val transcriptUrl: String? = null,
    /** Contract §5.5: the published words for this row's rights, or null for none. */
    val rightsLine: String? = null,
    /** §3.1's dated sponsor, when a log gives one; a catalog without the column reads null. */
    val sponsor: String? = null,
    /** The episode's face, a person credited in it (§3.3a), or null. */
    val star: String? = null,
    /** A castable script this episode can be recorded from (§3.1, Decision 068), or null. */
    val script: String? = null,
) {
    /** The credited star with a portrait, drawn beside the heading. */
    val starFace: Face?
        get() = star?.let { s -> credits.firstOrNull { it.personId == s && it.art != null } }
            ?.let { Face(it.name, it.art!!) }

    /** What Now Playing and the session show: the episode's face, else the series'. */
    val face: Face? get() = starFace ?: episode.seriesFace

    /** Portraits whose license asks for a credit, once each, leaving out the heading's face (Decision 069). */
    val owedCredits: List<Credit>
        get() {
            val headed = if (starFace == null) null else star
            return credits.filter { it.art?.credit != null && it.personId != headed }.distinctBy { it.personId }
        }
}

/**
 * [episodes] match titles, series, and people; [aired] is what aired on the date the
 * query names (null when it names none); [transcript] is what is said in a shown
 * transcript (§3.4), less [episodes], each row carrying its `transcriptUrl`.
 */
data class SearchResults(
    val series: List<SeriesRow>,
    val episodes: List<EpisodeRow>,
    /** `searchPeople(q)` (contract §5): credited people, most episodes first. */
    val people: List<PersonRow> = emptyList(),
    val aired: AiredResults? = null,
    val transcript: List<EpisodeRow> = emptyList(),
) {
    val isEmpty: Boolean
        get() = series.isEmpty() && episodes.isEmpty() && people.isEmpty() && aired?.episodes.isNullOrEmpty() &&
            transcript.isEmpty()
}

/** The episodes that aired on [prefix] (YYYY, YYYY-MM, or YYYY-MM-DD, [DateQuery]), oldest first. */
data class AiredResults(val prefix: String, val episodes: List<EpisodeRow>) {
    val title: String get() = "Aired ${DateQuery.label(prefix)}"
}

// --- People (withPerson, contract §5) ---

/** A credited person: facts from the `people` row only, never a written bio. */
data class Person(
    val id: String,
    val name: String,
    val birth: String?,
    val death: String?,
    /** The person's served portrait (§3.3a), or null. */
    val art: Artwork? = null,
) {
    val face: Face? get() = art?.let { Face(name, it) }
    val years: String? get() = years(birth, death)

    companion object {
        /** The years as every platform writes them (`API.lifeYears` on the web). */
        fun years(birth: String?, death: String?): String? {
            val b = birth?.take(4)?.ifEmpty { null }
            val d = death?.take(4)?.ifEmpty { null }
            return when {
                b != null && d != null -> "$b–$d"
                b != null -> "Born $b"
                d != null -> "Died $d"
                else -> null
            }
        }
    }
}

/** A people search row; [episodes] counts the distinct served episodes crediting them. */
data class PersonRow(val person: Person, val episodes: Int)

data class PersonRole(val role: String?, val character: String?) {
    companion object {
        /** A role as a heading word, on Detail's credits and a person's rows. */
        fun title(role: String?): String {
            val r = role ?: "cast"
            return when (r.lowercase()) {
                "cast" -> "Cast"
                "m. c.", "emcee" -> "Emcee"
                else -> r.replaceFirstChar { it.uppercase() }
            }
        }
    }
}

/** One episode on a person's page, with every role it credits them in. */
data class PersonEpisode(val episode: EpisodeRow, val roles: List<PersonRole>) {
    /** "Cast as Mrs. Stevenson, Narrator". */
    val rolesLine: String
        get() = roles.joinToString(", ") { r ->
            val t = PersonRole.title(r.role)
            r.character?.let { "$t as $it" } ?: t
        }
}

data class PersonSeriesGroup(val seriesKey: String, val seriesName: String, val episodes: List<PersonEpisode>)

data class PersonPage(
    val person: Person,
    /** Every served episode crediting the person, oldest first (R1). */
    val episodes: List<PersonEpisode>,
) {
    /**
     * By series, oldest or newest first, undated last either way; a series sits
     * where its first episode in that order does (`API.personGroups`).
     */
    fun groups(newestFirst: Boolean): List<PersonSeriesGroup> {
        val ordered = if (newestFirst) {
            episodes.filter { it.episode.airDate != null }.reversed() + episodes.filter { it.episode.airDate == null }
        } else episodes
        return ordered.groupBy { it.episode.seriesKey }.map { (key, eps) ->
            PersonSeriesGroup(key, eps.first().episode.seriesName, eps)
        }
    }
}

/** Filters for `seriesBrowse`; null means "any". */
data class BrowseFilter(
    val genre: String? = null,
    val network: String? = null,
    /** The first year of a decade, 1940 for the 1940s. */
    val decade: Int? = null,
    val sort: SeriesSort = SeriesSort.Name,
)

/** Series browse's orders (WEB-DESIGN §4.3) with its labels; Popular is Browse's default (ANDROID-DESIGN §4.2). */
enum class SeriesSort(val label: String) {
    Popular("Popular"),
    Name("A to Z"),
    Episodes("Most episodes"),
    FirstAired("Oldest first"),
}

/** A facet choice and how many series it would list against the other facets' selection. */
data class FacetCount<T>(val value: T, val series: Int)

/** A Listen shelf's rule; every shelf applies `recommendAnd`. */
sealed interface ShelfRule {
    /** Broadcasts that aired on this month and day, any year: `MM-DD`. */
    data class ThisDay(val monthDay: String) : ShelfRule

    /** Dated broadcasts of series in one genre, oldest first: the fallback for a catalog without `listenShelves`. */
    data class Genre(val genre: String) : ShelfRule
}

/**
 * One entry of `meta.listenShelves` (contract §5.1), drawn in order: [OnThisDay]
 * is a query by rule on the person's date; [GenreFirsts] carries its episode ids.
 */
sealed interface PublishedShelf {
    data object OnThisDay : PublishedShelf

    data class GenreFirsts(val genre: String, val episodes: List<String>) : PublishedShelf

    /** Decision 067: the series archive.org's listeners downloaded most, by their first episodes. Only ever published. */
    data class MostDownloaded(val episodes: List<String>) : PublishedShelf

    companion object {
        /** The published list, or null when the value is not a JSON array (an older catalog). Unknown rules are skipped. */
        fun parse(json: String): List<PublishedShelf>? {
            val list = runCatching { Json.parseToJsonElement(json) }.getOrNull() as? JsonArray ?: return null
            return list.mapNotNull { item ->
                val s = item as? JsonObject ?: return@mapNotNull null
                when ((s["rule"] as? JsonPrimitive)?.contentOrNull) {
                    "onThisDay" -> OnThisDay
                    "genreFirsts" -> {
                        val genre = (s["genre"] as? JsonPrimitive)?.contentOrNull ?: return@mapNotNull null
                        val ids = (s["episodes"] as? JsonArray)?.mapNotNull { (it as? JsonPrimitive)?.contentOrNull }
                            ?: return@mapNotNull null
                        GenreFirsts(genre, ids)
                    }
                    "mostDownloaded" -> {
                        val ids = (s["episodes"] as? JsonArray)?.mapNotNull { (it as? JsonPrimitive)?.contentOrNull }
                            ?: return@mapNotNull null
                        MostDownloaded(ids)
                    }
                    else -> null
                }
            }
        }
    }
}

/** A Listen shelf ready to draw: [heading] names a rule's own shelf; otherwise [genre] null is This day in radio. */
data class ListenShelf(val key: String, val genre: String?, val rows: List<EpisodeRow>, val heading: String? = null)
