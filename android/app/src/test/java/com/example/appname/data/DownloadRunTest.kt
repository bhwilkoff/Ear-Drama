package com.example.appname.data

import com.example.appname.data.DownloadRecord.State
import java.io.File
import java.nio.file.Files
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Decision 071: a season or a whole run asked for at once, the space it takes,
 * the Downloads place's grouping, a series removed, and the player choosing the
 * file only when it is finished. The Apple suite is DownloadRunTests.
 */
class DownloadRunTest {
    private class FakeTransport : DownloadTransport {
        val begun = mutableListOf<String>()
        val cancelled = mutableListOf<String>()
        override fun begin(token: String, url: String) { begun += url }
        override fun cancel(token: String) { cancelled += token }
        override fun cancelAll() {}
        override suspend fun liveTokens() = emptySet<String>()
    }

    private val dir: File = Files.createTempDirectory("downloads").toFile()
    private var now = 1_000L

    @After fun cleanUp() { dir.deleteRecursively() }

    private fun store(transport: DownloadTransport = FakeTransport()) = DownloadStore(dir, transport) { now }

    private fun request(id: String, bytes: Long? = 1_000) = DownloadRequest(
        id, id, DownloadRecord.seriesKeyOf(id).replaceFirstChar { it.uppercase() },
        "https://archive.org/download/x/${DownloadStore.fileStem(id)}.mp3", bytes,
    )

    private fun DownloadStore.finish(id: String, bytes: Int = 64) {
        val token = record(id)!!.token
        val temp = transferFile(token).apply { writeBytes(ByteArray(bytes) { 1 }) }
        transferFinished(token, temp, 200)
    }

    private fun detail(kbps: Int?, seconds: Double?, recordings: Boolean = true) = EpisodeDetail(
        episode = EpisodeRow("sus|1943-05-25", "sus", "Suspense", "1943-05-25", "1942-43", null, "Sorry, Wrong Number", seconds),
        rights = "unclaimed", rightsBasis = null, network = "CBS", noRecommend = null, credits = emptyList(),
        recordings = if (recordings) {
            listOf(Recording(0, "OTRR_Suspense", "https://archive.org/download/a/b.mp3", "VBR MP3", kbps, seconds, null, false))
        } else {
            emptyList()
        },
        detailJson = null,
    )

    @Test fun `the series key is the id before its bar`() {
        assertEquals("sus", DownloadRecord.seriesKeyOf("sus|1943-05-25"))
        assertEquals("x", DownloadRecord.seriesKeyOf("x|y|z"))
        assertEquals("lonely", DownloadRecord.seriesKeyOf("lonely"))
    }

    @Test fun `a request estimates bitrate times length`() {
        // 128 kbps for 30 minutes is 128,000 / 8 bytes a second for 1,800 s.
        assertEquals(28_800_000L, DownloadRequest.from(detail(128, 1_800.0), "t")!!.estimatedBytes)
        assertNull(DownloadRequest.from(detail(null, 1_800.0), "t")!!.estimatedBytes)
        assertNull(DownloadRequest.from(detail(128, null), "t")!!.estimatedBytes)
        assertNull(DownloadRequest.from(detail(128, 1_800.0, recordings = false), "t"))
    }

    @Test fun `a plan skips what is downloaded or running and retries what failed`() {
        val transport = FakeTransport()
        val store = store(transport)
        store.download(DownloadPlan(listOf(request("s|1"), request("s|2"), request("s|3")), emptyMap()))
        store.finish("s|1")
        store.transferFailed(store.record("s|3")!!.token, "lost")
        val plan = DownloadPlan(
            listOf(request("s|1"), request("s|2"), request("s|3"), request("s|4"), request("s|4", bytes = null)),
            store.records.value,
        )
        assertEquals(listOf("s|3", "s|4"), plan.requests.map { it.episodeId })
        assertEquals(2_000L, plan.estimatedBytes)
        assertEquals(listOf("s|3", "s|4"), store.missing(listOf("s|1", "s|2", "s|3", "s|4")))
        store.download(plan)
        assertEquals(5, transport.begun.size)
        assertEquals(State.Queued, store.record("s|3")?.state)
        assertNull(DownloadPlan(listOf(request("s|9", bytes = null)), emptyMap()).estimatedBytes)
    }

    @Test fun `the place groups by series in the order asked`() {
        val store = store()
        store.download(DownloadPlan(listOf(request("sus|3"), request("sus|1"), request("sus|2")), emptyMap()))
        store.download(DownloadPlan(listOf(request("baby|1")), emptyMap()))
        val groups = store.seriesGroups
        assertEquals(listOf("baby", "sus"), groups.map { it.first })
        assertEquals(listOf("sus|3", "sus|1", "sus|2"), groups[1].second.map { it.episodeId })
        assertTrue(store.hasDownloads("sus"))
        assertFalse(store.hasDownloads("gunsmoke"))
    }

    @Test fun `removing a series leaves the others and their bytes`() {
        val transport = FakeTransport()
        val store = store(transport)
        store.download(DownloadPlan(listOf(request("sus|1"), request("sus|2"), request("baby|1")), emptyMap()))
        store.finish("sus|1", bytes = 100)
        store.finish("baby|1", bytes = 40)
        assertEquals(140L, store.totalBytes)
        val running = store.record("sus|2")!!.token
        store.removeSeries("sus")
        assertEquals(listOf(running), transport.cancelled)
        assertEquals(setOf("baby|1"), store.records.value.keys)
        assertEquals(40L, store.totalBytes)
        assertEquals(1, dir.list().orEmpty().count { it != DownloadStore.INDEX_NAME })
    }

    @Test fun `the player opens the file only once it is finished`() {
        val store = store()
        val r = request("sus|1")
        store.download(DownloadPlan(listOf(r), emptyMap()))
        assertEquals(PlaybackSource(r.url, false), store.playbackSource(r.episodeId, r.url))
        store.transferProgressed(store.record(r.episodeId)!!.token, 10, 64)
        assertEquals(PlaybackSource(r.url, false), store.playbackSource(r.episodeId, r.url))
        store.finish(r.episodeId)
        val local = store.playbackSource(r.episodeId, r.url)
        assertTrue(local.isLocal)
        assertTrue(local.location.startsWith(dir.path))
        // Another copy of the episode is not the downloaded file.
        assertFalse(store.playbackSource(r.episodeId, "https://archive.org/other.mp3").isLocal)
        store.remove(r.episodeId)
        assertEquals(PlaybackSource(r.url, false), store.playbackSource(r.episodeId, r.url))
    }
}
