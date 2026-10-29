package com.example.appname.data

import com.example.appname.data.DownloadRecord.State
import java.io.File
import java.nio.file.Files
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The download state machine, driven through the transport callbacks the
 * worker calls. [leaks] states the disk rule (no file the records do not
 * account for); the control proves the check sees a store that skips its
 * partial-file cleanup.
 */
class DownloadStoreTest {

    private class FakeTransport : DownloadTransport {
        val begun = mutableListOf<String>()
        val cancelled = mutableListOf<String>()
        var cancelledAll = false
        var live = emptySet<String>()
        override fun begin(token: String, url: String) { begun += token }
        override fun cancel(token: String) { cancelled += token }
        override fun cancelAll() { cancelledAll = true }
        override suspend fun liveTokens() = live
    }

    private val dir: File = Files.createTempDirectory("downloads").toFile()
    private var now = 0L

    @After fun cleanUp() { dir.deleteRecursively() }

    private fun store(transport: DownloadTransport = FakeTransport()) = DownloadStore(dir, transport) { now }

    private val url = "https://archive.org/download/OTRR_Suspense/Suspense_420107.mp3"

    /** Writes [bytes] into the transfer's file, the way the worker does. */
    private fun DownloadStore.writeTransfer(token: String, bytes: Int): File =
        transferFile(token).apply { writeBytes(ByteArray(bytes) { 1 }) }

    /** Files on disk that no record accounts for (a finished file, or a live transfer's own file). */
    private fun leaks(store: DownloadStore): List<String> {
        val claimed = mutableSetOf(DownloadStore.INDEX_NAME)
        for (r in store.records.value.values) {
            if (r.state == State.Downloaded) claimed += r.fileName
            if (r.isActive) claimed += store.transferFile(r.token).name
        }
        return dir.list().orEmpty().filter { it !in claimed }
    }

    /** Every way a transfer can fail; returns the files each one leaves behind. */
    private fun failureLeaks(make: () -> DownloadStore): List<String> {
        val out = mutableListOf<String>()
        // A transfer error after some bytes landed.
        make().run {
            download("e1", "One", "Suspense", "suspense", url)
            val token = record("e1")!!.token
            writeTransfer(token, 4096)
            transferProgressed(token, 4096, 20_000)
            transferFailed(token, "connection reset")
            if (record("e1")?.state != State.Failed) out += "error did not mark failed"
            out += leaks(this).map { "error left $it" }
        }
        // A finished transfer with a server error status.
        make().run {
            download("e2", "Two", "Suspense", "suspense", url)
            val token = record("e2")!!.token
            transferFinished(token, writeTransfer(token, 512), 503)
            if (record("e2")?.state != State.Failed) out += "503 did not mark failed"
            out += leaks(this).map { "503 left $it" }
        }
        // An empty body.
        make().run {
            download("e3", "Three", "Suspense", "suspense", url)
            val token = record("e3")!!.token
            transferFinished(token, writeTransfer(token, 0), 200)
            if (record("e3")?.state != State.Failed) out += "empty body did not mark failed"
            out += leaks(this).map { "empty body left $it" }
        }
        return out
    }

    @Test fun `no failure leaves a partial file`() {
        assertEquals(emptyList<String>(), failureLeaks { store() })
    }

    @Test fun `control - a store that skips its partial cleanup is caught`() {
        val v = failureLeaks {
            object : DownloadStore(dir, FakeTransport(), { now }) {
                override fun deleteFiles(record: DownloadRecord) = Unit
            }
        }
        assertTrue(v.toString(), v.any { "partial" in it })
    }

    @Test fun `queued then downloading then downloaded, and the player gets the file`() {
        val transport = FakeTransport()
        val s = store(transport)
        s.download("e", "Title", "Suspense", "suspense", url)
        val r = s.record("e")!!
        assertEquals(State.Queued, r.state)
        assertEquals(listOf(r.token), transport.begun)
        assertTrue(r.fileName.endsWith(".mp3"))
        assertNull(s.localFile("e", url))

        s.transferProgressed(r.token, 1000, 4000)
        assertEquals(State.Downloading, s.record("e")!!.state)
        assertEquals(0.25f, s.record("e")!!.fraction)

        s.transferFinished(r.token, s.writeTransfer(r.token, 4000), 200)
        val done = s.record("e")!!
        assertEquals(State.Downloaded, done.state)
        assertEquals(4000L, done.receivedBytes)
        assertEquals(4000L, s.totalBytes)
        assertEquals(File(dir, done.fileName), s.localFile("e", url))
        assertNull("another version streams", s.localFile("e", "$url?other"))
        assertEquals(emptyList<String>(), leaks(s))
    }

