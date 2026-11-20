package com.example.appname.plays

import java.io.File
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * ReadCore's Kotlin port held to worker/test/read-golden.json, the file the Worker's own protocol writes and the web and
 * Swift ports read. Every case of a function a client ports; a snapshot must land a client on the server's own next
 * line. Negative controls (2026-11-19, each seen to fail before it was kept):
 *   the harness over a golden copy with one expected value flipped: failures non-empty ([the harness sees a drift]).
 *   leaderGone letting a class hand the lead on: the leaderGone goldens failed.
 *   assignmentFor ignoring a range's `to`: partsOf/whoReads/nextMine goldens failed.
 *   recordRefusal without the holds check (T5, 2026-11-19, seen to fail with the other T5 rules broken in one run): the recordRefusal golden "not another part's line" failed.
 */
class ReadCoreTest {
    private val golden: JsonObject = Json.parseToJsonElement(File("../../worker/test/read-golden.json").readText()).jsonObject
    private val cases: List<JsonObject> = golden["cases"]!!.jsonArray.map { it.jsonObject }

    private fun str(e: JsonElement?): String? = (e as? JsonPrimitive)?.takeIf { it !is JsonNull }?.contentOrNull
    private fun num(e: JsonElement?): Double = (e as JsonPrimitive).double

    private fun room(e: JsonElement): ReadCore.Room {
        val o = e.jsonObject
        return ReadCore.Room(
            kind = str(o["kind"]) ?: "adult", mode = str(o["mode"]) ?: "read", cursor = str(o["cursor"]).orEmpty(),
            cursorGen = o["cursor_gen"]?.jsonPrimitive?.int ?: 0, generation = o["generation"]?.jsonPrimitive?.int ?: 0,
            leader = str(o["leader"]).orEmpty(),
            claims = o["claims"]?.jsonObject?.mapValues { it.value.jsonPrimitive.content }.orEmpty(),
            seats = o["seats"]?.jsonArray?.map { ReadCore.Seat(str(it.jsonObject["id"])!!, str(it.jsonObject["label"])!!) }.orEmpty(),
            assignments = o["assignments"]?.jsonArray?.map {
                val a = it.jsonObject
                ReadCore.Assignment(str(a["part"])!!, str(a["seat"])!!, str(a["from"]), str(a["to"]))
            }.orEmpty(),
            done = o["done"]?.jsonArray?.map { it.jsonPrimitive.content }.orEmpty(),
            locked = o["locked"]?.jsonPrimitive?.boolean ?: false, ended = o["ended"]?.jsonPrimitive?.boolean ?: false,
            owner = str(o["owner"]), ownerName = str(o["owner_name"]),
        )
    }

    private fun member(e: JsonElement): ReadCore.Member? {
        if (e is JsonNull) return null
        val o = e.jsonObject
        return ReadCore.Member(str(o["id"])!!, str(o["role"]) ?: "reader", str(o["seat"]), num(o["joined_at"]), num(o["seen_at"]), str(o["name"]))
    }

    private fun members(e: JsonElement): List<ReadCore.Member> = e.jsonArray.mapNotNull(::member)
    private fun cast(e: JsonElement): List<Pair<String, String>> = e.jsonArray.map { it.jsonArray[0].jsonPrimitive.content to it.jsonArray[1].jsonPrimitive.content }
    private fun orNull(s: String?): JsonElement = s?.let(::JsonPrimitive) ?: JsonNull

    private fun range(r: ReadCore.PartRange) = buildJsonObject { put("part", JsonPrimitive(r.part)); put("from", orNull(r.from)); put("to", orNull(r.to)) }

