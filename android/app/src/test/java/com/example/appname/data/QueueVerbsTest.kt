package com.example.appname.data

import com.example.appname.playback.PlaybackQueue
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * The queue verbs (the web's `enqueue`, `dequeue`, `moveInQueue`): add, remove,
 * reorder, no duplicates, written to the synced queue with its own stamp, and
 * the plays-next rule (Decision 067) untouched by the order.
 */
class QueueVerbsTest {
    @get:Rule val tmp = TemporaryFolder()
    private var clock = 1_000L
    private val user by lazy { UserStore.open(tmp.newFile("user.sqlite").path) { clock } }

    @Test fun `adding appends and an episode queued twice moves to the end`() {
        assertEquals(listOf("a", "b", "c"), QueueEdit.add(listOf("a", "b"), "c"))
        assertEquals(listOf("b", "c", "a"), QueueEdit.add(listOf("a", "b", "c"), "a"))
    }

    @Test fun `removing drops one and ignores an episode that is not queued`() {
        assertEquals(listOf("a", "c"), QueueEdit.remove(listOf("a", "b", "c"), "b"))
        assertEquals(listOf("a"), QueueEdit.remove(listOf("a"), "zzz"))
    }

    @Test fun `moving swaps one step and stops at the ends`() {
        assertEquals(listOf("a", "c", "b"), QueueEdit.move(listOf("a", "b", "c"), "c", -1))
        assertEquals(listOf("a", "b", "c"), QueueEdit.move(listOf("a", "b", "c"), "a", -1))
        assertEquals(listOf("a", "b", "c"), QueueEdit.move(listOf("a", "b", "c"), "c", 1))
        assertEquals(listOf("a", "b"), QueueEdit.move(listOf("a", "b"), "nope", 1))
    }

    @Test fun `a drag keeps what the list did not name and drops duplicates`() {
        assertEquals(listOf("c", "a", "b", "d"), QueueEdit.reorder(listOf("a", "b", "c", "d"), listOf("c", "a", "a", "nope")))
    }

    @Test fun `the verbs write the synced queue with a new stamp and bump the screens' key`() = runBlocking {
        user.enqueue("a")
        clock = 2_000
        user.enqueue("b")
        clock = 3_000
        user.moveInQueue("b", -1)
        assertEquals(listOf("b", "a"), user.queue())
        assertEquals(3_000L, user.localChanges(all = false).queue?.updatedAt)

        val before = user.changes.value
        clock = 4_000
        user.dequeue("zzz")
        assertEquals("an edit that changes nothing writes nothing", before, user.changes.value)
        assertEquals(3_000L, user.localChanges(all = false).queue?.updatedAt)

        user.dequeue("b")
        assertEquals(listOf("a"), user.queue())
        assertTrue(user.changes.value > before)
        user.dequeue("a")
        assertEquals(emptyList<String>(), user.queue())
    }

    @Test fun `the order never changes the rule, the queue follows minus the episode playing`() {
        val queued = QueueEdit.move(listOf("a", "b", "c"), "c", -1)
        assertEquals(listOf("c", "b"), PlaybackQueue.after("a", queued))
        assertEquals(listOf("a", "b"), PlaybackQueue.after("c", queued))
    }
}
