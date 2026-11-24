package com.example.appname.playback

import androidx.core.net.toUri
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import com.example.appname.data.BrowseFilter
import com.example.appname.data.CatalogDatabase
import com.example.appname.data.DisplayVocabulary
import com.example.appname.data.EpisodeRow
import com.example.appname.data.GENRE_ORDER
import com.example.appname.data.SeriesRow
import com.example.appname.data.SeriesSort
import com.example.appname.ui.episodeTitle
import com.example.appname.ui.formatAirDate
import java.net.URLDecoder
import java.net.URLEncoder
import kotlinx.coroutines.withTimeoutOrNull

/**
 * One node of the car's browse tree: a folder, an episode or station that plays, or a plain message
 * ([browsable] and [playable] both false). [art] is a path under the art provider ("e/<id>" for an
 * episode's picture, "s/<key>" for a show's), never a URL.
 */
data class CarNode(
    val id: String,
    val title: String,
    val subtitle: String?,
    val browsable: Boolean,
    val playable: Boolean = !browsable,
    val art: String? = null,
)

/** A station the car can tune: [line] is what is on now, [artEpisodeId] the broadcast whose picture it wears. */
data class CarStation(val id: String, val name: String, val line: String?, val artEpisodeId: String?)

/**
 * The browse tree Android Auto draws (research 04 §3.2; Google's "design for driving": four tabs at
 * most, short lists, few levels). The root's children are the four tabs (R17): Continue, Stations,
 * Browse, Downloads.
 *
 * Browse is the driver-safe part of the app's Browse: the shows you follow, the most downloaded
 * shows, the genres, the length bands; a show opens on its episodes (on its seasons first when it
 * has many). Every order is the app's own rule (downloads, published shelves), and a list the app
 * chooses for the listener leaves out `no_recommend` broadcasts. A folder that cannot be built says
 * why in a message row within [budgetMs] (DR-3: a car loads within 10 s), never an empty screen or a
 * spinner.
 */
