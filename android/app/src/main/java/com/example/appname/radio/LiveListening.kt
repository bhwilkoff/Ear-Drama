package com.example.appname.radio

import java.time.Instant

/** What the player tells whoever listens live (WEB-DESIGN §4.9, R14). */
sealed interface TransportEvent {
    /** An episode was loaded, by anyone. */
    data class Loaded(val episodeId: String) : TransportEvent
    /** The player was paused: by the person, the notification, a headset, or audio focus. */
    data object Paused : TransportEvent
    /** The recording played to its end and nothing stopped it. */
    data object Ended : TransportEvent
    /** The sleep timer fired, by its clock or at the episode's end. */
    data object SleepFired : TransportEvent
    /** The player was stopped. */
    data object Stopped : TransportEvent
}

/**
 * Listening live as a state machine, the web's `liveTick` and Apple's
 * `LiveListening`: the slot on the air plays from where the clock stands;
 * when its recording ends, the next surviving slot plays when its own time
 * comes. A pause, another episode, or the sleep timer ends it, and so does
 * the evening's last slot: nothing plays after (R14).
 *
 * [lengths] holds the episodes the catalog resolved, with their default
 * copy's length; a slot whose episode is absent there never plays.
 */
class LiveListening(val slots: List<RadioSlot>, private val lengths: Map<String, Double?>) {
    sealed interface Action {
        data object None : Action
        data class Play(val episodeId: String, val atSeconds: Double) : Action
        data object Stop : Action
    }

    /** The `utcStart` of the slot loaded, null until one is. */
    var playing: Instant? = null
        private set
    /** True until a slot is loaded, and again once its recording ends. */
    var waiting = true
        private set
    var episodeId: String? = null
        private set
    var isOver = false
        private set

    /** Called once a second while live. */
    fun tick(now: Instant): Action {
        if (isOver) return Action.None
        val where = RadioClock.onAir(slots, now)
        if (where.phase == RadioClock.Phase.After) return end()
        val slot = slots[where.index ?: return Action.None]
        val episode = slot.playableEpisode ?: return Action.None
        if (episode.id !in lengths) return Action.None
        if (playing == slot.utcStart) return Action.None
        if (playing != null && !waiting) return Action.None // the slot before is still playing
        val at = RadioClock.liveOffset(slot, lengths[episode.id], now) ?: return Action.None
        playing = slot.utcStart
        waiting = false
        episodeId = episode.id
        return Action.Play(episode.id, at)
    }

    /** Called with each transport event. Returns [Action.Stop] when listening ends. */
    fun handle(event: TransportEvent): Action {
        if (isOver || playing == null) return Action.None
        return when (event) {
            is TransportEvent.Loaded -> if (event.episodeId == episodeId) Action.None else end()
            TransportEvent.Ended -> {
                waiting = true
                Action.None
            }
            TransportEvent.Paused, TransportEvent.SleepFired, TransportEvent.Stopped -> end()
        }
    }

    private fun end(): Action {
        isOver = true
        return Action.Stop
    }
}