    @Test fun `downloading twice is one download, and a failed one starts over with a new token`() {
        val transport = FakeTransport()
        val s = store(transport)
        s.download("e", "T", "S", "s", url)
        s.download("e", "T", "S", "s", url)
        assertEquals(1, transport.begun.size)
        val first = s.record("e")!!.token
        s.transferFailed(first, "x")
        s.download("e", "T", "S", "s", url)
        assertEquals(2, transport.begun.size)
        assertFalse(first == s.record("e")!!.token)
        // A late callback from the old transfer cannot fill the new record.
        s.transferFinished(first, s.writeTransfer(first, 100), 200)
        assertEquals(State.Queued, s.record("e")!!.state)
    }

    @Test fun `cancel stops the transfer and forgets the record`() {
        val transport = FakeTransport()
        val s = store(transport)
        s.download("e", "T", "S", "s", url)
        val token = s.record("e")!!.token
        s.writeTransfer(token, 100)
        s.cancel("e")
        assertNull(s.record("e"))
        assertEquals(listOf(token), transport.cancelled)
        assertEquals(emptyList<String>(), leaks(s))
    }

    @Test fun `remove and remove all reclaim the files`() {
        val transport = FakeTransport()
        val s = store(transport)
        for (id in listOf("a", "b")) {
            s.download(id, id, "S", "s", url)
            val t = s.record(id)!!.token
            s.transferFinished(t, s.writeTransfer(t, 10), 200)
        }
        s.remove("a")
        assertNull(s.record("a"))
        assertEquals(10L, s.totalBytes)
        s.removeAll()
        assertTrue(transport.cancelledAll)
        assertTrue(s.records.value.isEmpty())
        assertEquals(listOf(DownloadStore.INDEX_NAME), dir.list()!!.toList())
    }

    @Test fun `the index survives a relaunch and reconnect sweeps what a dead process left`() = runTest {
        val first = store()
        first.download("done", "Done", "S", "s", url)
        val t = first.record("done")!!.token
        first.transferFinished(t, first.writeTransfer(t, 10), 200)
        first.download("dead", "Dead", "S", "s", url)
        first.download("alive", "Alive", "S", "s", url)
        val aliveToken = first.record("alive")!!.token
        first.writeTransfer(aliveToken, 10)
        File(dir, "orphan.mp3.partial").writeText("x")

        val transport = FakeTransport().apply { live = setOf(aliveToken, "stray") }
        val second = store(transport)
        assertEquals(setOf("done", "dead", "alive"), second.records.value.keys)
        second.reconnect()
        assertEquals(State.Downloaded, second.record("done")!!.state)
        assertEquals(State.Failed, second.record("dead")!!.state)
        assertEquals(State.Queued, second.record("alive")!!.state)
        assertEquals(listOf("stray"), transport.cancelled)
        assertFalse(File(dir, "orphan.mp3.partial").exists())
        assertTrue("a live transfer keeps its file", second.transferFile(aliveToken).exists())
        assertEquals(emptyList<String>(), leaks(second))
    }

    @Test fun `file names never carry the episode id`() {
        val stem = DownloadStore.fileStem("suspense|1942-01-07|ab/c")
        assertEquals(32, stem.length)
        assertTrue(stem.all { it in "0123456789abcdef" })
    }

    @Test fun `the series key is stored, not read from the id`() {
        val s = store()
        s.download("opaque|1", "One", "S", "the-real-key", url)
        assertEquals("the-real-key", s.record("opaque|1")?.seriesKey)
        assertTrue(s.hasDownloads("the-real-key"))
        assertFalse(s.hasDownloads("opaque"))
        assertEquals("it survives a relaunch", "the-real-key", store().record("opaque|1")?.seriesKey)
    }

    @Test fun `a record written before the key was stored reads it from its id`() {
        val legacy = """{"episodeId":"sus|1","title":"T","seriesName":"S","remoteUrl":"u","fileName":"f","state":"Downloaded","addedAtMs":0,"token":"t"}"""
        File(dir, DownloadStore.INDEX_NAME).writeText("""{"sus|1":$legacy}""")
        assertEquals("sus", store().record("sus|1")?.seriesKey)
        assertEquals("x", DownloadRecord.legacySeriesKeyOf("x|y|z"))
        assertEquals("lonely", DownloadRecord.legacySeriesKeyOf("lonely"))
    }
}
