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

    private val pageCases = ((golden["playPage"] as JsonObject)["cases"] as JsonArray).map { it as JsonObject }

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
        author = str(o, "author"), hue = str(o, "hue"), era = str(o, "era"),
        life = (o["life"] as? JsonObject)?.let { l ->
            LabelLife((l["born"] as? JsonPrimitive)?.intOrNull, (l["died"] as? JsonPrimitive)?.intOrNull)
        },
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

    private fun pageMisses(make: (LabelItem, Double) -> LabelSpec = { i, size -> LabelSpec.make(i, size) }): List<String> = pageCases.mapNotNull { c ->
        val spec = make(item(c["item"] as JsonObject), (c["size"] as JsonPrimitive).doubleOrNull ?: 0.0)
        difference(LabelSpec.toJson(spec), c["want"])?.let { "${str(c, "name")}: $it" }
    }

    /** B31 2.1 (WEB-DESIGN 6.4r): the play's page label from the web's `playPage` goldens, all three tiers. */
    @Test fun everyPlayPageCaseMatches() {
        assertTrue("the playPage cases were not read", pageCases.size >= 20)
        val misses = pageMisses()
        assertTrue(misses.take(3).joinToString("\n"), misses.isEmpty())
        val tiers = pageCases.map { ((it["want"] as JsonObject)["tier"] as JsonPrimitive).content }.toSet()
        assertEquals(setOf("S", "M", "L"), tiers)
    }

    /** Negative controls: a page with no rest column, a ruler that forgets the era, and a monogram drawn from the middle each fail the goldens. */
    @Test fun thePlayPageGoldensSeeAMutant() {
        val noRest = pageMisses { i, size ->
            val spec = LabelSpec.make(i, size)
            spec.copy(cols = spec.cols?.let { c -> c.copy(bars = c.bars.map { b -> b.copy(rest = false) }) })
        }
        assertTrue("a page with no rest column passed every golden", noRest.isNotEmpty())
        val unlit = pageMisses { i, size ->
            val spec = LabelSpec.make(i, size)
            spec.copy(ruler = spec.ruler?.copy(lit = -1))
        }
        assertTrue("a ruler with no lit cell passed every golden", unlit.isNotEmpty())
        val centered = pageMisses { i, size ->
            val spec = LabelSpec.make(i, size)
            spec.copy(text = spec.text.map { t -> if (t.face == "display") t.copy(anchor = "middle") else t })
        }
        assertTrue("a centered monogram passed every golden", centered.isNotEmpty())
    }

    @Test fun thePlayPageKeepsItsColumnsOnThePage() {
        for ((size, most) in listOf(56.0 to 6, 128.0 to 10, 360.0 to 12)) for (n in listOf(1, 2, most, most + 1, 67)) {
            val bars = LabelSpec.make(LabelItem(kind = LabelKind.Play, name = "Peter Pan", cast = List(n) { 100 - it }), size).cols?.bars.orEmpty()
            assertEquals("$n parts at $size", minOf(n, most), bars.size)
            assertEquals("$n parts at $size: the rest column", if (n > most) 1 else 0, bars.count { it.rest })
            assertTrue("$n parts at $size: a column past the page", (bars.lastOrNull()?.let { it.x + it.w } ?: 0.0) <= 91.01)
        }
        assertEquals("SENECA", LabelMath.surnameOf("Lucius Annaeus Seneca Jr."))
        assertEquals("447-386 BCE", LabelMath.lifeOf(LabelLife(-447, -386)))
        assertEquals("board.comedy", LabelSpec.make(LabelItem(kind = LabelKind.Play, name = "X", hue = "comedy"), 128.0).ground)
        assertEquals("brand.surfaceAlt", LabelSpec.make(LabelItem(kind = LabelKind.Play, name = "X"), 128.0).ground)
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

    /** The "+N" never stands on its bars, whatever the parts' sizes, and the bars keep their shares (R4-2c). */
    @Test fun aPlaysPlusNNeverStandsOnItsBars() {
        fun overlap(cast: List<Int>): Boolean {
            val s = LabelSpec.make(LabelItem(kind = LabelKind.entries.first { it.key == "play" }, voices = cast.size, cast = cast), 48.0)
            val t = s.text[0]
            val last = s.cast!!.bars.last()
            val left = t.x - t.size * LabelMath.textWidth(t.s, "body")
            return last.x + last.w + LabelMath.castGap > left + 0.01
        }
        val casts = listOf(List(58) { 8 }, List(120) { 3 }, listOf(40, 38, 36, 30, 28, 27, 26, 25, 1), listOf(9, 9, 9, 9, 9, 9, 9, 1))
        for (cast in casts) {
            assertTrue("+${cast.size - 7} on its bars", !overlap(cast))
            val bars = LabelSpec.make(LabelItem(kind = LabelKind.entries.first { it.key == "play" }, voices = 9, cast = cast), 48.0).cast!!.bars
            bars.forEachIndexed { i, b -> assertTrue("bar $i's share", abs(b.w / bars[0].w - Math.round(100.0 * cast[i] / cast[0]) / 100.0) < 0.01) }
        }
        val fits = LabelSpec.make(LabelItem(kind = LabelKind.entries.first { it.key == "play" }, voices = 3, cast = listOf(30, 20, 10)), 48.0).cast!!.bars
        assertEquals("a cast that fits draws full width", 76.0, fits[0].w, 0.001)
    }

    /** V8: the rim and the head name `series.network`, never the first of the `networks` list. */
    @Test fun theRimNamesThePrimaryNetworkNotTheList() {
        val lux = SeriesRow(key = "lux", name = "Lux", genre = "drama", firstDate = "1935", lastDate = "1955", episodes = 9,
            networks = listOf("NBC Blue", "CBS"), network = "CBS")
        assertEquals("CBS", lux.labelItem().network)
        assertNull(lux.copy(network = null).labelItem().network)
    }
}
