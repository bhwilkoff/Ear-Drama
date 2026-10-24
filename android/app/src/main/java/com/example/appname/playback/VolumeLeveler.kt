package com.example.appname.playback

import android.content.Context
import android.media.audiofx.DynamicsProcessing
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * Decision 067: volume is leveled on the device as it plays, never from a
 * per-file measurement. One set of numbers on every platform (the web's
 * `Player.LEVEL`, Apple's `LevelNumbers`), so a listener moving between them
 * hears the same evenness.
 */
object LevelNumbers {
    const val THRESHOLD_DB = -24f
    const val RATIO = 4f
    const val KNEE_DB = 12f
    const val ATTACK_MS = 3f
    const val RELEASE_MS = 250f

    /** The Web Audio rule the browser applies on its own: 0.6 x the compression at 0 dBFS, here 10.8 dB. */
    val MAKEUP_DB: Float get() = 0.6f * -THRESHOLD_DB * (1 - 1 / RATIO)

    /** The limiter holds the made-up signal under this, so an onset the attack has not caught never clips. */
    const val CEILING_DB = -1f
}

/**
 * Android's own DynamicsProcessing effect (API 28, below the app's floor of 29)
 * on the player's audio session: one full-band compressor at [LevelNumbers],
 * then a limiter at -1 dBFS. On by default; the person's switch is kept on the
 * device. A device that cannot make the effect plays unleveled.
 */
class VolumeLeveler(context: Context) {
    private val prefs = context.getSharedPreferences("player", Context.MODE_PRIVATE)
    private val _on = MutableStateFlow(prefs.getBoolean(KEY, true))
    val on: StateFlow<Boolean> = _on
    private var effect: DynamicsProcessing? = null
    private var session = 0

    fun set(on: Boolean) {
        _on.value = on
        prefs.edit().putBoolean(KEY, on).apply()
        effect?.enabled = on
    }

    /** Puts the effect on [audioSessionId], replacing one on an earlier session. */
    fun attach(audioSessionId: Int) {
        if (audioSessionId == 0 || audioSessionId == session && effect != null) return
        release()
        session = audioSessionId
        effect = try {
            DynamicsProcessing(0, audioSessionId, config()).also { it.enabled = _on.value }
        } catch (e: RuntimeException) {
            println("[VolumeLeveler] no dynamics effect on this device; unleveled: ${e.message}")
            null
        }
    }

    fun release() {
        effect?.release()
        effect = null
        session = 0
    }

    private fun config(): DynamicsProcessing.Config {
        val config = DynamicsProcessing.Config.Builder(
            DynamicsProcessing.VARIANT_FAVOR_TIME_RESOLUTION, CHANNELS,
            false, 0, // no pre-EQ
            true, 1, // one full-band compressor
            false, 0, // no post-EQ
            true, // the limiter
        ).build()
        config.setMbcBandAllChannelsTo(
            0,
            DynamicsProcessing.MbcBand(
                true, FULL_BAND_HZ, LevelNumbers.ATTACK_MS, LevelNumbers.RELEASE_MS, LevelNumbers.RATIO,
                LevelNumbers.THRESHOLD_DB, LevelNumbers.KNEE_DB, NO_GATE_DB, 1f, 0f, LevelNumbers.MAKEUP_DB,
            ),
        )
        config.setLimiterAllChannelsTo(
            DynamicsProcessing.Limiter(true, true, 0, 1f, 60f, 10f, LevelNumbers.CEILING_DB, 0f),
        )
        return config
    }

    private companion object {
        const val KEY = "leveling"
        const val CHANNELS = 2
        const val FULL_BAND_HZ = 20_000f
        const val NO_GATE_DB = -90f
    }
}
