package com.example.appname.plays

import java.io.File
import java.security.MessageDigest
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * The Sound part without a view (B32 §3, §5; the case-for-case mirror of js/sound.test.js): Sound on every cast sheet counted by
 * its cue rows, slots and the edits a board makes, a performed cue that is never a line's chosen take, the manifest's rights gate
 * with planted rows that must be refused, the pack as a source that may be absent, own sounds on this device only and carried
 * whole by Export my data, and a sound this device lacks refusing the mix by name.
 *
 * Broken controls, 2026-11-26, each seen to fail one test: castParts without Sound (the first test); CC-BY-4.0 added to the
 * manifest gate (the planted-row test); [SoundCore.withoutOwn] keeping an own source (the own-sounds test); a performed take
 * counted among its line's takes (the performed-cue test).
 */
class SoundCoreTest {
    @get:Rule val tmp = TemporaryFolder()

    private fun say(id: String, role: String, vararg parts: LinePart) = ScriptLine(id, ScriptLine.Kind.Speech, role, parts.toList())
    private fun s(text: String) = LinePart.Say(text)

    /** Caesar Rodney's shape: cues inside speeches, no sound line; one direction. */
    private fun radio() = PlayScript(
        id = "fixture-radio", revision = "1", kind = "radio", title = "A ride in the rain",
        source = PlayScript.Source("x", "https://example.org"), rights = PlayScript.Rights("castable"),
        roles = listOf(PlayScript.Role("URIAH", 3, 20), PlayScript.Role("RODNEY", 3, 20)),
        lines = listOf(
            say("L0001", "URIAH", s("We got to make it, rain or no rain.")),
            say("L0002", "RODNEY", s("It's sprinkling.")),
            say("L0003", "URIAH", s("I felt it."), LinePart.Sound("another peal of thunder closer")),
            say("L0004", "RODNEY", LinePart.Direction("Sound of rain and wind"), s("I guess it is on us.")),
            say("L0005", "URIAH", s("Here, draw up your horse!"), LinePart.Direction("absently"), s("Whoa, boy!")),
            ScriptLine("L0006", ScriptLine.Kind.Direction, source = "They ride off."),
            say("L0007", "RODNEY", s("Giddap!")),
        ),
    )

    private fun quiet() = radio().copy(id = "fixture-quiet", lines = listOf(say("L0001", "A", s("Hello.")), say("L0002", "B", s("Hello yourself."))))

    private fun take(id: String, lineID: String, seconds: Double = 1.0, part: PartID = PartID.role("URIAH")) = Take(
        id = id, lineID = lineID, part = part, file = "$id.wav", created = 1.0, frames = (seconds * 48000).toInt(), sampleRate = 48000.0,
        capture = Take.Capture.Direct, heard = emptyMap(), peak = 0.5f, bleed = false,
    )

    private fun fresh(script: PlayScript = radio()) = Production.create(script, "P1")

    private val thunder = SoundSource(pack = "eardrama-sounds-1", cue = "thunder-close")

    // ---- Parts ----

    @Test fun `every script has a Sound part counted by its cue rows, then Stage directions`() {
        val parts = radio().castParts
        assertEquals(listOf("role:URIAH", "role:RODNEY", "sound", "directions"), parts.map { it.id.raw })
        assertEquals("Sound", PartID.SOUND.title)
        assertEquals("Stage directions", PartID.DIRECTIONS.title)
        assertEquals(listOf(3, 3, 2, 1), parts.map { it.lineCount })
        assertEquals("the cue pieces by the reader's rule", 2, parts.first { it.id == PartID.SOUND }.lineCount)
        assertEquals(listOf("role:A", "role:B", "sound"), quiet().castParts.map { it.id.raw })
        assertEquals("a script with no cue rows says Add sounds", "Add sounds", SoundCore.cuesText(0))
        assertEquals("1 cue", SoundCore.cuesText(1))
        assertEquals("1,234 cues", SoundCore.cuesText(1234))
    }

    @Test fun `stage directions never block, and say what is recorded and that the rest is silent`() {
        val p = fresh().copy(takes = listOf(take("T1", "L0006", part = PartID.DIRECTIONS)), chosen = mapOf("L0006" to "T1"))
        assertEquals("1 of 1 recorded", SoundCore.directionsLine(radio(), p))
        val none = fresh()
        assertEquals("0 of 1 recorded · the rest silent", SoundCore.directionsLine(radio(), none))
        assertTrue("an unread direction is not a missing speech", Relay.missingSpeech(none, radio()).none { it == "L0006" })
    }

    // ---- Slots and the board's edits ----

