package com.example.appname.together

import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.MockRequestHandleScope
import io.ktor.client.engine.mock.respond
import io.ktor.client.request.HttpRequestData
import io.ktor.client.request.HttpResponseData
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.content.TextContent
import io.ktor.http.headersOf
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/**
 * The Worker's rooms on a MockEngine, built from worker/src/rooms.js and the
 * rules RoomProtocol ports: only the current host's key writes, a new episode
 * must name its copy, the server stamps `updated_at` and bumps the generation,
 * a quiet or leaving host hands off to the longest-present member
 * (`nextHost`), an empty room ends, and a member past MEMBER_GONE_MS is gone.
 */
class FakeRooms(private val now: () -> Long) {
    data class Call(val method: String, val path: String, val key: String?)

    private class Member(val id: String, val key: String, val joinedAt: Long, var seenAt: Long)

    private class Room(val code: String, var state: RoomState, var generation: Long, var host: String) {
        val members = mutableListOf<Member>()
    }

    val calls = mutableListOf<Call>()

    /** Every key a join handed out, in order. */
    val joinedKeys = mutableListOf<String>()
    private val rooms = mutableMapOf<String, Room>()
    private var serial = 0

    /** The next room's code; tests name it so a join can be typed. */
    var nextCode = "7KQ2MX"

    val client = HttpClient(MockEngine { request -> handle(request) })

    fun api(baseUrl: String = "https://worker.test") = RoomsApi(client, baseUrl, now)

    fun state(code: String): RoomState? = rooms[code]?.state

    fun members(code: String): Int = rooms[code]?.members?.size ?: 0

    fun exists(code: String) = code in rooms

    fun count(method: String, pathPrefix: String = "") = calls.count { it.method == method && it.path.startsWith(pathPrefix) }

    private fun MockRequestHandleScope.handle(request: HttpRequestData): HttpResponseData {
        val path = request.url.encodedPath
        val method = request.method.value
        val key = request.headers[RoomsApi.KEY_HEADER]
        calls += Call(method, path, key)
        val body = (request.body as? TextContent)?.text
        val t = now()
        if (path == "/v1/rooms" && method == "POST") return create(body, t)
        val m = Regex("""^/v1/rooms/([^/]+)(?:/(join|state|leave))?$""").find(path) ?: return problem(404, "not_found")
        val code = RoomProtocol.normalizeCode(m.groupValues[1]) ?: return problem(400, "bad_code")
        val room = rooms[code] ?: return problem(404, "no_such_room")
        val action = "$method ${m.groupValues[2]}"
        if (action == "POST join") {
            settle(room, null, t) ?: return problem(410, "room_ended")
            if (room.members.size >= RoomProtocol.MAX_MEMBERS) return problem(409, "room_full")
            val member = newMember(t)
            room.members += member
            joinedKeys += member.key
            return snapshot(room, member, t, member.key)
        }
        val me = room.members.firstOrNull { it.key == key } ?: return problem(403, "not_a_member")
        settle(room, me.id, t) ?: return problem(410, "room_ended")
        val isHost = room.host == me.id
        return when (action) {
            "POST leave" -> {
                room.members.remove(me)
                if (isHost) {
                    val next = RoomProtocol.nextHost(room.members.map(::view), me.id, t)
                    if (next == null) rooms.remove(code) else room.host = next
                }
                if (room.members.isEmpty()) rooms.remove(code)
                json("""{"left":true,"room_ended":${code !in rooms}}""")
            }
            "DELETE " -> {
                if (!isHost) return problem(403, "host_only")
                rooms.remove(code)
                json("""{"ended":true}""")
            }
            "PUT state" -> {
                if (!isHost) return problem(403, "host_only")
                val next = applyHostState(room.state, Json.parseToJsonElement(body ?: "{}").jsonObject, t)
                    ?: return problem(400, "bad_request")
                room.state = next
                room.generation += 1
                me.seenAt = t
                snapshot(room, me, t)
            }
            "GET " -> snapshot(room, me, t)
            else -> problem(405, "method_not_allowed")
        }
    }

