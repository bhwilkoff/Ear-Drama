package com.example.appname.plays

import java.io.File
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * A scene's production (PLAYS-DESIGN §2.12), held to catalog/tests/golden/production_range.json, the file
 * js/plays.test.js and apple/Tests/ProductionRangeTests.swift read: the cast, Done, Listen Through and the mix
 * hold only the range, a cue outside it is out of the mix, a moved bound drops the range, and an old record is
 * read as it is. Each mutant of the core below must break [answers], as the JS test's mutants do.
 */
class ProductionRangeTest {
    private val golden = Json.parseToJsonElement(File("../../catalog/tests/golden/production_range.json").readText()).jsonObject
    private val lenient = Json { ignoreUnknownKeys = true }
    private val script = lenient.decodeFromJsonElement(PlayScript.serializer(), golden.getValue("script"))
    private val range = lenient.decodeFromJsonElement(ProductionRange.serializer(), golden.getValue("range"))
    private val heading = golden.getValue("heading").jsonPrimitive.content
    private val expect = golden.getValue("expect").jsonObject
    private val done = golden.getValue("done").jsonObject
    private val sound = ProductionStore.json.decodeFromJsonElement(SoundBlock.serializer(), golden.getValue("sound"))

    private fun strings(a: JsonArray) = a.map { it.jsonPrimitive.content }
    private fun pairs(a: JsonArray) = a.map { it.jsonArray[0].jsonPrimitive.content to it.jsonArray[1].jsonPrimitive.int }
    private fun cast(s: PlayScript) = s.castParts.map { it.id.raw to it.lineCount }

    /** The seams the golden exercises, so a mutant can replace one. */
    private data class Core(
        val scoped: (Production, PlayScript) -> PlayScript = { p, s -> p.scoped(s) },
        val castParts: (PlayScript, ProductionRange?) -> List<CastPart> = { s, r -> s.castParts(r) },
        val isComplete: (Production, PlayScript) -> Boolean = { p, s -> Relay.isComplete(p, s) },
        val timeline: (PlayScript, Production) -> MixTimeline = { s, p -> MixTimeline.build(s, p) },
        val drifted: (Production, PlayScript) -> Boolean = { p, s -> p.rangeDrifted(s) },
        val create: (PlayScript, ProductionRange, String) -> Production = { s, r, h -> Production.create(s, "golden", r, h) },
        val migrate: (Production) -> Production = { it.migrated() },
        val dropRange: (Production, PlayScript) -> Production = { p, s -> p.dropRange(s) },
    )

    private fun rangeProduction(core: Core, chosen: Map<String, String>, withSound: Boolean = false): Production {
        val takes = golden.getValue("takes").jsonArray.map { it.jsonObject }.map { t ->
            take(
                t.getValue("id").jsonPrimitive.content, t.getValue("lineID").jsonPrimitive.content,
                PartID(t.getValue("part").jsonPrimitive.content), t.getValue("frames").jsonPrimitive.int,
                t.getValue("loudness").jsonPrimitive.content.toDouble(), t.getValue("peak").jsonPrimitive.content.toFloat(),
            ).copy(cue = t["cue"]?.jsonPrimitive?.content)
        }
        return core.create(script, range, heading).copy(takes = takes, chosen = chosen, sound = if (withSound) sound else null)
    }

    private fun chosenOf(d: JsonObject) = d.getValue("chosen").jsonObject.mapValues { it.value.jsonPrimitive.content }

