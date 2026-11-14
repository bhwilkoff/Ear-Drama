package com.example.appname.plays

import java.io.File
import java.io.IOException
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/**
 * The play library as the lists read it (contract §4.1; mirrors api.test.js "the play library"): a stubbed fetch returns
 * the index (rows read, the bundle not read for the list), a missing index (the copy kept, else bundle rows), a library
 * script file, a script only in the bundle, an offline library script that is not bundled (the error surfaces); and
 * Home's Open parts (only shared productions someone else directs, speaking parts only).
 *
 * Seen to fail, 2026-11-14, then restored: `script` swallowing the fetch failure (`an offline library script that is
 * not bundled surfaces the error`).
 */
class PlayLibraryFeedTest {
    private val bundled = fixtureScript().copy(id = "gut-0", title = "Bundled")
    private val row = PlayRow(id = "gut-9", revision = "r9", title = "Library Play", voices = 3, minutes = 12, cast = listOf(9, 5, 1), lines = 15, path = "scripts/gut-9.json")
    private val indexText = PlayIndex.json.encodeToString(PlayIndex.serializer(), PlayIndex(1, 1, listOf(row)))
    private val scriptText = PlayIndex.json.encodeToString(PlayScriptFile.serializer(), PlayScriptFile(1, listOf(fixtureScript().copy(id = "gut-9", revision = "r9", title = "Library Play"))))

    private class Stub(val files: Map<String, String?>, val fail: Boolean = false) : LibraryTransport {
        val asked = mutableListOf<String>()
        override suspend fun get(path: String): String? {
            asked += path
            if (fail) throw IOException("offline")
            return files[path]
        }
    }

    private fun feed(t: LibraryTransport, cache: File? = null, bundleRead: () -> Unit = {}) =
        PlayLibraryFeed(t, cache) { bundleRead(); listOf(bundled) }

    @Test fun `the published index is the list, and the bundle is not read for it`() = runBlocking {
        var bundleReads = 0
        val f = feed(Stub(mapOf("index.json" to indexText))) { bundleReads++ }
        f.loadRows()
        val rows = f.rows.value as PlayLibraryFeed.Rows.Ready
        assertTrue(rows.published)
        assertEquals(listOf("gut-9"), rows.rows.map { it.id })
        assertEquals(0, bundleReads)
    }

    @Test fun `a missing index falls back to the bundle's rows`() = runBlocking {
        val f = feed(Stub(emptyMap()))
        f.loadRows()
        val rows = f.rows.value as PlayLibraryFeed.Rows.Ready
        assertEquals(false, rows.published)
        assertEquals(listOf("gut-0"), rows.rows.map { it.id })
        assertEquals(bundled.voices, rows.rows[0].voices)
    }

    @Test fun `an unreachable index reads the copy this device kept, else the bundle`() = runBlocking {
        val dir = temporaryRoot()
        feed(Stub(mapOf("index.json" to indexText)), dir).loadRows()
        val offline = feed(Stub(emptyMap(), fail = true), dir)
        offline.loadRows()
        assertEquals(listOf("gut-9"), (offline.rows.value as PlayLibraryFeed.Rows.Ready).rows.map { it.id })
        val bare = feed(Stub(emptyMap(), fail = true), temporaryRoot())
        bare.loadRows()
        assertEquals(listOf("gut-0"), (bare.rows.value as PlayLibraryFeed.Rows.Ready).rows.map { it.id })
    }

    @Test fun `no index and no bundle is unavailable`() = runBlocking {
        val f = PlayLibraryFeed(Stub(emptyMap()), null) { emptyList() }
        f.loadRows()
        assertEquals(PlayLibraryFeed.Rows.Unavailable, f.rows.value)
    }

    @Test fun `a library script opens from its file, and is kept for offline`() = runBlocking {
        val dir = temporaryRoot()
        val t = Stub(mapOf("index.json" to indexText, "scripts/gut-9.json" to scriptText))
        val s = feed(t, dir).script("gut-9")
        assertEquals("Library Play", s!!.title)
        assertEquals(1, t.asked.count { it == "scripts/gut-9.json" })
        val again = feed(Stub(mapOf("index.json" to indexText), fail = false), dir).script("gut-9")
        assertEquals("the kept file opens with no fetch", "Library Play", again!!.title)
    }

    @Test fun `a script only in the bundle opens from the bundle`() = runBlocking {
        val f = feed(Stub(mapOf("index.json" to indexText)))
        assertEquals("Bundled", f.script("gut-0")!!.title)
        assertNull(f.script("gut-nowhere"))
    }

