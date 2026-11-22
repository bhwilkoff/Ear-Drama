package com.example.appname.plays

import com.example.appname.kokoro.Kokoro
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * A part cast to a downloaded voice (PLAYS-DESIGN §2.8 engine `kokoro`, rule 8; Decision 078): it resolves when the model
 * is here, falls back visibly to its auto-cast system voice when it is not, auto-cast never picks a Kokoro voice, and the
 * system engine is never handed a Kokoro id.
 */
class KokoroCastTest {
    private val system = listOf(
        CastVoice("en-us-x-tpd-local", "English (United States) 1", "en-US", 400),
        CastVoice("en-gb-x-rjs-local", "English (United Kingdom)", "en-GB", 300),
    )
    private val molly = PartID.role("MOLLY")
    private val fibber = PartID.role("FIBBER")

    private fun cast(downloaded: Boolean, store: CastStore = MemoryCastStore()) =
        VoiceCast("p:K", fixtureScript().castParts.map { it.id }, { system }, store, downloaded = { Kokoro.castable(downloaded) })

    private class Engine : VoiceSetter {
        var voiceId: String? = null
        override fun setVoice(id: String): Boolean { voiceId = id; return true }
        override fun setPitch(pitch: Float) {}
        override fun setSpeechRate(rate: Float) {}
    }

    @Test fun `a Kokoro choice resolves to the Kokoro voice while the model is here`() {
        val store = MemoryCastStore()
        val c = cast(true, store)
        c.set(molly) { copy(engine = VoiceCastEntry.KOKORO, voice = "af_heart", name = "Heart (Kokoro)") }
        val r = c.resolve(molly)
        assertEquals("af_heart", r.voice?.id)
        assertEquals(VoiceCastEntry.KOKORO, r.voice?.engine)
        assertNull(r.missing)
    }

    @Test fun `after Delete the part is read by its auto-cast system voice and says the Kokoro voice is missing`() {
        val store = MemoryCastStore()
        cast(true, store).set(molly) { copy(engine = VoiceCastEntry.KOKORO, voice = "af_heart", name = "Heart (Kokoro)") }
        val r = cast(false, store).resolve(molly)
        assertEquals(system[0].id, r.voice?.id)
        assertEquals("Heart (Kokoro)", r.missing)
        assertEquals("the choice is kept and returns with the download", "af_heart", cast(true, store).resolve(molly).voice?.id)
    }

    @Test fun `the Default casts Kokoro first where it is downloaded, and nothing is stored`() {
        val store = MemoryCastStore()
        val speaking = fixtureScript().castParts.map { it.id }.filter { it.isSpeaking }
        assertTrue(speaking.all { cast(false).resolve(it).voice?.engine == VoiceCastEntry.SYSTEM })
        val c = cast(true, store)
        assertTrue(speaking.all { c.resolve(it).voice?.engine == VoiceCastEntry.KOKORO && c.resolve(it).isDefault })
        assertEquals("af_heart", c.resolve(speaking[0]).voice?.id)
        assertNull(store.text)
    }

    @Test fun `the system engine is handed the part's auto-cast system voice, never a Kokoro id`() {
        val c = cast(true)
        c.set(molly) { copy(engine = VoiceCastEntry.KOKORO, voice = "bm_george", name = "George (Kokoro)") }
        val e = Engine()
        assertTrue(c.prepare(molly, e))
        assertEquals(system[0].id, e.voiceId)
        assertEquals(system[0].id, c.systemFallback(molly)?.voice?.id)
    }

    @Test fun `the recorder's cue renders a Kokoro part through Kokoro and every other line through the system voice`() = runTest {
        val c = cast(true)
        c.set(molly) { copy(engine = VoiceCastEntry.KOKORO, voice = "af_heart", name = "Heart (Kokoro)") }
        val asked = ArrayList<String>()
        val systemVoice = object : StandInVoice {
            override suspend fun render(text: String, part: PartID, rate: Float): StandInAudio { asked += part.raw; return StandInAudio(FloatArray(10) { 0.1f }, 48_000.0) }
        }
        var kokoroLine: String? = null
        c.set(fibber) { copy(engine = VoiceCastEntry.SYSTEM, voice = system[0].id, name = system[0].name) }
        val v = KokoroStandIn(c, systemVoice) { text, id, _ -> kokoroLine = "$id:$text"; FloatArray(2_400) { 0.2f } }
        val a = v.render("Come in.", molly, 1f)!!
        assertEquals("af_heart:Come in.", kokoroLine)
        assertEquals("24 kHz resampled to the take rate", 4_800, a.samples.size)
        v.render("Doc!", fibber, 1f)
        assertEquals(listOf("role:FIBBER"), asked)
        val none = KokoroStandIn(c, systemVoice) { _, _, _ -> null }
        none.render("Come in.", molly, 1f)
        assertEquals("a line Kokoro cannot read goes to the system voice", listOf("role:FIBBER", "role:MOLLY"), asked)
    }
}
