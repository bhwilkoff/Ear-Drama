package com.example.appname.radio

import com.example.appname.data.EpisodeDetail
import java.time.Instant
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * The app's one live listener: owns the clock loop and drives the one player
 * through [LiveListening]. [play] starts an episode at an offset with nothing
 * queued behind it; [pause] pauses the player. Screens read [day] to mark
 * Listening live.
 */
class LiveRadio(
    private val play: (EpisodeDetail, startMs: Long) -> Unit,
    private val pause: () -> Unit,
    private val now: () -> Instant = Instant::now,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate),
) {
    private val _day = MutableStateFlow<TonightDay?>(null)
    /** The evening listened to live, null when not listening to one. */
    val day: StateFlow<TonightDay?> = _day
    private val _station = MutableStateFlow<String?>(null)
    /** The genre station listened to live (its genre), null when not. */
    val station: StateFlow<String?> = _station

    private var listening: LiveListening? = null
    private var details: Map<String, EpisodeDetail> = emptyMap()
    private var loop: Job? = null

    fun tuneIn(evening: RadioEvening) {
        stop()
        _day.value = evening.day
        start(evening.day.slots, evening.details)
    }

    /** A genre station: the slot on now and those after it ([StationClock.ahead]), on the evening's rules. */
    fun tuneIn(station: Station, slots: List<RadioSlot>, details: Map<String, EpisodeDetail>) {
        stop()
        _station.value = station.genre
        start(slots, details)
    }

    private fun start(slots: List<RadioSlot>, details: Map<String, EpisodeDetail>) {
        this.details = details
        listening = LiveListening(slots, details.mapValues { (_, d) -> d.defaultLength })
        tick()
        if (listening == null) return
        loop = scope.launch {
            while (isActive) {
                delay(1_000)
                tick()
            }
        }
    }

    /** Ends listening live; the audio keeps whatever state it is in. */
    fun stop() {
        loop?.cancel()
        loop = null
        listening = null
        _day.value = null
        _station.value = null
    }

    /** Listening live's own button: pauses, which ends it. */
    fun pauseAndStop() {
        stop()
        pause()
    }

    fun handle(event: TransportEvent) {
        val state = listening ?: return
        // The catalog may forward the file's id to a newer one (§3.5): the same episode.
        val named = if (event is TransportEvent.Loaded) {
            details.entries.firstOrNull { it.value.episode.id == event.episodeId }?.key?.let { TransportEvent.Loaded(it) } ?: event
        } else {
            event
        }
        apply(state.handle(named))
    }

    private fun tick() {
        val state = listening ?: return
        apply(state.tick(now()))
    }

    private fun apply(action: LiveListening.Action) {
        when (action) {
            LiveListening.Action.None -> Unit
            LiveListening.Action.Stop -> stop()
            is LiveListening.Action.Play -> details[action.episodeId]?.let { play(it, (action.atSeconds * 1000).toLong()) }
        }
    }
}

/** The default copy's length, else the episode's. */
val EpisodeDetail.defaultLength: Double? get() = recordings.firstOrNull()?.lengthSeconds ?: episode.lengthSeconds
