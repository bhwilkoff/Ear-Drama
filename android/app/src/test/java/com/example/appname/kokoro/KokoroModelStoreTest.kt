package com.example.appname.kokoro

import com.example.appname.plays.temporaryRoot
import java.io.File
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The model download (Decision 078, S6d): only on request, resumed with Range, each file checked against the manifest's
 * SHA-256, the manifest kept last, Delete removing everything. Run against a fake Release; nothing leaves the machine.
 */
class KokoroModelStoreTest {
    private val files = modelFiles()
    private fun release() = FakeRelease(files.mapValues { it.value.second } + (KokoroModelStore.MANIFEST to fixtureManifest(files).toByteArray()))

    @Test fun `nothing is here until the person downloads, then every file is checked and kept`() = runTest {
        val root = File(temporaryRoot(), "kokoro")
        val server = release()
        val store = KokoroModelStore(root, server)
        assertEquals(KokoroModelStore.State.Absent, store.state.value)
        assertTrue("constructing the store fetched nothing", server.requests.isEmpty())
        assertEquals("107 MB", KokoroModelStore.megabytes(store.downloadBytes()))
        store.download()
        assertEquals(KokoroModelStore.State.Ready, store.state.value)
        val p = store.paths()!!
        assertEquals(sha(files.getValue("kokoro-v1-model_q8f16.onnx").second), KokoroModelStore.sha256(p.model))
        assertEquals(listOf(KokoroModelStore.MANIFEST) + files.keys, server.requests.map { it.first })
        assertTrue(root.listFiles()!!.none { it.name.endsWith(".part") })
        assertEquals(KokoroModelStore.State.Ready, KokoroModelStore(root, NO_NETWORK).state.value)
    }

    @Test fun `a dropped connection resumes from the bytes already here with a Range`() = runTest {
        val root = File(temporaryRoot(), "kokoro")
        val server = release()
        server.breakAfter = 5_000_000
        val store = KokoroModelStore(root, server)
        store.download()
        assertTrue(store.state.value is KokoroModelStore.State.Failed)
        assertNull(store.paths())
        val partial = File(root, "kokoro-v1-model_q8f16.onnx.part").length() + File(root, "kokoro-v1-voices-en.bin.part").length()
        assertTrue("the partial file was kept", partial > 0)
        server.requests.clear()
        store.download()
        assertEquals(KokoroModelStore.State.Ready, store.state.value)
        val resumed = server.requests.first { it.first == "kokoro-v1-voices-en.bin" }
        assertTrue("the voice table resumed from ${resumed.second}", resumed.second > 0)
        assertEquals(sha(files.getValue("kokoro-v1-voices-en.bin").second), KokoroModelStore.sha256(store.paths()!!.voices))
    }

    @Test fun `a server that ignores the Range sends the whole file and it is written from the start`() = runTest {
        val root = File(temporaryRoot(), "kokoro").apply { mkdirs() }
        File(root, "kokoro-v1-voices-en.bin.part").writeBytes(ByteArray(1_000) { 7 })
        val server = release().apply { ignoreRange = true }
        val store = KokoroModelStore(root, server)
        store.download()
        assertEquals(KokoroModelStore.State.Ready, store.state.value)
        assertEquals(1_000L, server.requests.first { it.first == "kokoro-v1-voices-en.bin" }.second)
        assertEquals(sha(files.getValue("kokoro-v1-voices-en.bin").second), KokoroModelStore.sha256(store.paths()!!.voices))
    }

    @Test fun `a file whose SHA-256 differs from the manifest is deleted and never used`() = runTest {
        val root = File(temporaryRoot(), "kokoro")
        val tampered = files.mapValues { it.value.second }.toMutableMap()
        tampered["kokoro-v1-model_q8f16.onnx"] = tampered.getValue("kokoro-v1-model_q8f16.onnx").copyOf().also { it[100] = (it[100] + 1).toByte() }
        val server = FakeRelease(tampered + (KokoroModelStore.MANIFEST to fixtureManifest(files).toByteArray()))
        val store = KokoroModelStore(root, server)
        store.download()
        assertTrue(store.state.value is KokoroModelStore.State.Failed)
        assertNull(store.paths())
        assertFalse(File(root, "kokoro-v1-model_q8f16.onnx").exists())
        assertFalse(File(root, "kokoro-v1-model_q8f16.onnx.part").exists())
        assertFalse("no manifest, so nothing reads as downloaded", File(root, "manifest.json").exists())
    }

    @Test fun `a manifest naming a non-permissive file is refused before any model byte moves`() = runTest {
        val root = File(temporaryRoot(), "kokoro")
        val server = FakeRelease(files.mapValues { it.value.second } + (KokoroModelStore.MANIFEST to fixtureManifest(files, license = "CC-BY-NC-4.0").toByteArray()))
        val store = KokoroModelStore(root, server)
        store.download()
        assertTrue(store.state.value is KokoroModelStore.State.Failed)
        assertEquals(listOf(KokoroModelStore.MANIFEST), server.requests.map { it.first })
    }

    @Test fun `Delete removes every file`() = runTest {
        val root = downloadedRoot(File(temporaryRoot(), "kokoro"))
        val store = KokoroModelStore(root, NO_NETWORK)
        assertEquals(KokoroModelStore.State.Ready, store.state.value)
        store.delete()
        assertEquals(KokoroModelStore.State.Absent, store.state.value)
        assertFalse(root.exists())
        assertNull(store.paths())
    }

    @Test fun `a file shorter than the manifest says is not downloaded`() {
        val root = downloadedRoot(File(temporaryRoot(), "kokoro"))
        File(root, "kokoro-v1-tokenizer.json").writeText("{}")
        assertEquals(KokoroModelStore.State.Absent, KokoroModelStore(root, NO_NETWORK).state.value)
    }
}
