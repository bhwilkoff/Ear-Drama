package com.example.appname.playback

import com.example.appname.data.CatalogDatabase
import com.example.appname.data.EpisodeRow
import com.example.appname.radio.LiveRadio
import com.example.appname.radio.RadioClock
import com.example.appname.radio.RadioLoad
import com.example.appname.radio.Station
import com.example.appname.radio.StationClock
import com.example.appname.radio.TonightFile
import com.example.appname.ui.episodeTitle
import java.time.Instant

/**
 * The Stations screen's rows for the car: tonight's evening and the genre stations that have something
 * on the air now, each tuned at the clock's own position by the app's one [LiveRadio] (no second
 * clock, no day switcher). A station with a gap on the air, or an evening not under way, is not offered.
 */
class CarStations(
    private val tonight: suspend () -> TonightFile?,
    private val stations: suspend () -> List<Station>,
    private val db: suspend () -> CatalogDatabase?,
    private val live: LiveRadio,
    private val now: () -> Instant = Instant::now,
) {
    /** Where a tune-in starts: the episode and how far into it the clock stands. */
    data class Tuned(val episodeId: String, val startMs: Long)

    /** Throws when neither file can be read (offline). */
    suspend fun list(): List<CarStation> {
        val at = now()
        var failure: Exception? = null
        val evening = (RadioLoad.load({ tonight() }, db, RadioClock.localDate(at)) as? RadioLoad.Evening)?.evening
        val genre = try {
            stations()
        } catch (e: kotlin.coroutines.cancellation.CancellationException) {
            throw e
        } catch (e: Exception) {
            failure = e
            emptyList()
        }
        if (failure != null && evening == null) throw failure
        val database = db()
        val out = mutableListOf<CarStation>()
        if (evening != null) {
            val onAir = RadioClock.onAir(evening.day.slots, at)
            val episode = onAir.index?.let { evening.day.slots[it] }?.takeIf { evening.detail(it) != null }?.playableEpisode
            if (episode != null) {
                out += CarStation(TONIGHT, "Tonight in ${evening.day.year}", line(database?.episodes(listOf(episode.id))?.firstOrNull()), episode.id)
            }
        }
        for (station in genre) {
            val episode = StationClock.onNow(station.slots, at)?.slot?.playableEpisode ?: continue
            val row = database?.episodes(listOf(episode.id))?.firstOrNull() ?: continue
            out += CarStation(CarLibrary.STATION_PREFIX + station.genre, station.name, line(row), episode.id)
        }
        return out
    }

    /** Tunes [id] in the app's live listening and returns what the session should play; null when nothing is on. */
    suspend fun tune(id: String): Tuned? {
        val at = now()
        val play = if (id == TONIGHT) {
            val evening = (RadioLoad.load({ tonight() }, db, RadioClock.localDate(at)) as? RadioLoad.Evening)?.evening
                ?: return null
            live.tuneInForCar(evening)
        } else {
            val station = stations().firstOrNull { CarLibrary.STATION_PREFIX + it.genre == id } ?: return null
            val slots = StationClock.ahead(station.slots, at)
            live.tuneInForCar(station, slots, StationClock.details(slots, db()))
        }
        return play?.let { Tuned(it.episodeId, (it.atSeconds * 1000).toLong()) }
    }

    private fun line(row: EpisodeRow?): String? =
        row?.let { listOfNotNull(it.seriesName, episodeTitle(it).takeIf { t -> t != it.seriesName }).joinToString(" · ") }

    companion object {
        const val TONIGHT = CarLibrary.STATION_PREFIX + "tonight"
    }
}
