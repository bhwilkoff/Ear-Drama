package com.example.appname.playback

import android.net.Uri
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** The car's picture path: a served picture kept, the label when it cannot be fetched, a bounded directory, and the content address the item carries. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class CarArtTest {
    @get:Rule val tmp = TemporaryFolder()

    private val label = "LABEL".toByteArray()

    @Test fun `a served picture is fetched once and kept`() {
        var fetches = 0
        val store = CarArtStore(tmp.newFolder("a")) { fetches++; "JPEG".toByteArray() }
        val first = store.file("e:1", "https://x/y.jpg?width=500") { label }
        val second = store.file("e:1", "https://x/y.jpg?width=500") { label }
        assertEquals(first, second)
        assertEquals(1, fetches)
        assertArrayEquals("JPEG".toByteArray(), first.readBytes())
    }

    @Test fun `offline the label takes its place and is kept`() {
        var drawn = 0
        val store = CarArtStore(tmp.newFolder("b")) { null }
        val f = store.file("e:1", "https://x/y.jpg?width=500") { drawn++; label }
        store.file("e:1", "https://x/y.jpg?width=500") { drawn++; label }
        assertArrayEquals(label, f.readBytes())
        assertEquals(1, drawn)
    }

    @Test fun `no served picture draws the label with no fetch at all`() {
        val store = CarArtStore(tmp.newFolder("c")) { error("must not fetch") }
        assertArrayEquals(label, store.file("e:2", null) { label }.readBytes())
    }

    @Test fun `the directory is bounded`() {
        val dir = tmp.newFolder("d")
        val store = CarArtStore(dir) { null }
        repeat(CarArtStore.MAX_FILES + 25) { store.file("e:$it", null) { label } }
        assertTrue(dir.listFiles()!!.size <= CarArtStore.MAX_FILES)
    }

    @Test fun `an item carries a content address under the art authority`() {
        val node = CarNode("sus|1943-01-07", "T", null, browsable = false, art = CarLibrary.artOfEpisode("sus|1943-01-07"))
        val uri = node.toMediaItem("app.eardrama.carart").mediaMetadata.artworkUri!!
        assertEquals("content", uri.scheme)
        assertEquals("app.eardrama.carart", uri.authority)
        assertEquals(listOf("e", "sus|1943-01-07"), uri.pathSegments)
        assertEquals(null, node.toMediaItem(null).mediaMetadata.artworkUri)
        assertTrue(Uri.parse("content://a/b").scheme == "content")
    }
}