    @Test fun `slots are the cue rows plus added lines in script order, and a slot is never filled for the person`() {
        val script = radio()
        val slots = SoundCore.slotsOf(script, fresh())
        assertEquals(listOf("L0003" to 1, "L0004" to 0), slots.map { it.line to it.piece })
        assertTrue("every slot opens empty and not silent", slots.all { it.sounds.isEmpty() && !it.silent && it.id == null })
        val (added, id) = SoundCore.addSlot(fresh(), "L0002")
        val after = SoundCore.slotsOf(script, added)
        assertEquals(listOf("L0002", "L0003", "L0004"), after.map { it.line })
        assertTrue(after.first().added && after.first().id == id)
        assertEquals("one added slot per line", id, SoundCore.addSlot(added, "L0002").second)
        assertEquals("an added slot left empty is dropped", null, SoundCore.prune(added).sound)
        assertNotNull("but kept while it is open", SoundCore.prune(added, keep = id).sound)
        assertEquals(listOf("sound of rain and wind"), listOf(slots[1].text.lowercase()))
    }

    @Test fun `a sound added to a slot takes the placement the cue implies`() {
        val script = radio()
        var p = fresh()
        val slots = SoundCore.slotsOf(script, p)
        val (p1, id) = SoundCore.ensure(p, slots[0])
        p = p1
        val d = SoundCore.defaultPlacement(script, SoundCore.recordSlots(p).first())
        assertEquals("a cue printed after every said word plays After", "after", d.at)
        val (p2, soundId) = SoundCore.addSound(p, script, id, thunder)
        assertNotNull(soundId)
        assertEquals("after", SoundCore.recordSlots(p2).first().sounds.single().at)
        // Rain printed ahead of every said word is Before; a cue between said words is Under with its share of them.
        val (p3, id4) = SoundCore.ensure(fresh(), slots[1])
        assertEquals("before", SoundCore.defaultPlacement(script, SoundCore.recordSlots(p3).first { it.id == id4 }).at)
        val mid = script.lines[4]
        val midSlot = SoundSlot("m", mid.id, 1)
        val under = SoundCore.defaultPlacement(script, midSlot)
        assertEquals("under", under.at)
        assertEquals("five of the seven said words come before it", 5.0 / 7, under.share, 1e-9)
        val music = SoundCore.addSound(p1, script, id, SoundSource(pack = "eardrama-sounds-1", cue = "calm-prelude"), kind = "music").first
        val bed = SoundCore.recordSlots(music).first().sounds.single()
        assertEquals("a music cue after the words is a bed", "bed", bed.at)
        assertTrue(bed.loop && bed.until == "L0003" && bed.fadeInMs == 1500.0 && bed.fadeOutMs == 2000.0)
        assertFalse("every edit makes the mix stale", p2.listenedThrough)
    }

    @Test fun `the board's settings are held to what it offers`() {
        val script = radio()
        val (p0, id) = SoundCore.ensure(fresh(), SoundCore.slotsOf(script, fresh())[0])
        val (p1, sid) = SoundCore.addSound(p0, script, id, thunder)
        fun one(p: Production) = SoundCore.recordSlots(p).first().sounds.single()
        var p = SoundCore.updateSound(p1, id, sid!!, SoundCore.Patch(startMs = -5000.0, gainDb = 20.0, fadeInMs = 640.0, fadeOutMs = 1400.0))
        assertEquals("start never below -2 s", -2000.0, one(p).startMs, 0.0)
        assertEquals("level never above +6 dB", 6.0, one(p).gainDb, 0.0)
        assertEquals("fades are the board's choices", 500.0, one(p).fadeInMs, 0.0)
        assertEquals(1000.0, one(p).fadeOutMs, 0.0)
        p = SoundCore.updateSound(p, id, sid, SoundCore.Patch(startMs = 340.0))
        assertEquals("start in 0.1 s steps", 300.0, one(p).startMs, 0.0)
        p = SoundCore.updateSound(p, id, sid, SoundCore.Patch(at = "bed"))
        assertTrue(one(p).at == "bed" && one(p).loop && one(p).until == "L0003")
        p = SoundCore.updateSound(p, id, sid, SoundCore.Patch(at = "before"))
        assertTrue("leaving a bed drops its Until, loop and fades", one(p).until == null && !one(p).loop && one(p).fadeInMs == 0.0)
        p = SoundCore.updateSound(p, id, sid, SoundCore.Patch(duck = SoundCore.Duck.Depth(0.0)))
        assertEquals("Off", 0.0, one(p).duckDb!!, 0.0)
        p = SoundCore.updateSound(p, id, sid, SoundCore.Patch(duck = SoundCore.Duck.Lane))
        assertNull("the lane's own", one(p).duckDb)
        assertEquals("a slot holding a sound is never silent", false, SoundCore.recordSlots(SoundCore.setSilent(p, id, true)).first().silent)
        val empty = SoundCore.removeSound(p, id, sid)
        assertTrue(SoundCore.recordSlots(empty).first().sounds.isEmpty())
        assertTrue("Leave silent marks an empty slot done", SoundCore.recordSlots(SoundCore.setSilent(empty, id, true)).first().silent)
    }