    /** What a ported function answers for a golden case, shaped as the JSON the Worker wrote. */
    private fun answer(c: JsonObject): JsonElement? {
        val a = c["args"]!!.jsonArray
        return when (c["fn"]!!.jsonPrimitive.content) {
            "normalizeCode" -> orNull(ReadCore.normalizeCode(a[0].jsonPrimitive.content))
            "codeFromBytes" -> JsonPrimitive(ReadCore.codeFromBytes(a[0].jsonArray.map { it.jsonPrimitive.int }))
            "clockOffset" -> ReadCore.clockOffset(a[0].jsonArray.map { ReadCore.ClockSample(num(it.jsonObject["t0"]), num(it.jsonObject["server_time"]), num(it.jsonObject["t1"])) })
                ?.let(::JsonPrimitive) ?: JsonNull
            "canLead" -> JsonPrimitive(ReadCore.canLead(room(a[0]), str(a[1])))
            "partsOf" -> JsonArray(ReadCore.partsOf(room(a[0]), member(a[1])).map(::range))
            "whoReads" -> {
                val r = room(a[0])
                val w = ReadCore.whoReads(r, cast(a[1]), members(a[2]), a[3].jsonPrimitive.content, num(a[4]))
                if (w == null) JsonNull else buildJsonObject {
                    put("part", JsonPrimitive(w.part))
                    put("seat", orNull(w.seat))
                    put("members", buildJsonArray { w.members.forEach { add(JsonPrimitive(it)) } })
                    if (r.kind != "class") put("holder", orNull(w.holder))
                }
            }
            "nextMine" -> ReadCore.nextMine(room(a[0]), cast(a[1]), member(a[2]), a[3].jsonPrimitive.content)
                ?.let { n -> buildJsonObject { put("line", JsonPrimitive(n.line)); put("in", JsonPrimitive(n.inLines)) } } ?: JsonNull
            "cleanName" -> ReadCore.cleanName(room(a[0]), str(a[1])).let { if (it == ReadCore.NAME_REFUSED) JsonPrimitive(false) else orNull(it) }
            "receiverOf" -> orNull(ReadCore.receiverOf(room(a[0])))
            "recordRefusal" -> orNull(ReadCore.recordRefusal(room(a[0]), cast(a[1]), member(a[2]), a[3].jsonPrimitive.content))
            "leaderName" -> orNull(ReadCore.leaderName(room(a[0]), members(a[1])))
            "leaderGone" -> ReadCore.leaderGone(room(a[0]), members(a[1]), num(a[2])).let { l ->
                buildJsonObject { put("leader", JsonPrimitive(l.leader)); put("waiting", JsonPrimitive(l.waiting)) }
            }
            else -> null
        }
    }

    private val ported = setOf("normalizeCode", "codeFromBytes", "clockOffset", "canLead", "partsOf", "whoReads", "nextMine", "leaderGone", "cleanName", "receiverOf", "recordRefusal", "leaderName")

    /** JSON numbers compare by value, as the web's `JSON.stringify` and Swift's NSNumber compare them. */
    private fun same(x: JsonElement?, y: JsonElement?): Boolean = when {
        x is JsonPrimitive && y is JsonPrimitive && !x.isString && !y.isString && x.contentOrNull?.toDoubleOrNull() != null && y.contentOrNull?.toDoubleOrNull() != null ->
            x.content.toDouble() == y.content.toDouble()
        x is JsonObject && y is JsonObject -> x.keys == y.keys && x.keys.all { same(x[it], y[it]) }
        x is JsonArray && y is JsonArray -> x.size == y.size && x.indices.all { same(x[it], y[it]) }
        else -> x == y
    }

    /** Names of the golden cases the port answers differently from the Worker. */
    private fun failures(of: List<JsonObject>): List<String> {
        val bad = mutableListOf<String>()
        for (c in of) {
            val fn = c["fn"]!!.jsonPrimitive.content
            if (fn in ported) {
                if (!same(answer(c), c["expect"])) bad += "$fn: ${str(c["note"])}"
            } else if (fn == "joinSnapshot") {
                val snap = ShareJson.decodeFromString(ReadSnapshot.serializer(), c["expect"].toString())
                val got = ReadCore.nextMine(snap.room, cast(c["args"]!!.jsonArray[1]), snap.meMember, snap.cursor)
                val want = snap.nextMine
                if (got?.line != want?.line || got?.inLines != want?.inLines) bad += "snapshot next line: ${str(c["note"])}"
            }
        }
        return bad
    }

