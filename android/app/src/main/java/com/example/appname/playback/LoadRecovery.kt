package com.example.appname.playback

/**
 * What to do when a recording fails to load (resilient-media-streaming): one retry of the same
 * copy after a jittered wait, then the next copy in rank order (each given the same single
 * retry), then the error. The same machine as apple/Core/Player/LoadRecovery.swift and the
 * recovery in js/player.js.
 */
class LoadRecovery(chosen: String, ranked: List<String>) {
    sealed interface Step {
        /** Load the same copy again after [seconds]. */
        data class Retry(val seconds: Double) : Step
        /** This copy is spent; load [url]. */
        data class Fallback(val url: String) : Step
        /** Nothing left to try: surface the error. */
        data object GiveUp : Step
    }

    var current: String = chosen
        private set
    private val ranked = ranked.distinct()
    private val tried = mutableSetOf<String>()
    private var retried = false

    /** The copy loaded: a later failure (a seek, a dropped connection) gets its own retry. */
    fun loaded() {
        retried = false
        tried.clear()
    }

    /** The current copy failed. [jitter] is a factor around 1 (0.5..1.5 in the engine). */
    fun failed(jitter: Double): Step {
        if (!retried) {
            retried = true
            return Step.Retry(RETRY_SECONDS * jitter)
        }
        tried += current
        val next = ranked.firstOrNull { it !in tried && it != current } ?: return Step.GiveUp
        current = next
        retried = false
        return Step.Fallback(next)
    }

    companion object {
        const val RETRY_SECONDS = 1.0
    }
}
