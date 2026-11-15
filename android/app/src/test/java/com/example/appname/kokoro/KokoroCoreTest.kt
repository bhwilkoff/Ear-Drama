package com.example.appname.kokoro

import com.example.appname.plays.VoiceCastEntry
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/**
 * Kokoro's pure parts (Decision 078, S6d), the Kotlin mirror of js/kokoro.test.js: the voices, the tokenizer over published
 * phonemes, the style row, the render guard and the manifest's acceptance.
 */
class KokoroCoreTest {
    @Test fun `no voices until the model is downloaded, then all 28, best grade first, each named as Kokoro`() {
        assertTrue(Kokoro.castable(false).isEmpty())
        val v = Kokoro.castable(true)
        assertEquals(28, v.size)
        assertEquals(listOf("af_heart", "af_bella", "af_nicole", "bf_emma"), v.take(4).map { it.id })
        assertTrue(v.all { it.engine == VoiceCastEntry.KOKORO && it.name.endsWith(" (Kokoro)") })
        assertEquals("Heart (Kokoro)", v[0].name)
        assertEquals("female", v.first { it.id == "af_sky" }.gender)
        assertEquals("male", v.first { it.id == "bm_george" }.gender)
        assertEquals("en-GB", v.first { it.id == "bm_george" }.localeTag)
        assertEquals(Kokoro.VOICES.size.toLong() * 510 * 256 * 4, 14_622_720L)
    }

    @Test fun `tokenize pads with zero both ends and drops symbols the vocabulary lacks`() {
        assertArrayEquals(longArrayOf(0, 50, 157, 43, 16, 4, 0), Kokoro.tokenize("hˌa ¤.", FIXTURE_VOCAB))
        assertArrayEquals(longArrayOf(0, 0), Kokoro.tokenize("", FIXTURE_VOCAB))
        assertEquals(mapOf("a" to 43L, "ˈ" to 156L), Kokoro.parseVocab(vocabJson(mapOf("a" to 43L, "ˈ" to 156L))))
    }

    @Test fun `chunks never pass the limit, cut at punctuation, and join back to the input`() {
        val sentence = "ðə kˈæt sˈæt ˌɔn ðə mˈæt. "
        val ps = sentence.repeat(40)
        val parts = Kokoro.chunks(ps, 100)
        assertTrue(parts.size > 1)
        assertTrue(parts.all { it.length <= 100 })
        assertEquals(ps, parts.joinToString(""))
        assertTrue(parts.dropLast(1).all { it.endsWith(". ") || it.endsWith(".") })
        assertEquals(listOf("short"), Kokoro.chunks("short"))
        val noBreak = "a".repeat(250)
        assertEquals(noBreak, Kokoro.chunks(noBreak, 100).joinToString(""))
    }

    @Test fun `the style row is the voice's row for the unpadded length, capped at the last row`() {
        assertEquals((3 * 510 + 5) * 256, Kokoro.styleOffset(3, 7))
        assertEquals((0 * 510 + 509) * 256, Kokoro.styleOffset(0, 2_000))
        assertEquals(0, Kokoro.styleOffset(0, 2))
        val table = FloatArray(28 * 510 * 256) { it.toFloat() }
        val s = Kokoro.style(table, 1, 12)
        assertEquals(256, s.size)
        assertEquals(((510 + 10) * 256).toFloat(), s[0])
    }

    @Test fun `a render with any non-finite sample, or only near-silence, is never played`() {
        assertTrue(Kokoro.audible(floatArrayOf(0f, 0.2f, -0.3f)))
        assertFalse(Kokoro.audible(floatArrayOf(0.2f, Float.NaN, 0.1f)))
        assertFalse(Kokoro.audible(floatArrayOf(0.2f, Float.POSITIVE_INFINITY)))
        assertFalse(Kokoro.audible(FloatArray(24_000)))
        assertFalse(Kokoro.audible(FloatArray(0)))
    }

    @Test fun `speed carries the tempo and pitch the playback rate, clamped to the model's range`() {
        assertEquals(1f, Kokoro.speedFor(1.0, 1.0))
        assertEquals(1.25f, Kokoro.speedFor(1.0, 0.8), 1e-6f)
        assertEquals(2f, Kokoro.speedFor(2.0, 0.5))
        assertEquals(0.5f, Kokoro.speedFor(0.5, 1.5))
    }

    @Test fun `a British voice reads the gb phonemes where the file has them`() {
        val row = PhonemeLine("L1", "Tea?", "tˈi?", "tˈiː?")
        assertEquals("tˈiː?", Kokoro.phonemesFor(row, Kokoro.voice("bf_emma")!!))
        assertEquals("tˈi?", Kokoro.phonemesFor(row, Kokoro.voice("af_heart")!!))
        assertEquals("tˈi?", Kokoro.phonemesFor(row.copy(gb = null), Kokoro.voice("bm_lewis")!!))
        assertEquals("Well, Molly.", Kokoro.keyOf("  Well,\n _Molly_. "))
    }

    @Test fun `the manifest is accepted only with three permissive files, the app's voices and never fp16`() {
        val m = KokoroManifest.accept(fixtureManifest())
        assertEquals(setOf("model", "voices", "vocab"), m.files.map { it.role }.toSet())
        fun refused(label: String, text: String) {
            try {
                KokoroManifest.accept(text)
                fail("$label was accepted")
            } catch (_: IllegalArgumentException) {
            }
        }
        refused("a GPL file", fixtureManifest(license = "GPL-3.0"))
        refused("no license", fixtureManifest(license = ""))
        refused("fp16", manifestJson(KokoroManifest.accept(fixtureManifest()).files, precision = "fp16"))
        refused("other voices", manifestJson(m.files, voices = listOf("af_heart")))
        refused("no vocabulary", manifestJson(m.files.filter { it.role != "vocab" }))
        refused("a path with a slash", manifestJson(m.files.map { if (it.role == "model") it.copy(path = "../x.onnx") else it }))
        refused("a short voice table", manifestJson(m.files.map { if (it.role == "voices") it.copy(bytes = 10) else it }))
        refused("not JSON", "<html>")
    }
}
