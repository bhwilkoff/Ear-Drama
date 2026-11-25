package com.example.appname.plays

import java.io.File
import java.io.IOException
import java.security.MessageDigest
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
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
 * Own scripts shared (PLAYS-DESIGN §13 items 11 to 16; R4-5), the port of js/own-share.test.js over the shipped [OwnShare],
 * [OwnScripts] and [ProductionStore] with a fake Worker that answers as worker/src/plays-own.js does: the text sent once and as it
 * was hashed, owed and tried again, a share undone when it can never pass, the one resolver by every door and what it refuses to
 * draw, the freeze and Edit a copy, the words.
 *
 * Seen to fail, 2026-11-24, each rule broken alone in OwnShare.kt, OwnScripts.kt, PlaysShare.kt or ReadSession.kt, then restored
 * (tools/android_own_share_mutants.sh runs them all): the body without `own`, without the cast sheet, without the title; the
 * text not canonical; a text sent twice; `already_there` read as a failure; every error read as owed; every error read as
 * never passing; the share not undone; the freeze before the send; a freeze failure losing the share; the digest unchecked;
 * the canonical form unchecked; the core's check skipped; the cast sheet unmatched; the x-script names unchecked; the device
 * copy never first; the fetched script never kept; the production's copy ignored; the freeze not refused a write; Edit a copy
 * keeping the id; Edit a copy keeping the shared mark; a long copy title past its cap; Publish offered for an own script;
 * consent asked for one; a removal held with the account gone; an unreadable x-take answered as "no take".
 */
class OwnShareTest {
    private val text = "ANNA: Who is there? Déjà vu.\nBEN: Only me.\n\nSomebody knocks.\n\nANNA: Come in.\nSOUND: DOOR CLOSES\nBEN: Thank you.\n"

    private fun problem(status: Int, code: String, detail: String? = null) = PlaysException(
        code,
        when (status) { 401 -> PlaysException.Kind.Unauthorized; 429 -> PlaysException.Kind.RateLimited; 503 -> PlaysException.Kind.NotConfigured; else -> PlaysException.Kind.Refused },
        detail?.let(::JsonPrimitive), status,
    )

    private fun offline() = PlaysException("", PlaysException.Kind.Offline)

    private fun sha12(b: ByteArray) = MessageDigest.getInstance("SHA-256").digest(b).take(6).joinToString("") { "%02x".format(it.toInt() and 0xff) }

    private class Row(val body: JsonObject, var bytes: ByteArray? = null, var held: Boolean = false)

    /** The Worker's own-script half, over bytes, as worker/src/plays-own.js judges them. */
    private class Worker : PlaysTransport, ScriptWire {
        val rows = LinkedHashMap<String, Row>()
        val calls = ArrayList<List<String>>()
        val fail = HashMap<String, ArrayDeque<Throwable>>()
        var n = 0
        private fun failing(name: String) { fail[name]?.removeFirstOrNull()?.let { throw it } }
        fun count(name: String) = calls.count { it[0] == name }
        private fun row(pid: String) = rows[pid] ?: throw PlaysException("not_found", PlaysException.Kind.Refused, null, 404)
        private fun send(pid: String): ScriptBytes {
            val r = row(pid)
            if (r.held) throw PlaysException("script_removed", PlaysException.Kind.Refused, null, 410)
            val bytes = r.bytes ?: throw PlaysException("no_script", PlaysException.Kind.Refused, null, 404)
            val b = r.body
            val episode = b["episode_id"]?.jsonPrimitive?.content
            val meta = """{"id":"${b["script_id"]!!.jsonPrimitive.content}","revision":"${b["script_revision"]!!.jsonPrimitive.content}","title":"${b["title"]!!.jsonPrimitive.content}","episode_id":${if (episode == null) "null" else "\"$episode\""}}"""
            return ScriptBytes(bytes, meta)
        }