    // ---- A performed cue is a take like any line ----

    @Test fun `a performed cue is a take on its slot, never a lines chosen take`() {
        val script = radio()
        var p = fresh().copy(takes = listOf(take("T3", "L0003")), chosen = mapOf("L0003" to "T3"))
        val (p1, id) = SoundCore.ensure(p, SoundCore.slotsOf(script, p)[0])
        p = SoundCore.addPerformed(p1, script, id, take("K1", "L0003", 0.5))
        assertEquals("the line's chosen take stays", "T3", p.chosen["L0003"])
        assertEquals("the actor's take list never holds it", listOf("T3"), p.takes("L0003").map { it.id })
        val kept = p.takes.first { it.id == "K1" }
        assertEquals(id, kept.cue)
        assertEquals(PartID.SOUND, kept.part)
        assertEquals("the slot plays it", "K1", SoundCore.recordSlots(p).first().sounds.single().src.take)
        assertTrue("Delete unused keeps it", p.unusedTakes.none { it.id == "K1" })
        val timeline = MixTimeline.build(
            script.copy(lines = script.lines.map { it }),
            p.copy(takes = p.takes + script.speechLineIDs.filter { it != "L0003" }.map { take("V$it", it) }, chosen = p.chosen + script.speechLineIDs.filter { it != "L0003" }.associateWith { "V$it" }),
        )
        assertEquals("the mix places the performed take", listOf("K1"), timeline.sounds.map { it.src.take })
    }

    // ---- The pack: a source that may be absent, and its rights gate ----

    private fun row(id: String, mutate: (MutableMap<String, JsonElement>) -> Unit = {}): JsonObject {
        val m = mutableMapOf<String, JsonElement>(
            "id" to JsonPrimitive(id), "title" to JsonPrimitive("Thunder, close"), "category" to JsonPrimitive("weather"),
            "tags" to buildJsonArray { add(JsonPrimitive("thunder")); add(JsonPrimitive("storm")) },
            "kind" to JsonPrimitive("effect"), "ms" to JsonPrimitive(6120), "loop" to JsonPrimitive(false),
            "file" to JsonPrimitive("weather/$id.m4a"), "bytes" to JsonPrimitive(49210), "sha256" to JsonPrimitive("a".repeat(64)),
            "source" to buildJsonObject { put("name", "OpenGameArt"); put("page", "https://opengameart.org/content/x") },
            "license" to buildJsonObject { put("id", "CC0-1.0"); put("evidence", "https://opengameart.org/content/x"); put("checked", "2026-11-26") },
        )
        mutate(m)
        return JsonObject(m)
    }

    private fun lic(m: MutableMap<String, JsonElement>, vararg kv: Pair<String, String?>) {
        val old = (m["license"] as JsonObject).toMutableMap()
        for ((k, v) in kv) if (v == null) old.remove(k) else old[k] = JsonPrimitive(v)
        m["license"] = JsonObject(old)
    }

    private fun manifest(vararg rows: JsonObject): JsonElement = buildJsonObject {
        put("format", 1); put("pack", "eardrama-sounds-1"); put("built", "2026-11-26")
        put("categories", buildJsonArray { add(buildJsonObject { put("id", "weather"); put("title", "Weather"); put("bytes", 1340211) }) })
        put("cues", buildJsonArray { rows.forEach { add(it) } })
    }

