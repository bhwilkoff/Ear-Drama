package com.example.appname.data

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** Contract §3.3b: "That night on the radio" is a query over the air date, and an episode row carries its network. */
class SameDayTest {
    @get:Rule val tmp = TemporaryFolder()

    @Test fun `the other broadcasts of a date, by network with unknown last, capped, never the episode itself`() = runBlocking {
        val db = CatalogDatabase.open(CatalogFixture.build(tmp.root, episodes = CatalogFixture.SAME_DAY).path)!!
        try {
            assertEquals(
                listOf("cp|1943-05-25", "sus|1943-05-25b"),
                db.sameDay("1943-05-25", "sus|1943-05-25").map { it.id },
            )
            assertEquals(listOf("ABC", null), db.sameDay("1943-05-25", "sus|1943-05-25").map { it.network })
            assertEquals("the cap", 1, db.sameDay("1943-05-25", "sus|1943-05-25", limit = 1).size)
            assertTrue("control: undated has no day", db.sameDay(null, "x").isEmpty())
            assertTrue("control: a month is not a day", db.sameDay("1943-05", "x").isEmpty())
            assertNull("an episode row carries its network", db.episodes(listOf("sus|1943-05-25b")).single().network)
            assertEquals("CBS", db.episodes(listOf("sus|1943-05-26")).single().network)
        } finally {
            db.close()
        }
    }
}