        override suspend fun create(body: JsonObject): SharedRecord {
            failing("create")
            calls += listOf("create")
            lastBody = body
            val pid = "P${++n}"
            rows[pid] = Row(body)
            return SharedRecord(
                pid, body["script_id"]!!.jsonPrimitive.content, body["script_revision"]!!.jsonPrimitive.content, body["title"]?.jsonPrimitive?.content.orEmpty(),
                director = "me", publishable = false, ownScript = OwnScriptState("owed", "me", body["episode_id"]?.jsonPrimitive?.content),
            )
        }
        var lastBody: JsonObject? = null
        override suspend fun deleteProduction(pid: String) { calls += listOf("delete", pid); rows.remove(pid) }
        override suspend fun putScript(pid: String, text: String) {
            calls += listOf("put", pid)
            failing("put")
            val r = row(pid)
            if (r.bytes != null) throw PlaysException("already_there", PlaysException.Kind.Refused, null, 409)
            val bytes = text.toByteArray(Charsets.UTF_8)
            val digest = MessageDigest.getInstance("SHA-256").digest(bytes).take(6).joinToString("") { "%02x".format(it.toInt() and 0xff) }
            if (digest != r.body["script_revision"]!!.jsonPrimitive.content) throw PlaysException("revision_mismatch", PlaysException.Kind.Refused, null, 422)
            r.bytes = bytes
        }
        override suspend fun memberScript(pid: String): ScriptBytes { calls += listOf("member", pid); return send(pid) }
        override suspend fun inviteScript(token: String): ScriptBytes { calls += listOf("invite", token); return send(token.substringAfter(':')) }
        override suspend fun seatScript(key: String, pid: String): ScriptBytes { calls += listOf("seat", key, pid); return send(pid) }
        override suspend fun roomScript(code: String, key: String): ScriptBytes { calls += listOf("room", code, key); return send(code) }

        override suspend fun consent() = error("not used")
        override suspend fun list() = error("not used")
        override suspend fun get(pid: String) = error("not used")
        override suspend fun invite(pid: String) = error("not used")
        override suspend fun viewInvite(token: String) = error("not used")
        override suspend fun joinByInvite(token: String, part: String, displayName: String?) = error("not used")
        override suspend fun claim(pid: String, part: String) = error("not used")
        override suspend fun partAction(pid: String, part: String, action: String) = error("not used")
        override suspend fun agree(pid: String, version: String) = error("not used")
        override suspend fun upload(pid: String, takeId: String, bytes: ByteArray, meta: JsonObject) = error("not used")
        override suspend fun nextTake(pid: String) = error("not used")
        override suspend fun choose(pid: String, takeId: String) = error("not used")
        override suspend fun publish(pid: String) = error("not used")
        override suspend fun removeLine(pid: String, lineId: String, reason: String) = error("not used")
        override suspend fun report(pid: String, takeId: String?, userId: String?, reason: String, note: String?) = error("not used")
        override suspend fun block(userId: String) = error("not used")
        override suspend fun classes() = error("not used")
        override suspend fun classDetail(id: String) = error("not used")
        override suspend fun createClass(name: String, under13: Boolean) = error("not used")
        override suspend fun joinClass(code: String, displayName: String?) = error("not used")
    }

    private class Device(val root: File = temporaryRoot()) {
        val plays = ProductionStore(File(root, "Plays"))
        var clock = 1000L
        val own = OwnScripts(File(root, "Scripts"), { plays }, now = { ++clock })
        val freezer = ScriptFreezer { own.freeze(it) }
    }

    private suspend fun made(d: Device, title: String = "A Little Play", words: String = text): PlayScript {
        val rec = d.own.create(title, words)
        assertNull(d.own.keep(rec.copy(doc = OwnScript.done(rec.doc), done = true)))
        return d.own.script(rec.id)!!
    }

    private class Shared(val script: PlayScript, val local: Production, val sent: Sent) { val rec get() = sent.rec }

    private suspend fun shared(w: Worker, d: Device, script: PlayScript? = null): Shared {
        val s = script ?: made(d)
        val local = d.plays.create(s)
        return Shared(s, local, OwnShare.share(w, w, d.plays, local, s, null, d.freezer))
    }

    private fun resolver(w: Worker, d: Device? = null, kept: Boolean = false, catalog: suspend (String, String) -> PlayScript? = { _, _ -> null }) = OwnShare.Resolver(
        w, catalog,
        kept = { pid -> if (kept && d != null) d.plays.findShared(pid)?.let(d.plays::script) else null },
        device = { id -> d?.own?.script(id) },
    )

