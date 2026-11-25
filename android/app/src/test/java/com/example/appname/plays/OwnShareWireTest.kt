package com.example.appname.plays

import com.example.appname.account.SessionStore
import com.example.appname.account.StoredAccount
import com.example.appname.account.WorkerApi
import com.example.appname.account.WorkerConfig
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.http.HttpStatusCode
import io.ktor.http.content.OutgoingContent
import io.ktor.http.headersOf
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/**
 * The calls an own script's sharing makes (docs/WORKER.md "Own scripts"), over the shipped [PlaysApi] and [WorkerReadWire] with a
 * mock engine: the text sent as bytes, each door read by its own key (never in the address), `x-script` and `x-take` read as the
 * Worker names them, and no route that lists or searches shared scripts.
 */
class OwnShareWireTest {
    private class Seen(val method: String, val path: String, val headers: Map<String, String>, val body: ByteArray?)

    private val signedIn = object : SessionStore {
        override fun load() = StoredAccount("access", Long.MAX_VALUE / 2, "refresh", Long.MAX_VALUE / 2, "me", "google", mergePending = false)
        override fun save(account: StoredAccount?) {}
    }

    private fun worker(seen: MutableList<Seen>, answer: (Seen) -> Triple<HttpStatusCode, ByteArray, List<Pair<String, String>>>): WorkerApi {
        val engine = MockEngine { request ->
            val body = (request.body as? OutgoingContent.ByteArrayContent)?.bytes()
            val s = Seen(request.method.value, request.url.encodedPath, request.headers.entries().associate { it.key.lowercase() to it.value.first() } + listOfNotNull(request.body.contentType?.let { "content-type" to it.toString() }), body)
            seen += s
            val (status, bytes, headers) = answer(s)
            respond(bytes, status, headersOf(*headers.map { it.first to listOf(it.second) }.toTypedArray()))
        }
        return WorkerApi(HttpClient(engine), WorkerConfig("https://worker.test", "web", "svc", "https://eardrama.org/"), signedIn)
    }

    private val ok = HttpStatusCode.OK

    @Test fun `each door asks its own route with its own key, none in the address, and x-script comes with the bytes`() = runBlocking {
        val seen = ArrayList<Seen>()
        val api = PlaysApi(worker(seen) { Triple(ok, "[]".toByteArray(), listOf("x-script" to """{"id":"i"}""")) })
        api.inviteScript("tok")
        api.seatScript("sk", "P 1")
        api.memberScript("P1")
        val got = api.roomScript("ABC234", "mk")
        assertEquals(
            listOf("GET /v1/plays/open/invite/script", "GET /v1/plays/seat/productions/P%201/script", "GET /v1/plays/productions/P1/script", "GET /v1/read/ABC234/script"),
            seen.map { "${it.method} ${it.path}" },
        )
        assertEquals(listOf("tok", "sk", "mk"), listOf(seen[0].headers["x-invite"], seen[1].headers["x-seat-key"], seen[3].headers["x-read-key"]))
        assertTrue("no key rides an address", seen.none { it.path.contains("tok") || it.path.contains("sk") || it.path.contains("mk") })
        assertTrue("a member reads signed in, a door by its key alone", seen[2].headers["authorization"] == "Bearer access" && seen[0].headers["authorization"] == null)
        assertEquals(listOf("""{"id":"i"}""", 2), listOf(got.meta, got.bytes.size))
        assertNull("no x-script is none", PlaysApi(worker(seen) { Triple(ok, "[]".toByteArray(), emptyList()) }).roomScript("ABC234", "mk").meta)
    }

    @Test fun `the text goes as bytes with its content type, once to one place`() = runBlocking {
        val seen = ArrayList<Seen>()
        val api = PlaysApi(worker(seen) { Triple(HttpStatusCode.NoContent, ByteArray(0), emptyList()) })
        api.putScript("P1", "[{\"id\":\"L0001\"}]")
        val put = seen.single()
        assertEquals("PUT /v1/plays/productions/P1/script", "${put.method} ${put.path}")
        assertEquals("[{\"id\":\"L0001\"}]", String(put.body!!, Charsets.UTF_8))
        assertEquals("application/json", put.headers["content-type"])
    }

    @Test fun `a refusal keeps the Worker's code and status, so a sending knows whether it can pass`() = runBlocking {
        val api = PlaysApi(worker(ArrayList()) { Triple(HttpStatusCode.Conflict, """{"error":"already_there"}""".toByteArray(), listOf("content-type" to "application/json")) })
        try { api.putScript("P1", "[]"); fail("sent") } catch (e: PlaysException) { assertEquals(listOf("already_there", 409), listOf(e.code, e.status)) }
        val busy = PlaysApi(worker(ArrayList()) { Triple(HttpStatusCode.InternalServerError, """{"error":"oops"}""".toByteArray(), listOf("content-type" to "application/json")) })
        try { busy.putScript("P1", "[]"); fail("sent") } catch (e: PlaysException) { assertTrue("a server's own trouble may pass", OwnShare.passes(e)) }
        val gone = PlaysApi(worker(ArrayList()) { Triple(HttpStatusCode.Gone, """{"error":"script_removed"}""".toByteArray(), listOf("content-type" to "application/json")) })
        try { gone.putScript("P1", "[]"); fail("sent") } catch (e: PlaysException) { assertTrue("a refusal that is final does not", !OwnShare.passes(e)) }
    }

    @Test fun `a take whose fields cannot be read is an error, never no take`() = runBlocking {
        val wire = WorkerReadWire(worker(ArrayList()) { s ->
            if (s.path.endsWith("/takes/inbox")) {
                when (s.headers["x-read-key"]) {
                    "none" -> Triple(HttpStatusCode.NoContent, ByteArray(0), emptyList())
                    "bad" -> Triple(ok, byteArrayOf(1), listOf("x-take" to "{not json"))
                    "absent" -> Triple(ok, byteArrayOf(1), emptyList())
                    else -> Triple(ok, byteArrayOf(1), listOf("x-take" to """{"id":"T","lineID":"L0001","part":"role:ANNA"}"""))
                }
            } else Triple(ok, "{}".toByteArray(), emptyList())
        })
        assertEquals("a take with its fields", "T", wire.inbox("ABC234", "good")!!.take.id)
        assertNull("no take is none", wire.inbox("ABC234", "none"))
        for (key in listOf("bad", "absent")) {
            try { wire.inbox("ABC234", key); fail("$key: answered") } catch (e: ReadFailure) { assertEquals("error", e.code) }
        }
    }
}
