package com.example.appname.plays

import java.io.File
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.log10
import kotlin.math.sin
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/**
 * Sound in the mix (B32 K2), held to catalog/tests/golden/mix_sound.json, the same file js/plays.test.js reads:
 * cues place against takes, the duck is computed from the voice takes, the render is two-pass with one scalar,
 * and the record keeps what a slot plays.
 *
 * Broken controls, 2026-11-26: attack 120 -> 121 ms fails the envelope and duck tests; release 600 -> 500 fails
 * them too; no merge of voice gaps under 1 s fails the shape test (voice activity); the Before cue not moving
 * the line fails the shape test; the duck jumping instead of ramping fails the duck-at probes and the samples;
 * no fade out fails the samples; loop ignored fails the shape and samples; the scalar not applied fails the
 * samples; a sound-part line counted as voice fails the shape test; a fingerprint without the sound fails the
 * record test; unusedTakes ignoring slot takes fails the record test.
 */
class MixSoundTest {
    private val golden = Json.parseToJsonElement(File("../../catalog/tests/golden/mix_sound.json").readText()).jsonObject
    private val rate = golden.getValue("sampleRate").jsonPrimitive.int.toDouble()
    private val script = Json { ignoreUnknownKeys = true }.decodeFromJsonElement(PlayScript.serializer(), golden.getValue("script"))
    private val block = ProductionStore.json.decodeFromJsonElement(SoundBlock.serializer(), golden.getValue("sound"))
    private val expect = golden.getValue("expect").jsonObject
    private val takeRows = golden.getValue("takes").jsonArray.map { it.jsonObject }
    private val cueRows = golden.getValue("cues").jsonArray.map { it.jsonObject }

    private fun str(o: JsonObject, k: String) = o.getValue(k).jsonPrimitive.content
    private fun num(o: JsonObject, k: String) = o.getValue(k).jsonPrimitive.double

    private fun production(sound: SoundBlock?): Production {
        val takes = takeRows.map { take(str(it, "id"), str(it, "lineID"), PartID(str(it, "part")), it.getValue("frames").jsonPrimitive.int, num(it, "loudness"), num(it, "peak").toFloat()) }
        val chosen = golden.getValue("chosen").jsonObject.mapValues { it.value.jsonPrimitive.content }
        return Production.create(script, "golden").copy(takes = takes, chosen = chosen, sound = sound)
    }

    private fun resolver(have: (JsonObject) -> Boolean = { true }): (SoundSource, SoundCue) -> MixTimeline.SoundInfo? = { src, _ ->
        cueRows.firstOrNull { str(it, "pack") == src.pack && str(it, "cue") == src.cue }?.takeIf(have)?.let {
            MixTimeline.SoundInfo(it.getValue("frames").jsonPrimitive.int, str(it, "kind"), num(it, "loudness"), num(it, "peak").toFloat())
        }
    }

    private fun near(a: Double, b: Double, tol: Double = 1e-6) = abs(a - b) <= tol

    private fun synth(row: JsonObject): FloatArray {
        val spec = row.getValue("synth").jsonObject
        val frames = row.getValue("frames").jsonPrimitive.int
        val amp = num(spec, "amp")
        return if (str(spec, "type") == "sine") {
            val hz = num(spec, "hz")
            FloatArray(frames) { k -> (amp * sin(2 * PI * hz * k / rate)).toFloat() }
        } else {
            val every = spec.getValue("every").jsonPrimitive.int
            FloatArray(frames) { k -> if (k % every == 0) amp.toFloat() else 0f }
        }
    }