    private suspend fun ask(w: Worker, rec: SharedRecord, who: ScriptWho, fit: (PlayScript) -> Boolean = { true }) =
        resolver(w).scriptOf(rec.scriptID, rec.scriptRevision, who, fit)

    private suspend fun refused(code: String, name: String, block: suspend () -> Any?) {
        try { block(); fail("$name: resolved") } catch (e: PlaysException) { assertEquals(name, code, e.code) }
    }

    // ---- Sharing ----

    @Test fun `Share makes an own production with the cast sheet and title, then sends the lines as they were hashed, once`() = runBlocking {
        val w = Worker()
        val d = Device()
        val s = shared(w, d)
        val body = w.lastBody!!
        assertEquals(listOf(true, "A Little Play", s.script.id, s.script.revision), listOf(body["own"]!!.jsonPrimitive.boolean, body["title"]!!.jsonPrimitive.content, body["script_id"]!!.jsonPrimitive.content, body["script_revision"]!!.jsonPrimitive.content))
        assertEquals("every line in order", PlaysShare.castSheet(s.script), body["cast"]!!.jsonArray.map { it.jsonObject["id"]!!.jsonPrimitive.content to it.jsonObject["part"]!!.jsonPrimitive.content })
        assertFalse("no episode for a script that was pasted", body.containsKey("episode_id"))
        assertEquals("the canonical lines", OwnScript.canonicalLines(OwnShare.linesOf(s.script)), String(w.rows[s.rec.id]!!.bytes!!, Charsets.UTF_8))
        assertEquals("the lines hash to the revision", s.script.revision, sha12(w.rows[s.rec.id]!!.bytes!!))
        assertEquals("once", 1, w.count("put"))
        assertNull(s.sent.unsent)
        assertEquals("linked here", s.rec.id, d.plays.share(s.local.id)?.pid)
        val catalog = fixtureScript()
        val plain = OwnShare.makeBody(catalog)
        assertEquals("a catalog play sends no text and no title", listOf("script_id", "script_revision", "cast"), plain.keys.toList())
        assertEquals("a cast transcript names its episode, so a take-down finds it", "ep-1", OwnShare.makeBody(s.script.copy(episode = "ep-1"))["episode_id"]!!.jsonPrimitive.content)
    }

    @Test fun `a text already there is the same text - success`() = runBlocking {
        val w = Worker()
        w.fail["put"] = ArrayDeque(listOf(problem(409, "already_there")))
        val s = shared(w, Device())
        assertNull(s.sent.unsent)
    }

    @Test fun `a sending that may pass later leaves it owed, and Try again sends it`() = runBlocking {
        for (e in listOf(offline(), problem(503, "scripts_full"), problem(429, "rate_limited"), problem(401, "unauthorized"), problem(500, "oops"), RuntimeException("reset"))) {
            val w = Worker()
            val d = Device()
            w.fail["put"] = ArrayDeque(listOf(e))
            val s = shared(w, d)
            assertEquals("owed after ${(e as? PlaysException)?.code ?: e.message}", e, s.sent.unsent)
            assertEquals("the share stands", listOf(0, s.rec.id), listOf(w.count("delete"), d.plays.share(s.local.id)?.pid))
            assertTrue("and what is owed is what will be sent", d.own.frozen(s.script.id))
            assertNull("sent by Try again", OwnShare.sendOrUndo(w, w, s.rec.id, s.script, d.freezer))
            assertNotNull("there", w.rows[s.rec.id]!!.bytes)
        }
    }

    @Test fun `a sending that can never pass undoes the share, on the Worker and here`() = runBlocking {
        for ((status, code) in listOf(413 to "script_too_long", 422 to "revision_mismatch", 410 to "script_removed", 400 to "bad_request")) {
            val w = Worker()
            val d = Device()
            w.fail["put"] = ArrayDeque(listOf(problem(status, code)))
            val s = made(d)
            val local = d.plays.create(s)
            try { OwnShare.share(w, w, d.plays, local, s, null, d.freezer); fail("$code: shared") } catch (e: PlaysException) { assertEquals(code, e.code) }
            assertEquals("nothing is left shared", listOf(1, 0, null), listOf(w.count("delete"), w.rows.size, d.plays.share(local.id)))
            assertFalse("on disk too", File(d.plays.folder(local.id), "share.json").exists())
            assertFalse("and nothing is frozen", d.own.frozen(s.id))
        }
        val w = Worker()
        val d = Device()
        w.fail["create"] = ArrayDeque(listOf(problem(422, "bad_name", "title")))
        val s = made(d)
        val local = d.plays.create(s)
        try { OwnShare.share(w, w, d.plays, local, s, null, d.freezer); fail("shared") } catch (e: PlaysException) { assertEquals("bad_name", e.code) }
        assertEquals("no text was sent and nothing is linked", listOf(0, null), listOf(w.count("put"), d.plays.share(local.id)))
    }

