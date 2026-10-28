package com.example.appname.data

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** The search text rules every platform holds to: catalog/tests/golden/search_text.json (js/api.js is the reference). */
class SearchTextTest {
    private fun golden(): JsonObject {
        var dir: File? = File("").absoluteFile
        while (dir != null) {
            val f = File(dir, "catalog/tests/golden/search_text.json")
            if (f.exists()) return Json.parseToJsonElement(f.readText()).jsonObject
            dir = dir.parentFile
        }
        error("catalog/tests/golden/search_text.json not found")
    }

    @Test fun `a query's air date holds to the golden cases`() {
        val dates = golden()["dates"]!!.jsonArray
        assertTrue(dates.size > 10)
        dates.forEach { c ->
            val o = c.jsonObject
            val q = o["q"]!!.jsonPrimitive.content
            val d = DateQuery.parse(q)
            assertEquals("date of $q", o["prefix"]!!.jsonPrimitive.contentOrNull, d?.prefix)
            if (d != null) {
                assertEquals("rest of $q", o["rest"]!!.jsonPrimitive.content, d.rest)
                assertEquals("label of $q", o["label"]!!.jsonPrimitive.content, DateQuery.label(d.prefix))
            }
        }
    }

    @Test fun `a transcript snippet holds to the golden cases, verbatim`() {
        val s = golden()["snippets"]!!.jsonObject
        val text = s["text"]!!.jsonPrimitive.content
        val max = s["max"]!!.jsonPrimitive.int
        val cases = s["cases"]!!.jsonArray
        assertTrue(cases.size > 4)
        cases.forEach { c ->
            val o = c.jsonObject
            val words = o["words"]!!.jsonArray.map { it.jsonPrimitive.content }
            assertEquals("snippet for $words", o["snippet"]!!.jsonPrimitive.contentOrNull, Transcript.snippet(text, words, max))
        }
        assertEquals(listOf("the", "zeppelin"), Transcript.searchWords("Of the Zeppelin's ZEPPELIN"))
    }
}