    private fun sameShape(t: MixTimeline, want: JsonElement, name: String) {
        val w = want.jsonObject
        assertEquals("$name: total frames", w.getValue("totalFrames").jsonPrimitive.int, t.totalFrames)
        val wp = w.getValue("placements").jsonArray.map { it.jsonObject }
        assertEquals(
            "$name: voice placements",
            wp.map { listOf(str(it, "lineID"), str(it, "takeID"), it.getValue("start").jsonPrimitive.int, it.getValue("frames").jsonPrimitive.int) },
            t.placements.map { listOf(it.lineID, it.takeID, it.start, it.frames) },
        )
        assertTrue("$name: voice gains", t.placements.indices.all { near(t.placements[it].gain.toDouble(), num(wp[it], "gain")) })
        val ws = w["sounds"]?.jsonArray?.map { it.jsonObject }.orEmpty()
        assertEquals("$name: sound lanes present only with sound", w.containsKey("sounds"), t.sounds.isNotEmpty())
        if (ws.isEmpty()) {
            assertTrue("$name: no voice activity without sound", t.voice.isEmpty() && t.left.isEmpty())
            return
        }
        fun ints(o: JsonObject) = listOf("start", "frames", "inFrame", "outFrame", "fadeIn", "fadeOut").map { o.getValue(it).jsonPrimitive.int }
        assertEquals(
            "$name: sound placements",
            ws.map { listOf(str(it, "soundID"), str(it, "slotID"), str(it, "lane"), it.getValue("loop").jsonPrimitive.content, num(it, "duck")) + ints(it) },
            t.sounds.map { listOf(it.soundID, it.slotID, it.lane, it.loop.toString(), it.duck) + listOf(it.start, it.frames, it.inFrame, it.outFrame, it.fadeIn, it.fadeOut) },
        )
        assertTrue("$name: sound gains", t.sounds.indices.all { near(t.sounds[it].gain, num(ws[it], "gain")) })
        assertEquals(
            "$name: voice activity, gaps under 1 s held",
            w.getValue("voice").jsonArray.map { listOf(it.jsonArray[0].jsonPrimitive.int, it.jsonArray[1].jsonPrimitive.int) },
            t.voice.map { listOf(it.start, it.end) },
        )
        assertEquals("$name: sounds left out", w.getValue("left").jsonArray.map { it.jsonPrimitive.content }, t.left)
    }

    @Test fun `sound cues place against the takes as the golden says`() {
        val voiceOnly = MixTimeline.build(script, production(null))
        sameShape(voiceOnly, expect.getValue("voiceOnly"), "voice only")
        assertTrue("a play with no sound has the timeline it always had", voiceOnly.sounds.isEmpty() && voiceOnly.voice.isEmpty() && voiceOnly.left.isEmpty())
        sameShape(MixTimeline.build(script, production(SoundBlock(1, slots = listOf(block.slots[2])))), expect.getValue("silentOnly"), "only a silent slot")
        sameShape(MixTimeline.build(script, production(block), resolveSound = resolver()), expect.getValue("full"), "full")
        val notRain = resolver { str(it, "cue") != "rain-steady-1" }
        try {
            MixTimeline.build(script, production(block), resolveSound = notRain)
            fail("a sound not on this device is named, never dropped")
        } catch (e: MixTimeline.MissingSounds) {
            assertEquals(expect.getValue("missing").jsonObject.getValue("detail").jsonArray.map { it.jsonPrimitive.content }, e.ids)
        }
        sameShape(MixTimeline.build(script, production(block), resolveSound = notRain, withoutMissing = true), expect.getValue("withoutMissing"), "export without them")
        try {
            MixTimeline.build(script, production(block.copy(v = 2)), resolveSound = resolver())
            fail("a newer sound block is refused")
        } catch (e: MixTimeline.SoundVersion) {
            assertEquals(2, e.v)
        }
    }

