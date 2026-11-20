package com.example.appname.plays

import org.junit.Test
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue

/**
 * The class page's review queue (PLAYS-DESIGN §12.4 Review, §12.11), the mirror of `reviewQueue` in js/class-ui.js and Apple's
 * ClassReviewTests: the seats' chosen takes with no review, in play order then script order.
 */
class ClassReviewTest {
    private fun take(id: String, line: String, seat: String? = "s1") = SharedTake(id, line, "role:LUCY", "$id.wav", seat = seat)
    private fun record(id: String, title: String, takes: List<SharedTake>, chosen: Map<String, String>, reviews: Map<String, SharedReview> = emptyMap()) =
        SharedRecord(id = id, scriptID = "s", scriptRevision = "r1", title = title, takes = takes, chosen = chosen, reviews = reviews)
    private val order: (SharedRecord, String) -> Int = { _, line -> line.drop(1).toIntOrNull() ?: -1 }

    @Test fun aTakeFromTheRoomNeverWaits() {
        val r = record("p", "A", listOf(take("t1", "l1", seat = null)), mapOf("l1" to "t1"))
        assertTrue(ClassReview.queue(listOf(r), order).isEmpty())
    }

    @Test fun onlyTheChosenTakeWaits() {
        val r = record("p", "A", listOf(take("t1", "l1"), take("t2", "l1")), mapOf("l1" to "t2"))
        assertEquals(listOf("t2"), ClassReview.queue(listOf(r), order).map { it.id })
    }

    @Test fun aReviewedTakeLeavesTheQueue() {
        val r = record("p", "A", listOf(take("t1", "l1"), take("t2", "l2")), mapOf("l1" to "t1", "l2" to "t2"), mapOf("t1" to SharedReview("approved")))
        assertEquals(listOf("t2"), ClassReview.queue(listOf(r), order).map { it.id })
    }

    @Test fun theQueueRunsInPlayThenScriptOrder() {
        val b = record("pb", "B Play", listOf(take("tb", "l1")), mapOf("l1" to "tb"))
        val a = record("pa", "A Play", listOf(take("z9", "l9"), take("a1", "l2")), mapOf("l9" to "z9", "l2" to "a1"))
        assertEquals(listOf("a1", "z9", "tb"), ClassReview.queue(listOf(b, a), order).map { it.id })
    }

    @Test fun theCountReadsAsWords() {
        assertNull(ClassReview.waiting(0))
        assertEquals("1 take to review", ClassReview.waiting(1))
        assertEquals("4 takes to review", ClassReview.waiting(4))
    }

    @Test fun anEmptyNoteIsNoNote() {
        assertNull(ClassReview.note("  \n "))
        assertEquals("keep the pause", ClassReview.note(" keep the pause "))
        assertEquals(500, ClassReview.note("a".repeat(600))?.length)
    }

    @Test fun theRecordCarriesSeatAndReviewsFromTheWorker() {
        val json = """{"id":"p","scriptID":"s","scriptRevision":"r1","title":"T","takes":[{"id":"t1","lineID":"l1","part":"role:LUCY","file":"t1.wav","seat":"s1"}],"chosen":{"l1":"t1"},"reviews":{"t1":{"state":"again","note":"slower"}}}"""
        val r = ShareJson.decodeFromString(SharedRecord.serializer(), json)
        assertEquals("s1", r.takes.first().seat)
        assertEquals(SharedReview("again", "slower"), r.reviews["t1"])
        assertTrue(ClassReview.queue(listOf(r), order).isEmpty())
    }
}
