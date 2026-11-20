package com.example.appname.radio

import java.time.Instant

/**
 * What Home's On the air block shows (Decision 075; js/app.js `onAirNow`): [kicker] is "Tonight in
 * 1942" or a station's name, [slot] the one on now, [evening] set when it is the evening's, else
 * [station]; [note] the evening's start when a station stands in before it.
 */
data class HomeLive(
    val kicker: String,
    val slot: RadioSlot,
    val evening: RadioEvening?,
    val station: Station?,
    val note: String? = null,
) {
    /** The year the label ticks: the evening's, else the broadcast's own. */
    val tickYear: String?
        get() {
            val year = evening?.day?.year ?: slot.playableEpisode?.id?.substringAfter('|', "")?.take(4).orEmpty()
            return year.takeIf { it.length == 4 && it.all(Char::isDigit) }
        }

    /** Whole minutes since the slot began. */
    fun minutesIn(now: Instant): Long = ((now.toEpochMilli() - slot.utcStart.toEpochMilli()) / 60_000).coerceAtLeast(0)

    companion object {
        /**
         * 1. Tonight's evening, when a slot of it is on now with an episode that is not withheld.
         * 2. Else the first station, in file order, with such a slot on now; the note says when the
         *    evening starts if it has not.
         * 3. Else nothing: the block is absent.
         */
        fun now(evening: RadioEvening?, stations: List<Station>, now: Instant): HomeLive? {
            if (evening != null) {
                val onAir = RadioClock.onAir(evening.day.slots, now)
                val slot = onAir.index?.let { evening.day.slots[it] }
                if (slot != null && evening.detail(slot) != null) {
                    return HomeLive("Tonight in ${evening.day.year}", slot, evening, null)
                }
            }
            val note = evening?.takeIf { RadioClock.onAir(it.day.slots, now).phase == RadioClock.Phase.Before }?.let { e ->
                e.day.slots.firstOrNull()?.let { "Tonight in ${e.day.year} · Starts at ${RadioClock.clock(it.utcStart)}" }
            }
            for (station in stations) {
                val on = StationClock.onNow(station.slots, now) ?: continue
                if (on.slot.playableEpisode != null) return HomeLive(station.name, on.slot, null, station, note)
            }
            return null
        }
    }
}

/**
 * The dial under On the air (WEB-DESIGN §4.2r rule 2): a genre station, what it has on now ([on], null when nothing
 * playable is on) and that broadcast's year for the label's tick.
 */
data class DialEntry(val station: Station, val on: HomeLive?, val year: Int?) {
    val show: String? get() = on?.slot?.playableEpisode?.series

    companion object {
        fun entries(stations: List<Station>, now: Instant): List<DialEntry> = stations.map { station ->
            val at = StationClock.onNow(station.slots, now)
            if (at == null || at.slot.playableEpisode == null) return@map DialEntry(station, null, null)
            val on = HomeLive(station.name, at.slot, null, station)
            DialEntry(station, on, on.tickYear?.toInt()?.takeIf { it >= 1900 })
        }
    }
}