class CarLibrary(
    private val inProgressIds: suspend () -> List<String>,
    private val rows: suspend (List<String>) -> List<EpisodeRow>,
    /** The finished downloads, newest first: what plays with no signal (R17). */
    private val downloadedIds: () -> List<String> = { emptyList() },
    private val budgetMs: Long = 8_000,
    private val db: suspend () -> CatalogDatabase? = { null },
    /** The keys of the shows the listener follows. */
    private val followed: suspend () -> List<String> = { emptyList() },
    /** The stations on the air now; throws when they cannot be read (offline). */
    private val stations: suspend () -> List<CarStation> = { emptyList() },
) {
    companion object {
        const val ROOT = "root"
        const val CONTINUE = "tab:continue"
        const val RADIO = "tab:radio"
        const val SERIES = "tab:series"
        const val DOWNLOADS = "tab:downloads"
        const val FOLLOWING = "browse:following"
        const val POPULAR = "browse:popular"
        const val GENRES = "browse:genres"
        const val LENGTHS = "browse:lengths"
        const val STATION_PREFIX = "station:"

        /** Most rows one folder or page holds: long lists page, and none passes this. */
        const val PAGE_MAX = 100
        const val SEARCH_SERIES = 5
        const val SEARCH_EPISODES = 25
        private const val SHOWS_MAX = 50
        private const val SPLIT_AT = 100

        val TABS = listOf(
            CarNode(CONTINUE, "Continue", null, browsable = true),
            CarNode(RADIO, "Stations", null, browsable = true),
            CarNode(SERIES, "Browse", null, browsable = true),
            CarNode(DOWNLOADS, "Downloads", null, browsable = true),
        )

        private val BROWSE = listOf(
            CarNode(FOLLOWING, "Shows you follow", null, browsable = true),
            CarNode(POPULAR, "Popular shows", null, browsable = true),
            CarNode(GENRES, "Genres", null, browsable = true),
            CarNode(LENGTHS, "By length", null, browsable = true),
        )

        const val NO_CATALOG = "Open Ear Drama on your phone to download the catalog"
        const val SLOW = "Taking too long. Try again in a moment"
        const val OFFLINE_STATIONS = "Stations need a connection"

        fun isStation(id: String) = id.startsWith(STATION_PREFIX)

        fun message(text: String) = CarNode("msg:$text", text, null, browsable = false, playable = false)

        private fun enc(s: String) = URLEncoder.encode(s, "UTF-8")
        private fun dec(s: String) = URLDecoder.decode(s, "UTF-8")
        fun seriesId(key: String) = "series/${enc(key)}"
        fun artOfEpisode(id: String) = "e/${enc(id)}"
        fun artOfSeries(key: String) = "s/${enc(key)}"
        private fun seasonId(key: String, season: String?) = "season/${enc(key)}/${season?.let(::enc) ?: "~"}"

        fun episodeNode(row: EpisodeRow): CarNode {
            val title = episodeTitle(row)
            val subtitle = listOfNotNull(
                row.seriesName.takeIf { it != title },
                formatAirDate(row.airDate)?.takeIf { it != title },
            ).joinToString(" · ").ifEmpty { null }
            return CarNode(row.id, title, subtitle, browsable = false, art = artOfEpisode(row.id))
        }

        fun seriesNode(row: SeriesRow): CarNode {
            val run = listOfNotNull(row.firstDate?.take(4), row.lastDate?.take(4)).distinct().joinToString("–")
            val subtitle = listOfNotNull(run.ifEmpty { null }, "${row.episodes} episodes").joinToString(" · ")
            return CarNode(seriesId(row.key), row.name, subtitle, browsable = true, art = artOfSeries(row.key))
        }
    }

    val root = CarNode(ROOT, "Ear Drama", null, browsable = true)

    /** The children of [parentId], one page of them; null when no such folder exists. */
    suspend fun children(parentId: String, page: Int = 0, pageSize: Int = Int.MAX_VALUE): List<CarNode>? {
        val all = guarded(parentId) ?: return null
        if (page < 0 || pageSize <= 0) return all.take(PAGE_MAX)
        val size = pageSize.coerceAtMost(PAGE_MAX)
        return all.drop((page.toLong() * size).coerceAtMost(Int.MAX_VALUE.toLong()).toInt()).take(size)
    }

    /** A node by id, as `onGetItem` asks for it. */
    suspend fun item(id: String): CarNode? = when {
        id == ROOT -> root
        isStation(id) -> runCatching { stations() }.getOrNull()?.firstOrNull { it.id == id }?.let(::stationNode)
        id.startsWith("series/") -> db()?.series(dec(id.removePrefix("series/")))?.let(::seriesNode)
        else -> TABS.firstOrNull { it.id == id } ?: BROWSE.firstOrNull { it.id == id }
            ?: rows(listOf(id)).firstOrNull()?.let(::episodeNode)
    }

    /**
     * What "play X on Ear Drama" plays: a station named, else an episode the search finds, else a
     * show's episode in progress or first one, else where the listener left off; never nothing while
     * the catalog has anything.
     */
    suspend fun voiceTarget(query: String?): String? {
        val q = query?.trim().orEmpty()
        if (q.isNotEmpty()) {
            runCatching { stations() }.getOrNull()
                ?.firstOrNull { it.name.contains(q, ignoreCase = true) || q.contains(it.name, ignoreCase = true) }
                ?.let { return it.id }
            val found = withTimeoutOrNull(budgetMs) { db()?.search(q, SEARCH_EPISODES) }
            found?.series?.firstOrNull()?.let { s ->
                val inProgress = rows(inProgressIds()).firstOrNull { it.seriesKey == s.key }?.id
                (inProgress ?: seriesEpisodes(s.key).firstOrNull()?.id)?.let { return it }
            }
            found?.episodes?.firstOrNull()?.let { return it.id }
        }
        resumeTarget()?.let { return it }
        return withTimeoutOrNull(budgetMs) { db()?.randomEpisode()?.id }
    }

    /** Where the listener left off: the most recent episode in progress, or null. */
    suspend fun resumeTarget(): String? = withTimeoutOrNull(budgetMs) { rows(inProgressIds()).firstOrNull()?.id }

    /** The car's search: the shows then the episodes the app's own search finds for [query]. */
    suspend fun search(query: String, page: Int = 0, pageSize: Int = Int.MAX_VALUE): List<CarNode> {
        val q = query.trim()
        val all = if (q.isEmpty()) emptyList() else withTimeoutOrNull(budgetMs) {
            val database = db() ?: return@withTimeoutOrNull listOf(message(NO_CATALOG))
            val found = database.search(q, SEARCH_EPISODES)
            val nodes = found.series.take(SEARCH_SERIES).map(::seriesNode) +
                found.episodes.take(SEARCH_EPISODES).map(::episodeNode)
            nodes.ifEmpty { listOf(message("Nothing found for $q")) }
        } ?: listOf(message(SLOW))
        val size = pageSize.coerceIn(1, PAGE_MAX)
        return all.drop((page.coerceAtLeast(0).toLong() * size).coerceAtMost(Int.MAX_VALUE.toLong()).toInt()).take(size)
    }

    private suspend fun guarded(parentId: String): List<CarNode>? {
        var known = true
        val built = withTimeoutOrNull(budgetMs) {
            when (parentId) {
                ROOT -> TABS
                CONTINUE -> continuing()
                DOWNLOADS -> downloaded()
                RADIO -> onAir()
                SERIES -> BROWSE
                else -> browse(parentId) ?: run { known = false; null }
            }
        }
        if (!known) return null
        return built ?: listOf(message(SLOW))
    }

    private fun stationNode(s: CarStation) =
        CarNode(s.id, s.name, s.line, browsable = false, art = s.artEpisodeId?.let(::artOfEpisode))

    private suspend fun onAir(): List<CarNode> {
        val list = try {
            stations()
        } catch (e: kotlin.coroutines.cancellation.CancellationException) {
            throw e
        } catch (e: Exception) {
            return listOf(message(OFFLINE_STATIONS))
        }
        return list.map(::stationNode).ifEmpty { listOf(message("Nothing is on the air right now")) }
    }

    private suspend fun browse(id: String): List<CarNode>? {
        val known = id == FOLLOWING || id == POPULAR || id == GENRES || id == LENGTHS ||
            id.startsWith("genre/") || id.startsWith("length/") || id.startsWith("series/") || id.startsWith("season/")
        if (!known) return null
        val database = db() ?: return listOf(message(NO_CATALOG))
        return when {
            id == FOLLOWING -> followed().mapNotNull { database.series(it) }.map(::seriesNode)
                .ifEmpty { listOf(message("Follow a show on your phone and it appears here")) }
            id == POPULAR -> database.seriesBrowse(BrowseFilter(sort = SeriesSort.Popular, showLine = true), SHOWS_MAX)
                .map(::seriesNode)
            id == GENRES -> {
                val present = database.genres().filter {
                    DisplayVocabulary.genreName(it) != null && database.seriesCounts(BrowseFilter(genre = it)).first > 0
                }
                (GENRE_ORDER.filter { it in present } + present.filter { it !in GENRE_ORDER }).map {
                    CarNode("genre/${enc(it)}", DisplayVocabulary.genreName(it) ?: it, null, browsable = true)
                }
            }
            id == LENGTHS -> database.homeShelves().length.map { CarNode("length/${enc(it.key)}", it.label, null, browsable = true) }
            id.startsWith("genre/") -> database.seriesBrowse(
                BrowseFilter(genre = dec(id.removePrefix("genre/")), sort = SeriesSort.Popular, showLine = true), SHOWS_MAX,
            ).map(::seriesNode)
            id.startsWith("length/") -> {
                val band = dec(id.removePrefix("length/"))
                val ids = database.homeShelves().length.firstOrNull { it.key == band }?.ids.orEmpty()
                database.recommendableEpisodes(ids.take(PAGE_MAX)).map(::episodeNode)
            }
            id.startsWith("series/") -> seriesChildren(database, dec(id.removePrefix("series/")))
            else -> {
                val parts = id.removePrefix("season/").split("/", limit = 2)
                val season = dec(parts.getOrElse(1) { "~" })
                database.seasonEpisodes(dec(parts[0]), season.takeIf { it != "~" }).map(::episodeNode)
            }
        }
    }

    private suspend fun seriesEpisodes(key: String): List<EpisodeRow> {
        val database = db() ?: return emptyList()
        val page = database.seriesPage(key) ?: return emptyList()
        return page.seasons.flatMap { database.seasonEpisodes(page.series.key, it.season) }
    }

    /** A show opens on its episodes, oldest first; one with many across several seasons opens on its seasons. */
    private suspend fun seriesChildren(database: CatalogDatabase, key: String): List<CarNode>? {
        val page = database.seriesPage(key) ?: return null
        val total = page.seasons.sumOf { it.episodes }
        if (page.seasons.size > 1 && total > SPLIT_AT) {
            return page.seasons.map {
                CarNode(
                    seasonId(page.series.key, it.season),
                    it.season?.let { s -> "Season $s" } ?: "Undated",
                    "${it.episodes} episodes",
                    browsable = true,
                )
            }
        }
        return page.seasons.flatMap { database.seasonEpisodes(page.series.key, it.season) }.map(::episodeNode)
    }

    private suspend fun downloaded(): List<CarNode> {
        val ids = downloadedIds()
        return withTimeoutOrNull(budgetMs) {
            val byId = rows(ids).associateBy { it.id }
            ids.mapNotNull { byId[it] }.map(::episodeNode)
        }?.ifEmpty { listOf(message("No downloads yet")) } ?: listOf(message(SLOW))
    }

    private suspend fun continuing(): List<CarNode> =
        withTimeoutOrNull(budgetMs) { rows(inProgressIds()).distinctBy { it.id }.map(::episodeNode) }
            ?.ifEmpty { listOf(message("Nothing in progress")) } ?: listOf(message(SLOW))
}

/** The node as the media session serves it; [artAuthority], when given, is the art provider its picture is read through. */
fun CarNode.toMediaItem(artAuthority: String? = null): MediaItem = MediaItem.Builder()
    .setMediaId(id)
    .setMediaMetadata(
        MediaMetadata.Builder()
            .setTitle(title)
            .setSubtitle(subtitle)
            .setIsBrowsable(browsable)
            .setIsPlayable(playable)
            .setMediaType(
                when {
                    browsable -> MediaMetadata.MEDIA_TYPE_FOLDER_MIXED
                    playable -> MediaMetadata.MEDIA_TYPE_PODCAST_EPISODE
                    else -> MediaMetadata.MEDIA_TYPE_MIXED
                },
            )
            .also { b -> if (art != null && artAuthority != null) b.setArtworkUri("content://$artAuthority/$art".toUri()) }
            .build(),
    )
    .build()
