package com.example.appname.playback

/** What the listener picked. "End of this episode" is offered first (R20). */
sealed interface SleepMode {
    data object EndOfEpisode : SleepMode
    data class Minutes(val minutes: Int) : SleepMode
}

/** Where the timer stands. */
sealed interface SleepState {
    data object Off : SleepState

    /** [deadlineMs] is on the timer's clock for [SleepMode.Minutes], null for end of episode. */
    data class Armed(val mode: SleepMode, val deadlineMs: Long?) : SleepState

    /** It fired: playback paused, and nothing starts again until the listener presses play. */
    data object Fired : SleepState
}

/** What the player must do after a tick. */
data class SleepDecision(val volume: Float, val pause: Boolean)

/** The R20 rules as an interface, so a test can prove a check catches each one being broken. */
interface SleepPolicy {
    val state: SleepState
    val options: List<SleepMode>
    /** True while the player must pause at the end of the current item instead of advancing. */
    val pausesAtEndOfItem: Boolean
    fun arm(mode: SleepMode, nowMs: Long)
    fun cancel()
    /** [remainingMediaMs] is the episode's remaining media time, null when its length is unknown. */
    fun tick(nowMs: Long, remainingMediaMs: Long?, speed: Float): SleepDecision
    /** The current episode reached its end. */
    fun onItemEnded(): SleepDecision
    /** May the queue move on to the next episode by itself? */
    fun allowsAutoAdvance(): Boolean
    /** The listener pressed play: a fired timer stands down. */
    fun onUserPlay()
}

/**
 * R20: bedtime is a mode. It offers "End of this episode" first, then
 * durations; it fades the volume over the last [fadeMs] of real time; and once
 * it fires it never lets the next episode start.
 */
class SleepTimer(private val fadeMs: Long = FADE_MS) : SleepPolicy {

    companion object {
        const val FADE_MS = 10_000L
        val OPTIONS: List<SleepMode> = listOf(
            SleepMode.EndOfEpisode,
            SleepMode.Minutes(15),
            SleepMode.Minutes(30),
            SleepMode.Minutes(45),
            SleepMode.Minutes(60),
        )
        private val FULL = SleepDecision(volume = 1f, pause = false)
        private val FIRE = SleepDecision(volume = 1f, pause = true)
    }

    override var state: SleepState = SleepState.Off
        private set

    override val options: List<SleepMode> get() = OPTIONS

    override val pausesAtEndOfItem: Boolean
        get() = (state as? SleepState.Armed)?.mode == SleepMode.EndOfEpisode

    override fun arm(mode: SleepMode, nowMs: Long) {
        state = SleepState.Armed(mode, (mode as? SleepMode.Minutes)?.let { nowMs + it.minutes * 60_000L })
    }

    override fun cancel() {
        state = SleepState.Off
    }

    /** Real time left before the timer fires, or null when it cannot be known yet. */
    fun remainingMs(nowMs: Long, remainingMediaMs: Long?, speed: Float): Long? {
        val armed = state as? SleepState.Armed ?: return null
        return when (armed.mode) {
            SleepMode.EndOfEpisode -> remainingMediaMs?.let { (it / speed.coerceAtLeast(0.1f)).toLong() }
            is SleepMode.Minutes -> armed.deadlineMs!! - nowMs
        }
    }

    override fun tick(nowMs: Long, remainingMediaMs: Long?, speed: Float): SleepDecision {
        if (state !is SleepState.Armed) return FULL
        val remaining = remainingMs(nowMs, remainingMediaMs, speed) ?: return FULL
        if (remaining <= 0) {
            state = SleepState.Fired
            return FIRE
        }
        if (remaining >= fadeMs) return FULL
        return SleepDecision(volume = (remaining.toFloat() / fadeMs).coerceIn(0f, 1f), pause = false)
    }

    override fun onItemEnded(): SleepDecision {
        if ((state as? SleepState.Armed)?.mode == SleepMode.EndOfEpisode) {
            state = SleepState.Fired
            return FIRE
        }
        return if (state == SleepState.Fired) FIRE else FULL
    }

    override fun allowsAutoAdvance(): Boolean = when (val s = state) {
        SleepState.Off -> true
        SleepState.Fired -> false
        is SleepState.Armed -> s.mode != SleepMode.EndOfEpisode
    }

    override fun onUserPlay() {
        if (state == SleepState.Fired) state = SleepState.Off
    }
}
