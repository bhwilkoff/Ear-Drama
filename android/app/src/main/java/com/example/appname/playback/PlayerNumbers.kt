package com.example.appname.playback

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
     * Only an interruption rewinds ([rewound]); a finished episode starts over.
     */
    fun fromSaved(positionMs: Long, finished: Boolean): Long = if (finished) 0 else positionMs.coerceAtLeast(0)
}
