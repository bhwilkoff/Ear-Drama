package com.example.appname.plays

import java.io.File
import java.io.IOException
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/**
 * Own scripts on this device (PLAYS-DESIGN §13, ANDROID-DESIGN §4.23), the port of js/own.test.js's cases over the shipped
 * [OwnScripts] and [ProductionStore]: what is kept, the locks a take puts on a line, a change reaching its productions, a full
 * disk and a cut-short swap, folders of another version, export, Save as text, and what is refused unread. Real files in a
 * temporary folder; no network.
 *
 * Seen to fail, 2026-11-24, each rule broken alone in OwnScripts.kt or PlayFiles.kt, then restored: takes read only from
 * chosen ones; adopt touching a shared production, dropping the parts' states, or leaving changed lines finished; a file or
 * shared words read past the cap; a cut-short swap not recovered; a newer format opened or listed; Words changed with no date;
 * a script sealed over a refusal; the row's count of open lines; two names the same; a failed write leaving its folder; a
 * half-cast transcript's marks lost; an empty draft kept; an id that is none removed.
 */
class OwnScriptsTest {
    private val text = """A LITTLE PLAY

ANNA: Who is there?
BEN: Only me.

Somebody knocks twice.

ANNA: Come in, then. (She opens the door.) Mind the step.
BEN: Thank you.
SOUND: DOOR CLOSES
ANNA: Sit down.
"""

    private class Env(val root: File = temporaryRoot(), var failing: (File) -> Boolean = { false }) {
        val plays = ProductionStore(File(root, "Plays"))
        var clock = 1000L
        val adopted = ArrayList<String>()
        val scripts = File(root, "Scripts")
        fun open() = OwnScripts(scripts, { plays }, now = { ++clock }, onAdopted = { adopted += it }, writeFile = { file, words ->
            if (failing(file)) throw IOException("write failed: ENOSPC (No space left on device)")
            file.writeText(words)
        })
        var own = open()
    }

    private suspend fun made(env: Env, title: String = "A Little Play"): OwnRecord {
        val rec = env.own.create(title, text)
        val done = rec.copy(doc = OwnScript.done(rec.doc), done = true)
        assertNull(env.own.keep(done))
        return env.own.get(rec.id)!!
    }

    private fun step(rec: OwnRecord, op: OwnOp, takes: Set<String> = emptySet()): Pair<OwnRecord, String?> {
        val r = OwnScript.apply(rec.doc, op, OwnEnv(takes))
        return rec.copy(doc = r.doc) to r.refusal
    }

    private fun speech(rec: OwnRecord, role: String, n: Int = 0) = rec.doc.lines.filter { it.kind == "speech" && it.role == role }[n]

    private fun record(env: Env, script: PlayScript, lineID: String, created: Double = ReferenceDate.now()): String {
        val p = env.plays.create(script)
        val line = script.lines.first { it.id == lineID }
        env.plays.save(p.add(Take("t-${p.id}-$lineID", lineID, line.part, "$lineID.wav", created, 10, 48_000.0, Take.Capture.Direct, emptyMap(), null, 0.5f, false)))
        return p.id
    }

    @Test fun `a script is added with its parts proposed and no id given, and is not castable until Done`() = runBlocking {
        val env = Env()
        val rec = env.own.create("  A Little Play  ", text)
        assertTrue(OwnScript.isOwnId(rec.id))
        assertEquals("A Little Play", rec.title)
        assertTrue("no line id before Done", rec.doc.lines.all { it.id == null })
        assertNull("no castable script before Done", env.own.script(rec.id))
        val row = env.own.list().single()
        assertEquals(listOf("A Little Play", 2, 2, false), listOf(row.title, row.parts, row.open, row.done))
        assertEquals("2 lines have no part", row.facts)
        val back = env.own.get(rec.id)!!
        assertEquals("the working copy reads back whole", rec.doc.lines, back.doc.lines)
        assertEquals("and its keys go on from there", rec.doc.nextKey, back.doc.nextKey)
        assertEquals("and the text as pasted", OwnScript.normalize(text), back.original)
        assertEquals(listOf(row), env.own.rows.value)
    }

