package com.example.appname.data

import java.io.File
import kotlin.math.abs
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The label's Kotlin port held to the web's own cases: catalog/tests/golden/label_spec.json is the contract
 * every stack reads straight from the repo (js/label.test.js, LabelSpecTests.swift). Numbers match within
 * the file's tolerance; strings, nulls and array lengths exactly; an absent key and a null are the same.
 *
 * Negative control, 2026-11-19: art.label.arc.width.L 3.5 -> 3.6 in LabelTokens.kt failed the Suspense series
 * and episode cases; `theComparatorSeesADifference` fails when the comparator stops looking.
 */
class LabelSpecTest {
    private val golden = Json.parseToJsonElement(File("../../catalog/tests/golden/label_spec.json").readText()) as JsonObject
    private val cases = (golden["cases"] as JsonArray).map { it as JsonObject }
    private val tolerance = (golden["tolerance"] as JsonPrimitive).doubleOrNull ?: 0.01

    private fun str(o: JsonObject, k: String): String? = (o[k] as? JsonPrimitive)?.takeIf { it !is JsonNull }?.content

    private fun item(o: JsonObject) = LabelItem(
        kind = LabelKind.entries.first { it.key == (str(o, "kind") ?: "series") },
        name = str(o, "name"), genre = str(o, "genre"), first = str(o, "first"), last = str(o, "last"), network = str(o, "network"),
        tickYear = str(o, "tickYear"), date = str(o, "date"), num = str(o, "num"), finished = str(o, "finished"),
        voices = (o["voices"] as? JsonPrimitive)?.intOrNull ?: 0,
        opening = (o["opening"] as? JsonPrimitive)?.booleanOrNull ?: false,
        cast = (o["cast"] as? JsonArray)?.map { (it as JsonPrimitive).intOrNull ?: 0 } ?: emptyList(),
        parts = (o["parts"] as? JsonArray)?.map { p ->
            val po = p as JsonObject
            LabelPart((po["lines"] as JsonPrimitive).intOrNull ?: 0, str(po, "hue"))
        } ?: emptyList(),
    )

    /** The first difference between [got] and [want], as a path; null when equal. */
    private fun difference(got: JsonElement?, want: JsonElement?, path: String = "$"): String? {
        val g = got.takeIf { it !is JsonNull }
        val w = want.takeIf { it !is JsonNull }
        if (g == null && w == null) return null
        if (g is JsonObject && w is JsonObject) {
            for (k in (g.keys + w.keys).sorted()) difference(g[k], w[k], "$path.$k")?.let { return it }
            return null
        }
        if (g is JsonArray && w is JsonArray) {
            if (g.size != w.size) return "$path: ${g.size} items, wanted ${w.size}"
            for (i in g.indices) difference(g[i], w[i], "$path[$i]")?.let { return it }
            return null
        }
        if (g is JsonPrimitive && w is JsonPrimitive) {
            val a = g.doubleOrNull
            val b = w.doubleOrNull
            if (!g.isString && !w.isString && a != null && b != null) return if (abs(a - b) <= tolerance) null else "$path: $a, wanted $b"
            return if (g.content == w.content) null else "$path: ${g.content}, wanted ${w.content}"
        }
        return "$path: $g, wanted $w"
    }

    private fun run(c: JsonObject) =
        LabelSpec.toJson(LabelSpec.make(item(c["item"] as JsonObject), (c["size"] as JsonPrimitive).doubleOrNull ?: 0.0))

    @Test fun goldenFileIsThere() {
        assertTrue("label_spec.json was not read from the repo", cases.size >= 36)
    }

    @Test fun everyGoldenCaseMatches() {
        for (c in cases) {
            val miss = difference(run(c), c["want"])
            assertNull("${str(c, "name")}: $miss", miss)
        }
    }

    @Test fun theComparatorSeesADifference() {
        val c = cases.first()
        val spec = LabelSpec.make(item(c["item"] as JsonObject), 360.0)
        val drifted = spec.copy(arc = spec.arc!!.let { it.copy(width = it.width + 0.5) })
        assertNotNull(difference(LabelSpec.toJson(drifted), c["want"]))
        assertNotNull(difference(LabelSpec.toJson(spec.copy(rim = null)), c["want"]))
    }

    @Test fun tiersFollowTheWindow() {
        assertEquals("S", LabelSpec.make(LabelItem(name = "A"), 95.0).tier)
        assertEquals("M", LabelSpec.make(LabelItem(name = "A"), 96.0).tier)
        assertEquals("L", LabelSpec.make(LabelItem(name = "A"), 320.0).tier)
    }
}
