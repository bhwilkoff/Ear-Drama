package com.example.appname.plays

import java.io.File
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Own scripts (R4-1, Decision 088.3) in Kotlin, the port of js/own-core.test.js: every case of the three golden files
 * (catalog/tests/golden/own_script_parse.json, own_script_ops.json, ear_cast_lines.json), each file's control found
 * wrong, no word lost from any golden text, the caps, and the time budget (400 KB in under 100 ms; every hostile shape
 * under two seconds).
 *
 * Seen to fail, 2026-11-24, each mutation of OwnScript.kt run once then restored (a temporary script, not kept): a name
 * printed once counting as a part (`seen >= 1`), mixed names needing four row starts, no established form, no NFC, a
 * label with no words not waiting for them, titles read as whole names, COMMON words as parts, a column gap of four,
 * a lower-case label under a name, a bracket closing mid-row, an exit that does not resume the speech, a bracket joined
 * to a word, `_` dropped inside a word, Undo giving letters back, letters not following the numbered line, the cast
 * check on a part with a take, a cut inside an accent, keys not sorted, a shared script editable, words not lower-cased,
 * abbreviations ending a sentence, a heard line not ending a carry, times rounded up, a cue's last sentence cut one
 * unit late, and a left-out line settled as a part.
 */
class OwnScriptTest {
    private fun root(): File {
        var dir: File? = File("").absoluteFile
        while (dir != null) {
            if (File(dir, "catalog/tests/golden/own_script_parse.json").exists()) return dir
            dir = dir.parentFile
        }
        error("repository root not found")
    }

    private fun golden(name: String): JsonObject =
        Json.parseToJsonElement(File(root(), "catalog/tests/golden/$name").readText()).jsonObject

    private val parseG by lazy { golden("own_script_parse.json") }
    private val opsG by lazy { golden("own_script_ops.json") }
    private val earG by lazy { golden("ear_cast_lines.json") }

    // ---- JSON as plain data ----

    private fun tree(e: JsonElement?): Any? = when (e) {
        null, is JsonNull -> null
        is JsonPrimitive -> if (e.isString) e.content else e.booleanOrNull ?: e.longOrNull ?: e.content
        is JsonArray -> e.map { tree(it) }
        is JsonObject -> e.mapValues { tree(it.value) }
    }

    private fun canon(v: Any?) = OwnScript.canonicalLines(v)
    private fun same(got: Any?, want: JsonElement?, msg: String) = assertEquals(msg, canon(tree(want)), canon(got))

    private val JsonElement?.str: String get() = this!!.jsonPrimitive.content
    private fun JsonObject.opt(k: String): JsonElement? = this[k]?.takeIf { it !is JsonNull }

    private fun lineIn(o: JsonObject) = OwnLine(
        kind = o["kind"].str, role = o.opt("role")?.str, text = o["text"].str, label = o.opt("label")?.str,
        at = o.opt("at")?.jsonArray?.let { it[0].jsonPrimitive.content.toLong() to it[1].jsonPrimitive.content.toLong() },
    )

    private fun opIn(o: JsonObject): OwnOp {
        val name = o["op"].str
        val to = o.opt("to")
        return OwnOp(
            op = name, line = o.opt("line")?.jsonPrimitive?.int, at = o.opt("at")?.jsonPrimitive?.int, text = o.opt("text")?.str ?: "",
            to = when (to) {
                null -> null
                is JsonObject -> OwnTarget.Role(to["role"].str)
                else -> OwnTarget.KindOf(to.str)
            },
            after = o.opt("after")?.jsonPrimitive?.int, kind = o.opt("kind")?.str ?: "", role = o.opt("role")?.str ?: "",
            part = o.opt("part")?.str ?: "", rename = if (name == "rename") to.str else "",
        )
    }