    @Test fun `Done gives each line its id once and keeps the castable shape, sealed`() = runBlocking {
        val env = Env()
        val rec = made(env)
        val s = env.own.script(rec.id)!!
        assertEquals(listOf("own", "own", "Added by you", ""), listOf(s.kind, s.rights.bucket, s.source.name, s.source.url))
        assertTrue(s.isOwn)
        val built = OwnScript.toScript(rec.doc, OwnMeta(rec.id, rec.title))
        assertNull(OwnScript.refusalOf(built))
        assertEquals("the revision is its lines'", OwnScript.revisionOf(built["lines"]), s.revision)
        assertEquals(listOf("L0001", "L0002", "L0003"), s.lines.map { it.id }.take(3))
        assertEquals(listOf("A LITTLE PLAY", "Somebody knocks twice."), s.lines.filter { it.kind == ScriptLine.Kind.Direction }.map { it.source })
        assertEquals("the recorder casts it", listOf("ANNA", "BEN", "Sound", "Stage directions"), s.castParts.map { it.title })
        val row = env.own.list().single()
        assertTrue(row.done)
        assertEquals("2 parts · ${rec.doc.lines.size} lines", row.facts)
        assertEquals(rec.created, s.created)
    }

    @Test fun `words given to a script whose lines cannot be one leave the last that could`() = runBlocking {
        val env = Env()
        var rec = made(env)
        val before = env.own.script(rec.id)
        rec = step(rec, OwnOp("notPart", part = "ANNA")).first
        rec = step(rec, OwnOp("notPart", part = "BEN")).first
        assertEquals("no_parts", env.own.keep(rec))
        assertEquals("the castable script is the last one that could be cast", before, env.own.script(rec.id))
        assertEquals("and the working copy has the change", 0, env.own.get(rec.id)!!.doc.lines.count { it.kind == "speech" })
    }

    @Test fun `a full disk keeps nothing of a change and says why`() = runBlocking {
        val env = Env()
        var rec = made(env)
        fun files() = env.scripts.walk().filter { it.isFile }.sortedBy { it.path }.map { it.relativeTo(env.scripts).path to it.readText() }.toList()
        val before = files()
        rec = step(rec, OwnOp("words", line = speech(rec, "ANNA").k, text = "Who goes there?")).first
        for (which in listOf(OwnScripts.SCRIPT, OwnScripts.DOC, OwnScripts.ROW)) {
            env.failing = { it.name == which }
            try {
                env.own.keep(rec)
                fail("a full disk refuses ($which)")
            } catch (e: IOException) {
                assertEquals("This device is out of space.", OwnWords.notKept(e))
            }
            assertEquals("not one of the three files changed, and nothing is left over ($which)", before, files())
        }
        env.failing = { false }
        assertNull("Try again keeps it", env.own.keep(rec))
        assertEquals("Who goes there?", env.own.script(rec.id)!!.lines.first { it.role == "ANNA" }.spokenText)
        env.failing = { true }
        try { env.own.create("T", text); fail("Add a script refuses too") } catch (_: IOException) { }
        assertEquals("This device could not save it.", OwnWords.notKept(IOException("x")))
    }

    @Test fun `a swap cut short reads as the whole of one version, never half`() = runBlocking {
        val env = Env()
        val rec = made(env)
        val dir = File(env.scripts, rec.id)
        // Cut after the old folder stepped aside: the new one, which was whole, is taken.
        val next = File(env.scripts, ".${rec.id}.next")
        dir.copyRecursively(next)
        File(next, OwnScripts.ROW).writeText(File(next, OwnScripts.ROW).readText().replace("A Little Play", "Newer"))
        assertTrue(dir.renameTo(File(env.scripts, ".${rec.id}.old")))
        env.own = env.open()
        assertEquals(listOf("Newer"), env.own.list().map { it.title })
        assertEquals("nothing is left over", listOf(rec.id), env.scripts.list()!!.toList())
        // Cut before the new one was whole: the old one is put back.
        assertTrue(dir.renameTo(File(env.scripts, ".${rec.id}.old")))
        File(env.scripts, ".${rec.id}.next").apply { mkdirs() }.resolve(OwnScripts.DOC).writeText("{")
        env.own = env.open()
        assertNotNull(env.own.get(rec.id))
        assertEquals(listOf(rec.id), env.scripts.list()!!.toList())
        // Cut while a delete was under way: it stays deleted.
        assertTrue(dir.renameTo(File(env.scripts, ".${rec.id}.gone")))
        env.own = env.open()
        assertEquals(emptyList<OwnRow>(), env.own.list())
        assertEquals(emptyList<String>(), env.scripts.list()!!.toList())
    }

