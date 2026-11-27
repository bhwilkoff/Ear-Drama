package com.example.appname.plays

import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.security.MessageDigest
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.put

// Own scripts shared (PLAYS-DESIGN §13 items 11 to 16, docs/WORKER.md "Own scripts"; R4-5): the port of the share half of
// js/plays-share.js. The Worker compares the SHA-256 of what it is sent with the revision and never parses it, so this is where
// a script is shown to be whole before anything is drawn from it. No Android framework.

/** What the Worker answered with for a script: its bytes as they were hashed, and `x-script` as sent. */
class ScriptBytes(val bytes: ByteArray, val meta: String?)

/** The five doors an own script's text comes through, and the one it goes out by. Each reads with its own key. */
interface ScriptWire {
    suspend fun putScript(pid: String, text: String)
    suspend fun memberScript(pid: String): ScriptBytes
    suspend fun inviteScript(token: String): ScriptBytes
    suspend fun seatScript(key: String, pid: String): ScriptBytes
    suspend fun roomScript(code: String, key: String): ScriptBytes
}

/** Who asks, and so which route answers: a member, a holder of an invite, a class's seat, a member of a room. */
data class ScriptWho(val pid: String? = null, val token: String? = null, val seat: String? = null, val room: String? = null, val key: String? = null)

/** A script this device keeps, frozen once shared (the one seam [OwnScripts] gives the share). */
fun interface ScriptFreezer { suspend fun freeze(id: String) }

/** What the record says of the text: the Worker's `own_script`, read for one person. */
data class OwnState(val state: String, val held: Boolean, val mine: Boolean, val by: String?)

/** A production made on the Worker, and why its script has not reached it (null when it has). */
class Sent(val rec: SharedRecord, val unsent: Throwable?)

object OwnShare {
    const val READERS = "Only people you invite can read this script."
    const val CLASS_READERS = "Only this class can read this script."
    const val MEMBER_READERS = "Only people invited can read this script."
    const val CANT_PUBLISH = "This script can’t be published."
    const val NOT_SENT = "The script was not sent."
    const val REPORTED = "Reported. This production is hidden from you."

    fun isOwn(id: String): Boolean = OwnScript.isOwnId(id)

    // ---- The text, as it is hashed and sent ----

    /** [script]'s lines as plain data, the shape the revision was hashed from. */
    fun linesOf(script: PlayScript): List<Map<String, Any?>> = script.lines.map { l ->
        if (l.kind == ScriptLine.Kind.Speech) {
            mapOf(
                "id" to l.id, "kind" to "speech", "role" to l.role,
                "parts" to l.parts.orEmpty().map { p -> mapOf((if (p is LinePart.Say) "say" else "direction") to p.text) },
            )
        } else {
            mapOf("id" to l.id, "kind" to l.kind.name.lowercase(java.util.Locale.ROOT), "source" to l.source.orEmpty())
        }
    }

    /** The bytes `PUT /productions/:pid/script` carries. */
    fun canonical(script: PlayScript): String = OwnScript.canonicalLines(linesOf(script))

    /** What makes a production on the Worker: an own script's carries its title and, for a transcript, its episode. */
    fun makeBody(script: PlayScript, range: ProductionRange? = null, heading: String? = null): JsonObject = buildJsonObject {
        put("script_id", script.id)
        put("script_revision", script.revision)
        put("cast", JsonArray(PlaysShare.castSheet(script.wholeScript).map { (id, part) -> buildJsonObject { put("id", id); put("part", part) } }))
        if (range != null) {
            put("range", buildJsonObject { put("from", range.from); put("to", range.to) })
            if (!heading.isNullOrBlank()) put("heading", heading)
        }
        if (isOwn(script.id)) {
            put("own", true)
            put("title", script.title)
            script.episode?.let { put("episode_id", it) }
        }
    }

    // ---- Sending ----