    @Test fun `a disk that will not keep the freeze does not lose the share`() = runBlocking {
        val w = Worker()
        val d = Device()
        val s = made(d)
        val local = d.plays.create(s)
        val sent = OwnShare.share(w, w, d.plays, local, s, null) { throw IOException("full") }
        assertNull(sent.unsent)
        assertEquals(sent.rec.id, d.plays.share(local.id)?.pid)
    }

    // ---- The one resolver ----

    @Test fun `each door asks its own route, and what arrives is the script`() = runBlocking {
        val w = Worker()
        val d = Device()
        val s = shared(w, d)
        val doors = listOf(
            ScriptWho(pid = s.rec.id) to listOf("member", s.rec.id),
            ScriptWho(token = "t:${s.rec.id}", pid = s.rec.id) to listOf("invite", "t:${s.rec.id}"),
            ScriptWho(seat = "key", pid = s.rec.id) to listOf("seat", "key", s.rec.id),
            ScriptWho(room = s.rec.id, key = "mk", pid = s.rec.id) to listOf("room", s.rec.id, "mk"),
        )
        for ((who, call) in doors) {
            val got = ask(w, s.rec, who)
            assertEquals("${call[0]} route", call, w.calls.last())
            assertEquals("the lines", s.script.lines, got.lines)
            assertEquals(listOf(s.script.id, s.script.revision, "own", "A Little Play", "own"), listOf(got.id, got.revision, got.kind, got.title, got.rights.bucket))
            assertNull("the core keeps it", OwnScript.refusalOf(mapOf("id" to got.id, "title" to got.title, "lines" to OwnShare.linesOf(got))))
            assertEquals("and casts it", s.script.castParts.map { it.id }, got.castParts.map { it.id })
            assertEquals("the roles are counted here", s.script.roles, got.roles)
        }
        assertEquals("a catalog id is never asked of an own script's routes", 0, w.count("library"))
    }

    @Test fun `what is here comes first - the production's copy, then the device's script at that revision`() = runBlocking {
        val w = Worker()
        val d = Device()
        val s = shared(w, d)
        val before = w.calls.size
        val copy = resolver(w, d, kept = true).scriptOf(s.rec.scriptID, s.rec.scriptRevision, ScriptWho(pid = s.rec.id))
        assertEquals("the production's", s.script.lines, copy.lines)
        val mine = resolver(w, d).scriptOf(s.rec.scriptID, s.rec.scriptRevision, ScriptWho(pid = s.rec.id))
        assertEquals("the device's", "Added by you", mine.source.name)
        assertEquals("nothing was asked", before, w.calls.size)
        refused("script_damaged", "another revision is not what is here") { resolver(w, d, kept = true).scriptOf(s.rec.scriptID, "000000000000", ScriptWho(pid = s.rec.id)) }
    }

    @Test fun `a script is fetched once a page`() = runBlocking {
        val w = Worker()
        val s = shared(w, Device())
        val r = resolver(w)
        r.scriptOf(s.rec.scriptID, s.rec.scriptRevision, ScriptWho(pid = s.rec.id))
        r.scriptOf(s.rec.scriptID, s.rec.scriptRevision, ScriptWho(pid = s.rec.id))
        assertEquals(1, w.count("member"))
    }

    private fun wireOf(b: ByteArray, meta: String?) = object : ScriptWire {
        override suspend fun putScript(pid: String, text: String) = Unit
        override suspend fun memberScript(pid: String) = ScriptBytes(b, meta)
        override suspend fun inviteScript(token: String) = ScriptBytes(b, meta)
        override suspend fun seatScript(key: String, pid: String) = ScriptBytes(b, meta)
        override suspend fun roomScript(code: String, key: String) = ScriptBytes(b, meta)
    }

