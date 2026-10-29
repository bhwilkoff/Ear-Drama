package com.example.appname.data

import com.example.appname.account.FollowRow
import com.example.appname.account.HistoryRow
import com.example.appname.account.QueueState
import com.example.appname.account.SyncAnswer
import java.io.File
import java.nio.file.Files
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * Forwarding ids (docs/CATALOG-CONTRACT.md §3.5): every store that keeps an
 * episode id rewrites the ones the catalog moved, once, keeping each row's own
 * stamp. Fixture ids only; nothing here reads the real catalog.
 */
class IdForwardingTest {
    @get:Rule val tmp = TemporaryFolder()
    private var clock = 1_000L
    private val user by lazy { UserStore.open(tmp.newFile("user.sqlite").path) { clock } }
    private val forwarding = IdForwarding(
        aliases = mapOf("jb|1921-03-11" to "jb|1943-11-21", "jb|old-slug" to "jb|1944-01-02", "q|old" to "q|new"),
        tombstones = setOf("jb|gone"),
    )

    @Test fun `a list forwards, drops the gone, and keeps a repeat once`() {
        assertEquals(listOf("q|new", "x|unknown"), forwarding.forward(listOf("q|old", "jb|gone", "q|new", "x|unknown")))
        assertEquals("an id from a newer catalog is kept", "x|unknown", forwarding.resolve("x|unknown"))
    }

    @Test fun `progress moves once by the newer stamp, keeping its own`() = runBlocking {
        clock = 5_000; user.save("jb|1921-03-11", 600_000, 1_800_000)
        clock = 9_000; user.save("jb|1944-01-02", 300_000, 1_800_000)
        clock = 1_000; user.save("jb|old-slug", 50_000, 1_800_000)
        clock = 2_000; user.save("jb|gone", 90_000, 1_800_000)
        user.markUploaded(user.localChanges(all = false))
        clock = 5_500; user.save("jb|1921-03-11", 610_000, 1_800_000)   // changed again, not yet uploaded
        val before = user.changes.value

        assertEquals(2, user.forward(forwarding))
        assertTrue("screens re-query", user.changes.value > before)
        assertEquals(610_000L, user.progress("jb|1943-11-21")?.positionMs)
        assertNull("the old id is gone", user.progress("jb|1921-03-11"))
        assertEquals("the newer row it merged into wins", 300_000L, user.progress("jb|1944-01-02")?.positionMs)
        assertNull(user.progress("jb|old-slug"))
        assertNotNull("a tombstoned id stays: it is the listener's record", user.progress("jb|gone"))
        val owed = user.localChanges(all = false).history
        assertEquals("only the row that was owed goes up, under its new id", listOf("jb|1943-11-21"), owed.map { it.episodeId })
        assertEquals("with its own stamp", 5_500L, owed.single().updatedAt)
        assertEquals("it migrates once", 0, user.forward(forwarding))
    }

    @Test fun `follows move once by the newer stamp, keeping their own`() = runBlocking {
        val f = IdForwarding(
            seriesAliases = mapOf("jbp" to "jb", "older" to "suspense", "both" to "twin"),
            seriesTombstones = setOf("folkweave"),
        )
        clock = 5_000; user.setFollowing("jbp", true); user.setFollowing("folkweave", true)
        clock = 9_000; user.setFollowing("suspense", true); user.setFollowing("twin", false)
        clock = 1_000; user.setFollowing("older", true)
        clock = 2_000; user.setFollowing("both", true)
        user.markUploaded(user.localChanges(all = false))
        clock = 5_500; user.setFollowing("jbp", true)   // changed again, not yet uploaded

        assertEquals(3, user.forward(f))
        assertTrue("the follow moved to the new key", user.isFollowing("jb"))
        assertTrue("an older follow merges into the newer", user.isFollowing("suspense"))
        assertTrue("a newer unfollow of the new key wins", !user.isFollowing("twin"))
        assertTrue("a tombstoned key's follow stays: it is the listener's choice", user.isFollowing("folkweave"))
        assertEquals(listOf("jb", "suspense", "folkweave").sorted(), user.followed().sorted())
        val owed = user.localChanges(all = false).follows
        assertEquals("only the follow that was owed goes up, under its new key", listOf("jb"), owed.map { it.seriesId })
        assertEquals("with its own stamp", 5_500L, owed.single().updatedAt)
        assertEquals("it migrates once", 0, user.forward(f))
    }

