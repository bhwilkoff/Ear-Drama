package com.example.appname.data

/** A row of `series` (docs/CATALOG-CONTRACT.md §3.3). */
data class SeriesRow(
    val key: String,
    val name: String,
    val genre: String?,
    val firstDate: String?,
    val lastDate: String?,
    val episodes: Int,
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
)

/** One broadcast season of a series page; [season] is null for undated episodes. */
data class SeasonRow(val season: String?, val episodes: Int)

data class SeriesPage(
    val series: SeriesRow,
    val seasons: List<SeasonRow>,
)

data class Credit(val personId: String, val name: String, val role: String?, val character: String?)

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
)

/** [transcriptOnly]: the episodes found only by words in their transcript (§3.4). */
data class SearchResults(
    val series: List<SeriesRow>,
    val episodes: List<EpisodeRow>,
    val transcriptOnly: Set<String> = emptySet(),
) {
    val isEmpty: Boolean get() = series.isEmpty() && episodes.isEmpty()
}

/** Filters for `seriesBrowse`; null means "any". */
data class BrowseFilter(
    val genre: String? = null,
    val network: String? = null,
    /** The first year of a decade, 1940 for the 1940s. */
    val decade: Int? = null,
    val sort: SeriesSort = SeriesSort.Name,
)

/** Series browse's orders, the web's three (WEB-DESIGN §4.3) with its labels. */
enum class SeriesSort(val label: String) {
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

    /** Dated broadcasts of series in one genre, oldest first. */
    data class Genre(val genre: String) : ShelfRule
}