    @Test fun `what did not arrive whole is never drawn`() = runBlocking {
        val w = Worker()
        val d = Device()
        val s = shared(w, d)
        val script = s.script
        val whole = String(w.rows[s.rec.id]!!.bytes!!, Charsets.UTF_8)
        fun meta(id: String = script.id, revision: String, title: String = "T") = """{"id":"$id","revision":"$revision","title":"$title","episode_id":null}"""
        suspend fun serve(t: ByteArray, revision: String? = null, m: String? = "", metaId: String = script.id, title: String = "T"): PlayScript {
            val rev = revision ?: sha12(t)
            return OwnShare.Resolver(wireOf(t, if (m == "") meta(metaId, rev, title) else m), { _, _ -> null }).scriptOf(script.id, rev, ScriptWho(pid = s.rec.id))
        }
        suspend fun damaged(name: String, block: suspend () -> Any?) = refused("script_damaged", name, block)
        assertNotNull("control: the text itself is", serve(whole.toByteArray()))
        damaged("cut short") { serve(whole.dropLast(1).toByteArray(), script.revision) }
        damaged("one word changed") { serve(whole.replace("Come in", "Come on").toByteArray(), script.revision) }
        damaged("not canonical") { serve(whole.replace(",", ", ").toByteArray()) }
        damaged("not lines") { serve("""{"lines":[]}""".toByteArray()) }
        damaged("not JSON") { serve("not json".toByteArray()) }
        damaged("not UTF-8") { serve(byteArrayOf(0x5b, 0xff.toByte(), 0x5d)) }
        damaged("a byte order mark") { serve(("﻿" + whole).toByteArray()) }
        damaged("a kind no core knows") { serve(whole.replace("\"kind\":\"speech\"", "\"kind\":\"song\"").toByteArray()) }
        damaged("a line id twice") { serve(whole.replaceFirst("L0002", "L0001").toByteArray()) }
        damaged("no x-script") { serve(whole.toByteArray(), m = null) }
        damaged("another script's name") { serve(whole.toByteArray(), metaId = "own-00000000-0000-4000-8000-000000000000") }
        damaged("another revision's name") { serve(whole.toByteArray(), m = meta(revision = "000000000000")) }
        damaged("no title") { serve(whole.toByteArray(), title = "") }
    }

    @Test fun `the lines match the cast sheet, as each door knows it`() = runBlocking {
        val w = Worker()
        val d = Device()
        val s = shared(w, d)
        val parts = s.script.castParts.map { InvitePart(it.id.raw, it.lineCount) }
        suspend fun at(fit: (PlayScript) -> Boolean) = ask(w, s.rec, ScriptWho(pid = s.rec.id), fit)
        suspend fun damaged(name: String, fit: (PlayScript) -> Boolean) = refused("script_damaged", name) { at(fit) }
        assertNotNull("control: the invite's own parts", at(OwnShare.Fits.invite(parts)))
        damaged("a part the sheet does not have", OwnShare.Fits.invite(parts.drop(1)))
        damaged("a part the lines do not have", OwnShare.Fits.invite(parts + InvitePart("role:ZED", 1)))
        damaged("a part with other lines", OwnShare.Fits.invite(parts.mapIndexed { i, p -> if (i == 0) p.copy(lineCount = p.lineCount + 1) else p }))
        assertNotNull("control: the record's parts", at(OwnShare.Fits.record(s.rec.copy(parts = parts.associate { it.id to SharedPart("open") }))))
        damaged("a record of other parts", OwnShare.Fits.record(s.rec.copy(parts = mapOf("role:ANNA" to SharedPart("open")))))
        damaged("a take of a line it does not have", OwnShare.Fits.record(s.rec.copy(parts = parts.associate { it.id to SharedPart("open") }, takes = listOf(SharedTake("t", "L9999", "role:ANNA", "t.wav")))))
        assertNotNull("control: the room's cursor and claims", at(OwnShare.Fits.room("L0001", listOf("role:BEN"))))
        damaged("a cursor on no line", OwnShare.Fits.room("L9999", emptyList()))
        damaged("a claim of no part", OwnShare.Fits.room("L0001", listOf("role:ZED")))
        assertNotNull("control: the seat's casting", at(OwnShare.Fits.seat(listOf(Triple("role:ANNA", "L0001", null)))))
        damaged("cast to no part", OwnShare.Fits.seat(listOf(Triple("role:ZED", null, null))))
        damaged("cast from no line", OwnShare.Fits.seat(listOf(Triple("role:ANNA", "L9999", null))))
    }