    private fun MockRequestHandleScope.create(body: String?, t: Long): HttpResponseData {
        val input = Json.parseToJsonElement(body ?: "{}").jsonObject["state"]?.jsonObject ?: return problem(400, "bad_request")
        val blank = RoomState("", "", "", 0.0, false, 1.0, t)
        val state = applyHostState(blank, input, t) ?: return problem(400, "bad_request")
        val member = newMember(t)
        val room = Room(nextCode, state, 1, member.id).also { it.members += member }
        rooms[room.code] = room
        return snapshot(room, member, t, member.key)
    }

    /** `applyHostState`, as much as the clients exercise: a new episode names its copy; the server stamps the time. */
    private fun applyHostState(current: RoomState, input: JsonObject, t: Long): RoomState? {
        val episode = input["episode_id"]?.jsonPrimitive?.content ?: current.episodeId
        val archiveId = input["archive_id"]?.jsonPrimitive?.content
        val file = input["file"]?.jsonPrimitive?.content
        if (episode != current.episodeId && (archiveId == null || file == null)) return null
        if (archiveId != null && file != null && !RoomProtocol.cleanCopy(archiveId, file)) return null
        val rate = input["rate"]?.jsonPrimitive?.doubleOrNull ?: current.rate
        if (rate !in RoomProtocol.SPEEDS) return null
        val position = input["position"]?.jsonPrimitive?.doubleOrNull ?: RoomProtocol.expectedPosition(current, t)
        return RoomState(
            episodeId = episode,
            archiveId = archiveId ?: current.archiveId,
            file = file ?: current.file,
            position = position,
            playing = input["playing"]?.jsonPrimitive?.booleanOrNull ?: current.playing,
            rate = rate,
            updatedAt = t,
        ).takeIf { it.episodeId.isNotEmpty() && it.archiveId.isNotEmpty() }
    }

    /** rooms.js `settle`: the present member is marked, quiet ones dropped, the host handed on; null when nobody is left. */
    private fun settle(room: Room, presentId: String?, t: Long): Room? {
        room.members.firstOrNull { it.id == presentId }?.seenAt = t
        val live = RoomProtocol.liveMembers(room.members.map(::view), t).map { it.id }.toSet()
        room.members.removeAll { it.id !in live }
        if (room.host !in live) {
            val next = RoomProtocol.nextHost(room.members.map(::view), room.host, t)
            if (next == null) {
                rooms.remove(room.code)
                return null
            }
            room.host = next
        }
        return room
    }

    private fun view(m: Member) = RoomMember(m.id, m.joinedAt, m.seenAt)

    private fun newMember(t: Long): Member {
        serial += 1
        return Member("m$serial", "key-$serial-abcdefghijklmnop", t, t)
    }

    private fun MockRequestHandleScope.snapshot(room: Room, me: Member, t: Long, key: String? = null): HttpResponseData {
        val s = room.state
        val keyPart = key?.let { ""","member_key":"$it"""" } ?: ""
        return json(
            """{"v":1,"code":"${room.code}","role":"${if (room.host == me.id) "host" else "guest"}","members":${room.members.size},""" +
                """"generation":${room.generation},"state":{"episode_id":"${s.episodeId}","archive_id":"${s.archiveId}",""" +
                """"file":"${s.file}","position":${s.position},"playing":${s.playing},"rate":${s.rate},"updated_at":${s.updatedAt}},""" +
                """"server_time":$t$keyPart}""",
        )
    }

    private fun MockRequestHandleScope.json(text: String, status: Int = 200) =
        respond(text, HttpStatusCode.fromValue(status), headersOf(HttpHeaders.ContentType, "application/json"))

    private fun MockRequestHandleScope.problem(status: Int, error: String) = json("""{"error":"$error"}""", status)
}

/** A player that records what the room asked of it. */
class FakeRoomPlayer : RoomPlayer {
    var host: RoomState? = null
    var position = 0.0
    var playing = false
    var episode: String? = null
    val applied = mutableListOf<Correction>()
    val loads = mutableListOf<RoomState>()
    var listener: (() -> Unit)? = null

    override fun hostState(): RoomState? = host
    override fun sample(): PlayerSample? = episode?.let { PlayerSample(position, playing) }
    override fun episodeId(): String? = episode

    override suspend fun load(state: RoomState, position: Double) {
        loads += state
        episode = state.episodeId
        this.position = position
        playing = state.playing
    }

    override fun apply(correction: Correction) {
        applied += correction
    }

    override fun onChange(listener: (() -> Unit)?) {
        this.listener = listener
    }
}