    @Test fun `the manifest reader keeps only rows with a license in the gate, evidence and a checked date`() {
        val good = row("thunder-close")
        val planted = listOf(
            row("by-license") { lic(it, "id" to "CC-BY-4.0") },
            row("no-evidence") { lic(it, "evidence" to null) },
            row("no-date") { lic(it, "checked" to null) },
            row("freesound") { it["source"] = buildJsonObject { put("name", "Freesound"); put("page", "https://freesound.org/s/1") } },
            row("no-sha") { it["sha256"] = JsonPrimitive("nope") },
            row("no-ms") { it["ms"] = JsonPrimitive(0) },
            row("outside") { it["file"] = JsonPrimitive("../escape.m4a") },
            row("no-cat") { it["category"] = JsonPrimitive("nothing") },
        )
        val pack = SoundCore.readManifest(manifest(good, *planted.toTypedArray(), row("thunder-close")))
        assertEquals(listOf("thunder-close"), pack.cues.map { it.id })
        assertEquals("each refusal is named", planted.size + 1, pack.refused.size)
        assertEquals(listOf("by-license", "no-evidence", "no-date", "freesound", "no-sha", "no-ms", "outside", "no-cat", "thunder-close"), pack.refused.map { it.id })
        assertTrue(pack.refused.first().why.contains("CC-BY-4.0"))
        assertEquals("a pdm row is listed", 1, SoundCore.readManifest(manifest(row("waltz") { lic(it, "id" to "PDM-1.0") })).cues.size)
        try {
            SoundCore.readManifest(buildJsonObject { put("format", 2); put("pack", "x") })
            fail("a format this client does not read is refused")
        } catch (_: IllegalArgumentException) {
        }
    }

    @Test fun `search is by title and tags, seeded from the cue's own words`() {
        val pack = SoundCore.readManifest(manifest(row("thunder-close"), row("knock") { it["title"] = JsonPrimitive("Knock, wood"); it["tags"] = buildJsonArray { add(JsonPrimitive("knock")); add(JsonPrimitive("door")) } }))
        assertEquals("thunder", SoundCore.seedQuery("another peal of thunder closer", pack.cues))
        assertEquals("knock", SoundCore.seedQuery("Three knocks at the door", pack.cues))
        assertEquals("", SoundCore.seedQuery("hoofbeats on a bridge", pack.cues))
        assertEquals(listOf("knock"), SoundCore.search(pack.cues, "doo").map { it.id })
        assertEquals(listOf("thunder-close"), SoundCore.search(pack.cues, "storm", "weather").map { it.id })
        assertTrue(SoundCore.search(pack.cues, "zeppelin").isEmpty())
        assertEquals("0:06 · OpenGameArt · CC0", SoundCore.cueLine(pack.cues.first()))
    }

    @Test fun `no pack configured is absent and nothing is fetched, configured but unreachable says so`() = runBlocking {
        var asked = 0
        val none = SoundPack(tmp.newFolder("a"), { asked++; null }, manifestUrl = null)
        assertEquals(SoundPack.State.Absent, none.manifest())
        assertEquals("no pack means no request", 0, asked)
        val down = SoundPack(tmp.newFolder("b"), { throw java.io.IOException("offline") }, manifestUrl = "https://example.org/sounds/sounds.json")
        assertEquals(SoundPack.State.Unreachable, down.manifest())
    }

    @Test fun `a category downloads on the press, each file checked against its sha256, a bad file twice fails`() = runBlocking {
        val bytes = "pretend m4a".toByteArray()
        val sha = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
        val json = Json.encodeToString(JsonElement.serializer(), manifest(row("thunder-close") { it["sha256"] = JsonPrimitive(sha) }))
        var corrupt = false
        val fetch = SoundFetch { url -> if (url.endsWith("sounds.json")) json.toByteArray() else if (corrupt) "bad".toByteArray() else bytes }
        val pack = SoundPack(tmp.newFolder("c"), fetch, manifestUrl = "https://example.org/sounds/sounds.json")
        val ready = (pack.manifest() as SoundPack.State.Ready).pack
        assertFalse(pack.categoryHere(ready, "weather"))
        pack.download(ready, "weather")
        assertTrue(pack.categoryHere(ready, "weather"))
        assertEquals("pretend m4a", pack.file(ready, ready.cues.first()).readText())
        File(pack.file(ready, ready.cues.first()).path).writeText("tampered")
        assertFalse("a file that is not the one the manifest names is not here", pack.has(ready, ready.cues.first()))
        corrupt = true
        try {
            pack.download(ready, "weather")
            fail("a bad file twice fails the category")
        } catch (_: java.io.IOException) {
        }
        assertFalse("and is deleted", pack.file(ready, ready.cues.first()).exists())
    }

    // ---- Own sounds: this device only ----

