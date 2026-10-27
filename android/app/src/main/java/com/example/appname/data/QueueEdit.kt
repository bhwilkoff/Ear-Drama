package com.example.appname.data

/**
 * The queue verbs as pure list edits, the web's `Store.enqueue`, `dequeue`, and
 * `moveInQueue`, and Apple's `ListeningQueue`. They only order what the
 * person chose; what plays next stays `PlaybackQueue` (Decision 067).
 */
object QueueEdit {
    /** Adds to the end; an episode already queued moves to the end. */
    fun add(queue: List<String>, id: String): List<String> = queue.filter { it != id } + id

    fun remove(queue: List<String>, id: String): List<String> = queue.filter { it != id }

    /** One step up (-1) or down (+1); at an end, or for an id not queued, nothing changes. */
    fun move(queue: List<String>, id: String, delta: Int): List<String> {
        val i = queue.indexOf(id)
        val j = i + delta
        if (i < 0 || j !in queue.indices) return queue
        return queue.toMutableList().also { it[i] = queue[j]; it[j] = id }
    }

    /** The ids in a new order; queued ids the list did not name follow them, unknown ids are ignored. */
    fun reorder(queue: List<String>, ids: List<String>): List<String> {
        val named = ids.distinct().filter { it in queue }
        return named + queue.filter { it !in named }
    }
}