    @Test fun `a device that had only productions keeps them, and reading makes nothing`() = runBlocking {
        val env = Env()
        val p = env.plays.create(fixtureScript())
        env.plays.save(p.add(take("a", "L0003", PartID.role("MOLLY"), 4_800)))
        // What an earlier version wrote: no created, episode or edits in script.json.
        val old = File(env.plays.folder(p.id), "script.json")
        val bare = ProductionStore.json.parseToJsonElement(old.readText()).jsonObject.filterKeys { it !in setOf("created", "episode", "edits") }
        old.writeText(JsonObject(bare).toString())
        val before = env.plays.folder(p.id).walk().filter { it.isFile }.associate { it.name to it.readText() }
        assertEquals(emptyList<OwnRow>(), env.own.list())
        assertNull(env.own.draft())
        assertFalse("reading makes no folder", env.scripts.exists())
        val again = ProductionStore(File(env.root, "Plays"))
        assertEquals(listOf(p.id), again.productions.value.map { it.id })
        assertEquals("the stored script still reads", fixtureScript().lines, again.script(again.production(p.id)!!)!!.lines)
        assertEquals(before, env.plays.folder(p.id).walk().filter { it.isFile }.associate { it.name to it.readText() })
        assertEquals("a catalog script adopts nothing", emptyList<String>(), env.plays.adopt(fixtureScript().copy(id = "own-00000000-0000-4000-8000-000000000000")))
    }

    @Test fun `a folder of another version - a field missing takes its default, one unknown is ignored, a newer format is left alone`() = runBlocking {
        val env = Env()
        val rec = made(env)
        val doc = File(File(env.scripts, rec.id), OwnScripts.DOC)
        val tree = OwnScripts.json.parseToJsonElement(doc.readText()).jsonObject
        doc.writeText(JsonObject(tree.filterKeys { it !in setOf("extras", "ear", "episode", "format") } + ("later" to JsonNull)).toString())
        assertEquals(rec.doc.lines, env.own.get(rec.id)!!.doc.lines)
        val row = File(File(env.scripts, rec.id), OwnScripts.ROW)
        row.writeText(row.readText().replace("\"format\":1", "\"format\":2"))
        doc.writeText(doc.readText().replaceFirst("{", "{\"format\":2,"))
        assertEquals("not listed", emptyList<OwnRow>(), env.own.list())
        assertNull("not opened", env.own.get(rec.id))
        assertTrue("and not touched", doc.exists() && row.exists())
    }

    @Test fun `two changes kept close together end as the second`() = runBlocking {
        val env = Env()
        val rec = made(env)
        var slow = true
        env.failing = { if (it.name == OwnScripts.DOC && slow) { slow = false; Thread.sleep(40) }; false }
        val one = step(rec, OwnOp("words", line = speech(rec, "ANNA").k, text = "One?")).first
        val two = step(one, OwnOp("words", line = speech(rec, "ANNA").k, text = "Two?")).first
        coroutineScope {
            launch { env.own.keep(one) }
            launch { env.own.keep(two) }
        }
        assertEquals("Two?", env.own.get(rec.id)!!.doc.lines.first { it.role == "ANNA" }.text)
    }