    /** What failed; empty when every expectation of the golden holds for [core]. */
    private fun answers(core: Core): List<String> {
        val bad = ArrayList<String>()
        fun want(got: Any?, exp: Any?, name: String) { if (got != exp) bad += "$name: got $got, want $exp" }
        val p0 = core.create(script, range, heading)
        want(p0.title, expect.getValue("title").jsonPrimitive.content, "title")
        want(p0.format, expect.getValue("format").jsonPrimitive.int, "format")
        want(p0.range, range, "range stored")
        want(p0.parts.keys.map { it.raw }.sorted(), strings(expect.getValue("parts").jsonArray).sorted(), "parts of the range only")
        val s = core.scoped(p0, script)
        want(s.lines.map { it.id }, strings(expect.getValue("lineIDs").jsonArray), "line ids")
        val wantCast = pairs(expect.getValue("cast").jsonArray)
        want(core.castParts(script, range).map { it.id.raw to it.lineCount }, wantCast, "castParts(script, range)")
        want(cast(s), wantCast, "cast of the scoped script")
        want(cast(script), pairs(expect.getValue("wholeCast").jsonArray), "whole cast unchanged")
        want(s.voices to s.minutes, expect.getValue("voices").jsonPrimitive.int to expect.getValue("minutes").jsonPrimitive.int, "voices and minutes are the range's")
        want(Relay.listenPlan(p0, script).map { it.lineID }, strings(expect.getValue("listenBeforeAnyTake").jsonArray), "listen before any take")
        for (k in listOf("before", "after")) {
            val d = done.getValue(k).jsonObject
            val p = rangeProduction(core, chosenOf(d))
            want(core.isComplete(p, script), d.getValue("complete").jsonPrimitive.content.toBoolean(), "$k: Done")
            want(Relay.missingSpeech(p, script), strings(d.getValue("missing").jsonArray), "$k: missing")
            for ((part, lines) in d.getValue("partMissing").jsonObject) {
                want(Relay.missingLines(PartID(part), p, script), strings(lines.jsonArray), "$k: $part missing")
            }
            d["wholeMissing"]?.let { want(Relay.missingSpeech(p.copy(range = null), script), strings(it.jsonArray), "$k: the whole play is not done") }
        }
        val finished = rangeProduction(core, chosenOf(done.getValue("after").jsonObject), withSound = true)
        want(
            Relay.listenPlan(finished, script).map { it.lineID to if (it is Relay.ListenEntry.TakeEntry) "take" else "voice" },
            golden.getValue("listenAfter").jsonArray.map { it.jsonArray[0].jsonPrimitive.content to it.jsonArray[1].jsonPrimitive.content },
            "listen through after",
        )
        val export = golden.getValue("export").jsonObject
        try {
            val t = core.timeline(script, finished)
            want(t.placements.map { it.lineID }, strings(export.getValue("voice").jsonArray), "export voice lines")
            want(t.sounds.map { it.soundID }, strings(export.getValue("sounds").jsonArray), "export sounds")
            want(t.sounds.map { it.slotID }, listOf("S1"), "export sound slots")
        } catch (e: Exception) {
            bad += "export threw ${e::class.simpleName}"
        }
        var rec = Relay.take(PartID("role:DEMEA"), "", rangeProduction(core, chosenOf(done.getValue("after").jsonObject)), script)
        try {
            rec = Relay.finish(PartID("role:DEMEA"), rec, script)
            want(rec.state(PartID("role:DEMEA")).status, PartState.Status.Done, "finish in range")
        } catch (e: Relay.Refusal) {
            bad += "finish threw $e"
        }
        try {
            Relay.take(PartID("role:SYRUS"), "", p0, script)
            bad += "a part outside the range was taken"
        } catch (e: Relay.Refusal.NotOpen) {
            // the part is not on the range's cast sheet
        }
        for (c in golden.getValue("drift").jsonArray.map { it.jsonObject }) {
            val removed = c["remove"]?.jsonArray?.let(::strings).orEmpty()
            val revised = script.copy(revision = "r2", lines = script.lines.filter { it.id !in removed })
            val r = c["range"]?.let { lenient.decodeFromJsonElement(ProductionRange.serializer(), it) } ?: range
            want(core.drifted(p0.copy(range = r), revised), c.getValue("drifted").jsonPrimitive.content.toBoolean(), c.getValue("name").jsonPrimitive.content)
        }
        val dropped = core.dropRange(p0.copy(listenedThrough = true, mixedFrom = "x"), script)
        val gd = golden.getValue("dropped").jsonObject
        want(
            listOf(dropped.title, dropped.range, dropped.listenedThrough, dropped.parts.keys.map { it.raw }.sorted()),
            listOf(gd.getValue("title").jsonPrimitive.content, null, false, strings(gd.getValue("parts").jsonArray).sorted()),
            "dropped range",
        )
        val old = golden.getValue("old").jsonObject
        val oldRecord = ProductionStore.json.decodeFromJsonElement(Production.serializer(), old.getValue("record"))
        val migrated = core.migrate(oldRecord)
        val fingerprint = old.getValue("fingerprint").jsonPrimitive.content
        want(
            listOf(oldRecord.chosenFingerprint, migrated.chosenFingerprint, migrated.format, migrated.isFinished),
            listOf(fingerprint, fingerprint, 2, true), "old record migrated, fingerprint unchanged",
        )
        want(cast(migrated.scoped(script)), pairs(old.getValue("cast").jsonArray), "an old production is the whole play")
        want(Relay.listenPlan(migrated, script).size, script.lines.count { it.kind == ScriptLine.Kind.Speech }, "an old production listens through the whole play")
        want(oldRecord.copy(format = golden.getValue("tooNew").jsonObject.getValue("format").jsonPrimitive.intOrNull).tooNew, true, "a newer format is refused")
        want(migrated.tooNew, false, "control: the current format is read")
        return bad
    }

    @Test fun `the golden every platform runs holds for the core`() {
        val bad = answers(Core())
        assertTrue(bad.joinToString("\n"), bad.isEmpty())
    }

    @Test fun `each mutant of the core breaks the golden`() {
        val mutants = mapOf(
            "scoped ignores the range" to Core(scoped = { _, s -> s }, castParts = { s, _ -> s.castParts }),
            "the mix keeps cues outside the range" to Core(timeline = { s, p -> MixTimeline.build(s, p.copy(range = null)) }),
            "Done reads the whole play" to Core(isComplete = { p, s -> Relay.isComplete(p.copy(range = null), s) }),
            "a range is not dropped on drift" to Core(drifted = { _, _ -> false }),
            "migration rewrites the takes" to Core(migrate = { it.migrated().copy(chosen = emptyMap()) }),
            "title without the heading" to Core(create = { s, r, h -> Production.create(s, "golden", r, h).copy(title = s.title) }),
            "a drop that keeps the range" to Core(dropRange = { p, s -> p.dropRange(s).copy(range = p.range) }),
        )
        for ((name, core) in mutants) assertTrue("mutant caught: $name", answers(core).isNotEmpty())
    }

    @Test fun `a record keeps its range only when set and a newer record is not listed`() {
        val whole = ProductionStore.encodeRecord(Production.create(script, "W"))
        assertTrue("no range key on a whole play", !whole.contains("\"range\""))
        assertTrue("format 2 on a new production", whole.contains("\"format\":2"))
        val one = ProductionStore.encodeRecord(Production.create(script, "R", range, heading))
        assertEquals(range, ProductionStore.json.decodeFromString(Production.serializer(), one).range)
    }
}
