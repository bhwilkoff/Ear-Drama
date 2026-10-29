package com.example.appname.plays

import kotlinx.coroutines.CancellationException
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.put

// Shared plays, phase 2 (LOOP-PLAN M8, PLAYS-DESIGN §11.7, ANDROID-DESIGN §4.16):
// a production on this device, linked to its record on the Worker. No Android
// framework: ported from js/plays-share.js (and Apple's twin), run against a
// fake transport in PlaysShareTest. The Worker is the arbiter (C7): who holds
// which part, which take is chosen. Nothing here decides a claim; it asks and
// shows the answer.

val ShareJson = Json { ignoreUnknownKeys = true; encodeDefaults = false; explicitNulls = false }

/** `share.json` beside `production.json`: the Worker's id for this production and the consent version agreed to. */
@Serializable
data class ShareLink(val pid: String, val consented: String? = null)

@Serializable
data class SharedPart(
    val status: String = "open",
    val performer: String? = null,
    @SerialName("user_id") val userId: String? = null,
    @SerialName("claim_expires_at") val claimExpiresAt: Long? = null,
)

@Serializable
data class SharedTake(
    val id: String,
    val lineID: String,
    val part: String,
    val file: String,
    val created: Double = 0.0,
    val frames: Int = 0,
    val sampleRate: Double = 48_000.0,
    val capture: String = "direct",
    val heard: Map<String, String> = emptyMap(),
    val loudness: Double? = null,
    val peak: Float = 0f,
    val bleed: Boolean = false,
    @SerialName("user_id") val userId: String? = null,
)

@Serializable
data class SharedMember(
    @SerialName("user_id") val userId: String,
    @SerialName("display_name") val displayName: String? = null,
    val director: Boolean = false,
)

@Serializable
data class SharedArchive(val status: String = "", @SerialName("created_at") val createdAt: Long = 0)

/** The Worker's record (docs/WORKER.md, "The record"): production.json's fields plus the Worker's own. */
@Serializable
data class SharedRecord(
    val id: String,
    val scriptID: String,
    val scriptRevision: String,
    val title: String,
    val created: Double = 0.0,
    val parts: Map<String, SharedPart> = emptyMap(),
    val takes: List<SharedTake> = emptyList(),
    val chosen: Map<String, String> = emptyMap(),
    val director: String? = null,
    val members: List<SharedMember> = emptyList(),
    val next: String? = null,
    @SerialName("hidden_takes") val hiddenTakes: Int = 0,
    val archive: SharedArchive? = null,
    /** The owner's R2 switch (P1): false means uploads are off. */
    val uploads: Boolean = true,
)

/** `GET /consent`: the owner's words, shown as they arrive. */
@Serializable
data class Consent(val version: String, val text: String, val uploads: Boolean = true, val publishes: Boolean = false)

@Serializable
data class InviteMade(val id: String, val token: String, @SerialName("expires_at") val expiresAt: Long)

@Serializable
data class InvitePart(val id: String, val lineCount: Int = 0, val status: String = "open")

/** `POST /invites/view`: the cast sheet an invitation shows. */
@Serializable
data class InviteView(
    val id: String,
    val scriptID: String,
    val scriptRevision: String,
    val title: String,
    val parts: List<InvitePart> = emptyList(),
    val next: String? = null,
    val member: Boolean = false,
)

/** `GET /productions`: a shared production this person is in. */
@Serializable
data class RemoteRow(
    val id: String,
    val title: String,
    @SerialName("script_id") val scriptId: String = "",
    val director: String? = null,
    @SerialName("updated_at") val updatedAt: Long = 0,
)

@Serializable
data class ClassRow(
    val id: String,
    val name: String,
    val code: String? = null,
    val under13: Boolean = false,
    @SerialName("school_consent") val schoolConsent: Boolean = false,
)

@Serializable
data class ClassesAnswer(val teaching: List<ClassRow> = emptyList(), @SerialName("member_of") val memberOf: List<ClassRow> = emptyList())

@Serializable
data class PublishAnswer(val status: String = "")

/** A Worker refusal or a failure to reach it. [code] is the Worker's `error`; [detail] its `detail`, as sent. */
class PlaysException(
    val code: String,
    val kind: Kind = Kind.Refused,
    val detail: JsonElement? = null,
) : Exception("plays: $kind $code") {
    enum class Kind { Refused, RateLimited, Offline, NotConfigured, Unauthorized, Other }
}