    @Test fun `a take fixes its line's part and boundaries in every production, chosen or not`() = runBlocking {
        val env = Env()
        val rec = made(env)
        val s = env.own.script(rec.id)!!
        val anna = s.lines.first { it.role == "ANNA" }
        val ben = s.lines.filter { it.role == "BEN" }[1]
        val pid = record(env, s, anna.id)
        record(env, s, ben.id)
        val other = made(env, "Another")
        assertEquals("both productions' takes lock", setOf(anna.id, ben.id), env.own.takes(rec.id))
        assertEquals("another script's are free", emptySet<String>(), env.own.takes(other.id))
        // A take that is not the chosen one locks its line as well.
        val p = env.plays.production(pid)!!
        val firstBen = s.lines.first { it.role == "BEN" }.id
        env.plays.save(p.copy(takes = p.takes + Take("unchosen", firstBen, PartID.role("BEN"), "u.wav", 0.0, 10, 48_000.0, Take.Capture.Direct, emptyMap(), null, 0.5f, false)))
        assertTrue(firstBen in env.own.takes(rec.id))
        val takes = env.own.takes(rec.id)
        val k = speech(rec, "ANNA").k
        for (op in listOf(OwnOp("assign", line = k, to = OwnTarget.Role("BEN")), OwnOp("split", line = k, at = 4), OwnOp("leaveOut", line = k))) {
            assertEquals(op.op, "line_has_take", step(rec, op, takes).second)
        }
        assertEquals("lines_have_take", step(rec, OwnOp("leaveOutBelow", line = rec.doc.lines.first().k), takes).second)
        assertEquals("so is its part's name", "part_has_take", step(rec, OwnOp("rename", part = "ANNA", rename = "ANN"), takes).second)
        assertNull("its words may change", step(rec, OwnOp("words", line = k, text = "Who is it?"), takes).second)
    }

    @Test fun `a change reaches its productions - takes stay, and Words changed reads true only for an older take`() = runBlocking {
        val env = Env()
        var rec = made(env)
        val s = env.own.script(rec.id)!!
        val annas = s.lines.filter { it.role == "ANNA" }.map { it.id }
        val pid = record(env, s, annas[0], ReferenceDate.now() - 60)
        env.plays.save(env.plays.production(pid)!!.copy(listenedThrough = true, mixedFrom = "x"))
        val taken = setOf(annas[0])
        val old = env.plays.production(pid)!!.takes.single()
        rec = step(rec, OwnOp("words", line = speech(rec, "ANNA").k, text = "Who goes there?"), taken).first.copy(title = "Renamed")
        env.own.keep(rec)
        var p = env.plays.production(pid)!!
        var ps = env.plays.script(p)!!
        val now = env.own.script(rec.id)!!
        assertEquals(listOf("Renamed", now.revision, now.revision), listOf(p.title, p.scriptRevision, ps.revision))
        assertTrue("and the revision is new", now.revision != s.revision)
        assertEquals("the production reads the new words", "Who goes there?", ps.lines.first { it.id == annas[0] }.spokenText)
        assertEquals("the take stays", listOf(old), p.takes)
        assertEquals("words alone leave a finished play finished", true to "x", p.listenedThrough to p.mixedFrom)
        assertEquals("what was read of it is read again", listOf(pid), env.adopted)
        assertTrue("the old take reads Words changed", OwnScripts.wordsChanged(ps, old))
        assertFalse("a take of the new words does not", OwnScripts.wordsChanged(ps, old.copy(created = ReferenceDate.now() + 60)))
        assertFalse("nor one on another line", OwnScripts.wordsChanged(ps, old.copy(lineID = annas[1])))
        rec = step(rec, OwnOp("words", line = speech(rec, "ANNA").k, text = "Who is there."), taken).first
        env.own.keep(rec)
        assertFalse("a changed comma is not changed words", OwnScripts.wordsChanged(env.own.script(rec.id), old))
        // A part renamed and a line split: parts follow, and the play is no longer finished.
        val renamed = step(rec, OwnOp("rename", part = "BEN", rename = "BENJAMIN"), taken)
        assertNull(renamed.second)
        val second = speech(renamed.first, "ANNA", 1)
        val split = step(renamed.first, OwnOp("split", line = second.k, at = 13), taken)
        assertNull("a free line splits", split.second)
        env.own.keep(split.first)
        p = env.plays.production(pid)!!
        ps = env.plays.script(p)!!
        assertEquals("the parts follow", listOf("role:ANNA", "role:BENJAMIN"), p.parts.keys.map { it.raw }.filter { it.startsWith("role:") }.sorted())
        assertTrue("the split line takes a letter", ps.lines.any { it.id == "${second.id}a" })
        assertEquals("new lines make it unfinished", false to null, p.listenedThrough to p.mixedFrom)
        assertEquals("and the take is still there", 1, p.takes.size)
        val stored = ProductionStore(File(env.root, "Plays")).production(pid)!!
        assertEquals("and it is kept, not only in memory", ps.revision, stored.scriptRevision)
    }

