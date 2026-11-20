package com.example.appname.plays

import com.example.appname.account.WorkerApi
import com.example.appname.account.WorkerException
import io.ktor.http.HttpMethod
import java.io.IOException
import java.net.URLEncoder
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

// The class's side of reading together (Decision 082; docs/WORKER.md "Seats" and "Classes"): a student's seat (no
// account, a key held in memory for the app run) and the teacher's class page (seats, casting, progress). Every call
// goes through the one shared client; the teacher's calls refresh the JWT first.

@Serializable data class ReadSeatList(val `class`: Klass, val seats: List<Seat>) {
    @Serializable data class Klass(val id: String, val name: String)
    @Serializable data class Seat(val id: String, val label: String, val taken: Boolean = false)
}

@Serializable data class ReadSeatClaim(@SerialName("seat_key") val seatKey: String, val seat: String)

@Serializable data class ReadClassDetail(val id: String, val name: String, val code: String? = null, val under13: Boolean = false, val seats: List<Seat> = emptyList()) {
    @Serializable data class Seat(val id: String, val label: String, val claimed: Boolean = false)
}

@Serializable data class ReadProgress(val productions: List<Production> = emptyList()) {
    @Serializable data class Part(val part: String, val lines: Int = 0, val recorded: Int = 0, val approved: Int = 0, val again: Int = 0)
    @Serializable data class SeatRow(val seat: String, val label: String, val parts: List<Part> = emptyList())
    @Serializable data class Production(val id: String, val title: String, val seats: List<SeatRow> = emptyList())
}

@Serializable data class ReadProductionInfo(
    val id: String,
    val scriptID: String,
    val scriptRevision: String,
    val assignments: List<ReadSnapshot.AssignmentRow> = emptyList(),
)

interface ReadClassWire {
    suspend fun seatList(code: String): ReadSeatList
    suspend fun seatClaim(code: String, seat: String, move: Boolean): ReadSeatClaim
    suspend fun detail(id: String): ReadClassDetail
    suspend fun progress(id: String): ReadProgress
    suspend fun production(pid: String): ReadProductionInfo
    suspend fun addSeats(id: String, text: String)
    suspend fun removeSeat(id: String, seat: String)
    suspend fun releaseSeat(id: String, seat: String)
    suspend fun classProduction(id: String, scriptId: String, revision: String, cast: List<Pair<String, String>>): ReadProductionInfo
    suspend fun assign(pid: String, assignments: List<ReadCore.Assignment>): List<ReadCore.Assignment>

    /** The director marks an arrived take of a class production (approved or again, with a typed note a seat alone sees). */
    suspend fun review(pid: String, takeId: String, state: String, note: String?)
    suspend fun consent(): Consent
    suspend fun agree(pid: String, version: String)
    suspend fun publish(pid: String, creditName: String)

    /** One line's chosen take to archive.org through the Worker; `not_ready` and `already_sent` are the Worker's codes. */
    suspend fun sendFile(pid: String, lineId: String, bytes: ByteArray)
}

class WorkerReadClass(private val worker: WorkerApi) : ReadClassWire {
    private val p = "/v1/plays"
    private fun enc(s: String) = URLEncoder.encode(s, "UTF-8").replace("+", "%20")

    private suspend fun <T> guarded(block: suspend () -> T): T = try {
        block()
    } catch (e: CancellationException) {
        throw e
    } catch (e: WorkerException) {
        throw ReadFailure(e.code ?: if (e.status == 429) "rate_limited" else "error")
    } catch (e: IOException) {
        throw ReadFailure("offline")
    } catch (e: com.example.appname.account.SignedOutException) {
        throw ReadFailure("not_configured")
    }

    private fun body(o: JsonObject) = ShareJson.encodeToString(JsonObject.serializer(), o)

    private suspend fun signed(method: HttpMethod, path: String, o: JsonObject? = null): String = guarded { worker.callText(method, path, o?.let(::body)) }
    private suspend fun anon(method: HttpMethod, path: String, o: JsonObject? = null): String = guarded { worker.anonText(method, path, o?.let(::body)) }

    override suspend fun seatList(code: String) = ShareJson.decodeFromString<ReadSeatList>(anon(HttpMethod.Post, "$p/seat/list", buildJsonObject { put("code", code) }))

    override suspend fun seatClaim(code: String, seat: String, move: Boolean) = ShareJson.decodeFromString<ReadSeatClaim>(
        anon(HttpMethod.Post, "$p/seat/claim", buildJsonObject { put("code", code); put("seat", seat); if (move) put("move", true) }),
    )

    override suspend fun detail(id: String) = ShareJson.decodeFromString<ReadClassDetail>(signed(HttpMethod.Get, "$p/classes/${enc(id)}"))