    private fun envIn(o: JsonObject): OwnEnv {
        val e = o.opt("env")?.jsonObject ?: return OwnEnv()
        return OwnEnv(e.opt("takes")?.jsonArray?.map { it.str }?.toSet() ?: emptySet(), e.opt("shared")?.jsonPrimitive?.booleanOrNull ?: false)
    }

    private fun lineOut(l: OwnLine, withKey: Boolean = false): Map<String, Any?> = buildMap {
        if (withKey) { put("k", l.k); put("id", l.id) }
        put("kind", l.kind)
        if (!l.role.isNullOrEmpty()) put("role", l.role)
        put("text", l.text)
        if (!l.label.isNullOrEmpty()) put("label", l.label)
    }

    private fun spanOut(a: Pair<Long, Long>?) = a?.let { listOf(it.first, it.second) }

    // ---- The golden runners ----

    private fun runParseCase(c: JsonObject) {
        val r = OwnScript.parse(c["raw"].str)
        same(
            mapOf("lines" to r.lines.map { lineOut(it) }, "parts" to r.parts.map { mapOf("name" to it.first, "lines" to it.second) }),
            c["want"], "${c["layout"].str}: ${c["name"].str}",
        )
    }

    private fun runParse() {
        for (c in parseG["normalize"]!!.jsonArray) {
            val o = c.jsonObject
            assertEquals("normalize ${o["name"].str}", o["want"].str, OwnScript.normalize(o["raw"].str))
        }
        for (c in parseG["names"]!!.jsonArray) {
            val o = c.jsonObject
            val n = OwnScript.partName(o["raw"].str)
            assertEquals("name ${o["raw"]}", o["name"].str, n)
            assertEquals("name refusal ${o["raw"]}", o.opt("refusal")?.str, OwnScript.partNameRefusal(n))
        }
        for (c in parseG["pieces"]!!.jsonArray) {
            val o = c.jsonObject
            val got = OwnScript.pieces(o["text"].str).map { mapOf((if (it is OwnPiece.Say) "say" else "direction") to it.text) }
            same(got, o["parts"], "pieces of ${o["text"]}")
        }
        for (c in parseG["cases"]!!.jsonArray) runParseCase(c.jsonObject)
    }

    private fun runSequence(c: JsonObject) {
        var doc = OwnScript.newDoc(c["lines"]!!.jsonArray.map { lineIn(it.jsonObject) })
        val refusals = ArrayList<String?>()
        for (st in c["steps"]!!.jsonArray) {
            val s = st.jsonObject
            if (s["op"].str == "done") { doc = OwnScript.done(doc, s.opt("keepOpen")?.jsonPrimitive?.booleanOrNull ?: false); refusals.add(null); continue }
            val r = OwnScript.apply(doc, opIn(s), envIn(s))
            doc = r.doc
            refusals.add(r.refusal)
        }
        same(
            mapOf("refusals" to refusals, "letters" to doc.letters, "undo" to doc.undo.size, "lines" to doc.lines.map { lineOut(it, true) }),
            c["want"], c["name"].str,
        )
    }