/** Every Worker call the apps make for shared plays; `PlaysApi` is the Ktor one, tests bring a fake. */
interface PlaysTransport {
    suspend fun consent(): Consent
    suspend fun create(body: JsonObject): SharedRecord
    suspend fun list(): List<RemoteRow>
    suspend fun get(pid: String): SharedRecord
    suspend fun invite(pid: String): InviteMade
    suspend fun viewInvite(token: String): InviteView
    suspend fun joinByInvite(token: String, part: String, displayName: String?): SharedRecord
    suspend fun claim(pid: String, part: String): SharedRecord
    suspend fun partAction(pid: String, part: String, action: String): SharedRecord
    suspend fun agree(pid: String, version: String)
    suspend fun upload(pid: String, takeId: String, bytes: ByteArray, meta: JsonObject)
    suspend fun audio(pid: String, takeId: String): ByteArray
    suspend fun choose(pid: String, takeId: String): SharedRecord
    suspend fun publish(pid: String): PublishAnswer
    suspend fun report(pid: String, takeId: String?, userId: String?, reason: String, note: String?)
    suspend fun block(userId: String)
    suspend fun classes(): ClassesAnswer
    suspend fun classDetail(id: String): ClassRow
    suspend fun createClass(name: String, under13: Boolean): ClassRow
    suspend fun joinClass(code: String, displayName: String?): ClassRow
}

/** What `PlaysShare` needs of the productions on this device; `ProductionStore` is the real one. */
interface ShareStore {
    fun all(): List<Production>
    fun production(id: String): Production?
    fun save(production: Production)
    fun create(script: PlayScript): Production
    fun share(id: String): ShareLink?
    fun setShare(id: String, link: ShareLink)
    fun findShared(pid: String): Production?
    fun readTake(id: String, file: String): ByteArray

    /** Another member's take as its audio arrived; a file that exists is never overwritten. */
    fun importTake(id: String, file: String, bytes: ByteArray)
}

object PlaysShare {
    const val DAY_MS = 86_400_000L
    private const val FOUNDATION_OFFSET_S = 978_307_200.0

    /** The cast sheet the Worker checks against its manifest: every line in script order. */
    fun castSheet(script: PlayScript): List<Pair<String, String>> = script.lines.map { it.id to it.part.raw }

    fun isMine(rec: SharedRecord, part: String, me: String?): Boolean {
        val s = rec.parts[part] ?: return false
        return s.status == "recording" && me != null && s.userId == me
    }

    fun recordingPart(rec: SharedRecord): String? = rec.parts.entries.firstOrNull { it.value.status == "recording" }?.key

    fun myParts(rec: SharedRecord, me: String?): List<String> = rec.parts.keys.filter { isMine(rec, it, me) }

    /** The owner's switch (Decision 066, P1): false until the take store exists. */
    fun uploadsOpen(rec: SharedRecord?): Boolean = rec != null && rec.uploads

    /** Any open part may be taken while no part records (C7). */
    fun canClaim(rec: SharedRecord, part: String): Boolean =
        recordingPart(rec) == null && (rec.parts[part]?.status ?: "open") == "open"

    /** Speaking lines with no chosen take this person can see. */
    fun unvoiced(rec: SharedRecord, script: PlayScript): List<String> = script.speechLineIDs.filter { it !in rec.chosen }

    fun complete(rec: SharedRecord, script: PlayScript): Boolean =
        recordingPart(rec) == null &&
            rec.parts.values.all { it.status == "done" || it.status == "silent" } &&
            unvoiced(rec, script).isEmpty()

    fun isDirector(rec: SharedRecord, me: String?): Boolean = me != null && rec.director == me

    /** The one line shown while the Worker cannot upload to archive.org (P6). */
    const val PUBLISH_WAITS = "Publishing opens when the Ear Drama archive account is connected."

    /** Publish for the director of a complete play (rule 9). Whether the Worker can upload is [Consent.publishes]. */
    fun canPublish(rec: SharedRecord, script: PlayScript, me: String?): Boolean =
        isDirector(rec, me) && rec.archive == null && complete(rec, script)

    /**
     * The local record follows the Worker's parts: only this person's live claim
     * records here (so the phase 1 recorder opens for it); done and silent come
     * across with the performer's name; anyone else's claim is open here.
     */
    fun mirror(local: Production, rec: SharedRecord, me: String?): Production {
        val parts = rec.parts.entries.associate { (id, s) ->
            val status = when (s.status) {
                "recording" -> if (me != null && s.userId == me) PartState.Status.Recording else PartState.Status.Open
                "done" -> PartState.Status.Done
                "silent" -> PartState.Status.Silent
                else -> PartState.Status.Open
            }
            val performer = s.performer?.takeIf { status != PartState.Status.Open }
            PartID(id) to PartState(status, performer)
        }
        return local.copy(parts = parts)
    }

