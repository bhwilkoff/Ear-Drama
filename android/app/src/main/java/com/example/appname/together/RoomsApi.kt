package com.example.appname.together

import io.ktor.client.HttpClient
import io.ktor.client.request.header
import io.ktor.client.request.request
import io.ktor.client.request.setBody
import io.ktor.client.statement.HttpResponse
import io.ktor.client.statement.bodyAsText
import io.ktor.http.ContentType
import io.ktor.http.HttpMethod
import io.ktor.http.content.TextContent
import io.ktor.http.isSuccess
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/** A refusal from the Worker (`{ error }`), or [status] 0 when it could not be reached. */
class RoomException(val status: Int, val error: String?) : Exception("room: $status ${error.orEmpty()}")

/** A room entered by create or join: the snapshot and this member's key, returned once. */
class Entered(val snapshot: RoomSnapshot, val key: String)

/**
 * Listen Together's transport: the Worker's `/v1/rooms` (docs/WORKER.md) on
 * the app's one Ktor client ([com.example.appname.data.ApiClient.client]).
 * It holds no rule; `RoomProtocol` does. No account: a room takes no bearer
 * token, only the member key as `x-room-key` (Decision 065). While the
 * Worker URL is a `REPLACE_WITH` placeholder [available] is false and
 * nothing is sent.
 */
class RoomsApi(
    private val http: HttpClient,
    private val baseUrl: String,
    private val now: () -> Long = System::currentTimeMillis,
) {
    val available: Boolean get() = baseUrl.isNotBlank() && !baseUrl.startsWith("REPLACE_WITH")

    /** `POST /v1/rooms`: the creator is host. */
    suspend fun create(state: RoomState): Entered =
        entered(send(HttpMethod.Post, "/v1/rooms", body = json.encodeToString(CreateBody(WireState.of(state)))))

    /** `POST /v1/rooms/{code}/join`: the code is the whole invitation. */
    suspend fun join(code: String): Entered = entered(send(HttpMethod.Post, "/v1/rooms/$code/join"))

    /** `GET /v1/rooms/{code}`, with the round trip as a clock sample. */
    suspend fun read(code: String, key: String): Pair<RoomSnapshot, ClockSample> {
        val t0 = now()
        val text = ok(send(HttpMethod.Get, "/v1/rooms/$code", key))
        val t1 = now()
        val snapshot = json.decodeFromString<WireSnapshot>(text).toSnapshot()
        return snapshot to ClockSample(t0, snapshot.serverTime, t1)
    }

    /** `PUT /v1/rooms/{code}/state`: the host's whole state; a guest's key is refused (`403 host_only`). */
    suspend fun putState(code: String, key: String, state: RoomState): RoomSnapshot {
        val body = json.encodeToString(WireState.of(state).copy(updatedAt = null))
        return json.decodeFromString<WireSnapshot>(ok(send(HttpMethod.Put, "/v1/rooms/$code/state", key, body))).toSnapshot()
    }

    /** `POST /v1/rooms/{code}/leave`; true when leaving ended the room. */
    suspend fun leave(code: String, key: String): Boolean =
        json.decodeFromString<LeaveAnswer>(ok(send(HttpMethod.Post, "/v1/rooms/$code/leave", key))).roomEnded

    /** `DELETE /v1/rooms/{code}`: the host ends the room for everyone. */
    suspend fun end(code: String, key: String) {
        ok(send(HttpMethod.Delete, "/v1/rooms/$code", key))
    }

    private suspend fun entered(response: HttpResponse): Entered {
        val wire = json.decodeFromString<WireSnapshot>(ok(response))
        return Entered(wire.toSnapshot(), wire.memberKey ?: throw RoomException(response.status.value, "no_key"))
    }

    private suspend fun send(method: HttpMethod, path: String, key: String? = null, body: String? = null): HttpResponse {
        if (!available) throw RoomException(0, "not_available")
        return try {
            http.request(baseUrl.trimEnd('/') + path) {
                this.method = method
                key?.let { header(KEY_HEADER, it) }
                if (body != null) setBody(TextContent(body, ContentType.Application.Json))
            }
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: Exception) {
            throw RoomException(0, e.javaClass.simpleName)
        }
    }

    private suspend fun ok(response: HttpResponse): String {
        val text = response.bodyAsText()
        if (response.status.isSuccess()) return text
        val problem = runCatching { json.decodeFromString<WireProblem>(text) }.getOrNull()
        throw RoomException(response.status.value, problem?.error)
    }

    companion object {
        const val KEY_HEADER = "x-room-key"
        private val json = Json {
            ignoreUnknownKeys = true
            encodeDefaults = false
            explicitNulls = false
        }
    }
}

@Serializable
private data class CreateBody(val state: WireState)

@Serializable
internal data class WireState(
    @SerialName("episode_id") val episodeId: String,
    @SerialName("archive_id") val archiveId: String,
    val file: String,
    val position: Double,
    val playing: Boolean,
    val rate: Double,
    @SerialName("updated_at") val updatedAt: Long? = null,
) {
    fun toState() = RoomState(episodeId, archiveId, file, position, playing, rate, updatedAt ?: 0)

    companion object {
        fun of(s: RoomState) = WireState(s.episodeId, s.archiveId, s.file, s.position, s.playing, s.rate)
    }
}

@Serializable
internal data class WireSnapshot(
    val code: String,
    val role: String,
    val members: Int,
    val generation: Long,
    val state: WireState,
    @SerialName("server_time") val serverTime: Long,
    @SerialName("member_key") val memberKey: String? = null,
) {
    fun toSnapshot() = RoomSnapshot(code, role == "host", members, generation, state.toState(), serverTime)
}

@Serializable
private data class LeaveAnswer(@SerialName("room_ended") val roomEnded: Boolean = false)

@Serializable
private data class WireProblem(val error: String? = null)
