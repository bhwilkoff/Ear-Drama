package com.example.appname.together

import java.io.File
import java.security.MessageDigest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.double
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The port is golden-checked against worker/src/room-protocol.js: every
 * expected answer in `room-golden.json` was computed by the Worker's own
 * functions (`node android/scripts/room-golden.mjs`), so the two stacks
 * cannot drift apart on a threshold, a rate, a code, or a handoff.
 */
class RoomProtocolTest {
    private val protocolJs = File("../../worker/src/room-protocol.js")
    private val golden: JsonObject =
        Json.parseToJsonElement(javaClass.getResource("/together/room-golden.json")!!.readText()).jsonObject

    private fun JsonElement.d() = jsonPrimitive.double
    private fun JsonElement.l() = jsonPrimitive.long
    private fun JsonElement.s(): String? = if (this is JsonNull) null else jsonPrimitive.content

    private fun state(o: JsonObject) = RoomState(
        episodeId = o["episode_id"]!!.s()!!,
        archiveId = o["archive_id"]!!.s()!!,
        file = o["file"]!!.s()!!,
        position = o["position"]!!.d(),
        playing = o["playing"]!!.jsonPrimitive.boolean,
        rate = o["rate"]!!.d(),
        updatedAt = o["updated_at"]!!.l(),
    )

    /** The JS answer's shape: `{ action, position?, play?, rate? }`. */
    private fun asJs(c: Correction): Map<String, Any> = when (c) {
        Correction.None -> mapOf("action" to "none")
        is Correction.Pause -> mapOf("action" to "pause", "position" to c.position)
        is Correction.Seek -> if (c.play) mapOf("action" to "seek", "position" to c.position, "play" to true) else mapOf("action" to "seek", "position" to c.position)
        is Correction.Play -> mapOf("action" to "play", "position" to c.position, "rate" to c.rate)
        is Correction.Rate -> mapOf("action" to "rate", "rate" to c.rate)
    }

    private fun fromJs(o: JsonObject): Map<String, Any> = o.mapValues { (_, v) ->
        val p = v.jsonPrimitive
        p.booleanOrNull ?: if (p.isString) p.content else p.double
    }

    @Test fun `the golden file is the current room-protocol js`() {
        val sha = MessageDigest.getInstance("SHA-256").digest(protocolJs.readBytes()).joinToString("") { "%02x".format(it) }
        assertEquals(
            "worker/src/room-protocol.js changed: run `node android/scripts/room-golden.mjs` and port what changed",
            golden["protocol_sha256"]!!.s(),
            sha,
        )
    }

    @Test fun `the constants are the Worker's`() {
        val c = golden["constants"]!!.jsonObject
        assertEquals(c["code_alphabet"]!!.s(), RoomProtocol.CODE_ALPHABET)
        assertEquals(c["code_length"]!!.l().toInt(), RoomProtocol.CODE_LENGTH)
        assertEquals(c["max_members"]!!.l().toInt(), RoomProtocol.MAX_MEMBERS)
        assertEquals(c["member_gone_ms"]!!.l(), RoomProtocol.MEMBER_GONE_MS)
        assertEquals(c["speeds"]!!.jsonArray.map { it.d() }, RoomProtocol.SPEEDS)
        val drift = c["drift"]!!.jsonObject
        assertEquals(drift["ignoreBelow"]!!.d(), RoomProtocol.IGNORE_BELOW, 0.0)
        assertEquals(drift["seekAbove"]!!.d(), RoomProtocol.SEEK_ABOVE, 0.0)
        assertEquals(drift["nudge"]!!.d(), RoomProtocol.NUDGE, 0.0)
        assertEquals(drift["pollFastMs"]!!.l(), RoomProtocol.POLL_FAST_MS)
        assertEquals(drift["pollSlowMs"]!!.l(), RoomProtocol.POLL_SLOW_MS)
        assertEquals(drift["slowAfterStillMs"]!!.l(), RoomProtocol.SLOW_AFTER_STILL_MS)
    }

