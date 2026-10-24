package com.example.appname.data

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** Decision 068, contract §3.1: an episode's linked script reaches Detail and Browse; an older catalog links none. */
class EpisodeScriptTest {
    @get:Rule val tmp = TemporaryFolder()

    @Test fun `Detail and Browse carry the linked script`() = runBlocking {
        val db = CatalogDatabase.open(CatalogFixture.build(tmp.root, withScript = true).path)!!
        try {
            assertEquals("grw-A1", db.episodeDetail("sus|1943-05-25")?.script)
            assertNull(db.episodeDetail("sus|1943-01-07")?.script)
            assertEquals(mapOf("suspense" to listOf("grw-A1")), db.scriptedSeries())
        } finally {
            db.close()
        }
    }

    @Test fun `a catalog without the column links none`() = runBlocking {
        val db = CatalogDatabase.open(CatalogFixture.build(tmp.root).path)!!
        try {
            assertNull(db.episodeDetail("sus|1943-05-25")?.script)
            assertTrue(db.scriptedSeries().isEmpty())
        } finally {
            db.close()
        }
    }
}