    @Test fun `an offline library script that is not bundled surfaces the error`() = runBlocking {
        val f = feed(Stub(mapOf("index.json" to indexText, "scripts/gut-9.json" to null), fail = false))
        f.loadRows()
        val dead = PlayLibraryFeed(object : LibraryTransport {
            override suspend fun get(path: String): String? = if (path == "index.json") indexText else throw IOException("offline")
        }, null) { listOf(bundled) }
        try {
            dead.script("gut-9")
            fail("the failure should surface")
        } catch (e: IOException) {
            assertNotNull(e.message)
        }
    }

    // MARK: Open parts

    private class Worker(val rows: List<RemoteRow>, val records: Map<String, SharedRecord>) : PlaysTransport {
        override suspend fun consent() = error("not used")
        override suspend fun create(body: JsonObject) = error("not used")
        override suspend fun list() = rows
        override suspend fun get(pid: String) = records.getValue(pid)
        override suspend fun invite(pid: String) = error("not used")
        override suspend fun viewInvite(token: String) = error("not used")
        override suspend fun joinByInvite(token: String, part: String, displayName: String?) = error("not used")
        override suspend fun claim(pid: String, part: String) = error("not used")
        override suspend fun partAction(pid: String, part: String, action: String) = error("not used")
        override suspend fun agree(pid: String, version: String) = error("not used")
        override suspend fun upload(pid: String, takeId: String, bytes: ByteArray, meta: JsonObject) = error("not used")
        override suspend fun audio(pid: String, takeId: String) = error("not used")
        override suspend fun choose(pid: String, takeId: String) = error("not used")
        override suspend fun publish(pid: String) = error("not used")
        override suspend fun removeLine(pid: String, lineId: String, reason: String) = error("not used")
        override suspend fun report(pid: String, takeId: String?, userId: String?, reason: String, note: String?) = error("not used")
        override suspend fun block(userId: String) = error("not used")
        override suspend fun classes() = error("not used")
        override suspend fun classDetail(id: String) = error("not used")
        override suspend fun createClass(name: String, under13: Boolean) = error("not used")
        override suspend fun joinClass(code: String, displayName: String?) = error("not used")
    }

    @Test fun `open parts leave out the person's own productions and count only open speaking parts`() = runBlocking {
        val s = fixtureScript()
        fun rec(id: String, parts: Map<String, SharedPart>) = SharedRecord(id, s.id, s.revision, "T-$id", parts = parts, director = "someone")
        val rows = listOf(
            RemoteRow("mine", "Mine", s.id, director = "me", updatedAt = 9),
            RemoteRow("theirs", "Theirs", s.id, director = "ann", updatedAt = 8),
            RemoteRow("full", "Full", s.id, director = "ann", updatedAt = 7),
            RemoteRow("nodir", "No director", s.id, director = null, updatedAt = 6),
        )
        val records = mapOf(
            "mine" to rec("mine", emptyMap()),
            "theirs" to rec("theirs", mapOf("role:MOLLY" to SharedPart("done"), "directions" to SharedPart("open"), "sound" to SharedPart("open"))),
            "full" to rec("full", mapOf("role:MOLLY" to SharedPart("done"), "role:FIBBER" to SharedPart("done"), "role:DOC" to SharedPart("done"))),
            "nodir" to rec("nodir", emptyMap()),
        )
        val sharing = SharedPlays(Worker(rows, records), PlaysShareTestStore(), { "me" }, { listOf(s) })
        val open = sharing.openParts()
        assertEquals(listOf("theirs"), open.map { it.row.id })
        assertEquals("FIBBER and DOC are open; directions and sound are not parts", 2, open[0].open)
        assertTrue(SharedPlays(Worker(rows, records), PlaysShareTestStore(), { null }, { listOf(s) }).openParts().isEmpty())
    }

    private class PlaysShareTestStore : ShareStore {
        override fun all() = emptyList<Production>()
        override fun production(id: String): Production? = null
        override fun save(production: Production) = Unit
        override fun create(script: PlayScript) = Production.create(script)
        override fun share(id: String): ShareLink? = null
        override fun setShare(id: String, link: ShareLink) = Unit
        override fun findShared(pid: String): Production? = null
        override fun readTake(id: String, file: String) = ByteArray(0)
        override fun importTake(id: String, file: String, bytes: ByteArray) = Unit
    }
}
