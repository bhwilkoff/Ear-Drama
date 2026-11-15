package com.example.appname.kokoro

import com.example.appname.plays.MicrophoneCapture
import com.example.appname.plays.TakeAudio
import com.example.appname.plays.fixtureScript
import com.example.appname.plays.temporaryRoot
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/**
 * The downloaded voices reading lines (Decision 078, S6d), with the real reader over a fake renderer: phonemes from the
 * play's published file only, a refused render (NaN, silence, a failure) handing the line back to the system voice, and
 * every render marked so no writer in the app will keep it.
 */
class KokoroReaderTest {
    private val script = fixtureScript()

    private fun reader(renderer: FakeRenderer = FakeRenderer(), phonemes: String? = phonemeFile(script), root: File = downloadedRoot(File(temporaryRoot(), "k"))) =
        KokoroReader(KokoroModelStore(root, NO_NETWORK), { id -> if (id == script.id) phonemes else null }, { _, _ -> renderer }, Dispatchers.Unconfined)

    @Test fun `a line with published phonemes renders in the cast voice and is marked synthetic`() = runTest {
        val fake = FakeRenderer()
        val r = reader(fake)
        val audio = r.render(script.id, "Yes, dearie?", "af_bella", 1f)!!
        assertEquals(12_000, audio.size)
        assertEquals(3, fake.calls.single().second)
        assertEquals(Kokoro.tokenize("yes, dearie?", FIXTURE_VOCAB).toList(), fake.calls.single().first.toList())
        try {
            TakeAudio.write(MicrophoneCapture(audio, 24_000.0), File(temporaryRoot(), "k.wav"))
            fail("a Kokoro render was written as a take")
        } catch (_: IllegalStateException) {
        }
    }

    @Test fun `each piece handed to the player is marked too`() = runTest {
        val r = reader()
        var pieces = 0
        assertTrue(r.renderPieces(script.id, "Come in.", "am_puck", 1f) { piece ->
            pieces += 1
            try {
                TakeAudio.write(MicrophoneCapture(piece, 24_000.0), File(temporaryRoot(), "p.wav"))
                fail("a Kokoro piece was written")
            } catch (_: IllegalStateException) {
            }
        })
        assertEquals(1, pieces)
    }

    @Test fun `a British voice is given the gb phonemes`() = runTest {
        val fake = FakeRenderer()
        reader(fake).render(script.id, "Tea?", "bf_emma", 1f)
        assertEquals(Kokoro.tokenize("tea? ː", FIXTURE_VOCAB).toList(), fake.calls.single().first.toList())
    }

    @Test fun `non-finite, silent and failed renders are refused, so the system voice reads the line`() = runTest {
        for (mode in listOf("nan", "silent", "throw")) {
            val r = reader(FakeRenderer(mode))
            assertNull(mode, r.render(script.id, "Come in.", "af_heart", 1f))
            assertTrue(mode, r.lastRefusal != null)
        }
    }

    @Test fun `a play the catalog held, a line not in the file, or no model reads nothing`() = runTest {
        val held = reader(phonemes = null)
        assertFalse(held.prepare(script.id))
        assertEquals(false, held.hasPhonemes(script.id))
        assertNull(held.render(script.id, "Come in.", "af_heart", 1f))
        val r = reader()
        assertNull(r.render(script.id, "A line no one wrote.", "af_heart", 1f))
        assertNull(r.render(script.id, "Come in.", "not_a_voice", 1f))
        val absent = KokoroReader(KokoroModelStore(File(temporaryRoot(), "none"), NO_NETWORK), { phonemeFile(script) }, { _, _ -> FakeRenderer() })
        assertTrue(absent.voices().isEmpty())
        assertNull(absent.render(script.id, "Come in.", "af_heart", 1f))
    }

    @Test fun `unloading closes the model`() = runTest {
        val fake = FakeRenderer()
        val r = reader(fake)
        assertTrue(r.warm())
        r.unload()
        assertTrue(fake.closed)
    }
}