    private fun runOps() {
        for (c in opsG["sequences"]!!.jsonArray) runSequence(c.jsonObject)
        for (c in opsG["cut"]!!.jsonArray) {
            val o = c.jsonObject
            assertEquals("cut ${o["text"]} at ${o["at"]}", o["want"]!!.jsonPrimitive.int, OwnScript.cutAt(o["text"].str, o["at"]!!.jsonPrimitive.int))
        }
        for (c in opsG["wordsChanged"]!!.jsonArray) {
            val o = c.jsonObject
            assertEquals("words changed $o", o["want"]!!.jsonPrimitive.booleanOrNull, OwnScript.wordsChanged(o["before"].str, o["after"].str))
        }
        for (c in opsG["nearest"]!!.jsonArray) {
            val o = c.jsonObject
            val lines = o["roles"].str.map { r -> if (r == '.') OwnLine(kind = "open", text = "x") else OwnLine(kind = "speech", role = r.toString(), text = "x") }
            same(OwnScript.nearestParts(lines, o["at"]!!.jsonPrimitive.int), o["want"], "nearest in ${o["roles"]} at ${o["at"]}")
        }
        val w = opsG["letters"]!!.jsonObject
        var doc = OwnScript.done(OwnScript.newDoc(listOf(OwnLine(kind = "speech", role = "A", text = w["text"].str))))
        repeat(w["splits"]!!.jsonPrimitive.int) {
            val t = doc.lines.first { it.k == 1 }.text
            doc = OwnScript.apply(doc, OwnOp("split", line = 1, at = t.lastIndexOf(' ') + 1)).doc
        }
        same(doc.lines.map { it.id }, w["want"], "letters past z")
        for (c in opsG["canonical"]!!.jsonArray) {
            val o = c.jsonObject
            assertEquals("canonical JSON", o["json"].str, OwnScript.canonicalLines(tree(o["lines"])))
            assertEquals("revision", o["revision"].str, OwnScript.revisionOf(tree(o["lines"])))
        }
        for (c in opsG["scripts"]!!.jsonArray) {
            val o = c.jsonObject
            var d = OwnScript.newDoc(OwnScript.parse(o["raw"].str).lines)
            for (st in o["steps"]!!.jsonArray) d = OwnScript.apply(d, opIn(st.jsonObject)).doc
            val want = o["want"]!!.jsonObject
            val s = OwnScript.seal(OwnScript.toScript(OwnScript.done(d), OwnMeta(want["id"].str, o["title"].str)))
            same(s, want, o["name"].str)
            assertEquals("${o["name"].str}: may be kept", o.opt("refusal")?.str, OwnScript.refusalOf(s))
        }
        for (c in opsG["refusals"]!!.jsonArray) {
            val o = c.jsonObject
            assertEquals("refusal: ${o["name"].str}", o.opt("want")?.str, OwnScript.refusalOf(tree(o["script"])))
        }
    }

    private fun castOut(d: OwnDoc): List<Any?> {
        val m = OwnScript.castOf(d)
        return d.lines.map { l -> when (val w = m[l.k]) { OwnWho.Out -> mapOf("out" to true); null -> null; is OwnWho.Role -> mapOf("role" to w.name) } }
    }

    private fun runCast(c: JsonObject) {
        val vtt = earG["vtt"].str
        var d = OwnScript.fromCues(OwnScript.parseCues(vtt))
        val refusals = ArrayList<String?>()
        for (st in c["steps"]!!.jsonArray) {
            val s = st.jsonObject
            var r = OwnResult(d, null)
            if (s["hear"] != null) r = OwnResult(OwnScript.hear(d, s["hear"]!!.jsonPrimitive.int, s["from"]!!.jsonPrimitive.int), null)
            else if (s["tap"] != null) {
                val who = if (s.opt("out")?.jsonPrimitive?.booleanOrNull == true) OwnWho.Out else OwnWho.Role(s["role"].str)
                r = OwnScript.tap(d, s["tap"]!!.jsonPrimitive.int, who, envIn(s))
            } else if (s["leaveOut"] != null) r = OwnScript.leaveOutHeard(d, s["leaveOut"]!!.jsonPrimitive.int, envIn(s))
            else if (s["undo"] != null) r = OwnScript.apply(d, OwnOp("undo"))
            else if (s["done"] != null) r = OwnResult(OwnScript.done(d, s.opt("keepOpen")?.jsonPrimitive?.booleanOrNull ?: false), null)
            else r = OwnScript.apply(d, opIn(s), envIn(s))
            d = r.doc
            refusals.add(r.refusal)
        }
        val settled = OwnScript.settle(d).lines.map { l ->
            buildMap<String, Any?> {
                put("k", l.k); put("kind", l.kind)
                if (!l.role.isNullOrEmpty()) put("role", l.role)
                put("text", l.text); put("at", spanOut(l.at))
            }
        }
        val count = OwnScript.castCount(d)
        same(
            mapOf("refusals" to refusals, "cast" to castOut(d), "count" to mapOf("cast" to count.first, "lines" to count.second), "settled" to settled),
            c["want"], c["name"].str,
        )
    }

