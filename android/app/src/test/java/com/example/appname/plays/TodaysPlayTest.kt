package com.example.appname.plays

import java.io.File
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Today's play (Decision 075) held to the golden every client shares,
 * `catalog/tests/golden/todays_play.json`: the hashes (unsigned 64-bit) and every dated case.
 */
class TodaysPlayTest {
    private fun golden(): JsonObject {
        var dir: File? = File("").absoluteFile
        while (dir != null) {
            val f = File(dir, "catalog/tests/golden/todays_play.json")
            if (f.exists()) return Json.parseToJsonElement(f.readText()).jsonObject
            dir = dir.parentFile
        }
        error("catalog/tests/golden/todays_play.json not found")
    }

    private fun scripts(ids: JsonArray): List<PlayScript> =
        ids.map { fixtureScript().copy(id = it.jsonPrimitive.content) }

    @Test fun `the hashes are the golden hashes`() {
        val hashes = golden()["hashes"]!!.jsonArray
        assertTrue(hashes.size >= 4)
        hashes.forEach { h ->
            val o = h.jsonObject
            val text = o["text"]!!.jsonPrimitive.content
            assertEquals(text, o["fnv1a64"]!!.jsonPrimitive.content, "%016x".format(PlayScript.fnv1a64(text).toLong()))
        }
    }

    @Test fun `every dated case picks the golden play`() {
        val g = golden()
        val cases = g["cases"]!!.jsonArray
        assertTrue(cases.size >= 5)
        cases.forEach { c ->
            val o = c.jsonObject
            val ids = (o["ids"] as? JsonArray) ?: g["ids"]!!.jsonArray
            val date = o["date"]!!.jsonPrimitive.content
            assertEquals(date, o["want"]!!.jsonPrimitive.contentOrNull, PlayScript.todaysPlay(scripts(ids), date)?.id)
        }
    }

    @Test fun `today's scene is today's play over the scene pool, case for case`() {
        val scene = golden()["scene"]!!.jsonObject
        val rows = scene["rows"]!!.jsonArray.map {
            val o = it.jsonObject
            val id = o["id"]!!.jsonPrimitive.content
            PlayRow(id = id, title = id, voices = o["voices"]!!.jsonPrimitive.int, minutes = o["minutes"]!!.jsonPrimitive.int)
        }
        val cases = scene["cases"]!!.jsonArray
        assertTrue(cases.size >= 5)
        cases.forEach { c ->
            val o = c.jsonObject
            val ids = (o["ids"] as? JsonArray)?.map { it.jsonPrimitive.content }?.toSet()
            val pool = if (ids == null) rows else rows.filter { it.id in ids }
            val date = o["date"]!!.jsonPrimitive.content
            assertEquals("$date ${ids ?: "all"}", o["want"]!!.jsonPrimitive.contentOrNull, PlayScript.todaysScene(pool, date)?.id)
        }
    }

    @Test fun `no plays means no play of the day`() {
        assertNull(PlayScript.todaysPlay(emptyList(), "2026-11-14"))
    }
}