    @Test fun `a synced follow for the old key lands on the new one`() = runBlocking {
        clock = 1_000; user.setFollowing("jb", true)
        user.markUploaded(user.localChanges(all = false))
        user.applyRemote(
            SyncAnswer(serverTime = 10, follows = listOf(FollowRow("jbp", following = false, updatedAt = 9_000, device = "web"))),
            "android",
        )
        user.forward(IdForwarding(seriesAliases = mapOf("jbp" to "jb")))
        assertTrue("another device's later unfollow wins", !user.isFollowing("jb"))
        assertTrue("a row the Worker sent is not sent back", user.localChanges(all = false).follows.isEmpty())
    }

    @Test fun `a synced row for the old id lands on the new one`() = runBlocking {
        user.applyRemote(
            SyncAnswer(
                serverTime = 10,
                history = listOf(HistoryRow("jb|1921-03-11", position = 900.0, duration = 1800.0, updatedAt = 9_000, device = "web")),
            ),
            "android",
        )
        user.forward(forwarding)
        assertEquals(900_000L, user.progress("jb|1943-11-21")?.positionMs)
        assertNull(user.progress("jb|1921-03-11"))
        assertTrue("a row the Worker sent is not sent back", user.localChanges(all = false).history.isEmpty())
    }

    @Test fun `the queue forwards keeping its stamp and dirty flag`() = runBlocking {
        clock = 4_000
        user.setQueue(listOf("q|old", "jb|gone", "q|new"))
        user.markUploaded(user.localChanges(all = false))
        assertEquals(1, user.forward(forwarding))
        assertEquals(listOf("q|new"), user.queue())
        assertNull("a rewrite is never uploaded as an edit", user.localChanges(all = false).queue)
        assertEquals(4_000L, user.localChanges(all = true).queue?.updatedAt)
        assertEquals(0, user.forward(forwarding))
        user.applyRemote(SyncAnswer(10, queue = QueueState(listOf("jb|1921-03-11", "jb|gone"), 9_000, "web")), "android")
        user.forward(forwarding)
        assertEquals("a synced queue forwards too", listOf("jb|1943-11-21"), user.queue())
    }
}

class DownloadForwardingTest {
    private class NoTransport : DownloadTransport {
        override fun begin(token: String, url: String) {}
        override fun cancel(token: String) {}
        override fun cancelAll() {}
        override suspend fun liveTokens() = emptySet<String>()
    }

    private val dir: File = Files.createTempDirectory("downloads").toFile()

    @After fun cleanUp() { dir.deleteRecursively() }

    @Test fun `a download is re-keyed and its file keeps its name`() {
        val store = DownloadStore(dir, NoTransport()) { 0L }
        val url = "https://archive.org/download/PDP_JackBenny/Jack%20Benny%20Show,%20The%2043-11-21.mp3"
        store.download("jb|1921-03-11", "No. 4", "The Jack Benny Program", "jbp", url)
        store.download("q|old", "Old", "Q", "q", url)
        store.download("q|new", "New", "Q", "q", url)
        val fileName = store.record("jb|1921-03-11")!!.fileName
        store.forward(
            IdForwarding(
                mapOf("jb|1921-03-11" to "jb|1943-11-21", "q|old" to "q|new"),
                seriesAliases = mapOf("jbp" to "jb"),
            ),
        )
        assertEquals("the series key forwards like a follow", "jb", store.record("jb|1943-11-21")?.seriesKey)
        assertTrue(store.hasDownloads("jb") && !store.hasDownloads("jbp"))
        assertNull(store.record("jb|1921-03-11"))
        assertEquals("the file keeps its name", fileName, store.record("jb|1943-11-21")?.fileName)
        assertEquals("jb|1943-11-21", store.record("jb|1943-11-21")?.episodeId)
        assertEquals("the new id's own download is kept", "New", store.record("q|new")?.title)
        assertNull("the moved second copy goes", store.record("q|old"))
        assertNotNull("the index is saved", DownloadStore(dir, NoTransport()) { 0L }.record("jb|1943-11-21"))
    }
}
