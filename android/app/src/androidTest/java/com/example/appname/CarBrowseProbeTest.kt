package com.example.appname

import android.content.ComponentName
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import androidx.media3.common.MediaItem
import androidx.media3.session.MediaBrowser
import androidx.media3.session.SessionToken
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.SettableFuture
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * A media browser client of the real [com.example.appname.playback.PlaybackService], as Android Auto is
 * one: it walks the tabs, a show, a search, and the picture behind an item, and logs what it sees under
 * the tag CarProbe. It plays nothing. Run by hand on a device:
 * `adb shell am instrument -w -e class com.example.appname.CarBrowseProbeTest <test package>/androidx.test.runner.AndroidJUnitRunner`.
 */
@RunWith(AndroidJUnit4::class)
class CarBrowseProbeTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val thread = HandlerThread("probe").also { it.start() }
    private val handler = Handler(thread.looper)

    private fun say(text: String) = Log.i("CarProbe", text)

    /** A controller is used only on its application looper; the walk waits on the futures from the test thread. */
    private fun <T> onLooper(call: () -> ListenableFuture<T>): T {
        val box = SettableFuture.create<ListenableFuture<T>>()
        handler.post { try { box.set(call()) } catch (e: Throwable) { box.setException(e) } }
        return box.get(10, TimeUnit.SECONDS).get(12, TimeUnit.SECONDS)
    }

    private fun connect(): MediaBrowser {
        val token = SessionToken(context, ComponentName(context.packageName, "com.example.appname.playback.PlaybackService"))
        return MediaBrowser.Builder(context, token).setApplicationLooper(thread.looper).buildAsync().get(15, TimeUnit.SECONDS)
    }

    private fun MediaBrowser.children(id: String, size: Int = 100): List<MediaItem> {
        val started = System.nanoTime()
        val result = onLooper { getChildren(id, 0, size, null) }
        val items = result.value?.toList().orEmpty()
        say("children($id) -> ${items.size} in ${(System.nanoTime() - started) / 1_000_000} ms, code=${result.resultCode}")
        items.take(5).forEach {
            val m = it.mediaMetadata
            say("  [${if (m.isBrowsable == true) "folder" else if (m.isPlayable == true) "play" else "text"}] ${m.title} | ${m.subtitle} | ${it.mediaId} | art=${m.artworkUri}")
        }
        return items
    }

    private fun artBytes(item: MediaItem): Int {
        val uri = item.mediaMetadata.artworkUri ?: return -1
        return context.contentResolver.openInputStream(uri)?.use { it.readBytes().size } ?: -1
    }

    private fun <T> post(block: () -> T): T {
        val box = SettableFuture.create<T>()
        handler.post { try { box.set(block()) } catch (e: Throwable) { box.setException(e) } }
        return box.get(10, TimeUnit.SECONDS)
    }

    /** Plays a station and a spoken request through the session (mute the device's media volume first), then pauses. */
    @Test fun play() {
        val browser = connect()
        try {
            val stations = browser.children("tab:radio")
            val requests = listOf(
                "station" to stations.first { it.mediaMetadata.isPlayable == true },
                "voice 'suspense'" to MediaItem.Builder()
                    .setRequestMetadata(MediaItem.RequestMetadata.Builder().setSearchQuery("suspense").build()).build(),
                "voice (nothing said)" to MediaItem.Builder()
                    .setRequestMetadata(MediaItem.RequestMetadata.Builder().setSearchQuery("").build()).build(),
            )
            for ((label, item) in requests) {
                post { browser.setMediaItem(item); browser.prepare(); browser.play() }
                Thread.sleep(6_000)
                val state = post {
                    "${browser.currentMediaItem?.mediaId} | ${browser.currentMediaItem?.mediaMetadata?.title} | pos=${browser.currentPosition} ms | state=${browser.playbackState} playWhenReady=${browser.playWhenReady} queue=${browser.mediaItemCount}"
                }
                say("play $label -> $state")
                post { browser.pause() }
            }
        } finally {
            handler.post { browser.release() }
        }
    }

    @Test fun walk() {
        val browser = connect()
        try {
            val root = onLooper { browser.getLibraryRoot(null) }.value!!
            say("root ${root.mediaMetadata.title}")
            val tabs = browser.children(root.mediaId)
            assertTrue("four tabs at most", tabs.size <= 4)
            for (tab in tabs) {
                browser.children(tab.mediaId).firstOrNull { it.mediaMetadata.artworkUri != null }
                    ?.let { say("${tab.mediaMetadata.title} first art bytes ${artBytes(it)}") }
            }
            val browse = tabs.first { it.mediaMetadata.title == "Browse" }
            for (door in browser.children(browse.mediaId)) {
                val inside = browser.children(door.mediaId)
                val folder = inside.firstOrNull { it.mediaMetadata.isBrowsable == true }
                if (folder != null) {
                    val deeper = browser.children(folder.mediaId)
                    deeper.firstOrNull { it.mediaMetadata.isBrowsable == true }?.let { browser.children(it.mediaId) }
                }
            }
            val shows = browser.children("browse:popular")
            shows.firstOrNull()?.let { say("show art bytes ${artBytes(it)}") }
            for (q in listOf("suspense", "lux", "zzzzqx")) {
                onLooper { browser.search(q, null) }
                val found = onLooper { browser.getSearchResult(q, 0, 50, null) }
                val items = found.value?.toList().orEmpty()
                say("search($q) -> ${items.size}: ${items.take(3).map { it.mediaMetadata.title }}")
            }
        } finally {
            handler.post { browser.release() }
        }
    }
}