    @Test fun `the Worker's refusals pass through by their codes`() = runBlocking {
        val w = Worker()
        val s = shared(w, Device())
        w.rows[s.rec.id]!!.held = true
        refused("script_removed", "removed") { ask(w, s.rec, ScriptWho(pid = s.rec.id)) }
        w.rows[s.rec.id]!!.held = false
        w.rows[s.rec.id]!!.bytes = null
        refused("no_script", "owed") { ask(w, s.rec, ScriptWho(pid = s.rec.id)) }
    }

    @Test fun `a cast transcript keeps its source - the episode, linked`() = runBlocking {
        val w = Worker()
        val d = Device()
        val s = shared(w, d, made(d).copy(episode = "ep-9"))
        val got = ask(w, s.rec, ScriptWho(pid = s.rec.id))
        assertEquals(listOf("ep-9", PlayScript.Source("Automatic transcript", "https://eardrama.org/episode/ep-9")), listOf(got.episode, got.source))
    }

    @Test fun `a catalog play is the library's at the recorded revision, else the bundle's, else a refusal`() = runBlocking {
        val lib = fixtureScript().copy(revision = "b")
        val r = OwnShare.Resolver(Worker(), { id, rev -> lib.takeIf { it.id == id && it.revision == rev } })
        assertEquals(lib, r.scriptOf("gut-0", "b"))
        refused("revision_mismatch", "none") { r.scriptOf("gut-0", "c") }
    }

    @Test fun `a person who joins keeps the script in their production, and reads it with no Worker`() = runBlocking {
        val w = Worker()
        val d = Device()
        val other = Device()
        val s = shared(w, d)
        val got = ask(w, s.rec, ScriptWho(token = "t:${s.rec.id}", pid = s.rec.id))
        val local = PlaysShare.localFor(other.plays, s.rec.id, got)
        val kept = other.plays.script(local)!!
        assertEquals("kept whole", listOf(s.script.lines, s.script.id, s.script.revision), listOf(kept.lines, local.scriptID, local.scriptRevision))
        w.rows.clear()
        val again = resolver(w, other, kept = true).scriptOf(s.rec.scriptID, s.rec.scriptRevision, ScriptWho(pid = s.rec.id))
        assertEquals("read from the production", s.script.lines, again.lines)
        assertEquals("and it is not one of their own scripts", 0, other.own.list().size)
    }

    // ---- Frozen, and Edit a copy ----

    @Test fun `sharing freezes the script - a change made before reached its productions, none after can`() = runBlocking {
        val w = Worker()
        val d = Device()
        val s = shared(w, d)
        assertTrue("frozen", d.own.frozen(s.script.id))
        val at = d.own.get(s.script.id)!!.shared
        d.own.freeze(s.script.id)
        assertEquals("once", at, d.own.get(s.script.id)!!.shared)
        assertEquals("the same text", s.script.revision, d.own.script(s.script.id)!!.revision)
        d.own.freeze("own-00000000-0000-4000-8000-000000000000")
        assertEquals("a script that is not here is not made", 1, d.own.list().size)
        val row = d.own.exportRows().single()
        assertTrue("Export my data says when it was shared", Regex("^\\d{4}-").containsMatchIn(row["shared"]!!.jsonPrimitive.content))
        val open = d.own.get(s.script.id)!!.copy(shared = null)
        val edited = open.copy(doc = OwnScript.apply(open.doc, OwnOp("words", line = open.doc.lines[0].k, text = "Changed elsewhere.")).doc)
        assertEquals("a page that opened it before may not write over it", "shared", d.own.keep(edited))
        assertEquals(s.script.revision, d.own.script(s.script.id)!!.revision)
        assertTrue(d.own.frozen(s.script.id))
        val plain = made(d, "Another")
        assertFalse("and nothing for one that was not", d.own.exportRows().first { it["id"]!!.jsonPrimitive.content == plain.id }.containsKey("shared"))
    }