    @Test fun `drift correction matches the Worker on every shared case`() {
        val cases = golden["drift"]!!.jsonArray
        assertTrue(cases.size >= 20)
        cases.forEachIndexed { i, case ->
            val o = case.jsonObject
            val s = state(o["state"]!!.jsonObject)
            val now = o["server_now"]!!.l()
            val p = o["player"]!!.jsonObject
            val player = PlayerSample(p["position"]!!.d(), p["playing"]!!.jsonPrimitive.boolean)
            assertEquals("case $i expected position", o["expected_position"]!!.d(), RoomProtocol.expectedPosition(s, now), 0.0)
            assertEquals("case $i", fromJs(o["correction"]!!.jsonObject), asJs(RoomProtocol.correction(s, now, player)))
        }
        // Every action the Worker can answer is among the cases.
        val actions = cases.map { it.jsonObject["correction"]!!.jsonObject["action"]!!.s() }.toSet()
        assertEquals(setOf("none", "pause", "seek", "play", "rate"), actions)
    }

    @Test fun `codes, the clock, the cadence, handoff, and copies match the Worker`() {
        golden["codes"]!!.jsonArray.forEach {
            val o = it.jsonObject
            assertEquals(o["typed"]!!.s(), o["code"]!!.s(), RoomProtocol.normalizeCode(o["typed"]!!.s()))
        }
        golden["clock"]!!.jsonArray.forEach {
            val o = it.jsonObject
            val samples = o["samples"]!!.jsonArray.map { s ->
                val x = s.jsonObject
                ClockSample(x["t0"]!!.l(), x["server_time"]!!.l(), x["t1"]!!.l())
            }
            assertEquals(samples.toString(), o["offset"]!!.let { v -> if (v is JsonNull) null else v.d() }, RoomProtocol.clockOffset(samples))
        }
        golden["poll"]!!.jsonArray.forEach {
            val o = it.jsonObject
            assertEquals(o["interval"]!!.l(), RoomProtocol.pollInterval(o["last_change_at"]!!.l(), o["now"]!!.l()))
        }
        golden["handoff"]!!.jsonArray.forEachIndexed { i, it ->
            val o = it.jsonObject
            val members = (o["members"] as JsonArray).map { m ->
                val x = m.jsonObject
                RoomMember(x["id"]!!.s()!!, x["joined_at"]!!.l(), x["seen_at"]!!.l())
            }
            assertEquals("handoff $i", o["next"]!!.s(), RoomProtocol.nextHost(members, o["leaving"]!!.s(), o["now"]!!.l()))
        }
        golden["copies"]!!.jsonArray.forEach {
            val o = it.jsonObject
            val id = o["archive_id"]!!.s()!!
            val file = o["file"]!!.s()!!
            assertEquals("$id/$file", o["clean"]!!.jsonPrimitive.boolean, RoomProtocol.cleanCopy(id, file))
        }
    }

    @Test fun `the guest builds the host's copy URL and reads one back`() {
        val url = RoomProtocol.copyUrl("OTRR_Suspense_Singles", "disc 1/Suspense 48-03-11 (The Lodger).mp3")
        assertEquals("https://archive.org/download/OTRR_Suspense_Singles/disc%201/Suspense%2048-03-11%20(The%20Lodger).mp3", url)
        assertEquals("OTRR_Suspense_Singles" to "disc 1/Suspense 48-03-11 (The Lodger).mp3", RoomProtocol.copyOf(url))
        assertEquals(null, RoomProtocol.copyOf("https://example.com/download/x/a.mp3"))
        assertEquals(null, RoomProtocol.copyOf("https://archive.org/download/x/..%2Fevil.mp3"))
        assertEquals(1.0, RoomProtocol.roomRate(0.97), 0.0)
        assertEquals(1.5, RoomProtocol.roomRate(1.545), 0.0)
    }

    /** The Worker's test fails if room-protocol.js gains an import; the port is held to the same. */
    @Test fun `the protocol port imports nothing`() {
        val source = File("src/main/java/com/example/appname/together/RoomProtocol.kt").readText()
        assertEquals(emptyList<String>(), source.lines().filter { it.startsWith("import ") })
        assertTrue("the JS side still has none", protocolJs.readLines().none { it.startsWith("import ") })
    }
}
