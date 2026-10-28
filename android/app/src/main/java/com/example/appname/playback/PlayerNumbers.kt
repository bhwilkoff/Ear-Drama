package com.example.appname.playback

import com.example.appname.data.UserStore

/**
 * DECISIONS 062: one set of player numbers on every platform. The web
 * (`js/player.js`) and Apple (`AudioPlayer`) carry the same values; change
 * them together or not at all.
 */
object PlayerNumbers {
    /** The sleep timer fades the volume over its last 10 seconds. */
    const val SLEEP_FADE_MS = 10_000L

    val SPEEDS: List<Float> = listOf(0.75f, 1f, 1.25f, 1.5f, 2f)

    /** The listening position saves this often while playing, and on every pause. */
    const val SAVE_EVERY_MS = 5_000L

    /** Resuming after an interruption starts this far back, so the last line is heard again. */
    const val RESUME_REWIND_MS = 3_000L

    /** Where playback resumes after an interruption (audio focus handed back) at [positionMs]. */
    fun rewound(positionMs: Long): Long = (positionMs - RESUME_REWIND_MS).coerceAtLeast(0)

    /**
     * Where a saved position resumes: exactly where it was saved, as on the web.
     * Only an interruption rewinds ([rewound]); a finished episode starts over,
     * and so does a place at or past the catalog's [lengthMs] less the finished
     * slack (a duration once misread as longer than the recording saved one).
     */
    fun fromSaved(positionMs: Long, finished: Boolean, lengthMs: Long? = null): Long = when {
        finished -> 0
        lengthMs != null && lengthMs > 0 && positionMs >= lengthMs - UserStore.FINISHED_WITHIN_MS -> 0
        else -> positionMs.coerceAtLeast(0)
    }
}