    @Test fun `a part being recorded keeps its state through a change`() = runBlocking {
        val env = Env()
        val rec = made(env)
        val s = env.own.script(rec.id)!!
        val p = env.plays.create(s)
        env.plays.save(p.withPart(PartID.role("ANNA"), PartState(PartState.Status.Recording, "Pat")))
        env.own.keep(step(rec, OwnOp("words", line = speech(rec, "BEN").k, text = "Nobody.")).first)
        assertEquals(PartState(PartState.Status.Recording, "Pat"), env.plays.production(p.id)!!.state(PartID.role("ANNA")))
    }

    @Test fun `a shared production keeps its own text`() = runBlocking {
        val env = Env()
        val rec = made(env)
        val s = env.own.script(rec.id)!!
        val pid = record(env, s, s.lines.first { it.role == "ANNA" }.id)
        env.plays.setShare(pid, ShareLink("w1"))
        env.own.keep(step(rec, OwnOp("words", line = speech(rec, "BEN").k, text = "Nobody.")).first)
        assertEquals("frozen", s.revision, env.plays.production(pid)!!.scriptRevision)
        assertEquals(s.revision, env.plays.script(env.plays.production(pid)!!)!!.revision)
        assertEquals(emptyList<String>(), env.adopted)
    }

    @Test fun `deleting a script leaves its productions their copy`() = runBlocking {
        val env = Env()
        val rec = made(env)
        val s = env.own.script(rec.id)!!
        val pid = record(env, s, s.lines.first { it.role == "ANNA" }.id)
        val keep = made(env, "Kept")
        assertEquals(listOf(pid), env.own.productions(rec.id).map { it.id })
        env.own.remove(rec.id)
        assertNull(env.own.get(rec.id))
        assertNull(env.own.script(rec.id))
        assertEquals("and only it", listOf(keep.id), env.own.list().map { it.id })
        assertEquals("the production reads its own copy", s.id, env.plays.script(env.plays.production(pid)!!)!!.id)
        env.own.remove("../Plays")
        assertNotNull("an id that is none removes nothing", env.plays.production(pid))
    }

    @Test fun `the text being added is kept, and goes when it is empty`() = runBlocking {
        val env = Env()
        assertNull(env.own.draft())
        env.own.setDraft(OwnDraft("T", "ANNA: Hello"))
        assertEquals(OwnDraft("T", "ANNA: Hello"), env.open().draft())
        assertEquals("and it is no script", emptyList<OwnRow>(), env.own.list())
        env.own.setDraft(OwnDraft())
        assertNull(env.own.draft())
        assertEquals(emptyList<String>(), env.scripts.list()!!.toList())
    }

    @Test fun `Export my data carries every own script, Done or not`() = runBlocking {
        val env = Env()
        val rec = made(env)
        env.own.create("Not yet", text)
        val rows = env.own.exportRows()
        fun JsonObject.str(k: String) = this[k]!!.jsonPrimitive.content
        assertEquals(listOf("Not yet", "A Little Play"), rows.map { it.str("title") })
        assertEquals(listOf("Added by you", "Added by you"), rows.map { it.str("source") })
        assertEquals(listOf("false", "true"), rows.map { it.str("done") })
        val lines = rows[1]["lines"] as JsonArray
        assertEquals(listOf(rec.id, rec.doc.lines.size, "L0003"), listOf(rows[1].str("id"), lines.size, lines[2].jsonObject.str("id")))
        assertEquals("a speech's own fields and no others", setOf("id", "kind", "role", "parts"), lines.map { it.jsonObject }.first { it.str("kind") == "speech" }.keys)
        assertTrue(rows[1].str("created").startsWith("1970-01-01T"))
        assertEquals("a line with no part says so", listOf("A LITTLE PLAY", "Somebody knocks twice."), rows[0]["lines"]!!.jsonArray.map { it.jsonObject }.filter { it.str("kind") == "open" }.map { it.str("source") })
    }