    /** A refusal that may pass by itself: no answer, the server's own trouble, too many asks, signed out. */
    fun passes(e: Throwable?): Boolean {
        if (e !is PlaysException) return true
        return when (e.kind) {
            PlaysException.Kind.Refused -> e.status >= 500
            else -> true
        }
    }

    /** Sends a production's own script, once. A text already there is the same text. */
    suspend fun sendScript(wire: ScriptWire, pid: String, script: PlayScript) {
        try {
            wire.putScript(pid, canonical(script))
        } catch (e: PlaysException) {
            if (e.code != "already_there") throw e
        }
    }

    /**
     * [sendScript] for a production just made: null, or the error. From here the script is frozen (item 12); one that can
     * never be sent takes its production with it.
     */
    suspend fun sendOrUndo(api: PlaysTransport, wire: ScriptWire, pid: String, script: PlayScript, scripts: ScriptFreezer?): Throwable? {
        suspend fun freeze() { try { scripts?.freeze(script.id) } catch (e: CancellationException) { throw e } catch (_: Exception) { } }
        try {
            sendScript(wire, pid, script)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (!passes(e)) {
                try { api.deleteProduction(pid) } catch (x: CancellationException) { throw x } catch (_: Exception) { }
                return e
            }
            freeze()
            return e
        }
        freeze()
        return null
    }

    /**
     * "Share this production": the Worker makes the record, then an own script's lines follow. A sending that may pass later
     * leaves the production shared and `unsent`; one that never can undoes the share and throws.
     */
    suspend fun share(
        api: PlaysTransport, wire: ScriptWire?, store: ShareStore, local: Production, script: PlayScript, displayName: String?, scripts: ScriptFreezer? = null,
    ): Sent {
        val name = displayName?.trim().orEmpty()
        val body = JsonObject(makeBody(script) + if (name.isNotEmpty()) mapOf("display_name" to JsonPrimitive(name)) else emptyMap())
        val rec = api.create(body)
        store.setShare(local.id, ShareLink(rec.id))
        if (!isOwn(script.id)) return Sent(rec, null)
        val unsent = sendOrUndo(api, wire ?: error("no wire for an own script"), rec.id, script, scripts) ?: return Sent(rec, null)
        if (passes(unsent)) return Sent(rec, unsent)
        store.unshare(local.id)
        throw unsent
    }

    // ---- What the record says ----

    /** The record's own script: null for a catalog play, else its state, with `held` (the owner removed it) and `mine` (this person brought it). */
    fun ownState(rec: SharedRecord?, me: String? = null): OwnState? {
        val s = rec?.ownScript ?: return null
        return OwnState(s.state, held = s.state == "removed" && s.by != null, mine = me != null && s.by == me, by = s.by)
    }

    fun publishable(rec: SharedRecord): Boolean = rec.publishable

    /** Why Publish is absent, in the place it would be; null when it may be offered. */
    fun neverPublishes(rec: SharedRecord): String? =
        if (publishable(rec)) null else if (isOwn(rec.scriptID)) CANT_PUBLISH else "This play cannot be published."

    /** Who can read a shared own script, in the one line that says so. */
    fun readers(rec: SharedRecord, me: String?): String = when {
        rec.classId != null -> CLASS_READERS
        rec.director == me -> READERS
        else -> MEMBER_READERS
    }

    // ---- What each door knows of the cast sheet ----

    private fun sameParts(script: PlayScript, want: List<Pair<String, Int?>>): Boolean {
        // The Worker's cast lists Sound only where its record holds it (B32): the board's part stays local.
        val have = script.castParts.filter { it.id != PartID.SOUND || want.any { (id, _) -> id == PartID.SOUND.raw } }
        return have.size == want.size && want.all { (id, n) -> have.any { it.id.raw == id && (n == null || it.id == PartID.SOUND || it.lineCount == n) } }
    }

    private fun holdsLines(script: PlayScript, ids: List<String?>): Boolean {
        val at = script.lines.map { it.id }.toSet()
        return ids.all { it.isNullOrEmpty() || it in at }
    }