    override suspend fun progress(id: String) = ShareJson.decodeFromString<ReadProgress>(signed(HttpMethod.Get, "$p/classes/${enc(id)}/progress"))

    override suspend fun production(pid: String) = ShareJson.decodeFromString<ReadProductionInfo>(signed(HttpMethod.Get, "$p/productions/${enc(pid)}"))

    override suspend fun addSeats(id: String, text: String) { signed(HttpMethod.Post, "$p/classes/${enc(id)}/seats", buildJsonObject { put("text", text) }) }

    override suspend fun removeSeat(id: String, seat: String) { signed(HttpMethod.Delete, "$p/classes/${enc(id)}/seats/${enc(seat)}") }

    override suspend fun releaseSeat(id: String, seat: String) { signed(HttpMethod.Post, "$p/classes/${enc(id)}/seats/${enc(seat)}/release", JsonObject(emptyMap())) }

    override suspend fun classProduction(id: String, scriptId: String, revision: String, cast: List<Pair<String, String>>): ReadProductionInfo {
        val o = buildJsonObject {
            put("script_id", scriptId)
            put("script_revision", revision)
            put("cast", JsonArray(cast.map { (line, part) -> buildJsonObject { put("id", line); put("part", part) } }))
        }
        return ShareJson.decodeFromString(signed(HttpMethod.Post, "$p/classes/${enc(id)}/productions", o))
    }

    override suspend fun assign(pid: String, assignments: List<ReadCore.Assignment>): List<ReadCore.Assignment> {
        val o = buildJsonObject { put("assignments", ReadClass.toWire(assignments)) }
        val r = ShareJson.decodeFromString<ReadProductionInfo>(signed(HttpMethod.Put, "$p/productions/${enc(pid)}/assignments", o))
        return r.assignments.map { ReadCore.Assignment(it.part, it.seat, it.from, it.to) }
    }

    override suspend fun review(pid: String, takeId: String, state: String, note: String?) {
        signed(HttpMethod.Post, "$p/productions/${enc(pid)}/takes/${enc(takeId)}/review", buildJsonObject { put("state", state); note?.takeIf { it.isNotBlank() }?.let { put("note", it.trim()) } })
    }

    override suspend fun consent(): Consent = ShareJson.decodeFromString(signed(HttpMethod.Get, "$p/consent"))

    override suspend fun agree(pid: String, version: String) { signed(HttpMethod.Post, "$p/productions/${enc(pid)}/consent", buildJsonObject { put("version", version) }) }

    override suspend fun publish(pid: String, creditName: String) { signed(HttpMethod.Post, "$p/productions/${enc(pid)}/publish", buildJsonObject { put("credit_name", creditName) }) }

    override suspend fun sendFile(pid: String, lineId: String, bytes: ByteArray) {
        guarded { worker.callBytes(HttpMethod.Put, "$p/productions/${enc(pid)}/archive/files/${enc(lineId)}", bytes, mapOf("content-type" to "audio/wav")) }
    }
}

object ReadClass {
    /** The casting the Worker takes: a whole part as `{ part, seat }`, a range with its `from` and `to`. */
    fun toWire(assignments: List<ReadCore.Assignment>): JsonArray = JsonArray(
        assignments.map { a ->
            buildJsonObject {
                put("part", a.part)
                put("seat", a.seat)
                if (a.from != null || a.to != null) {
                    put("from", a.from?.let(::JsonPrimitive) ?: JsonNull)
                    put("to", a.to?.let(::JsonPrimitive) ?: JsonNull)
                }
            }
        },
    )

    /** What the casting board needs from a script, computed once: the cast, words per line, scene starts, part facts. */
    class Facts(script: PlayScript) {
        val cast: List<Pair<String, String>> = script.lines.map { it.id to it.part.raw }
        val words: List<Int> = script.lines.map { l -> l.spokenText.split(Regex("\\s+")).count { it.isNotEmpty() } }
        val starts: List<Int> = ScriptReading.sectionsOf(script).filter { it.level != ScriptReading.Level.Part }.map { it.index }
        val facts: List<ReadCore.PartFacts> = ReadCore.partFacts(cast, words, starts).sortedByDescending { it.words }
    }

    /** The body that opens a room: an adult room on a play, or a class room over a production's casting. */
    fun openingBody(script: PlayScript, classId: String? = null, productionId: String? = null, mode: String = "read"): JsonObject = buildJsonObject {
        put("script_id", script.id)
        put("script_revision", script.revision)
        put("mode", mode)
        put("cast", JsonArray(script.lines.map { l -> buildJsonObject { put("id", l.id); put("part", l.part.raw) } }))
        if (classId != null) { put("kind", "class"); put("class_id", classId) }
        if (productionId != null) put("production_id", productionId)
    }
}