    @Test fun `Save as text reads back as the same speeches`() = runBlocking {
        val env = Env()
        val s = env.own.script(made(env).id)!!
        val saved = OwnScripts.asText(s)
        assertTrue("a name in capitals over its words (Fountain)", saved.contains("\n\nANNA\nWho is there?\n\n"))
        val back = OwnScript.parse(saved).lines
        assertEquals(s.lines.filter { it.kind == ScriptLine.Kind.Speech }.map { it.role }, back.filter { it.kind == "speech" }.map { it.role })
        assertEquals("ANNA" to "Come in, then. (She opens the door.) Mind the step.", back.filter { it.kind == "speech" }.map { it.role to it.text }[2])
        assertEquals("a sound cue too", listOf("SOUND: DOOR CLOSES"), back.filter { it.kind == "sound" }.map { it.text })
        assertEquals("AB C.txt", OwnScripts.fileName("A/B: \"C\"?"))
        assertEquals("Script.txt", OwnScripts.fileName("///"))
    }

    @Test fun `a file is text or refused, counted before it is read`() {
        fun bytes(vararg x: Int) = ByteArray(x.size) { x[it].toByte() }
        fun words(b: ByteArray) = (OwnText.decode(b) as OwnText.Read).text
        assertEquals("ANNA: Café", words("ANNA: Café".toByteArray()))
        assertEquals("A", words(bytes(0xef, 0xbb, 0xbf, 0x41)))
        assertEquals("Aé", words(bytes(0xff, 0xfe, 0x41, 0, 0xe9, 0)))
        assertEquals("A", words(bytes(0xfe, 0xff, 0, 0x41)))
        assertEquals("an old Windows file", "Café’", words(bytes(0x43, 0x61, 0x66, 0xe9, 0x92)))
        for ((b, what) in listOf(
            "%PDF-1.4".toByteArray() to "a PDF", "{\\rtf1".toByteArray() to "RTF", bytes(0x50, 0x4b, 3, 4, 0) to ".docx", bytes(0x41, 0, 0x42) to "a binary",
            bytes(0xff, 0xd8, 0xff, 1, 2, 3, 4, 5) to "a picture",
        )) assertEquals(what, OwnText.Refused("not_text"), OwnText.decode(b))
        assertEquals("too many bytes, unread", OwnText.Refused("too_long"), OwnText.decode(ByteArray(OwnText.MAX_READ + 1)))
        assertEquals("too many once read", OwnText.Refused("too_long"), OwnText.decode("é".repeat(OwnScript.MAX_BYTES / 2 + 1).toByteArray()))
        assertEquals("the cap itself is allowed", OwnScript.MAX_BYTES, words("a".repeat(OwnScript.MAX_BYTES).toByteArray()).length)
        // A stream that never ends is left at the cap.
        var given = 0L
        val endless = object : java.io.InputStream() {
            override fun read(): Int { given += 1; return 'a'.code }
            override fun read(b: ByteArray, off: Int, len: Int): Int { given += len; b.fill('a'.code.toByte(), off, off + len); return len }
        }
        assertEquals(OwnText.Refused("too_long"), OwnText.read(endless))
        assertTrue("read $given", given <= OwnText.MAX_READ + 1)
        // Words shared from another app.
        assertEquals(OwnText.Read("ANNA: Hi", "T"), OwnText.shared("ANNA: Hi", "T"))
        assertEquals(OwnText.Refused("too_long"), OwnText.shared("é".repeat(OwnScript.MAX_BYTES / 2 + 1)))
        val unread = object : CharSequence {
            override val length = Int.MAX_VALUE
            override fun get(index: Int): Char = error("read past the cap")
            override fun subSequence(startIndex: Int, endIndex: Int): CharSequence = error("read past the cap")
            override fun toString(): String = error("read past the cap")
        }
        assertEquals("measured, never read", OwnText.Refused("too_long"), OwnText.shared(unread))
    }

    @Test fun `the nearest speakers of every line answer as the core does`() {
        val rnd = kotlin.random.Random(7)
        repeat(200) { round ->
            val lines = List(1 + rnd.nextInt(30)) { i ->
                val r = rnd.nextInt(10)
                if (r < 4) OwnLine(i + 1, null, "speech", "ABCD"[rnd.nextInt(1 + rnd.nextInt(4))].toString(), "x")
                else if (r < 6) OwnLine(i + 1, null, "direction", null, "x") else OwnLine(i + 1, null, "open", null, "x")
            }
            val all = OwnScripts.nearestAll(lines)
            lines.forEachIndexed { i, l -> if (l.kind == "open") assertEquals("round $round line $i", OwnScript.nearestParts(lines, i), all[l.k]) }
        }
        val big = List(6000) { OwnLine(it, null, if (it == 0) "speech" else "open", if (it == 0) "A" else null, "x") }
        val t = System.nanoTime()
        OwnScripts.nearestAll(big)
        assertTrue("6,000 lines in ${(System.nanoTime() - t) / 1_000_000} ms", System.nanoTime() - t < 500_000_000L)
    }