    @Test fun `the duck is computed from the voice takes as the golden says`() {
        val voice = expect.getValue("full").jsonObject.getValue("voice").jsonArray.map { MixTimeline.Span(it.jsonArray[0].jsonPrimitive.int, it.jsonArray[1].jsonPrimitive.int) }
        for ((depth, points) in expect.getValue("envelopes").jsonObject) {
            assertEquals(
                "breakpoints at $depth dB",
                points.jsonArray.map { it.jsonArray[0].jsonPrimitive.int to it.jsonArray[1].jsonPrimitive.double },
                MixSound.duckEnvelope(voice, depth.toDouble(), rate),
            )
        }
        assertEquals("Off has no duck", emptyList<MixSound.Point>(), MixSound.duckEnvelope(voice, 0.0, rate))
        var worst = 0.0
        for (probe in expect.getValue("duckAt").jsonArray) {
            val (depth, frame, db) = probe.jsonArray
            val g = MixSound.duckGains(MixSound.duckEnvelope(voice, depth.jsonPrimitive.double, rate), frame.jsonPrimitive.int, 1)[0]
            worst = maxOf(worst, abs(20 * log10(g) - db.jsonPrimitive.double))
        }
        assertTrue("the envelope at each probe (worst $worst dB)", worst < 1e-6)
        val d = golden.getValue("defaults").jsonObject
        assertEquals(
            listOf(-6.0, -12.0, 120.0, 600.0, 1000.0),
            listOf("effectsDuckDb", "musicDuckDb", "attackMs", "releaseMs", "holdMs").map { num(d, it) },
        )
        assertEquals(
            listOf(MixSound.Defaults.EFFECTS_DUCK_DB, MixSound.Defaults.MUSIC_DUCK_DB, MixSound.Defaults.ATTACK_MS, MixSound.Defaults.RELEASE_MS, MixSound.Defaults.HOLD_MS),
            listOf("effectsDuckDb", "musicDuckDb", "attackMs", "releaseMs", "holdMs").map { num(d, it) },
        )
    }

    private fun lsb(x: Float): Int = floor(x.coerceIn(-1f, 1f).toDouble() * 32767 + 0.5).toInt()

    @Test fun `the mix with sound renders the golden samples to 1 LSB held under -1 dBFS`() {
        val timeline = MixTimeline.build(script, production(block), resolveSound = resolver())
        val takes = takeRows.associate { str(it, "id") to synth(it) }
        val cues = cueRows.associate { "${str(it, "pack")}/${str(it, "cue")}" to synth(it) }
        val loadVoice = { p: MixTimeline.Placement -> takes.getValue(p.takeID) }
        val loadSound = { x: MixTimeline.SoundPlacement -> x.src.take?.let { takes[it] } ?: cues["${x.src.pack}/${x.src.cue}"] }
        val every = expect.getValue("samplesEvery").jsonPrimitive.int
        for (chunk in listOf(48_000, 17_760)) {
            val sink = MemorySink()
            val measured = MixRenderer.renderWith(timeline, chunk, loadVoice, loadSound, sink)
            val mix = sink.samples
            assertEquals("the mix is as long as its timeline (chunks of $chunk)", timeline.totalFrames, mix.size)
            var worst = 0
            var at = -1
            expect.getValue("samples").jsonArray.forEachIndexed { i, want ->
                val d = abs(lsb(mix[i * every]) - want.jsonPrimitive.int)
                if (d > worst) { worst = d; at = i * every }
            }
            for (pair in expect.getValue("samplesAt").jsonArray) {
                val f = pair.jsonArray[0].jsonPrimitive.int
                val d = abs(lsb(mix[f]) - pair.jsonArray[1].jsonPrimitive.int)
                if (d > worst) { worst = d; at = f }
            }
            assertTrue("every golden sample within 1 LSB (chunks of $chunk; worst $worst at $at)", worst <= 1)
            assertTrue("the peak (${measured.peak})", near(measured.peak, num(expect, "peak")))
            assertTrue("the one scalar (${measured.scalar})", near(measured.scalar, num(expect, "scalar")))
            assertTrue("held at -1 dBFS", mix.maxOf { abs(it) } <= Math.pow(10.0, -1.0 / 20) + 1.0 / 32768)
        }
        assertEquals("a quiet mix is not raised", 1.0, MixSound.mixScalar(0.5), 0.0)
    }

