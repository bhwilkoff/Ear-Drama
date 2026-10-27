package com.example.appname.app

import com.example.appname.data.UserStore
import com.example.appname.playback.PlaybackEngine

/**
 * The person's queue verbs: each edits the synced queue, then tells the player
 * to rebuild what follows the playing episode. None of them changes what plays
 * next (Decision 067); they only order what the person chose.
 */
class QueueVerbs(private val user: UserStore, private val playback: PlaybackEngine) {
    suspend fun add(id: String) { user.enqueue(id); playback.queueChanged() }
    suspend fun remove(id: String) { user.dequeue(id); playback.queueChanged() }
    suspend fun move(id: String, delta: Int) { user.moveInQueue(id, delta); playback.queueChanged() }
    suspend fun reorder(ids: List<String>) { user.reorderQueue(ids); playback.queueChanged() }
}
