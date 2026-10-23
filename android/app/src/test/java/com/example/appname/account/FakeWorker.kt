package com.example.appname.account

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
import kotlinx.coroutines.CompletableDeferred

/** The tests' store: the same contract as the Keystore one, in memory. */
class MemorySessionStore(initial: StoredAccount? = null) : SessionStore {
    @Volatile var saved: StoredAccount? = initial
        private set

    override fun load(): StoredAccount? = saved

    override fun save(account: StoredAccount?) {
        saved = account
    }
}

/**
 * A Worker on a MockEngine, strict where the real one is (worker/src/auth.js):
 * a refresh token works once, and a spent one coming back ends every session.
 */
class FakeWorker(private val now: () -> Long) {
    data class Call(val method: String, val path: String, val token: String?, val body: String?)

    val calls = mutableListOf<Call>()
    var accessTtlMs = 60 * 60 * 1000L
    var serverTime = 10_000L
    var answer = SyncAnswer(serverTime = 0)

    /** Every /v1/sync GET answers 401, even with a fresh token. */
    var syncAlwaysUnauthorized = false

    /** Answers this status for the next call to a path, once. */
    val failNext = mutableMapOf<String, Int>()

    /** When set, a refresh waits on it before answering. */
    var refreshGate: CompletableDeferred<Unit>? = null

    private val liveAccess = mutableSetOf<String>()
    private val liveRefresh = mutableSetOf<String>()
    private val spentRefresh = mutableSetOf<String>()
    private var serial = 0

    val config = WorkerConfig("https://worker.test", "web-client", "services.id", "https://eardrama.org/auth/apple/")

    val client = HttpClient(MockEngine { request -> handle(request) })

    fun count(method: String, path: String) = synchronized(calls) { calls.count { it.method == method && it.path.startsWith(path) } }

    fun last(method: String, path: String) = synchronized(calls) { calls.last { it.method == method && it.path.startsWith(path) } }

    /** A signed-in account the fake will honor, its access token [expiresInMs] from now. */
    fun account(expiresInMs: Long = accessTtlMs, mergePending: Boolean = false): StoredAccount {
        val s = issue()
        return StoredAccount(
            accessToken = s.accessToken,
            accessExpiresAt = now() + expiresInMs,
            refreshToken = s.refreshToken,
            refreshExpiresAt = s.refreshExpiresAt,
            userId = "user-1",
            provider = "google",
            mergePending = mergePending,
        )
    }

    private fun issue(): Session = synchronized(this) {
        serial += 1
        val access = "access-$serial"
        val refresh = "refresh-$serial"
        liveAccess += access
        liveRefresh += refresh
        Session(access, now() + accessTtlMs, refresh, now() + 60L * 86_400_000, "user-1", "google")
    }

    private suspend fun MockRequestHandleScope.handle(request: HttpRequestData): HttpResponseData {
        val path = request.url.encodedPath + (request.url.encodedQuery.takeIf { it.isNotEmpty() }?.let { "?$it" } ?: "")
        val token = request.headers[HttpHeaders.Authorization]?.removePrefix("Bearer ")
        val body = (request.body as? TextContent)?.text
        val method = request.method.value
        synchronized(calls) { calls += Call(method, path, token, body) }
        synchronized(this@FakeWorker) { failNext.remove(request.url.encodedPath) }?.let { return problem(it, "forced") }

        if (method == "POST" && path == "/v1/auth/refresh") {
            refreshGate?.await()
            val refresh = WorkerJson.decodeFromString<RefreshBody>(body!!).refreshToken
            synchronized(this@FakeWorker) {
                if (refresh in spentRefresh) {
                    liveAccess.clear()
                    liveRefresh.clear()
                    return problem(401, "invalid_refresh")
                }
                if (refresh !in liveRefresh) return problem(401, "invalid_refresh")
                liveRefresh -= refresh
                spentRefresh += refresh
            }
            return ok(WorkerJson.encodeToString(issue()))
        }
        if (method == "POST" && path.startsWith("/v1/auth/")) return ok(WorkerJson.encodeToString(issue()))

        if (token == null || synchronized(this@FakeWorker) { token !in liveAccess }) return problem(401, "unauthorized")
        return when {
            method == "GET" && path.startsWith("/v1/sync") ->
                if (syncAlwaysUnauthorized) problem(401, "unauthorized") else ok(WorkerJson.encodeToString(answer))
            (method == "PUT" && path == "/v1/sync") || (method == "POST" && path == "/v1/sync/merge") ->
                ok("""{"server_time":$serverTime,"applied":{"history":0,"follows":0,"queue":false}}""")
            method == "DELETE" && path == "/v1/account" -> {
                synchronized(this@FakeWorker) { liveAccess.clear() }
                ok("""{"deleted":true,"apple_token_revoked":null}""")
            }
            method == "POST" && path == "/v1/auth/signout" -> respond("", HttpStatusCode.NoContent)
            else -> problem(404, "not_found")
        }
    }

    private fun MockRequestHandleScope.ok(json: String) =
        respond(json, HttpStatusCode.OK, headersOf(HttpHeaders.ContentType, "application/json"))

    private fun MockRequestHandleScope.problem(status: Int, error: String) =
        respond("""{"error":"$error"}""", HttpStatusCode.fromValue(status), headersOf(HttpHeaders.ContentType, "application/json"))
}
