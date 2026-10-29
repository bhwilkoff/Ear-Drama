package com.example.appname.plays

import com.example.appname.account.SignedOutException
import com.example.appname.account.WorkerApi
import com.example.appname.account.WorkerException
import io.ktor.http.HttpMethod
import java.io.IOException
import java.net.URLEncoder
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * Shared plays' calls (docs/WORKER.md, "Shared plays") on the app's one
 * Worker client: [WorkerApi] checks the access token before each, so a call
 * here never carries a stale one (AGENTS.md hard rule). Every route is
 * signed in (Decision 057). It holds no rule; [PlaysShare] does.
 */
class PlaysApi(private val worker: WorkerApi) : PlaysTransport {
    private val p = "/v1/plays"
    private fun at(pid: String) = "$p/productions/${enc(pid)}"
    private fun enc(s: String) = URLEncoder.encode(s, "UTF-8").replace("+", "%20")

    private suspend inline fun <T> guarded(block: () -> T): T = try {
        block()
    } catch (e: CancellationException) {
        throw e
    } catch (e: WorkerException) {
        throw PlaysException(
            e.code.orEmpty(),
            when (e.status) {
                401 -> PlaysException.Kind.Unauthorized
                429 -> PlaysException.Kind.RateLimited
                503 -> PlaysException.Kind.NotConfigured
                else -> PlaysException.Kind.Refused
            },
            e.detail,
        )
    } catch (e: SignedOutException) {
        throw PlaysException("", PlaysException.Kind.Unauthorized)
    } catch (e: PlaysException) {
        throw e
    } catch (e: IOException) {
        throw PlaysException("", PlaysException.Kind.Offline)
    }

    private suspend fun text(method: HttpMethod, path: String, body: JsonObject? = null): String =
        guarded { worker.callText(method, path, body?.let { ShareJson.encodeToString(JsonObject.serializer(), it) }) }

    private suspend inline fun <reified T> decode(method: HttpMethod, path: String, body: JsonObject? = null): T =
        ShareJson.decodeFromString(text(method, path, body))

    override suspend fun consent(): Consent = decode(HttpMethod.Get, "$p/consent")

    override suspend fun create(body: JsonObject): SharedRecord = decode(HttpMethod.Post, "$p/productions", body)

    override suspend fun list(): List<RemoteRow> {
        val answer = decode<Productions>(HttpMethod.Get, "$p/productions")
        return answer.productions
    }

    override suspend fun get(pid: String): SharedRecord = decode(HttpMethod.Get, at(pid))

    override suspend fun invite(pid: String): InviteMade = decode(HttpMethod.Post, "${at(pid)}/invites", JsonObject(emptyMap()))

    override suspend fun viewInvite(token: String): InviteView =
        decode(HttpMethod.Post, "$p/invites/view", buildJsonObject { put("token", token) })

    override suspend fun joinByInvite(token: String, part: String, displayName: String?): SharedRecord =
        decode(
            HttpMethod.Post, "$p/invites/claim",
            buildJsonObject { put("token", token); put("part", part); displayName?.let { put("display_name", it) } },
        )

    override suspend fun claim(pid: String, part: String): SharedRecord =
        decode(HttpMethod.Post, "${at(pid)}/claim", buildJsonObject { put("part", part) })

    override suspend fun partAction(pid: String, part: String, action: String): SharedRecord =
        decode(HttpMethod.Post, "${at(pid)}/parts/${enc(part)}/$action", JsonObject(emptyMap()))

    override suspend fun agree(pid: String, version: String) {
        text(HttpMethod.Post, "${at(pid)}/consent", buildJsonObject { put("version", version) })
    }

    override suspend fun upload(pid: String, takeId: String, bytes: ByteArray, meta: JsonObject) {
        guarded {
            worker.callBytes(
                HttpMethod.Put, "${at(pid)}/takes/${enc(takeId)}", bytes,
                mapOf("content-type" to "audio/wav", "x-take" to ShareJson.encodeToString(JsonObject.serializer(), meta)),
            )
        }
    }

    override suspend fun audio(pid: String, takeId: String): ByteArray =
        guarded { worker.callBytes(HttpMethod.Get, "${at(pid)}/takes/${enc(takeId)}/audio") }

    override suspend fun choose(pid: String, takeId: String): SharedRecord =
        decode(HttpMethod.Post, "${at(pid)}/chosen", buildJsonObject { put("take_id", takeId) })

    override suspend fun publish(pid: String): PublishAnswer = decode(HttpMethod.Post, "${at(pid)}/publish", JsonObject(emptyMap()))

    override suspend fun removeLine(pid: String, lineId: String, reason: String) {
        text(HttpMethod.Post, "${at(pid)}/archive/lines/${enc(lineId)}/remove", buildJsonObject { put("reason", reason) })
    }

    override suspend fun report(pid: String, takeId: String?, userId: String?, reason: String, note: String?) {
        text(
            HttpMethod.Post, "$p/reports",
            buildJsonObject {
                put("production_id", pid)
                takeId?.let { put("take_id", it) }
                userId?.let { put("user_id", it) }
                put("reason", reason)
                note?.takeIf { it.isNotBlank() }?.let { put("note", it.trim()) }
            },
        )
    }

    override suspend fun block(userId: String) {
        text(HttpMethod.Post, "$p/blocks", buildJsonObject { put("user_id", userId) })
    }

    override suspend fun classes(): ClassesAnswer = decode(HttpMethod.Get, "$p/classes")

    override suspend fun classDetail(id: String): ClassRow = decode(HttpMethod.Get, "$p/classes/${enc(id)}")

    override suspend fun createClass(name: String, under13: Boolean): ClassRow =
        decode(HttpMethod.Post, "$p/classes", buildJsonObject { put("name", name); put("under13", under13) })

    override suspend fun joinClass(code: String, displayName: String?): ClassRow =
        decode(
            HttpMethod.Post, "$p/classes/join",
            buildJsonObject { put("code", code); displayName?.let { put("display_name", it) } },
        )

    @kotlinx.serialization.Serializable
    private data class Productions(val productions: List<RemoteRow> = emptyList())
}
