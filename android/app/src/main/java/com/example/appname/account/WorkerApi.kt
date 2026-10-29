package com.example.appname.account

import io.ktor.client.HttpClient
import io.ktor.client.request.header
import io.ktor.client.request.request
import io.ktor.client.request.setBody
import io.ktor.client.statement.HttpResponse
import io.ktor.client.statement.bodyAsBytes
import io.ktor.client.statement.bodyAsText
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpMethod
import io.ktor.http.content.ByteArrayContent
import io.ktor.http.content.TextContent
import io.ktor.http.isSuccess
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Every call to the Worker (docs/WORKER.md), on the app's one Ktor client
 * ([com.example.appname.data.ApiClient.client]); no screen reaches the Worker
 * any other way (AGENTS.md hard rule).
 *
 * REFRESH BEFORE EVERY CALL: each signed-in call first checks the access
 * token and refreshes when under [REFRESH_MARGIN_MS] remain. Refreshes go one
 * at a time behind [refreshLock], and whoever waits re-reads the account once
 * inside: the Worker treats a refresh token sent twice as stolen and ends
 * every session of that sign-in, so a second refresh would sign the person out.
 * A 401 on a call earns exactly one forced refresh and one retry; a second 401
 * surfaces. A refresh the Worker refuses ends the session here too.
 */
