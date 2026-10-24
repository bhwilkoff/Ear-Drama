package com.example.appname.radio

import com.example.appname.data.CatalogDatabase
import com.example.appname.data.EpisodeDetail
import java.time.Instant
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

// Genre stations (docs/CATALOG-CONTRACT.md §8, R10, Decision 068): each
// station's schedule is published back to back on the one clock; the client
// only looks up what is on now and where in it. Mirrors js/api.js (onNow,
// ahead) and apple/Core/Radio/Stations.swift.

/**
 * A genre station. Its slots are [RadioSlot]s, so the one [LiveListening]
 * plays a station exactly as it plays an evening. [name] is the genre's name
 * from the data, never written here.
 */
data class Station(val genre: String, val name: String, val slots: List<RadioSlot>)

/** `stations.json`: one station per genre. */
object StationsFile {
    private val json = Json { ignoreUnknownKeys = true }

    fun decode(text: String): List<Station> =
        json.decodeFromString(Wire.serializer(), text).stations.map { s ->
            Station(s.genre, s.name, s.slots.map { it.radioSlot() })
        }

    @Serializable
    private data class Wire(val stations: List<WireStation> = emptyList())

    @Serializable
    private data class WireStation(val genre: String, val name: String, val slots: List<WireSlot> = emptyList())

    /** `utc_start`, `utc_end`, `length_s`, and its episode, or `withheld` (it keeps its time; nothing plays). */
    @Serializable
    private data class WireSlot(
        @Serializable(with = InstantSerializer::class) @SerialName("utc_start") val utcStart: Instant,
        @Serializable(with = InstantSerializer::class) @SerialName("utc_end") val utcEnd: Instant,
        @SerialName("length_s") val lengthS: Int,
        val episode: WireEpisode? = null,
        val withheld: Boolean = false,
    ) {
        fun radioSlot() = RadioSlot(
            etStart = "",
            etEnd = "",
            lengthMin = (lengthS + 59) / 60,
            utcStart = utcStart,
            utcEnd = utcEnd,
            episode = episode?.let { RadioSlot.Episode(it.id, it.series, it.title, lengthS.toDouble()) },
            gap = episode == null,
            withheld = withheld || episode == null,
        )
    }

    @Serializable
    private data class WireEpisode(val id: String, val series: String, val title: String? = null)
}

/** What a station has on at an instant. */
object StationClock {
    /** [offsetSeconds] is how long ago the slot started. */
    data class OnNow(val index: Int, val slot: RadioSlot, val offsetSeconds: Double)

    /**
     * The slot whose instants hold [now], found by halving (the slots are back
     * to back and in order), or null before the first or after the last. A
     * boundary belongs to the slot that starts.
     */
    fun onNow(slots: List<RadioSlot>, now: Instant): OnNow? {
        var lo = 0
        var hi = slots.size - 1
        while (lo <= hi) {
            val mid = (lo + hi) ushr 1
            val s = slots[mid]
            when {
                now < s.utcStart -> hi = mid - 1
                now >= s.utcEnd -> lo = mid + 1
                else -> return OnNow(mid, s, (now.toEpochMilli() - s.utcStart.toEpochMilli()) / 1000.0)
            }
        }
        return null
    }

    /**
     * The slot on now and every slot starting within [spanSeconds] of now: what
     * one tune-in may play. Listening ends after the last (R14).
     */
    fun ahead(slots: List<RadioSlot>, now: Instant, spanSeconds: Long = 12 * 3600): List<RadioSlot> {
        val on = onNow(slots, now) ?: return emptyList()
        val horizon = now.plusSeconds(spanSeconds)
        return slots.drop(on.index).takeWhile { it.utcStart < horizon }
    }

    /** The episodes one tune-in may play, resolved in the open catalog; a slot absent here never plays. */
    suspend fun details(slots: List<RadioSlot>, db: CatalogDatabase?): Map<String, EpisodeDetail> = buildMap {
        for (slot in slots) {
            val episode = slot.playableEpisode ?: continue
            val detail = db?.episodeDetail(episode.id) ?: continue
            if (detail.recordings.isEmpty()) continue
            put(episode.id, detail)
        }
    }
}