    // ---- What was cast by ear ----

    private val vtt = EarCoreTest.VTT
    private val episode = OwnEpisode("planetman|n53", "https://eardrama.org/episode/planetman%7Cn53")

    private fun half(own: OwnScripts): Pair<OwnRecord, EarCore.Session> {
        val s = EarCore.Session(OwnScript.fromCues(OwnScript.parseCues(vtt)))
        for (t in 0L..500L step 16) s.tick(t, true)
        s.give("Announcer")
        for (t in 500L..4500L step 16) s.tick(t, true)
        s.give("Dantro")
        for (t in 4500L..6500L step 16) s.tick(t, true)
        return own.begin("Secret Council", s.doc, episode, OwnEar("x", "u", 6500)).copy(extras = s.names) to s
    }

    @Test fun `looking keeps nothing - a casting begun is a row that says how far it is`() = runBlocking {
        val env = Env()
        val (rec, _) = half(env.own)
        assertFalse("begin keeps nothing by itself", env.scripts.exists())
        env.own.keep(rec)
        val row = env.own.list().single()
        assertEquals(listOf(episode.id, EarCount(4, 7), false, 2), listOf(row.episode, row.ear, row.done, row.parts))
        assertEquals("4 of 7 lines cast", row.facts)
        assertEquals(rec.id, env.own.ofEpisode { it == episode.id }!!.id)
        assertNull("and by no other", env.own.ofEpisode { it == "other" })
        assertNull("no script before Done", env.own.script(rec.id))
        val back = env.own.get(rec.id)!!
        assertEquals("the marks, the times and what was heard", rec.doc.copy(undo = emptyList()), back.doc)
        assertEquals(6500L to episode, back.ear!!.place to back.episode)
        assertTrue("and no step to take back", back.doc.undo.isEmpty())
    }

    @Test fun `Done on part of it is a script, and casting goes on from it`() = runBlocking {
        val env = Env()
        val (begun, _) = half(env.own)
        val rec = begun.copy(doc = OwnScript.done(begun.doc, keepOpen = true), done = true)
        assertNull(env.own.keep(rec))
        val s = env.own.script(rec.id)!!
        fun who(l: ScriptLine) = l.role ?: l.kind.name.lowercase()
        assertEquals(listOf("ANNOUNCER", "ANNOUNCER", "DANTRO", "DANTRO", "direction", "direction", "direction"), s.lines.map(::who))
        assertEquals(PlayScript.Source("Automatic transcript", episode.url) to episode.id, s.source to s.episode)
        assertEquals("own" to "own", s.kind to s.rights.bucket)
        assertFalse("no time is in the script: the broadcast is no cue", File(File(env.scripts, rec.id), OwnScripts.SCRIPT).readText().contains("\"at\""))
        assertEquals(true to EarCount(4, 7), env.own.list().single().let { it.done to it.ear })
        val back = env.own.get(rec.id)!!
        val t = EarCore.Session(back.doc, back.extras)
        t.tick(8100, true)
        t.give("Patrol")
        for (ms in 8100L..14100L step 16) t.tick(ms, true)
        env.own.keep(back.copy(doc = t.doc))
        assertEquals(
            "more of it cast later, the same ids",
            listOf("L0004" to "DANTRO", "L0005" to "PATROL", "L0006" to "PATROL", "L0007" to "PATROL"), env.own.script(rec.id)!!.lines.map { it.id to who(it) }.drop(3),
        )
    }