class WorkerApi(
    private val http: HttpClient,
    val config: WorkerConfig,
    private val store: SessionStore,
    private val now: () -> Long = System::currentTimeMillis,
) {
    private val _account = MutableStateFlow(store.load())

    /** The signed-in account, or null. Every change is written through to [store] first. */
    val account: StateFlow<StoredAccount?> = _account

    private val refreshLock = Mutex()
    private val writeLock = Any()

    companion object {
        const val REFRESH_MARGIN_MS = 5 * 60 * 1000L
    }

    /** `POST /v1/auth/{apple|google}` with the provider's identity token and the raw nonce it was asked with. */
    suspend fun signIn(provider: String, idToken: String, nonce: String, device: String): StoredAccount {
        val response = send(HttpMethod.Post, "/v1/auth/$provider", WorkerJson.encodeToString(SignInBody(idToken, nonce, device)))
        val session = decode<Session>(response)
        val account = StoredAccount(
            accessToken = session.accessToken,
            accessExpiresAt = session.accessExpiresAt,
            refreshToken = session.refreshToken,
            refreshExpiresAt = session.refreshExpiresAt,
            userId = session.userId,
            provider = session.provider ?: provider,
            mergePending = true,
        )
        synchronized(writeLock) {
            store.save(account)
            _account.value = account
        }
        return account
    }

    suspend fun read(since: Long): SyncAnswer = WorkerJson.decodeFromString(authed(HttpMethod.Get, "/v1/sync?since=$since"))

    suspend fun upload(changes: SyncUpload): Long =
        WorkerJson.decodeFromString<UploadAnswer>(authed(HttpMethod.Put, "/v1/sync", WorkerJson.encodeToString(changes))).serverTime

    suspend fun merge(changes: SyncUpload): Long =
        WorkerJson.decodeFromString<UploadAnswer>(authed(HttpMethod.Post, "/v1/sync/merge", WorkerJson.encodeToString(changes))).serverTime

    /** Ends this sign-in at the Worker when it can be reached; the device forgets it either way. */
    suspend fun signOut() {
        try {
            authed(HttpMethod.Post, "/v1/auth/signout")
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: Exception) {
            // Offline or already ended: the tokens are dropped below, and the refresh token expires on its own.
        }
        clear()
    }

    /**
     * `DELETE /v1/account`. Only once the Worker says the account is gone does
     * the device drop its tokens and account state; a failure leaves both so
     * the person can try again. An Apple account sends a fresh authorization
     * code so the Worker can revoke the Apple token (DECISIONS 063).
     */
    suspend fun deleteAccount(appleAuthorizationCode: String? = null, appleClientId: String? = null) {
        authed(HttpMethod.Delete, "/v1/account", WorkerJson.encodeToString(DeleteBody(appleAuthorizationCode, appleClientId)))
        clear()
    }

    /** Sync's bookkeeping (cursor, merge flag, last sync, last error), applied only to the same account. */
    fun update(userId: String, change: (StoredAccount) -> StoredAccount) {
        synchronized(writeLock) {
            val current = _account.value ?: return
            if (current.userId != userId) return
            val next = change(current)
            store.save(next)
            _account.value = next
        }
    }

    private fun clear() {
        synchronized(writeLock) {
            store.save(null)
            _account.value = null
        }
    }

    /** The access token with at least five minutes left. [failed] forces a refresh unless another caller already replaced it. */
    internal suspend fun freshAccessToken(failed: String? = null): String {
        val current = _account.value ?: throw SignedOutException()
        if (failed == null && current.accessExpiresAt - now() > REFRESH_MARGIN_MS) return current.accessToken
        return refreshLock.withLock {
            val latest = _account.value ?: throw SignedOutException()
            val stillGood = if (failed != null) {
                latest.accessToken != failed
            } else {
                latest.accessExpiresAt - now() > REFRESH_MARGIN_MS
            }
            if (stillGood) return@withLock latest.accessToken
            val response = send(HttpMethod.Post, "/v1/auth/refresh", WorkerJson.encodeToString(RefreshBody(latest.refreshToken)))
            if (response.status.value == 401) {
                // Spent, expired, or ended elsewhere: this sign-in is over.
                clear()
                throw SignedOutException()
            }
            val session = decode<Session>(response)
            update(latest.userId) {
                it.copy(
                    accessToken = session.accessToken,
                    accessExpiresAt = session.accessExpiresAt,
                    refreshToken = session.refreshToken,
                    refreshExpiresAt = session.refreshExpiresAt,
                )
            }
            if (_account.value == null) throw SignedOutException()
            session.accessToken
        }
    }

    private suspend fun authed(method: HttpMethod, path: String, body: String? = null): String =
        authedResponse(method, path, body).bodyAsText()

    /** Shared plays (docs/WORKER.md): a signed-in call with a JSON body, answered as text. */
    suspend fun callText(method: HttpMethod, path: String, body: String? = null): String = authed(method, path, body)

    /**
     * A signed-in call that sends [raw] bytes (a take's audio) with [headers],
     * or reads the answer as bytes, through the same refresh and one retry.
     */
    suspend fun callBytes(
        method: HttpMethod,
        path: String,
        raw: ByteArray? = null,
        headers: Map<String, String> = emptyMap(),
    ): ByteArray = authedResponse(method, path, null, raw, headers).bodyAsBytes()

    /**
     * A read that needs no account (an open invite, the finished listing): no bearer, no
     * refresh, and a 401 is never retried. A placeholder Worker is a 503 `not_configured`.
     */
    suspend fun openBytes(path: String, headers: Map<String, String> = emptyMap()): ByteArray {
        if (!config.workerReady) throw WorkerException(503, "not_configured")
        return ok(send(HttpMethod.Get, path, headers = headers)).bodyAsBytes()
    }

    private suspend fun authedResponse(
        method: HttpMethod,
        path: String,
        body: String? = null,
        raw: ByteArray? = null,
        headers: Map<String, String> = emptyMap(),
    ): HttpResponse {
        val token = freshAccessToken()
        var response = send(method, path, body, token, raw, headers)
        if (response.status.value == 401) {
            response = send(method, path, body, freshAccessToken(failed = token), raw, headers)
        }
        return ok(response)
    }

    private suspend fun send(
        method: HttpMethod,
        path: String,
        body: String? = null,
        token: String? = null,
        raw: ByteArray? = null,
        headers: Map<String, String> = emptyMap(),
    ): HttpResponse {
        if (!config.workerReady) throw SignedOutException()
        return http.request(config.baseUrl.trimEnd('/') + path) {
            this.method = method
            token?.let { header(HttpHeaders.Authorization, "Bearer $it") }
            headers.forEach { (name, value) -> if (!name.equals(HttpHeaders.ContentType, true)) header(name, value) }
            if (raw != null) {
                val type = headers.entries.firstOrNull { it.key.equals(HttpHeaders.ContentType, true) }?.let { ContentType.parse(it.value) }
                setBody(ByteArrayContent(raw, type))
            } else if (body != null) {
                setBody(TextContent(body, ContentType.Application.Json))
            }
        }
    }

    private suspend fun ok(response: HttpResponse): HttpResponse {
        if (response.status.isSuccess()) return response
        val problem = runCatching { WorkerJson.decodeFromString<WorkerProblem>(response.bodyAsText()) }.getOrNull()
        throw WorkerException(response.status.value, problem?.error, problem?.detail)
    }

    private suspend inline fun <reified T> decode(response: HttpResponse): T =
        WorkerJson.decodeFromString(ok(response).bodyAsText())
}