    private fun holdsParts(script: PlayScript, ids: Collection<String>): Boolean {
        val at = script.castParts.map { it.id.raw }.toSet()
        return ids.all { it in at }
    }

    object Fits {
        fun invite(parts: List<InvitePart>): (PlayScript) -> Boolean = { s -> sameParts(s, parts.map { it.id to it.lineCount }) }
        fun record(rec: SharedRecord): (PlayScript) -> Boolean = { s -> sameParts(s, rec.parts.keys.map { it to null }) && holdsLines(s, rec.takes.map { it.lineID }) }
        fun room(cursor: String?, claimed: Collection<String>): (PlayScript) -> Boolean = { s -> holdsLines(s, listOf(cursor)) && holdsParts(s, claimed) }
        fun seat(assignments: List<Triple<String, String?, String?>>): (PlayScript) -> Boolean =
            { s -> holdsParts(s, assignments.map { it.first }) && holdsLines(s, assignments.flatMap { listOf(it.second, it.third) }) }
    }

    // ---- What arrives ----

    private fun damaged(why: String) = PlaysException("script_damaged", PlaysException.Kind.Refused, JsonPrimitive(why))

    private fun plain(e: JsonElement): Any? = when (e) {
        is JsonNull -> null
        is JsonObject -> e.mapValues { plain(it.value) }
        is JsonArray -> e.map(::plain)
        is JsonPrimitive -> when {
            e.isString -> e.content
            e.content == "true" -> true
            e.content == "false" -> false
            else -> e.content.toLongOrNull() ?: e.content.toDouble()
        }
    }

    private fun sha12(bytes: ByteArray): String {
        val d = MessageDigest.getInstance("SHA-256").digest(bytes)
        return d.take(6).joinToString("") { "%02x".format(it.toInt() and 0xff) }
    }

    private fun rolesOf(lines: List<*>): List<Map<String, Any?>> {
        val roles = LinkedHashMap<String, IntArray>()
        for (l in lines) {
            val m = l as Map<*, *>
            if (m["kind"] != "speech") continue
            val c = roles.getOrPut(m["role"] as String) { IntArray(2) }
            c[0] += 1
            for (p in m["parts"] as List<*>) (p as Map<*, *>)["say"]?.let { c[1] += OwnScript.wordsOf(it as String).size }
        }
        return roles.map { (name, c) -> mapOf("name" to name, "lines" to c[0], "words" to c[1]) }
    }