    @Test fun `own sounds are kept on this device, listed, removed and exported whole, never published`() {
        val own = OwnSounds(tmp.newFolder("mine"))
        val tone = FloatArray(4800) { (0.3 * Math.sin(it * 0.1)).toFloat() }
        val a = own.add("Owl at night", tone, "recorded", nowMs = 1_000)
        val b = own.add("", tone, "file", nowMs = 2_000)
        assertEquals(listOf(b.id, a.id), own.list().map { it.id })
        assertTrue(b.name.startsWith("Sound of "))
        assertEquals(0.1, a.seconds, 1e-9)
        assertEquals(tone.size, own.load(a.id)!!.size)
        val rows = own.exportRows()
        assertEquals(2, rows.size)
        assertTrue("each sound whole: its audio travels with the row", rows.all { (it["wav"] as JsonPrimitive).content.length > 100 })
        assertEquals("Owl at night", (rows.first { (it["id"] as JsonPrimitive).content == a.id }["name"] as JsonPrimitive).content)

        val script = radio()
        var p = fresh()
        val (p1, id) = SoundCore.ensure(p, SoundCore.slotsOf(script, p)[0])
        p = SoundCore.addSound(p1, script, id, SoundSource(own = a.id)).first
        p = SoundCore.addSound(p, script, id, thunder).first
        assertEquals(SoundCore.Sources(listOf("thunder-close"), listOf(a.id), emptyList()), SoundCore.sources(p))
        val published = SoundCore.withoutOwn(p.sound)!!
        assertEquals("the published block leaves own sounds out", listOf(thunder), published.slots.single().sounds.map { it.src })
        val onlyOwn = SoundCore.withoutOwn(SoundCore.addSound(p1, script, id, SoundSource(own = a.id)).first.sound)!!
        assertTrue("a slot left holding nothing goes with them", onlyOwn.slots.isEmpty())

        own.remove(a.id)
        assertFalse(own.has(a.id))
        assertEquals(listOf(b.id), own.list().map { it.id })
    }

    @Test fun `an own sound over the limits is refused by name`() {
        val own = OwnSounds(tmp.newFolder("mine2"))
        val big = tmp.newFile("big.bin")
        java.io.RandomAccessFile(big, "rw").use { it.setLength(SoundCore.OWN_FILE_MAX_BYTES + 1) }
        try {
            own.bring(big, "huge")
            fail("a file over 50 MB is refused")
        } catch (e: OwnSounds.TooBig) {
            assertEquals("That file is larger than 50 MB.", e.message)
        }
    }

    // ---- The mix with sound ---- (the golden holds the numbers: MixSoundTest)

    @Test fun `a sound this device lacks refuses the mix by name, and Export without them leaves it out`() {
        val script = radio()
        var p = fresh()
        val all = script.speechLineIDs
        p = p.copy(takes = all.map { take("V$it", it) }, chosen = all.associateWith { "V$it" })
        val (p1, id) = SoundCore.ensure(p, SoundCore.slotsOf(script, p)[0])
        val own = SoundCore.addSound(p1, script, id, SoundSource(own = "GONE-0000")).first
        try {
            MixTimeline.build(script, own, resolveSound = { _, _ -> null })
            fail("a missing sound is named, never dropped")
        } catch (e: MixTimeline.MissingSounds) {
            assertEquals(1, e.ids.size)
        }
        val without = MixTimeline.build(script, own, resolveSound = { _, _ -> null }, withoutMissing = true)
        assertTrue(without.sounds.isEmpty())
        assertEquals(1, without.left.size)
        assertEquals("1 sound is on another device.", SoundCore.missingLine(listOf("5C2F7A00-1111-2222-3333-444455556666")))
        assertEquals("2 sounds are on another device: Owl at night, Gate creak.", SoundCore.missingLine(listOf("Owl at night", "Gate creak")))
    }

    @Test fun `the cast sheet's words for the Sound part`() {
        val script = radio()
        var p = fresh()
        assertEquals("2 cues · none chosen", SoundCore.partLine(script, p, taken = false))
        val (p1, id) = SoundCore.ensure(p, SoundCore.slotsOf(script, p)[0])
        p = SoundCore.addSound(p1, script, id, thunder).first
        assertEquals("1 of 2 cues", SoundCore.partLine(script, p, taken = true))
        val (p2, id2) = SoundCore.ensure(p, SoundCore.slotsOf(script, p)[1])
        p = SoundCore.addSound(p2, script, id2, SoundSource(pack = "eardrama-sounds-1", cue = "calm-prelude"), kind = "music").first
        assertEquals("2 of 2 cues · 1 bed", SoundCore.partLine(script, p, taken = true))
        assertEquals("Add sounds", SoundCore.partLine(quiet(), fresh(quiet()), taken = false))
    }

    @Test fun `a record without a sound block reads, encodes and fingerprints as it always did`() {
        val p = fresh()
        val text = ProductionStore.encodeRecord(p)
        assertFalse("no sound block, though the Sound part is on the cast sheet", text.contains("\"slots\"") || text.contains("\"lanes\""))
        assertEquals(p, ProductionStore.json.decodeFromString(Production.serializer(), text))
        assertEquals("", p.chosenFingerprint)
    }
}