    fun follow(store: ShareStore, localId: String, rec: SharedRecord, me: String?): Production? {
        val local = store.production(localId) ?: return null
        val next = mirror(local, rec, me)
        if (next != local) store.save(next)
        return next
    }

    private fun candidates(local: Production, script: PlayScript, rec: SharedRecord, me: String?): List<Take> {
        val onServer = rec.takes.map { it.id }.toSet()
        val out = LinkedHashMap<String, Take>()
        for (part in myParts(rec, me)) {
            for (l in script.lines(PartID(part))) {
                val t = local.chosenTake(l.id)
                if (t != null && t.id !in onServer) out[t.id] = t
            }
        }
        return out.values.toList()
    }

    /** The chosen take of each line of a part this person holds that the Worker lacks, never a flagged one (§5). */
    fun pending(local: Production, script: PlayScript, rec: SharedRecord, me: String?): List<Take> =
        candidates(local, script, rec, me).filter { !it.bleed }

    /** Chosen takes the bleed check flagged: kept on the device, never sent, to be re-taken. */
    fun flaggedPending(local: Production, script: PlayScript, rec: SharedRecord, me: String?): Int =
        candidates(local, script, rec, me).count { it.bleed }

    /** The take's fields as the Worker reads them from `x-take` (docs/WORKER.md). */
    fun metaOf(t: Take): JsonObject = buildJsonObject {
        put("lineID", t.lineID)
        put("part", t.part.raw)
        put("file", t.file)
        put("created", t.created)
        put("frames", t.frames)
        put("sampleRate", t.sampleRate)
        put("capture", if (t.capture == Take.Capture.Aec) "aec" else "direct")
        put("heard", JsonObject(t.heard.mapValues { JsonPrimitive(it.value) }))
        put("peak", t.peak.toDouble())
        put("bleed", t.bleed)
        t.loudness?.takeIf { it.isFinite() }?.let { put("loudness", it) }
    }

    enum class Stop { UploadsOff }

    data class UploadResult(val sent: Int, val flagged: Int, val stopped: Stop? = null, val error: Exception? = null)