    /**
     * The Worker's bytes as a castable script, or `script_damaged`: their SHA-256 is the revision, they are canonical, the
     * core keeps them, and they match the cast sheet ([fit]).
     */
    fun arrived(got: ScriptBytes, id: String, revision: String, fit: (PlayScript) -> Boolean, link: (String) -> String): PlayScript {
        if (sha12(got.bytes) != revision) throw damaged("digest")
        val lines: List<*>
        try {
            val text = Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(got.bytes)).toString()
            val parsed = plain(ShareJson.parseToJsonElement(text)) as? List<*> ?: throw damaged("text")
            if (OwnScript.canonicalLines(parsed) != text) throw damaged("text")
            lines = parsed
        } catch (e: PlaysException) {
            throw e
        } catch (e: Exception) {
            throw damaged("text")
        }
        val meta = try { got.meta?.let { ShareJson.parseToJsonElement(it) as? JsonObject } } catch (e: Exception) { null }
        fun field(k: String) = (meta?.get(k) as? JsonPrimitive)?.takeIf { it.isString }?.content
        val title = field("title")
        if (meta == null || field("id") != id || field("revision") != revision || title == null) throw damaged("names")
        val episode = field("episode_id")?.takeIf { it.isNotEmpty() }
        val map = buildMap<String, Any?> {
            put("id", id); put("revision", revision); put("kind", "own"); put("title", title); put("authors", emptyList<Any?>())
            put("source", if (episode != null) mapOf("name" to "Automatic transcript", "url" to link(episode)) else mapOf("name" to "Shared script", "url" to ""))
            if (episode != null) put("episode", episode)
            put("rights", mapOf("bucket" to "own", "evidence" to emptyList<Any?>()))
            put("roles", rolesOf(lines))
            put("lines", lines)
        }
        OwnScript.refusalOf(map)?.let { throw damaged(it) }
        val script = try {
            ProductionStore.json.decodeFromJsonElement(PlayScript.serializer(), OwnScripts.element(map))
        } catch (e: Exception) {
            throw damaged("shape")
        }
        if (!fit(script)) throw damaged("cast sheet")
        return script
    }

    private suspend fun readAs(wire: ScriptWire, who: ScriptWho): ScriptBytes = when {
        who.token != null -> wire.inviteScript(who.token)
        who.seat != null -> wire.seatScript(who.seat, who.pid ?: throw PlaysException("not_found"))
        who.room != null -> wire.roomScript(who.room, who.key ?: throw PlaysException("not_found"))
        else -> wire.memberScript(who.pid ?: throw PlaysException("not_found"))
    }

    /**
     * The one way every screen gets "the script of this production, invite, seat or room" (item 11). A catalog play is the
     * library's at [revision], else the bundle's. An own script is this device's copy in the production, this device's script
     * at that revision, then the Worker's, drawn only once it is shown to be whole. Throws with the Worker's code,
     * `revision_mismatch` or `script_damaged`; what it answers is never null.
     */
    class Resolver(
        private val wire: ScriptWire,
        /** A catalog play at a revision: the library's, else the bundle's; null when neither has it. */
        private val catalog: suspend (id: String, revision: String) -> PlayScript?,
        /** The copy kept in a shared production's folder, by its Worker id. */
        private val kept: suspend (pid: String) -> PlayScript? = { null },
        /** This device's own script, by id. */
        private val device: suspend (id: String) -> PlayScript? = { null },
        private val link: (String) -> String = { "https://eardrama.org/episode/$it" },
    ) {
        private val fetched = HashMap<String, PlayScript>()

        fun forget() { fetched.clear() }

        suspend fun scriptOf(id: String, revision: String, who: ScriptWho = ScriptWho(), fit: (PlayScript) -> Boolean = { true }): PlayScript {
            if (!isOwn(id)) return catalog(id, revision) ?: throw PlaysException("revision_mismatch")
            who.pid?.let { pid -> kept(pid)?.takeIf { it.id == id && it.revision == revision }?.let { return it } }
            device(id)?.takeIf { it.revision == revision }?.let { return it }
            val key = "$id@$revision"
            fetched[key]?.takeIf(fit)?.let { return it }
            val script = arrived(readAs(wire, who), id, revision, fit, link)
            fetched[key] = script
            return script
        }
    }

    // ---- The words ----

    private val SCRIPT_CODES = setOf(
        "script_too_long", "too_many_scripts", "scripts_full", "script_removed", "script_reported", "script_damaged", "no_script",
        "bad_script_id", "revision_mismatch", "script_not_publishable", "not_on_device", "needs_account",
    )

    /** The refusals an own script's sharing can meet, for screens whose other words are another's; "" for any other. */
    fun scriptLine(err: Throwable?): String {
        val e = err as? PlaysException ?: return ""
        return if (e.code in SCRIPT_CODES || (e.code == "bad_name" && e.detail != null)) PlaysShare.line(e) else ""
    }

    /** Whether Report script offers these, with Copyright first. */
    val SCRIPT_REASONS = listOf("copyright" to "Copyright") + listOf(
        "offensive" to "Offensive", "harassment" to "Harassment", "personal_information" to "Personal information",
        "not_a_performance" to "Not a performance", "other" to "Other",
    )

    /** `detail` of a `bad_name` or a `too_many_scripts` refusal, as text. */
    internal fun detailText(e: PlaysException): String = (e.detail as? JsonPrimitive)?.contentOrNull.orEmpty()
}