    @Test fun `Edit a copy - a new script of the same text, with its own id, no takes, not frozen, its lines' ids kept`() = runBlocking {
        val w = Worker()
        val d = Device()
        val s = shared(w, d)
        val rec = d.own.copy(s.script)
        val copy = d.own.script(rec.id)!!
        assertTrue("a new id", rec.id != s.script.id && OwnScript.isOwnId(rec.id))
        assertEquals(listOf(s.script.lines, s.script.revision, "A Little Play (copy)", null, true), listOf(copy.lines, copy.revision, copy.title, rec.shared, rec.done))
        assertFalse("it can be changed", d.own.frozen(rec.id))
        assertTrue("and the first is still frozen", d.own.frozen(s.script.id))
        val changed = rec.copy(doc = OwnScript.apply(rec.doc, OwnOp("words", line = rec.doc.lines[0].k, text = "Other words.")).doc)
        assertNull(d.own.keep(changed))
        assertTrue("its own text now", d.own.script(rec.id)!!.revision != s.script.revision)
        assertEquals("the first unchanged", s.script.revision, d.own.script(s.script.id)!!.revision)
        assertEquals("a long title stays inside the cap", OwnScript.MAX_TITLE, d.own.copy(s.script.copy(title = "x".repeat(OwnScript.MAX_TITLE))).title.length)
    }

    @Test fun `Edit a copy on a device without the script - from the production's text`() = runBlocking {
        val w = Worker()
        val d = Device()
        val other = Device()
        val s = shared(w, d, made(d).copy(episode = "ep-9", source = PlayScript.Source("Automatic transcript", "u")))
        val got = ask(w, s.rec, ScriptWho(pid = s.rec.id))
        val copy = other.own.script(other.own.copy(got).id)!!
        assertEquals(listOf(s.script.lines, "ep-9", "Automatic transcript"), listOf(copy.lines, copy.episode, copy.source.name))
    }

    // ---- What the record says ----

    @Test fun `the text's state - held when the owner removed it, gone with the account that brought it, whose it is`() {
        fun of(state: String, by: String?) = OwnShare.ownState(SharedRecord("p", "own-x", "r", "t", ownScript = OwnScriptState(state, by)), "me")
        assertNull("a catalog play has none", OwnShare.ownState(SharedRecord("p", "gut-0", "r", "t"), "me"))
        assertEquals(OwnState("kept", held = false, mine = true, by = "me"), of("kept", "me"))
        assertFalse("kept, hers", of("kept", "ann")!!.mine)
        assertTrue("the owner's removal holds it", of("removed", "ann")!!.held)
        assertFalse("with its bringer's account, members go on", of("removed", null)!!.held)
    }

    @Test fun `Publish is absent where the record says so, with the reason`() {
        val script = fixtureScript()
        fun rec(publishable: Boolean = true, id: String = "own-00000000-0000-4000-8000-000000000001") = SharedRecord(
            "p", id, script.revision, "t", parts = mapOf("role:MOLLY" to SharedPart("done", userId = "me"), "role:FIBBER" to SharedPart("done"), "role:DOC" to SharedPart("done")),
            chosen = script.speechLineIDs.associateWith { "t" }, director = "me",
            members = listOf(SharedMember("me", "Me", director = true, performer = true), SharedMember("ann", "Ann", performer = true)), publishable = publishable,
        )
        assertFalse("an own script", PlaysShare.canPublish(rec(false), script, "me"))
        assertTrue("control: a castable one", PlaysShare.canPublish(rec(true), script, "me"))
        assertFalse("no consent is asked for what is never published", PlaysShare.needsMyConsent(rec(false), script, "ann"))
        assertTrue("control", PlaysShare.needsMyConsent(rec(true), script, "ann"))
        assertEquals("This script can’t be published.", OwnShare.neverPublishes(rec(false)))
        assertEquals("This play cannot be published.", OwnShare.neverPublishes(rec(false, "grw-1")))
        assertNull(OwnShare.neverPublishes(rec(true)))
        assertEquals("one line says who can read it", listOf(OwnShare.READERS, OwnShare.CLASS_READERS, OwnShare.MEMBER_READERS), listOf(
            OwnShare.readers(rec().copy(director = "me"), "me"), OwnShare.readers(rec().copy(classId = "c"), "me"), OwnShare.readers(rec(), "ann"),
        ))
    }