    private fun runEar() {
        for (c in earG["cues"]!!.jsonArray) {
            val o = c.jsonObject
            same(OwnScript.parseCues(o["raw"].str).map { mapOf("text" to it.text, "at" to spanOut(it.at)) }, o["want"], "cues: ${o["name"].str}")
        }
        for (c in earG["sentences"]!!.jsonArray) {
            val o = c.jsonObject
            same(OwnScript.fromCues(listOf(OwnCue(o["text"].str, null))).lines.map { it.text }, o["want"], "sentences of ${o["text"]}")
        }
        for (c in earG["times"]!!.jsonArray) {
            val o = c.jsonObject
            val cue = o["cue"]!!.jsonObject
            val at = cue.opt("at")?.jsonArray?.let { it[0].jsonPrimitive.content.toLong() to it[1].jsonPrimitive.content.toLong() }
            same(OwnScript.fromCues(listOf(OwnCue(cue["text"].str, at))).lines.map { mapOf("text" to it.text, "at" to spanOut(it.at)) }, o["want"], "times: ${o["name"].str}")
        }
        val d = OwnScript.fromCues(OwnScript.parseCues(earG["vtt"].str))
        same(d.lines.map { mapOf("k" to it.k, "text" to it.text, "at" to spanOut(it.at)) }, earG["lines"], "the lines of the transcript")
        for (c in earG["lineAt"]!!.jsonArray) {
            val o = c.jsonObject
            assertEquals("the line at ${o["ms"]}", o["want"]!!.jsonPrimitive.int, OwnScript.lineAt(d, o["ms"]!!.jsonPrimitive.content.toLong()))
        }
        for (c in earG["casts"]!!.jsonArray) runCast(c.jsonObject)
        var s = OwnScript.hear(OwnScript.tap(d, 1, OwnWho.Role("Dantro")).doc, 3, 1)
        s = OwnScript.hear(OwnScript.tap(s, 4, OwnWho.Role("Pat")).doc, 6, 4)
        s = OwnScript.done(OwnScript.tap(s, 6, OwnWho.Out).doc, keepOpen = true)
        val script = earG["script"]!!.jsonObject
        val ep = script["episode"]!!.jsonObject
        val id = opsG["scripts"]!!.jsonArray[0].jsonObject["want"]!!.jsonObject["id"].str
        same(OwnScript.seal(OwnScript.toScript(s, OwnMeta(id, "The Visit", ep["id"].str, ep["url"].str))), script["want"], "a half-cast transcript as a script")
    }

    private inline fun fails(block: () -> Unit): Boolean = try { block(); false } catch (e: AssertionError) { true }

    // ---- The goldens ----

    @Test fun `golden own_script_parse every stack`() {
        assertTrue("40 pasted texts", parseG["cases"]!!.jsonArray.size >= 40)
        assertTrue("eight layouts", parseG["cases"]!!.jsonArray.map { it.jsonObject["layout"].str }.toSet().size >= 8)
        runParse()
    }

    @Test fun `golden own_script_ops every stack`() = runOps()

    @Test fun `golden ear_cast_lines every stack`() = runEar()

    @Test fun `each golden file's control is found wrong`() {
        assertTrue("own_script_parse control passed", fails { runParseCase(parseG["control"]!!.jsonObject) })
        assertTrue("own_script_ops control passed", fails { runSequence(opsG["control"]!!.jsonObject) })
        assertTrue("ear_cast_lines control passed", fails { runCast(earG["control"]!!.jsonObject) })
    }

    // ---- Nothing is lost, nothing is written ----

