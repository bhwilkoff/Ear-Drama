package com.example.appname.playback

/**
 * What may play after an episode ends (Decision 067, the owner's rule until
 * serial arcs exist): one episode, then whatever the person queued, whatever
 * its series, then stop. Nothing the person did not choose starts by itself.
 * The same rule as the web's `Player.nextInQueue` and Apple's `PlaybackQueue`.
 */
object PlaybackQueue {
    /** The person's queue behind [episodeId], in order, without the episode itself. */
    fun after(episodeId: String, queued: List<String>): List<String> = queued.filter { it != episodeId }.distinct()
}
