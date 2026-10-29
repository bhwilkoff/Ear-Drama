package com.example.appname.account

import com.example.appname.data.UserStore
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** DECISIONS 063: the anonymous merge goes once; a pull applies last write wins, removals as markers. */
class SyncEngineTest {
    @get:Rule val tmp = TemporaryFolder()

    private var clock = 1_000_000L
    private val fake = FakeWorker { clock }
    private val user by lazy { UserStore.open(tmp.newFile("user.sqlite").path) { clock } }

    private fun engine(account: StoredAccount?): Pair<WorkerApi, SyncEngine> {
        val api = WorkerApi(fake.client, fake.config, MemorySessionStore(account)) { clock }
        return api to SyncEngine(api, user, "android") { clock }
    }

    @Test fun `the signed-out history is merged once, then only changes go up`() = runBlocking {
        user.save("sus|1943-01-07", 600_000, 1_800_000)
        user.save("cp|1944-01-07", 1_790_000, 1_800_000)
        fake.answer = SyncAnswer(serverTime = 7_000)
        val (api, sync) = engine(null)
        api.signIn("google", "id-token", "nonce", "android")

        assertTrue(sync.sync())
        assertEquals(1, fake.count("POST", "/v1/sync/merge"))
        val merged = WorkerJson.decodeFromString<SyncUpload>(fake.last("POST", "/v1/sync/merge").body!!)
        assertEquals(setOf("sus|1943-01-07", "cp|1944-01-07"), merged.history!!.map { it.episodeId }.toSet())
        assertEquals(600.0, merged.history.first { it.episodeId == "sus|1943-01-07" }.position, 0.0)
        assertEquals("the first read after the merge is everything", "/v1/sync?since=0", fake.last("GET", "/v1/sync").path)
        assertFalse(api.account.value!!.mergePending)

        assertTrue(sync.sync())
        assertEquals("the merge is sent once", 1, fake.count("POST", "/v1/sync/merge"))
        assertEquals("nothing changed, nothing sent", 0, fake.count("PUT", "/v1/sync"))
        assertEquals("/v1/sync?since=7000", fake.last("GET", "/v1/sync").path)

        clock += 1_000
        user.save("sus|1943-01-07", 700_000, 1_800_000)
        assertTrue(sync.sync())
        val put = WorkerJson.decodeFromString<SyncUpload>(fake.last("PUT", "/v1/sync").body!!)
        assertEquals(listOf("sus|1943-01-07"), put.history!!.map { it.episodeId })
        assertNotNull(api.account.value!!.lastSyncAt)
    }

    @Test fun `a pulled row for an id the catalog moved lands on the id it now is`() = runBlocking {
        val api = WorkerApi(fake.client, fake.config, MemorySessionStore(fake.account())) { clock }
        val forwarding = com.example.appname.data.IdForwarding(mapOf("jb|1921-03-11" to "jb|1943-11-21"))
        val sync = SyncEngine(api, user, "android", forwarding = { forwarding }) { clock }
        fake.answer = SyncAnswer(
            serverTime = 9_000,
            history = listOf(HistoryRow("jb|1921-03-11", position = 900.0, duration = 1800.0, updatedAt = 8_000, device = "web")),
            queue = QueueState(listOf("jb|1921-03-11"), 8_000, "web"),
        )
        assertTrue(sync.sync())
        assertEquals(900_000L, user.progress("jb|1943-11-21")?.positionMs)
        assertNull(user.progress("jb|1921-03-11"))
        assertEquals(listOf("jb|1943-11-21"), user.queue())
    }

    @Test fun `a merge that fails stays pending and is retried`() = runBlocking {
        user.save("sus|1943-01-07", 600_000, 1_800_000)
        val (api, sync) = engine(fake.account(mergePending = true))
        fake.failNext["/v1/sync/merge"] = 503
        assertFalse(sync.sync())
        assertEquals("Sync failed: the server answered 503.", api.account.value!!.lastError)
        assertTrue(api.account.value!!.mergePending)
        assertTrue(sync.sync())
        assertFalse(api.account.value!!.mergePending)
        assertNull(api.account.value!!.lastError)
    }

    @Test fun `a pull applies last write wins, with markers`() = runBlocking {
        clock = 1_000
        user.save("clean|1", 100_000, 1_800_000)
        user.setFollowing("dropped", true)
        user.markUploaded(user.localChanges(all = true))
        clock = 5_000
        user.save("mine|1", 300_000, 1_800_000) // changed here, not yet sent
        user.save("tie|1", 400_000, 1_800_000)

        user.applyRemote(
            SyncAnswer(
                serverTime = 9_000,
                history = listOf(
                    HistoryRow("mine|1", position = 50.0, duration = 1800.0, updatedAt = 4_000, device = "iphone"),
                    HistoryRow("clean|1", deleted = true, updatedAt = 2_000, device = "web"),
                    HistoryRow("new|1", position = 120.0, duration = 1800.0, updatedAt = 3_000, device = "web"),
                    // Equal stamps: the Worker keeps the later device name; "web" sorts after "android".
                    HistoryRow("tie|1", position = 60.0, duration = 1800.0, updatedAt = 5_000, device = "web"),
                ),
                follows = listOf(
                    FollowRow("dropped", following = false, updatedAt = 3_000, device = "web"),
                    FollowRow("added", following = true, updatedAt = 3_000, device = "web"),
                ),
                queue = QueueState(listOf("new|1", "mine|1"), updatedAt = 3_000, device = "web"),
            ),
            device = "android",
        )

        assertEquals("the newer local row stays", 300_000L, user.progress("mine|1")!!.positionMs)
        assertNull("a removal marker removes the row", user.progress("clean|1"))
        assertEquals(120_000L, user.progress("new|1")!!.positionMs)
        assertEquals("an equal stamp goes to the later device name", 60_000L, user.progress("tie|1")!!.positionMs)
        assertEquals(setOf("mine|1", "new|1", "tie|1"), user.inProgress().map { it.episodeId }.toSet())
        assertEquals(listOf("added"), user.followed())
        assertEquals(listOf("new|1", "mine|1"), user.queue())

        val pending = user.localChanges(all = false)
        assertEquals("only the kept local row goes up", listOf("mine|1"), pending.history.map { it.episodeId })
        assertTrue("applied rows are clean", pending.follows.isEmpty() && pending.queue == null)
    }

    @Test fun `local removals go up as markers`() = runBlocking {
        val (_, sync) = engine(fake.account())
        user.save("gone|1", 300_000, 1_800_000)
        user.setFollowing("series", true)
        assertTrue(sync.sync())
        clock += 1_000
        user.forget("gone|1")
        user.setFollowing("series", false)
        assertTrue(sync.sync())
        val put = WorkerJson.decodeFromString<SyncUpload>(fake.last("PUT", "/v1/sync").body!!)
        assertEquals(listOf(true), put.history!!.map { it.deleted })
        assertEquals(listOf(false), put.follows!!.map { it.following })
        assertNull(user.progress("gone|1"))
    }

    @Test fun `signed out, sync sends nothing`() = runBlocking {
        val (_, sync) = engine(null)
        user.save("sus|1943-01-07", 600_000, 1_800_000)
        assertFalse(sync.sync())
        assertTrue(fake.calls.isEmpty())
    }

    @Test fun `after deletion nothing syncs`() = runBlocking {
        val (api, sync) = engine(fake.account())
        api.deleteAccount()
        val before = fake.calls.size
        assertFalse(sync.sync())
        assertEquals(before, fake.calls.size)
    }
}