    @Test fun `the parts page finishes one, and a half-cast one exports with its parts and its episode`() = runBlocking {
        val env = Env()
        val (rec, s) = half(env.own)
        env.own.keep(rec)
        val x = env.own.exportRows().single()
        fun JsonObject.str(k: String) = this[k]!!.jsonPrimitive.content
        assertEquals("Automatic transcript" to episode.id, x.str("source") to x.str("episode"))
        assertEquals(
            listOf("ANNOUNCER", "ANNOUNCER", "DANTRO", "DANTRO", "open", "open", "open"),
            x["lines"]!!.jsonArray.map { it.jsonObject }.map { if (it.containsKey("role")) it.str("role") else it.str("kind") },
        )
        s.leaveOut()
        env.own.keep(rec.copy(doc = OwnScript.done(OwnScript.settle(s.doc)), done = true))
        assertEquals(6, env.own.script(rec.id)!!.lines.size)
        val row = env.own.list().single()
        assertEquals("nothing is left to cast", listOf(true, 6, 0, "2 parts · 6 lines"), listOf(row.ear!!.let { it.cast == it.lines }, row.lines, row.open, row.facts))
    }

    @Test fun `a real play, pasted, is corrected, kept and read by the recorder's own core`() = runBlocking {
        val lib = CastableLibrary.decode(File("../../catalog/plays/castable-scripts.json").readText()).scripts
        val play = lib.maxBy { it.lines.size }
        val env = Env()
        val rec = env.own.create(play.title, OwnScripts.asText(play))
        assertTrue("${rec.doc.lines.size} lines of a real text", rec.doc.lines.size > 200)
        assertNull(env.own.keep(rec.copy(doc = OwnScript.done(rec.doc), done = true)))
        val s = env.own.script(rec.id)!!
        val p = env.plays.create(s)
        assertNotNull("a part to record", Relay.next(p, s))
        assertEquals("every speech is castable", s.lines.count { it.kind == ScriptLine.Kind.Speech }, s.speechLineIDs.size)
    }

    @Test fun `Next asks what Done would keep - a text under the raw cap can still build past the kept size`() {
        fun words(n: Int) = (1..n).joinToString("\n") { "ANNA: Hello there $it." } + "\n"
        val long = words(5_900)
        assertNull("the raw text is under every cap", OwnScript.textRefusal(long))
        assertTrue("and under the line cap", OwnScript.parse(long).lines.size <= OwnScript.MAX_LINES)
        assertEquals("but Done would refuse it, so Next does", "too_long" to true, OwnScripts.judge(long).let { it.first to (it.second != null) })
        assertNull("a shorter one goes on", OwnScripts.judge(words(3_000)).first)
        assertEquals("too many lines is the same answer", "too_many_lines", OwnScripts.judge((1..OwnScript.MAX_LINES + 1).joinToString("\n") { "A: x" }).first)
    }

    @Test fun `nothing leaves the device - no own-script file names the network, the Worker, or a sign-in`() {
        val leak = Regex("HttpClient|okHttp|WebSocket|WorkerApi|PlaysApi|accounts|SharedPlays|readWire")
        val src = File("src/main/java/com/example/appname")
        for (f in listOf("plays/OwnScript.kt", "plays/OwnScripts.kt", "plays/EarCore.kt", "ui/screens/OwnAddScreen.kt", "ui/screens/OwnPartsScreen.kt", "ui/screens/OwnSheets.kt")) {
            val code = File(src, f).readText().replace(Regex("(?s)/\\*.*?\\*/"), "").replace(Regex("(?m)//.*$"), "")
            assertEquals(f, emptyList<String>(), leak.findAll(code).map { it.value }.toList())
        }
        val ear = File(src, "ui/screens/EarScreen.kt").readText()
        for (word in listOf("ExoPlayer.Builder", "MediaPlayer(", "AudioRecord", "RECORD_AUDIO", "PlaysApi", "Publish")) assertFalse("EarScreen has $word", ear.contains(word))
        val plays = File(src, "ui/screens/PlaysScreens.kt").readText()
        // Sharing is the person's own act (R4-5): Share carries the line that says who can read it, and Read together shares first.
        assertTrue("Share on a production of one says who can read it", plays.contains("readers = if (script.isOwn) com.example.appname.plays.OwnShare.READERS"))
        assertTrue("Read together is on its page", plays.contains("        ReadTogetherButton(script)\n    },"))
        assertTrue("and shares first", File(src, "ui/screens/ReadScreens.kt").readText().contains("Share \${script.title}?"))
        assertTrue("no Kokoro voice offered", File(src, "ui/CastUi.kt").readText().contains("script?.isOwn != true"))
    }
}