    private fun bare(s: String): String {
        val b = StringBuilder()
        var i = 0
        while (i < s.length) {
            val cp = s.codePointAt(i)
            if (Character.isLetterOrDigit(cp) || Character.getType(cp).toByte().let {
                    it == Character.NON_SPACING_MARK || it == Character.COMBINING_SPACING_MARK || it == Character.ENCLOSING_MARK
                }
            ) b.appendCodePoint(cp)
            i += Character.charCount(cp)
        }
        return b.toString()
    }

    @Test fun `every letter and digit of every golden text is in its lines, in order, and no other`() {
        for (c in parseG["cases"]!!.jsonArray) {
            val o = c.jsonObject
            val r = OwnScript.parse(o["raw"].str)
            assertEquals("${o["layout"].str}: ${o["name"].str}", bare(r.text), bare(r.lines.joinToString("") { (it.label ?: "") + it.text }))
        }
    }

    @Test fun `every row of a line is a slice of the normalized text`() {
        for (c in parseG["cases"]!!.jsonArray) {
            val r = OwnScript.parse(c.jsonObject["raw"].str)
            for (l in r.lines) for (row in l.text.split('\n').drop(1)) assertTrue(row, r.text.contains(row))
        }
    }

    @Test fun `a lone surrogate is U+FFFD and nothing throws on it`() {
        assertEquals("a\ufffdb\ufffdc\ud83d\ude00", OwnScript.normalize("a\ud800b\udc00c\ud83d\ude00"))
        assertEquals(2, OwnScript.parse("A\ud800: x\nB: y\nA\ud800: z\nB: w").parts.size)
        assertEquals(1, OwnScript.cutAt("x\ud800y", 1))
    }

    @Test fun `pieces and textOf are inverse over 20000 made-up texts`() {
        val al = listOf("a", "B", " ", "(", ")", "[", "]", ".", "\n", "\u00e9")
        val rnd = java.util.Random(7)
        repeat(20000) {
            var s = ""
            repeat(1 + rnd.nextInt(14)) { s += al[rnd.nextInt(al.size)] }
            s = OwnScript.trim(s)
            if (s.isNotEmpty()) {
                val p = OwnScript.pieces(s)
                assertEquals(s, p, OwnScript.pieces(OwnScript.textOf(p)))
            }
        }
    }

    @Test fun `a kept doc and a copy of a script go on where they were`() {
        var d = OwnScript.done(OwnScript.newDoc(OwnScript.parse("ANNA: One two.\nBEN: Three.\nANNA: Four.\nBEN: Five.").lines))
        d = OwnScript.apply(d, OwnOp("split", line = 1, at = 4)).doc
        val again = OwnScript.kept(d)
        assertNull(OwnScript.apply(again, OwnOp("split", line = 2, at = 1)).refusal)
        assertEquals("nothing_to_undo", OwnScript.apply(again, OwnOp("undo")).refusal)
        assertEquals("L0001b", OwnScript.apply(again, OwnOp("add", after = 1, kind = "sound", text = "x")).doc.lines[1].id)
        val id = "own-3f2b8c1e-5a7d-4e90-8b21-0c9d7e6f5a43"
        val s = OwnScript.toScript(d, OwnMeta(id, "T"))
        val copy = OwnScript.fromScript(s)
        assertEquals("L0001b", OwnScript.apply(copy, OwnOp("add", after = 1, kind = "sound", text = "x")).doc.lines[1].id)
        assertEquals(canon(s), canon(OwnScript.toScript(copy, OwnMeta(id, "T"))))
    }

    // ---- Caps ----

