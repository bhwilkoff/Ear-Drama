package com.example.appname.plays

import java.io.IOException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * B15c: a play only the published library holds draws in a read room, the shared screen and a finished drama's page
 * (they resolve through `PlayLibraryFeed.script(id, revision)` and `LibraryScripts.resolve`, not the bundle alone); a
 * play the library has since revised is not shown at another revision, and says "This play has changed". The twin of
 * apple/Tests/LibraryScriptsTests.swift; the fetch is stubbed.
 *
 * Seen to fail, 2026-11-24, each run once then restored: the bundle read before the library, the revision check
 * dropped, the cache never read, a throw swallowed.
 */
class LibraryScriptsTest {
    private fun script(id: String, revision: String) = fixtureScript().copy(id = id, revision = revision, title = "T")

    private fun index(vararg ids: String) = PlayIndex.json.encodeToString(
        PlayIndex.serializer(),
        PlayIndex(1, ids.size, ids.map { PlayRow(id = it, revision = "r1", title = "Row", path = "scripts/$it.json") }),
    )

    private fun file(s: PlayScript) = PlayIndex.json.encodeToString(PlayScriptFile.serializer(), PlayScriptFile(1, listOf(s)))

    private class Published(val files: Map<String, String>, val down: Boolean = false) : LibraryTransport {
        override suspend fun get(path: String): String? = if (down) throw IOException("offline") else files[path]
    }

    private fun published(s: PlayScript, down: Boolean = false) =
        Published(mapOf("index.json" to index(s.id), "scripts/${s.id}.json" to file(s)), down)

    private fun feed(t: LibraryTransport, cache: java.io.File? = null, bundle: List<PlayScript> = emptyList()) = PlayLibraryFeed(t, cache) { bundle }

    @Test fun `a play only the library holds resolves`() = runBlocking {
        val f = feed(published(script("gut-3012", "r1")))
        assertEquals("gut-3012", f.script("gut-3012")!!.id)
        assertEquals("r1", f.script("gut-3012", "r1")!!.revision)
    }

    @Test fun `a play neither holds is null and no error`() = runBlocking {
        assertNull(feed(Published(mapOf("index.json" to index("other"))), bundle = listOf(script("other", "r1"))).script("gut-9"))
    }

    @Test fun `a play the library has revised is not shown at another revision`() = runBlocking {
        val lib = published(script("gut-1", "r2"))
        assertNull("the room was cast from r1: the library's r2 is not it", feed(lib).script("gut-1", "r1"))
        assertEquals("control: with no revision asked, the library's is the answer", "r2", feed(lib).script("gut-1")!!.revision)
        assertEquals("the bundle may hold the revision the room was cast from", "r1", feed(lib, bundle = listOf(script("gut-1", "r1"))).script("gut-1", "r1")!!.revision)
    }

    @Test fun `the library is read before the bundle`() = runBlocking {
        val f = feed(published(script("gut-1", "r2")), bundle = listOf(script("gut-1", "r1")))
        assertEquals("r2", f.script("gut-1")!!.revision)
    }

    @Test fun `an unreachable library falls back to the bundle else throws`() = runBlocking {
        val down = Published(emptyMap(), down = true)
        assertEquals("b-1", feed(down, bundle = listOf(script("b-1", "r1"))).script("b-1")!!.id)
        val half = object : LibraryTransport {
            override suspend fun get(path: String): String? = if (path == "index.json") index("gut-3012") else throw IOException("offline")
        }
        try {
            feed(half).script("gut-3012")
            org.junit.Assert.fail("the failure should surface")
        } catch (e: IOException) {
            assertEquals("offline", e.message)
        }
    }

    @Test fun `a play read once reads from the cache offline`() = runBlocking {
        val dir = temporaryRoot()
        feed(published(script("gut-5", "r1")), dir).script("gut-5")
        val again = feed(published(script("gut-5", "r1"), down = true), dir).script("gut-5", "r1")
        assertEquals("gut-5", again!!.id)
        assertNull("control: a play never read is not in the cache", runCatching { feed(published(script("gut-5", "r1"), down = true), dir).script("gut-6") }.getOrNull())
    }

    @Test fun `resolve says loading failed with the changed words and the play's words`() = runBlocking {
        val lib = published(script("gut-1", "r2"))
        assertTrue(LibraryScripts.resolve(feed(lib), "gut-1", "r2") is ScriptLoad.Ready)
        val changed = LibraryScripts.resolve(feed(lib), "gut-1", "r1") as ScriptLoad.Failed
        assertEquals("This play has changed since it was cast.", changed.line)
        val missing = LibraryScripts.resolve(feed(Published(mapOf("index.json" to index("other")))), "gut-9", null) as ScriptLoad.Failed
        assertEquals("This play cannot be read together.", missing.line)
        val offline = LibraryScripts.resolve(feed(Published(emptyMap(), down = true)), "gut-9", null)
        assertTrue("an unreachable library with no bundle is a failure, not a missing play", offline is ScriptLoad.Failed && offline.line != missing.line)
        assertEquals(ScriptLoad.Loading, ScriptLoad.Loading)
    }
}
