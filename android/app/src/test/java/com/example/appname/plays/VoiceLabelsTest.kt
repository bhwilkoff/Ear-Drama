package com.example.appname.plays

import java.util.Locale
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.sin
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * A device voice named from what it sounds like (PLAYS-DESIGN §2.8 rule 12; owner 2026-11-23: "there is no way to choose a
 * voice based upon a numer instead of a name or description"), the locale alias left out, and register alternating in
 * auto-cast where Android reports no gender. The Pixel 8a's Google voices are the fixture: [VoiceLabels.SEED] holds what
 * was measured there.
 *
 * Seen to fail, 2026-11-23, against mutated VoiceCast.kt (restored after): the alias kept (3 of 8 failed), auto-cast
 * alternating on gender only (1), the labels built without the traits (1).
 */
class VoiceLabelsTest {
    private fun raw(name: String, tag: String = "en-US", quality: Int = 400, default: Boolean = false, alias: Boolean = false) =
        RawVoice(name, tag, quality, networkRequired = false, notInstalled = false, isDefault = default, alias = alias)

    /** The Pixel 8a's castable list, 2026-11-23: the locale stand-in plus eight named US voices, all quality 400. */
    private val pixel = listOf(raw("en-US-language", default = true, alias = true)) +
        listOf("iob", "iog", "iol", "iom", "sfg", "tpc", "tpd", "tpf").map { raw("en-us-x-$it-local") }

    private fun cast() = VoiceCasting.castable(pixel, Locale.US, VoiceLabels.SEED)

    @Test fun `every Pixel voice is named by its sound and accent, never by a number`() {
        val v = cast()
        assertEquals(
            mapOf(
                "en-us-x-iob-local" to "High, lively · US",
                "en-us-x-iog-local" to "Very high · US",
                "en-us-x-iol-local" to "Low, bright · US",
                "en-us-x-iom-local" to "Low, clear · US",
                "en-us-x-sfg-local" to "High, even · US",
                "en-us-x-tpc-local" to "Middle · US",
                "en-us-x-tpd-local" to "Low, warm · US",
                "en-us-x-tpf-local" to "High, varied · US",
            ),
            v.associate { it.id to it.name },
        )
        assertEquals(v.size, v.map { it.name }.toSet().size)
        assertTrue(v.none { it.name.any(Char::isDigit) || it.name.contains("United States") })
    }

    @Test fun `the locale alias is left out beside a named voice of its locale, kept when it is the only one`() {
        assertTrue(cast().none { it.id == "en-US-language" })
        val alone = VoiceCasting.castable(listOf(raw("en-US-language", alias = true), raw("en-gb-x-rjs-local", "en-GB")), Locale.US)
        assertEquals(setOf("en-US-language", "en-gb-x-rjs-local"), alone.map { it.id }.toSet())
    }

    @Test fun `auto-cast alternates lower and higher voices where no gender is reported`() {
        val v = cast()
        val parts = (1..6).map { PartID.role("P$it") }
        val a = VoiceCasting.autoCast(parts, v)
        val registers = parts.map { p -> v.first { it.id == a.getValue(p).voice }.register }
        assertEquals(listOf("higher", "lower", "higher", "lower", "higher", "lower"), registers)
        assertEquals(parts.size, a.values.map { it.voice }.toSet().size)
        val renamed = (1..6).map { PartID.role("Z$it") }
        assertEquals(a.values.map { it.voice }, VoiceCasting.autoCast(renamed, v).values.map { it.voice })
    }

    @Test fun `a chip drops an accent every voice shares and keeps one that tells voices apart`() {
        val only = VoiceCast("p:x", listOf(PartID.role("A")), { cast() }, MemoryCastStore())
        assertEquals("US", only.soleAccent())
        assertEquals("Low, warm", chipVoiceName("Low, warm · US", only.soleAccent()))
        val mixed = VoiceCast("p:y", listOf(PartID.role("A")), { cast() + CastVoice("en-gb-x-rjs-local", "Low · UK", "en-GB", 400) }, MemoryCastStore())
        assertEquals(null, mixed.soleAccent())
        assertEquals("Low, warm · US", chipVoiceName("Low, warm · US", mixed.soleAccent()))
    }

    @Test fun `a register is the band its median pitch falls in`() {
        assertEquals(listOf("Deep", "Low", "Middle", "High", "Very high"), listOf(100.0, 130.0, 160.0, 200.0, 240.0).map(VoiceLabels::band))
        assertEquals("lower", VoiceLabels.register(VoiceTraits(164.9, 1.5, 2000.0, 4.0)))
        assertEquals("higher", VoiceLabels.register(VoiceTraits(165.0, 1.5, 2000.0, 4.0)))
    }

    @Test fun `two in a register take the ends of the trait that parts them, four split again, a true tie shows the code`() {
        val t = mapOf(
            "a-x-one-local" to VoiceTraits(130.0, 1.5, 1500.0, 4.0),
            "a-x-two-local" to VoiceTraits(131.0, 1.5, 2500.0, 4.0),
        )
        val two = VoiceLabels.labels(t.keys.map { it to "en-GB" }, t)
        assertEquals("Low, warm · UK", two["a-x-one-local"])
        assertEquals("Low, bright · UK", two["a-x-two-local"])

        val four = mapOf(
            "b-x-p-local" to VoiceTraits(200.0, 1.2, 1500.0, 4.0),
            "b-x-q-local" to VoiceTraits(201.0, 1.8, 1510.0, 4.0),
            "b-x-r-local" to VoiceTraits(202.0, 1.2, 2500.0, 4.0),
            "b-x-s-local" to VoiceTraits(203.0, 1.8, 2510.0, 4.0),
        )
        val l4 = VoiceLabels.labels(four.keys.map { it to "en-AU" }, four)
        assertEquals(4, l4.values.toSet().size)
        assertTrue(l4.values.all { it.startsWith("High, ") && it.endsWith(" · Australia") })

        val same = VoiceTraits(150.0, 1.5, 2000.0, 4.0)
        val tie = VoiceLabels.labels(listOf("c-x-aa-local" to "en-US", "c-x-bb-local" to "en-US"), mapOf("c-x-aa-local" to same, "c-x-bb-local" to same))
        assertEquals(setOf("Middle · US (aa)", "Middle · US (bb)"), tie.values.toSet())
    }

    @Test fun `an unmeasured voice reads its accent and the engine's code until its numbers arrive`() {
        val l = VoiceLabels.labels(listOf("en-us-x-zzz-local" to "en-US", "en-US-language" to "en-US"), emptyMap())
        assertEquals("US voice (zzz)", l["en-us-x-zzz-local"])
        assertEquals("US voice (language)", l["en-US-language"])
    }

    @Test fun `traits survive their stored form, and a broken row is no traits`() {
        val t = VoiceTraits(193.5, 1.725, 1752.0, 4.4)
        assertEquals(t, VoiceTraits.decode(t.encode()))
        assertEquals(null, VoiceTraits.decode("1,2,x"))
        assertEquals(null, VoiceTraits.decode(null))
    }

    /** A voiced signal with harmonics and a gentle vibrato, pitch [f0], with silence before and after. */
    private fun voiced(f0: Double, sr: Int = 24_000, seconds: Double = 2.0): FloatArray {
        val pad = sr / 4
        val n = (sr * seconds).toInt()
        val out = FloatArray(n + 2 * pad)
        var phase = 0.0
        for (i in 0 until n) {
            val f = f0 * (1 + 0.03 * sin(2 * PI * 5 * i / sr))
            phase += 2 * PI * f / sr
            out[pad + i] = (0.4 * sin(phase) + 0.2 * sin(2 * phase) + 0.1 * sin(3 * phase)).toFloat()
        }
        return out
    }

    @Test fun `the measure finds a voice's pitch and its sounding length`() {
        val low = must(VoiceMeasure.measure(voiced(120.0), 24_000))
        val high = must(VoiceMeasure.measure(voiced(220.0), 24_000))
        assertTrue("low f0 ${low.f0}", abs(low.f0 - 120) < 6)
        assertTrue("high f0 ${high.f0}", abs(high.f0 - 220) < 10)
        assertTrue("pace ${low.pace}", abs(low.pace - 2.0) < 0.05)
        assertNotEquals(VoiceLabels.band(low.f0), VoiceLabels.band(high.f0))
        assertEquals(null, VoiceMeasure.measure(FloatArray(24_000), 24_000))
    }

    private fun <T> must(v: T?): T { assertNotNull(v); return v!! }
}