    @Test fun `every ported golden case holds`() {
        val ran = cases.count { it["fn"]!!.jsonPrimitive.content in ported || it["fn"]!!.jsonPrimitive.content == "joinSnapshot" }
        assertTrue("the golden file has its cases ($ran)", ran >= 50)
        assertEquals(emptyList<String>(), failures(cases))
    }

    @Test fun `the constants are the protocol's`() {
        val k = golden["constants"]!!.jsonObject
        assertEquals(k["CODE_ALPHABET"]!!.jsonPrimitive.content, ReadCore.CODE_ALPHABET)
        assertEquals(k["CODE_LENGTH"]!!.jsonPrimitive.int, ReadCore.CODE_LENGTH)
        assertEquals(k["MAX_MEMBERS"]!!.jsonPrimitive.int, ReadCore.MAX_MEMBERS)
        assertEquals(k["MEMBER_GONE_MS"]!!.jsonPrimitive.double.toLong(), ReadCore.MEMBER_GONE_MS)
        assertEquals(k["LEADER_GONE_MS"]!!.jsonPrimitive.double.toLong(), ReadCore.LEADER_GONE_MS)
        assertEquals(k["POLL_MS"]!!.jsonPrimitive.double.toLong(), ReadCore.POLL_MS)
        assertEquals(k["MODES"]!!.jsonArray.map { it.jsonPrimitive.content }, ReadCore.MODES)
    }

    /** The harness is a test only once it is seen to fail: one expected answer flipped must be caught. */
    @Test fun `the golden harness sees a drift`() {
        val i = cases.indexOfFirst { it["fn"]!!.jsonPrimitive.content == "nextMine" }
        val flipped = cases.toMutableList()
        flipped[i] = JsonObject(cases[i] + ("expect" to buildJsonObject { put("line", JsonPrimitive("zz")); put("in", JsonPrimitive(99)) }))
        assertFalse(failures(flipped).isEmpty())
    }

    @Test fun `the snapshot carries the leader's name and read open parts`() {
        val snaps = cases.filter { it["fn"]!!.jsonPrimitive.content == "joinSnapshot" }.map { it["expect"]!!.jsonObject }
        val named = snaps.first { str(it["leader_name"]) == "Ben" }
        val snap = ShareJson.decodeFromString(ReadSnapshot.serializer(), named.toString())
        assertEquals("Ben", ReadCore.waitingFor(snap))
        assertTrue(snap.readOpen)
    }

    @Test fun `a reader says when its next line is coming`() {
        assertEquals("Next: you, in 3 lines", ReadCore.nextLine(ReadCore.Next("l4", 3)))
        assertEquals("Next: you, in 1 line", ReadCore.nextLine(ReadCore.Next("l4", 1)))
        assertEquals("Your line", ReadCore.nextLine(ReadCore.Next("l4", 0)))
        assertEquals(null, ReadCore.nextLine(null))
    }

    @Test fun `fill evenly is deterministic and keeps the casting made`() {
        val cast = listOf("a" to "P1", "b" to "P2", "c" to "P1", "d" to "P3", "e" to "P2")
        val words = listOf(10, 4, 10, 2, 4)
        val facts = ReadCore.partFacts(cast, words, listOf(0))
        assertEquals(20, facts.first { it.part == "P1" }.words)
        val seats = listOf(ReadCore.Seat("s1", "Ann"), ReadCore.Seat("s2", "Bo"))
        val made = listOf(ReadCore.Assignment("P3", "s1"))
        val out = ReadCore.fillEvenly(facts, seats, made, cast, words)
        assertEquals(made.first(), out.first())
        assertEquals("s2", out.first { it.part == "P1" }.seat)
        assertEquals(out, ReadCore.fillEvenly(facts, seats, made, cast, words))
        assertEquals(2, ReadCore.sceneRanges(cast, "P1", listOf(0, 2)).size)
    }
}
