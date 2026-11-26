package com.example.appname.plays

import java.io.File
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Register hints from the catalog (catalog DECISIONS 049): the golden every stack runs
 * (catalog/tests/golden/voice_register_cast.json, also js/voice-cast.test.js and apple VoiceRegisterCastTests), the roles'
 * `register` decoded, and a person's own choice winning.
 *
 * Seen to fail, 2026-11-26, against mutated copies of plays/VoiceCast.kt (restored after): autoCast ignoring [registers] (four
 * cases), the bias orders swapped (the web case), the no-kind fallback skipped (a woman's part on a man's voice), a matched
 * reuse pitched in the old order (two parts at 0.86); and PlayScript.registers returning nothing (the decode test).
 */
class VoiceRegisterCastTest {
    private fun root(): File {
        var dir: File? = File("").absoluteFile
        while (dir != null) {
            if (File(dir, "catalog/tests/golden/voice_register_cast.json").exists()) return dir
            dir = dir.parentFile
        }
        error("repository root not found")
    }

    private val golden by lazy { Json.parseToJsonElement(File(root(), "catalog/tests/golden/voice_register_cast.json").readText()).jsonObject }

    /** What is wrong with one case, one line a part; empty when the cast is the case's. */
    private fun run(c: JsonObject): List<String> {
        val voices = c["voices"]!!.jsonArray.map { v ->
            val o = v.jsonObject
            val id = o["id"]!!.jsonPrimitive.content
            CastVoice(id, id, "en-US", 0, gender = o["gender"]?.jsonPrimitive?.contentOrNull,
                      engine = o["engine"]?.jsonPrimitive?.contentOrNull ?: VoiceCastEntry.SYSTEM,
                      register = o["register"]?.jsonPrimitive?.contentOrNull)
        }
        val parts = c["parts"]!!.jsonArray.map { PartID(it.jsonObject["id"]!!.jsonPrimitive.content) }
        val registers = c["parts"]!!.jsonArray.mapNotNull { p ->
            p.jsonObject["register"]?.jsonPrimitive?.contentOrNull?.let { PartID(p.jsonObject["id"]!!.jsonPrimitive.content) to it }
        }.toMap()
        val got = VoiceCasting.autoCast(parts, voices, registers = registers)
        return c["cast"]!!.jsonObject.mapNotNull { (part, want) ->
            val e = got[PartID(part)]
            val voice = want.jsonArray[0].jsonPrimitive.contentOrNull
            val pitch = want.jsonArray[1].jsonPrimitive.doubleOrNull ?: Double.NaN
            if (e?.voice != voice || Math.abs((e?.pitch ?: Double.NaN) - pitch) > 1e-9) "$part: want $voice $pitch, got ${e?.voice} ${e?.pitch}" else null
        }.sorted()
    }

    @Test fun `golden voice_register_cast every stack, and its control is found wrong`() {
        val cases = golden["cases"]!!.jsonArray
        assertTrue("the golden file is found", cases.size >= 5)
        for (c in cases) assertEquals(c.jsonObject["name"]!!.jsonPrimitive.content, emptyList<String>(), run(c.jsonObject))
        assertTrue("the control is wrong on purpose and is found wrong", run(golden["control"]!!.jsonObject).isNotEmpty())
    }

    @Test fun `a script's roles carry their published register, only high or low`() {
        val text = """
            {"id":"gut-1","revision":"r","kind":"stage","title":"T","authors":[],"source":{"name":"s","url":"u"},
             "rights":{"bucket":"b","evidence":[]},"lines":[],
             "roles":[{"name":"NORA","lines":3,"words":9,"register":"high"},{"name":"HELMER","lines":2,"words":5,"register":"low"},
                      {"name":"ALL","lines":1,"words":1},{"name":"ODD","lines":1,"words":1,"register":"loud"}]}
        """.trimIndent()
        val json = Json { ignoreUnknownKeys = true }
        val script = json.decodeFromString(PlayScript.serializer(), text)
        assertEquals("high and low only; none for ALL or a bad value", mapOf(PartID.role("NORA") to "high", PartID.role("HELMER") to "low"), script.registers)
        val old = json.decodeFromString(PlayScript.serializer(), text.replace(",\"register\":\"high\"", ""))
        assertNull("a script from before the field decodes, with no register", old.registers[PartID.role("NORA")])
    }

    @Test fun `a register reaches the Default, and a person's own choice wins`() {
        val michael = CastVoice("am_michael", "Michael (Kokoro)", "en-US", 0, gender = "male", engine = VoiceCastEntry.KOKORO)
        val heart = CastVoice("af_heart", "Heart (Kokoro)", "en-US", 0, gender = "female", engine = VoiceCastEntry.KOKORO)
        val store = MemoryCastStore()
        val parts = listOf(PartID.role("MOLLY"), PartID.role("FIBBER"))
        val cast = VoiceCast("p:REG", parts, { listOf(michael, heart) }, store,
                             registers = mapOf(PartID.role("MOLLY") to "high", PartID.role("FIBBER") to "low"))
        assertEquals("the woman's part on the woman's voice, though it is listed second",
                     listOf("af_heart", "am_michael"), parts.map { cast.entry(it)?.voice })
        assertNull("the Default is never written", VoiceCasting.load("p:REG", store))
        cast.set(PartID.role("MOLLY")) { VoiceCastEntry(VoiceCastEntry.KOKORO, "am_michael", "Michael (Kokoro)") }
        assertEquals("the person's choice for the part wins over its register", "am_michael", cast.entry(PartID.role("MOLLY"))?.voice)
        val plain = VoiceCast("p:REG2", parts, { listOf(michael, heart) }, store)
        assertEquals("without a register the largest part takes the best voice, as before", "am_michael", plain.entry(PartID.role("MOLLY"))?.voice)
    }
}
