package com.example.appname.playback

import com.example.appname.data.EpisodeDetail
import kotlin.math.min
import kotlin.math.pow

/**
 * DECISIONS 061: play at -21 LUFS, reached by cutting. A volume factor in
 * (0, 1]: the gain is -21 - I, clamped so the true peak stays at or below
 * -1 dBTP, and never above 0 dB (ExoPlayer's volume cannot boost). Unmeasured
 * plays at 1. The same numbers as the web's `API.playbackVolume` (js/api.js).
 */
object LoudnessLevel {
    const val TARGET = -21.0

    fun volume(i: Double?, tp: Double?): Float {
        if (i == null || !i.isFinite()) return 1f
        var gain = TARGET - i
        if (tp != null && tp.isFinite()) gain = min(gain, -1 - tp)
        gain = min(gain, 0.0)
        return 10.0.pow(gain / 20).toFloat()
    }

    /** The measurement belongs to the default (rank 0) copy only; any other version plays at unity. */
    fun volume(detail: EpisodeDetail, url: String): Float =
        if (detail.recordings.firstOrNull { it.rank == 0 }?.url == url) volume(detail.loudnessI, detail.loudnessTp)
        else 1f
}
