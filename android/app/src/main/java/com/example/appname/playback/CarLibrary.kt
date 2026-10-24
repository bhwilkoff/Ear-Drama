package com.example.appname.playback

import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import com.example.appname.data.EpisodeRow
import com.example.appname.ui.episodeTitle
import com.example.appname.ui.formatAirDate
import kotlinx.coroutines.withTimeoutOrNull

/** One node of the car's browse tree: a folder, or an episode that plays. */
data class CarNode(val id: String, val title: String, val subtitle: String?, val browsable: Boolean)

/**
 * The browse tree Android Auto draws (research 04 §3.2). The root's children
 * are the car's four tabs, Continue, Stations, Browse, Downloads (R17). Continue
 * lists this device's in-progress episodes and Downloads its finished
 * downloads; Stations and Browse are empty in the stub (Decision 056). No node carries art: the catalog has none to give.
 */
class CarLibrary(
    private val inProgressIds: suspend () -> List<String>,
    private val rows: suspend (List<String>) -> List<EpisodeRow>,
    /** The finished downloads, newest first: what plays with no signal (R17). */
    private val downloadedIds: () -> List<String> = { emptyList() },
    /** DR-3: a car loads content within 10 s, so a slow catalog yields an empty list instead. */
    private val budgetMs: Long = 8_000,
) {
    companion object {
        const val ROOT = "root"
        const val CONTINUE = "tab:continue"
        const val RADIO = "tab:radio"
        const val SERIES = "tab:series"
        const val DOWNLOADS = "tab:downloads"

        val TABS = listOf(
            CarNode(CONTINUE, "Continue", null, browsable = true),
            CarNode(RADIO, "Stations", null, browsable = true),
            CarNode(SERIES, "Browse", null, browsable = true),
            CarNode(DOWNLOADS, "Downloads", null, browsable = true),
        )

        fun episodeNode(row: EpisodeRow): CarNode {
            val title = episodeTitle(row)
            val subtitle = listOfNotNull(
                row.seriesName.takeIf { it != title },
                formatAirDate(row.airDate)?.takeIf { it != title },
            ).joinToString(" · ").ifEmpty { null }
            return CarNode(row.id, title, subtitle, browsable = false)
        }
    }

    val root = CarNode(ROOT, "Ear Drama", null, browsable = true)

    /** The children of [parentId], one page of them; null when no such folder exists. */
    suspend fun children(parentId: String, page: Int = 0, pageSize: Int = Int.MAX_VALUE): List<CarNode>? {
        val all = when (parentId) {
            ROOT -> TABS
            CONTINUE -> continuing()
            DOWNLOADS -> downloaded()
            RADIO, SERIES -> emptyList()
            else -> return null
        }
        if (page < 0 || pageSize <= 0) return all
        return all.drop((page.toLong() * pageSize).coerceAtMost(Int.MAX_VALUE.toLong()).toInt()).take(pageSize)
    }

    /** A node by id, as `onGetItem` asks for it. */
    suspend fun item(id: String): CarNode? = when (id) {
        ROOT -> root
        else -> TABS.firstOrNull { it.id == id } ?: rows(listOf(id)).firstOrNull()?.let(::episodeNode)
    }

    private suspend fun downloaded(): List<CarNode> {
        val ids = downloadedIds()
        return withTimeoutOrNull(budgetMs) {
            val byId = rows(ids).associateBy { it.id }
            ids.mapNotNull { byId[it] }.map(::episodeNode)
        } ?: emptyList()
    }

    private suspend fun continuing(): List<CarNode> =
        withTimeoutOrNull(budgetMs) { rows(inProgressIds()).distinctBy { it.id }.map(::episodeNode) } ?: emptyList()
}

/** The node as the media session serves it: a title and subtitle, no artwork, browsable or playable. */
fun CarNode.toMediaItem(): MediaItem = MediaItem.Builder()
    .setMediaId(id)
    .setMediaMetadata(
        MediaMetadata.Builder()
            .setTitle(title)
            .setSubtitle(subtitle)
            .setIsBrowsable(browsable)
            .setIsPlayable(!browsable)
            .setMediaType(
                if (browsable) MediaMetadata.MEDIA_TYPE_FOLDER_MIXED else MediaMetadata.MEDIA_TYPE_PODCAST_EPISODE,
            )
            .build(),
    )
    .build()