    @Test fun `too much is refused text lines canonical bytes`() {
        val max = OwnScript.MAX_BYTES
        assertNull(OwnScript.textRefusal("a".repeat(max)))
        assertEquals("too_long", OwnScript.textRefusal("a".repeat(max + 1)))
        assertEquals("too_long", OwnScript.textRefusal("\u00e9".repeat(200001)))
        assertNull(OwnScript.textRefusal("\u4e2d".repeat(133333)))
        assertEquals("empty", OwnScript.textRefusal(" \ufeff\n\t"))
        assertEquals("a\u00e9\u4e2d\ud83d\ude00".toByteArray(Charsets.UTF_8).size, OwnScript.utf8Length("a\u00e9\u4e2d\ud83d\ude00"))
        val id = "own-3f2b8c1e-5a7d-4e90-8b21-0c9d7e6f5a43"
        fun of(n: Int, text: String) = OwnScript.toScript(OwnScript.done(OwnScript.newDoc(List(n) { OwnLine(kind = "speech", role = "A", text = text) })), OwnMeta(id, "T"))
        assertEquals("too_many_lines", OwnScript.refusalOf(of(6001, "x")))
        assertNull(OwnScript.refusalOf(of(1, "x".repeat(399900))))
        assertEquals("too_long", OwnScript.refusalOf(of(1, "x".repeat(400000))))
        val full = OwnScript.newDoc(List(6000) { OwnLine(kind = "speech", role = "A", text = "x y") })
        assertEquals("too_many_lines", OwnScript.apply(full, OwnOp("split", line = 1, at = 1)).refusal)
        assertEquals("too_many_lines", OwnScript.apply(full, OwnOp("add", after = 1, kind = "sound", text = "x")).refusal)
        assertEquals(6000, OwnScript.MAX_LINES)
        assertEquals(40, OwnScript.MAX_PART_NAME)
        assertEquals(300, OwnScript.MAX_TITLE)
        val most = OwnScript.toScript(OwnScript.done(OwnScript.newDoc(List(6000) { OwnLine(kind = "speech", role = "A".repeat(40), text = "w$it") })), OwnMeta(id, "T"))
        assertEquals("L6000", ((most["lines"] as List<*>)[5999] as Map<*, *>)["id"])
        assertEquals("too_long", OwnScript.refusalOf(most))
    }

    // ---- Time ----

    private fun fill(unit: String, n: Int = OwnScript.MAX_BYTES): String = unit.repeat((n + unit.length - 1) / unit.length).substring(0, n)
    private inline fun took(block: () -> Unit): Double { val t = System.nanoTime(); block(); return (System.nanoTime() - t) / 1e6 }

    @Test fun `400 KB of script is read in under 100 ms`() {
        val text = fill("ANNA: The lamp has gone out again, and there is no oil (she looks for it).\n\nBEN. We could light the candle\nfrom the stove.\n\nIt would be a small light, but a light.\n\nANNA\nSo be it.\n\n")
        repeat(3) { OwnScript.parse(text) }
        val best = (1..7).minOf { took { OwnScript.parse(text) } }
        assertTrue("$best ms", best < 100)
    }

    @Test fun `no text makes it slow 400 KB of each hostile shape each under two seconds`() {
        val shapes = listOf(
            "(", "[", "(a\n", "(a\n\n", "[a\n", "([", "((a", "A${" ".repeat(5000)}x", "A ", "A. ", "A:", "A: ", ":", ".", "_", "*", "**a", "-",
            "A (b [c ", "MR. ", "ABCDE FGHI\n", "A\t", "A   b\n", "@A:\n", "\r", "\ud800", "e\u0301\u0301", "\ud83d\udc69\u200d", "Aaa. Bbb\n",
            "Exit\n", "SOUND ", "ACT ", "END OF ", "A(", "A,(", "A.(", "A.B.",
        )
        for (s in shapes) {
            val text = fill(s)
            val ms = took { OwnScript.parse(text); OwnScript.pieces(text); OwnScript.cutAt(text, 200000); OwnScript.wordsChanged(text, text) }
            assertTrue("${s.take(12)}: $ms ms", ms < 2000)
        }
        for (s in listOf("<", "-->\n", "<a", "&amp;", "00:01.000 --> 00:02.000\nHi. There.\n\n", "Mr. A. B? \"C\" ", "1:")) {
            val ms = took { OwnScript.fromCues(OwnScript.parseCues(fill(s))) }
            assertTrue("cues ${s.take(12)}: $ms ms", ms < 2000)
        }
    }
}
