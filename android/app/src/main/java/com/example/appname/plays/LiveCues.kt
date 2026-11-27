package com.example.appname.plays

import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Handler
import android.os.Looper
import java.io.File
import kotlin.math.pow
import kotlinx.coroutines.CompletableDeferred

/**
 * The Sound part's cues in a live listen (B32 section 4.4: close, not sample-exact), the mirror of Apple's `LiveCues.swift` and
 * the web's `liveCues`: each sound starts as its entry comes, loops for Under-to-the-end and beds, and drops by its duck while a
 * voice sounds. The export is the computed mix (`MixRenderer`); this is only what a listen hears. A sound with no file here
 * plays nothing.
 */
interface ListenCuePlayer {
    /** Starts a cue; null when its file is not on this device. */
    fun start(cue: SoundCore.LiveCue, file: File?): LiveCueHandle?
    fun stopAll()
}

/** One sounding cue. */
interface LiveCueHandle {
    val soundID: String
    val isBed: Boolean
    fun duck(on: Boolean)
    fun stop()

    /** Returns when the cue has played out (a loop only when stopped). */
    suspend fun done()
}

/** The cues a listen plays: what each plan entry holds, and where each sound's file is. */
class ListenCues(val entries: List<SoundCore.EntryCues>, val file: (SoundSource) -> File?, val player: ListenCuePlayer)

/** MediaPlayer per cue: the level from the cue's gain, fades and the duck as volume ramps. */
class SystemCuePlayer(private val muted: Boolean = false) : ListenCuePlayer {
    private val playing = ArrayList<SystemCueHandle>()

    override fun start(cue: SoundCore.LiveCue, file: File?): LiveCueHandle? {
        if (file == null || !file.isFile) return null
        val x = cue.sound
        val music = x.at == "bed"
        val duckDb = x.duckDb ?: if (music) MixSound.Defaults.MUSIC_DUCK_DB else MixSound.Defaults.EFFECTS_DUCK_DB
        val gain = MixSound.clampNum(x.gainDb, MixSound.Defaults.GAIN_MIN_DB, MixSound.Defaults.GAIN_MAX_DB, 0.0)
        val level = if (muted) 0f else 10.0.pow(gain / 20).toFloat()
        val player = runCatching {
            MediaPlayer().apply {
                setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
                setDataSource(file.path)
                isLooping = x.loop
                prepare()
            }
        }.getOrNull() ?: return null
        val handle = SystemCueHandle(player, x.id, music, level, duckDb, x.fadeInMs, x.fadeOutMs, maxOf(0.0, x.startMs))
        playing.removeAll { !it.alive }
        playing += handle
        return handle
    }

    override fun stopAll() {
        playing.toList().forEach { it.stop(immediate = true) }
        playing.clear()
    }
}

class SystemCueHandle(
    private val player: MediaPlayer,
    override val soundID: String,
    override val isBed: Boolean,
    private val level: Float,
    private val duckDb: Double,
    fadeInMs: Double,
    private val fadeOutMs: Double,
    delayMs: Double,
) : LiveCueHandle {
    private val main = Handler(Looper.getMainLooper())
    private val finished = CompletableDeferred<Unit>()
    private var volume = if (fadeInMs > 0) 0f else level
    private var ramp: Runnable? = null

    @Volatile
    var alive = true
        private set

    init {
        player.setVolume(volume, volume)
        player.setOnCompletionListener { finish() }
        main.postDelayed({ if (alive) { player.start(); if (fadeInMs > 0) rampTo(level, fadeInMs) } }, delayMs.toLong())
    }

    private fun rampTo(to: Float, ms: Double, then: (() -> Unit)? = null) {
        ramp?.let(main::removeCallbacks)
        val from = volume
        val began = System.currentTimeMillis()
        val step = object : Runnable {
            override fun run() {
                if (!alive) return
                val t = if (ms <= 0) 1.0 else ((System.currentTimeMillis() - began) / ms).coerceIn(0.0, 1.0)
                volume = (from + (to - from) * t).toFloat()
                runCatching { player.setVolume(volume, volume) }
                if (t < 1.0) main.postDelayed(this, 20) else then?.invoke()
            }
        }
        ramp = step
        main.post(step)
    }

    override fun duck(on: Boolean) {
        if (!alive || duckDb >= 0) return
        rampTo(if (on) level * 10.0.pow(duckDb / 20).toFloat() else level, if (on) MixSound.Defaults.ATTACK_MS else MixSound.Defaults.RELEASE_MS)
    }

    override fun stop() = stop(immediate = false)

    fun stop(immediate: Boolean) {
        if (!alive) return
        if (!immediate && fadeOutMs > 0 && runCatching { player.isPlaying }.getOrDefault(false)) rampTo(0f, fadeOutMs) { finish() } else finish()
    }

    override suspend fun done() {
        if (alive) finished.await()
    }

    private fun finish() {
        if (!alive) return
        alive = false
        main.removeCallbacksAndMessages(null)
        runCatching { player.stop() }
        runCatching { player.release() }
        finished.complete(Unit)
    }
}
