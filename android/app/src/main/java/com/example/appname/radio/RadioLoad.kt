package com.example.appname.radio

import com.example.appname.data.CatalogDatabase
import com.example.appname.data.EpisodeDetail
import kotlin.coroutines.cancellation.CancellationException

/** The Radio tab's evening, resolved against the open catalog. */
data class RadioEvening(
    val day: TonightDay,
    val zone: String,
    /**
     * The surviving slots' episodes the catalog holds; a slot absent here is
     * drawn as a gap ("Not in the catalog") and never plays.
     */
    val details: Map<String, EpisodeDetail>,
    /** The evenings a listener may pick for this date (Decision 067), oldest first, [day] among them. */
    val choices: List<String> = listOf(day.evening),
) {
    fun detail(slot: RadioSlot): EpisodeDetail? = slot.playableEpisode?.let { details[it.id] }
}

sealed interface RadioLoad {
    data object Loading : RadioLoad
    /** No file is published, or it holds no evening for today. */
    data object Nothing : RadioLoad
    data class Evening(val evening: RadioEvening) : RadioLoad
    /** The file could not be fetched (offline, or the host failed). */
    data object Failed : RadioLoad

    companion object {
        /**
         * Reads the file through the one API client ([fetch]) and resolves each
         * surviving slot in the catalog. Screens never fetch it themselves.
         */
        suspend fun load(
            fetch: suspend () -> TonightFile?,
            db: suspend () -> CatalogDatabase?,
            date: String,
            picked: String? = null,
        ): RadioLoad {
            val file = try {
                fetch()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                println("[Radio] tonight.json unreachable: ${e.message}")
                return Failed
            }
            val published = file?.day(date) ?: return Nothing
            val day = picked?.let { e -> published.choices.firstOrNull { it.evening == e } } ?: published
            val catalog = db()
            val details = buildMap {
                for (slot in day.slots) {
                    val episode = slot.playableEpisode ?: continue
                    val detail = catalog?.episodeDetail(episode.id) ?: continue
                    if (detail.recordings.isEmpty()) continue
                    put(episode.id, detail)
                }
            }
            return Evening(RadioEvening(day, file.zone, details, published.choices.map { it.evening }))
        }
    }
}