    @Test fun `a cue the loader cannot give is named, never dropped`() {
        val timeline = MixTimeline.build(script, production(block), resolveSound = resolver())
        val takes = takeRows.associate { str(it, "id") to synth(it) }
        try {
            MixRenderer.renderWith(timeline, 4_096, { takes.getValue(it.takeID) }, { null }, MemorySink())
            fail("a missing cue must not be mixed as silence")
        } catch (e: MixTimeline.MissingSounds) {
            assertEquals(listOf(timeline.sounds[0].soundID), e.ids)
        }
    }

    @Test fun `the sound block in the record keeps old records unchanged and performed cues kept`() {
        val plain = production(null)
        assertEquals("a record with no sound keeps its fingerprint", "L0001=t1,L0002=t2,L0004=t4,L0005=t5", plain.chosenFingerprint)
        assertEquals("only silent slots change nothing", plain.chosenFingerprint, production(SoundBlock(1, slots = listOf(block.slots[2]))).chosenFingerprint)
        val withSound = production(block)
        assertNotEquals("placing a sound makes the mix stale", plain.chosenFingerprint, withSound.chosenFingerprint)
        val s = block.slots
        val moved = production(block.copy(slots = listOf(s[0], s[1].copy(sounds = s[1].sounds.mapIndexed { i, c -> if (i == 2) c.copy(startMs = -400.0) else c }), s[2])))
        assertNotEquals("moving a sound makes the mix stale", withSound.chosenFingerprint, moved.chosenFingerprint)
        assertEquals("a take a slot plays is not unused", emptyList<String>(), withSound.unusedTakes.map { it.id })
        assertEquals("without the slot it is", listOf("k-door"), plain.unusedTakes.map { it.id })
        assertEquals("a take a slot plays is not deleted", emptyList<Take>(), withSound.deleteTake("k-door").second)
        assertEquals("nor discarded", emptyList<Take>(), withSound.discardUnused().second)
        assertEquals("without the slot it goes", listOf("k-door"), plain.deleteTake("k-door").second.map { it.id })
        assertTrue(!MixSound.hasSound(plain) && MixSound.hasSound(withSound))
    }

    @Test fun `an old record round-trips with no sound key and one with sound keeps it`() {
        val plain = production(null)
        val text = ProductionStore.encodeRecord(plain)
        assertFalse("no sound key", Json.parseToJsonElement(text).jsonObject.containsKey("sound"))
        val back = ProductionStore.json.decodeFromString(Production.serializer(), text)
        assertEquals(plain, back)
        assertEquals(text, ProductionStore.encodeRecord(back))
        val withSound = production(block)
        val written = ProductionStore.encodeRecord(withSound)
        assertTrue(Json.parseToJsonElement(written).jsonObject.containsKey("sound"))
        assertEquals(withSound.sound, ProductionStore.json.decodeFromString(Production.serializer(), written).sound)
    }

    @Test fun `the export carries the sound block when a production has one`() {
        fun export(sound: JsonElement?) = com.example.appname.data.DataExport(
            0, emptyList(), emptyList(), emptyList(),
            listOf(com.example.appname.data.DataExport.Production("p", "T", 0, emptyList(), sound)),
        ).json()
        val with = Json.parseToJsonElement(export(ProductionStore.json.encodeToJsonElement(SoundBlock.serializer(), block))).jsonObject
        val row = with.getValue("takes").jsonArray[0].jsonObject
        assertEquals("S1", row.getValue("sound").jsonObject.getValue("slots").jsonArray[0].jsonObject.getValue("id").jsonPrimitive.content)
        val without = Json.parseToJsonElement(export(null)).jsonObject.getValue("takes").jsonArray[0].jsonObject
        assertFalse(without.containsKey("sound"))
    }
}
