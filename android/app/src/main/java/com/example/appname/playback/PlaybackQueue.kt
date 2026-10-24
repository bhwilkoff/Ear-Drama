package com.example.appname.playback

import com.example.appname.data.ArcAhead

/**
 * What may play after an episode ends (Decision 067): a part of a story arc is
 * followed by the arc's remaining parts; at the arc's last part the next story
 * is offered, never started. After the arc (or outside one), whatever the
 * person queued, whatever its series, then stop. Nothing the person did not
 * choose starts by itself. The same rule as the web's `Player.upNext` and
 * Apple's `PlaybackQueue`.
 */
object PlaybackQueue {
    /** The person's queue behind [episodeId], in order, without the episode itself. */
    fun after(episodeId: String, queued: List<String>): List<String> = queued.filter { it != episodeId }.distinct()

    /** The arc's remaining parts, then the person's queue, each episode once. */
    fun after(episodeId: String, arc: ArcAhead?, queued: List<String>): List<String> =
        (arc?.rest.orEmpty() + queued).filter { it != episodeId }.distinct()

    /** The episode that offers [arc]'s next story: its last part (the episode itself when nothing is ahead). */
    fun offeredBy(episodeId: String, arc: ArcAhead?): String? =
        if (arc?.nextStory == null) null else arc.rest.lastOrNull() ?: episodeId
}
