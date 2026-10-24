package com.example.appname.data

import com.example.appname.playback.PlaybackQueue
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** Decision 067, contract §3.3: a serial plays to its arc's end and stops; the next story is offered, never started. */
class ArcsTest {
    @get:Rule val tmp = TemporaryFolder()

    @Test fun `an arc's remaining parts come in part order, and only the last part names the next story`() = runBlocking {
        val db = CatalogDatabase.open(CatalogFixture.build(tmp.root, withArcs = true).path)!!
        try {
            assertEquals(ArcAhead(listOf("sus|1943-01-07", "sus|1943-05-25"), "sus|u1"), db.arcAhead("sus|1942-06-17"))
            assertEquals(ArcAhead(emptyList(), "sus|u1"), db.arcAhead("sus|1943-05-25"))
            assertEquals("the last story offers none", ArcAhead(emptyList(), null), db.arcAhead("sus|u2"))
            assertEquals("an alias resolves", ArcAhead(emptyList(), "sus|u1"), db.arcAhead("suspense|sorry-wrong-number"))
            assertNull("outside an arc", db.arcAhead("cp|1943-02-24"))
        } finally {
            db.close()
        }
    }

    @Test fun `a catalog that predates arcs has none`() = runBlocking {
        val db = CatalogDatabase.open(CatalogFixture.build(tmp.root).path)!!
        try {
            assertNull(db.arcAhead("sus|1942-06-17"))
        } finally {
            db.close()
        }
    }

    @Test fun `the arc plays to its end, then only what the person queued`() {
        val arc = ArcAhead(listOf("s|2", "s|3"), "s|4")
        assertEquals(listOf("s|2", "s|3", "q|1"), PlaybackQueue.after("s|1", arc, listOf("q|1", "s|3")))
        assertEquals("the next story is never queued", emptyList<String>(), PlaybackQueue.after("s|3", ArcAhead(emptyList(), "s|4"), emptyList()))
        assertEquals("outside an arc: the queue", listOf("q|1"), PlaybackQueue.after("x|1", null, listOf("q|1")))
        assertEquals("the last part offers it", "s|3", PlaybackQueue.offeredBy("s|1", arc))
        assertEquals("the episode itself when it is the last part", "s|3", PlaybackQueue.offeredBy("s|3", ArcAhead(emptyList(), "s|4")))
        assertNull("no next story, no offer", PlaybackQueue.offeredBy("s|1", ArcAhead(listOf("s|2"), null)))
    }
}