    /**
     * Uploads this person's pending takes to the members. No consent is asked
     * (Decision 072): `GET /consent` is read only for the owner's switch, first,
     * so a closed store never reaches the upload endpoint.
     */
    suspend fun upload(
        api: PlaysTransport,
        store: ShareStore,
        local: Production,
        script: PlayScript,
        rec: SharedRecord,
        me: String?,
    ): UploadResult {
        val link = store.share(local.id) ?: return UploadResult(0, 0, error = PlaysException("not_found"))
        val flagged = flaggedPending(local, script, rec, me)
        val send = pending(local, script, rec, me)
        var sent = 0
        if (send.isEmpty()) return UploadResult(sent, flagged)
        if (!uploadsOpen(rec)) return UploadResult(sent, flagged, Stop.UploadsOff)
        try {
            val consent = api.consent()
            if (!consent.uploads) return UploadResult(sent, flagged, Stop.UploadsOff)
            for (t in send) {
                val bytes = store.readTake(local.id, t.file)
                try {
                    api.upload(link.pid, t.id, bytes, metaOf(t))
                    sent++
                } catch (e: PlaysException) {
                    if (e.code == "take_exists") continue
                    throw e
                }
            }
            // The person's own choice of take wins on the Worker too.
            val fresh = api.get(link.pid)
            for (part in myParts(fresh, me)) {
                for (l in script.lines(PartID(part))) {
                    val mine = local.chosen[l.id] ?: continue
                    if (fresh.chosen[l.id] != mine && fresh.takes.any { it.id == mine }) api.choose(link.pid, mine)
                }
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            return UploadResult(sent, flagged, error = e)
        }
        return UploadResult(sent, flagged)
    }

    /**
     * The Worker's chosen takes, with this person's own pick kept on each line
     * of a part they hold: their choice of take wins on the Worker too.
     */
    fun mergedChosen(local: Production, script: PlayScript, rec: SharedRecord, me: String?): Map<String, String> {
        val out = rec.chosen.toMutableMap()
        for (part in myParts(rec, me)) {
            for (l in script.lines(PartID(part))) local.chosen[l.id]?.let { out[l.id] = it }
        }
        return out
    }

    /** Chosen takes the Worker shows this person that this device does not hold yet. */
    fun missingHere(local: Production, rec: SharedRecord): List<String> {
        val have = local.takes.map { it.id }.toSet()
        return rec.chosen.values.filter { it !in have && rec.takes.any { t -> t.id == it } }
    }

    /** True when this device already holds and plays exactly what the Worker shows. */
    fun inStep(local: Production, script: PlayScript, rec: SharedRecord, me: String?): Boolean =
        missingHere(local, rec).isEmpty() && mergedChosen(local, script, rec, me) == local.chosen

    /**
     * Brings the chosen takes of the other members into this device, so the
     * phase 1 listen-through can play the whole play. Only takes the Worker
     * shows this person arrive (blocked and reported ones never do).
     */
    suspend fun bringHome(api: PlaysTransport, store: ShareStore, localId: String, rec: SharedRecord, script: PlayScript, me: String?): Int {
        val local = store.production(localId) ?: return 0
        val add = mutableListOf<Take>()
        for (takeId in missingHere(local, rec)) {
            val t = rec.takes.first { it.id == takeId }
            val file = "m-$takeId.wav"
            store.importTake(localId, file, api.audio(rec.id, takeId))
            add += Take(
                id = t.id, lineID = t.lineID, part = PartID(t.part), file = file, created = t.created, frames = t.frames,
                sampleRate = t.sampleRate,
                capture = if (t.capture == "aec") Take.Capture.Aec else Take.Capture.Direct,
                heard = t.heard, loudness = t.loudness, peak = t.peak, bleed = false,
            )
        }
        val withTakes = local.copy(takes = local.takes + add)
        val chosen = mergedChosen(withTakes, script, rec, me)
        store.save(withTakes.copy(chosen = chosen, listenedThrough = withTakes.listenedThrough && chosen == local.chosen))
        return add.size
    }

    /** "Share": the Worker makes the record; the caller directs it. */
    suspend fun share(api: PlaysTransport, store: ShareStore, local: Production, script: PlayScript, displayName: String?): SharedRecord {
        val name = displayName?.trim().orEmpty()
        val body = buildJsonObject {
            put("script_id", script.id)
            put("script_revision", script.revision)
            put("cast", JsonArray(castSheet(script).map { (id, part) -> buildJsonObject { put("id", id); put("part", part) } }))
            if (name.isNotEmpty()) put("display_name", name)
        }
        val rec = api.create(body)
        store.setShare(local.id, ShareLink(rec.id))
        return rec
    }

    /** The production on this device for a shared one, made from the bundle's script on first open. */
    fun localFor(store: ShareStore, pid: String, script: PlayScript?): Production {
        store.findShared(pid)?.let { return it }
        script ?: throw PlaysException("revision_mismatch")
        val local = store.create(script)
        store.setShare(local.id, ShareLink(pid))
        return local
    }

    /** The bundle's script for a shared production, only at the revision it was cast from. */
    fun scriptFor(scripts: List<PlayScript>, scriptID: String, revision: String): PlayScript? =
        scripts.firstOrNull { it.id == scriptID && it.revision == revision }

    data class Joined(val rec: SharedRecord, val local: Production)

    /** Joins by an invite and claims [part]; makes the production on this device on the first join. */
    suspend fun join(
        api: PlaysTransport,
        store: ShareStore,
        token: String,
        part: String,
        displayName: String?,
        script: PlayScript?,
    ): Joined {
        val rec = api.joinByInvite(token, part, displayName?.trim()?.takeIf { it.isNotEmpty() })
        return Joined(rec, localFor(store, rec.id, script))
    }

    data class LibraryRow(val local: Production?, val pid: String?, val remote: RemoteRow? = null)

    /**
     * Library's Ear dramas (Decision 068): this device's productions, then the
     * shared ones this person is in that this device has not opened yet, newest first.
     */
    fun libraryRows(store: ShareStore, remote: List<RemoteRow>?): List<LibraryRow> {
        val rows = store.all().map { LibraryRow(it, store.share(it.id)?.pid) }.toMutableList()
        val here = rows.mapNotNull { it.pid }.toSet()
        for (r in remote.orEmpty()) if (r.id !in here) rows += LibraryRow(null, r.id, r)
        fun whenOf(r: LibraryRow): Double = r.local?.let { it.created + FOUNDATION_OFFSET_S } ?: ((r.remote?.updatedAt ?: 0) / 1000.0)
        return rows.sortedByDescending(::whenOf)
    }

    // Invite links (DEEP_LINKS.md): the token rides the fragment, so it never reaches a server log.

    /** `https://eardrama.org/invite#{token}`, the twin of `eardrama://invite#{token}`. */
    fun inviteLink(token: String, origin: String = "https://eardrama.org"): String = "${origin.trimEnd('/')}/invite#$token"

    private val TOKEN = Regex("^[A-Za-z0-9_-]{43}$")

    fun isToken(text: String?): Boolean = text != null && TOKEN.matches(text)

    /** "Works for N days.", rounded to the nearest day (at least 1). */
    fun worksFor(expiresAt: Long, now: Long): String {
        val days = Math.round((expiresAt - now).toDouble() / DAY_MS).coerceAtLeast(1)
        return if (days == 1L) "Works for 1 day." else "Works for $days days."
    }

    /**
     * The token from `/invite#{token}` (path "/invite", fragment the token), or
     * from the `#invite={token}` the 404 forwarder leaves on the web's root.
     */
    fun inviteToken(path: String, fragment: String): String? {
        val hash = fragment.removePrefix("#")
        hash.split('&').firstOrNull { it.substringBefore('=') == "invite" }
            ?.substringAfter('=', "")?.takeIf { isToken(it) }?.let { return it }
        if (Regex("(^|/)invite/?$").containsMatchIn(path) && isToken(hash)) return hash
        return null
    }

    /** A class code as its teacher reads it out: two groups of four. */
    fun classCodeDisplay(code: String): String {
        val c = classCodeNormalize(code)
        return if (c.length == 8) c.substring(0, 4) + " " + c.substring(4) else c
    }

    fun classCodeNormalize(input: String): String = input.filter { it.isLetterOrDigit() }.uppercase()

    // One plain line for each refusal (AGENTS.md: a refusal, a warning, or a fact).

    private val LINES = mapOf(
        "storage_not_configured" to "Uploads are off.",
        "uploads_off" to "Uploads are off.",
        "not_open" to "This part is taken.",
        "no_such_part" to "This part is not in the play.",
        "line_is_another_part" to "This part is not yours to record.",
        "unsupported_audio" to "A take could not be read.",
        "audio_mismatch" to "A take could not be read.",
        "bleed_flagged" to "A take holds the device voice. Re-take it with headphones.",
        "publish_waits" to PUBLISH_WAITS,
        "consent_version_mismatch" to "The consent changed. Read it again.",
        "not_your_claim" to "This part is not yours to record.",
        "not_your_part" to "Only its performer or the director can open this part.",
        "speaking_part_needs_a_voice" to "A speaking part needs a voice.",
        "not_finished" to "This part is not finished.",
        "invite_not_found" to "This invite does not work.",
        "not_found" to "This production is not shared with you.",
        "no_such_take" to "This take is not available.",
        "incomplete" to "Every part must be done or left silent first.",
        "reported_take" to "A chosen take has been reported.",
        "consent_missing" to "Not every performer has agreed to the consent.",
        "school_consent_required" to "This class needs its school's consent before anyone can join.",
        "class_not_found" to "No class has that code.",
        "you_teach_this_class" to "You teach this class.",
        "revision_mismatch" to "This play has changed since it was cast.",
        "not_castable" to "This play cannot be shared.",
        "cast_mismatch" to "This play cannot be shared.",
        "production_full" to "This production is full.",
        "too_many_productions" to "You have too many shared productions.",
        "too_many_takes" to "This line has too many takes.",
        "take_too_long" to "A take is too long.",
        "too_large" to "A take is too long.",
        "director_only" to "Only the director can do that.",
        "name_too_long" to "That name is too long.",
        "name_has_link" to "A name cannot hold a link.",
        "name_not_allowed" to "That name is not allowed.",
        "name_reserved" to "That name is not allowed.",
        "bad_name" to "That name is not allowed.",
        "rate_limited" to "Too many tries. Try again in a minute.",
    )

    fun line(err: Throwable?): String {
        if (err == null) return ""
        if (err !is PlaysException) return "Ear Drama could not be reached."
        val detail = err.detail
        if (err.code == "another_part_is_recording") {
            val part = (detail as? JsonPrimitive)?.contentOrNull.orEmpty()
            return "${PartID(part).title} is still recording."
        }
        if (err.code == "lines_missing") {
            val n = (detail as? JsonArray)?.size ?: 0
            return if (n == 1) "1 line still needs a take." else "$n lines still need a take."
        }
        LINES[err.code]?.let { return it }
        return when (err.kind) {
            PlaysException.Kind.RateLimited -> LINES.getValue("rate_limited")
            PlaysException.Kind.Offline -> "You are offline."
            PlaysException.Kind.NotConfigured -> "Not available yet."
            PlaysException.Kind.Unauthorized -> "Sign in again."
            else -> "Ear Drama could not be reached."
        }
    }
}