    @Test fun `every refusal has its words`() {
        fun said(code: String, detail: String? = null, status: Int = 422) = PlaysShare.line(problem(status, code, detail))
        assertEquals("The title is not allowed.", said("bad_name", "title"))
        assertEquals("The part name ANNA is not allowed.", said("bad_name", "role:ANNA"))
        assertEquals("a person's name, as before", "That name is not allowed.", said("bad_name"))
        assertEquals("You have shared 20 scripts. Delete a production of one first.", said("too_many_scripts", "20"))
        for ((code, words) in listOf(
            "script_too_long" to "This script is too long to share.", "scripts_full" to "Sharing scripts is full.", "script_removed" to "This script was removed.",
            "script_reported" to "This script has been reported.", "script_damaged" to "This script did not arrive whole.", "no_script" to "This script has not been sent yet.",
        )) {
            assertEquals(code, words, said(code))
            assertEquals("$code on a screen with other words", words, OwnShare.scriptLine(problem(422, code)))
        }
        assertEquals("a 503 with a code says the code's", "Sharing scripts is full.", PlaysShare.line(problem(503, "scripts_full")))
        assertEquals("a room's own refusal is the room's", "", OwnShare.scriptLine(problem(403, "room_full")))
        assertEquals("Copyright is first of Report script's reasons", "copyright", OwnShare.SCRIPT_REASONS.first().first)
        val src = File("../worker/src/plays-own.js").takeIf { it.isFile } ?: File("worker/src/plays-own.js")
        if (src.isFile) {
            val codes = Regex("""(?:problem|refuse)\((\d+), "([a-z_]+)"""").findAll(src.readText()).map { it.groupValues[2] }.toSet() - setOf("bad_request", "length_required", "already_there")
            assertTrue("${codes.size} codes read", codes.size > 8)
            for (code in codes) assertTrue("$code has no words", said(code) != said("nothing_like_it"))
        }
    }

    // ---- The class export ----

    @Test fun `the class export gains each kept own script's lines from the teacher's device, and says which did not load`() = runBlocking {
        val w = Worker()
        val d = Device()
        val s = made(d)
        val export = """{"class":{"id":"c"},"productions":[
            {"id":"P1","title":"Mine","script_id":"${s.id}","script_revision":"${s.revision}","script":{"state":"kept"}},
            {"id":"P2","title":"Owed","script_id":"${s.id}","script_revision":"${s.revision}","script":{"state":"owed"}},
            {"id":"P3","title":"Gone","script_id":"own-00000000-0000-4000-8000-000000000009","script_revision":"x","script":{"state":"kept"}},
            {"id":"P4","title":"A catalog play","script_id":"gut-0","script_revision":"r"}]}"""
        val r = resolver(w, d)
        val (text, without) = ClassExport.withLines(export) { pid, id, rev -> r.scriptOf(id, rev, ScriptWho(pid = pid)) }
        val out = ShareJson.parseToJsonElement(text).jsonObject["productions"]!!.jsonArray.map { it.jsonObject }
        assertEquals("only a kept script gains its lines", listOf(true, false, false, false), out.map { (it["script"]?.jsonObject?.containsKey("lines")) == true })
        assertEquals("they are the lines the revision was hashed from", OwnScript.canonicalLines(OwnShare.linesOf(s)), OwnScript.canonicalLines(out[0]["script"]!!.jsonObject["lines"]!!.jsonArray.map { plainOf(it) }))
        assertEquals("and the one that did not load is named", listOf("Gone"), without)
        assertEquals("a text with nothing to add is answered as it came", listOf("""{"productions":[]}""", emptyList<String>()), ClassExport.withLines("""{"productions":[]}""") { _, _, _ -> error("none") }.toList())
    }

    private fun plainOf(e: kotlinx.serialization.json.JsonElement): Any? = when (e) {
        is kotlinx.serialization.json.JsonNull -> null
        is JsonObject -> e.mapValues { plainOf(it.value) }
        is kotlinx.serialization.json.JsonArray -> e.map(::plainOf)
        is JsonPrimitive -> e.content
    }
}
