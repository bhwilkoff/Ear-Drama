package com.example.appname.plays

import com.example.appname.account.MemorySessionStore
import com.example.appname.account.WorkerApi
import com.example.appname.account.WorkerConfig
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.headersOf
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/**
 * Plays that need no account (owner, 2026-10-29), against a stub shaped like
 * worker/src/plays-open.js: no bearer, the token in a header, a 410 for a gone invite.
 */
class OpenPlaysTest {
    private data class Seen(val method: String, val path: String, val bearer: String?, val invite: String?)

    private val seen = mutableListOf<Seen>()
    private var status = HttpStatusCode.OK
    private var answer = "{}"

    private val client = HttpClient(
        MockEngine { request ->
            seen += Seen(
                request.method.value,
                request.url.encodedPath + (request.url.encodedQuery.takeIf { it.isNotEmpty() }?.let { "?$it" } ?: ""),
                request.headers[HttpHeaders.Authorization],
                request.headers["x-invite"],
            )
            respond(answer, status, headersOf(HttpHeaders.ContentType, "application/json"))
        },
    )
    private val config = WorkerConfig("https://worker.test", "web-client", "services.id", "https://eardrama.org/auth/apple/")
    private fun api(config: WorkerConfig = this.config) = OpenPlaysApi(WorkerApi(client, config, MemorySessionStore(null)))

    private val invite = """
        {"id":"P1","scriptID":"s1","scriptRevision":"r1","title":"A Play","source":"https://example.test/s1",
         "parts":[{"id":"role:HAMLET","lineCount":3,"status":"recording","performer":"Pat"},{"id":"role:OPHELIA","lineCount":2,"status":"open"}],
         "members":[{"name":"Pat","director":true}],
         "takes":[{"id":"T1","lineID":"L1","part":"role:HAMLET","frames":4800,"sampleRate":48000.0,"audio":"/v1/plays/open/invite/takes/T1/audio"}],
         "chosen":{"L1":"T1"},"next":"role:OPHELIA","archive":null,"expires_at":1800000000000}
    """.trimIndent()

    @Test fun `an invite is read signed out with no bearer and the token in a header`() = runBlocking {
        answer = invite
        val v = api().openInvite("TOKEN-0123456789012345")
        assertEquals("A Play", v.title)
        assertEquals(listOf("recording", "open"), v.parts.map { it.status })
        assertEquals("Pat", v.parts[0].performer)
        assertNull(v.parts[1].performer)
        assertEquals(listOf(OpenMember("Pat", true)), v.members)
        assertEquals("/v1/plays/open/invite/takes/T1/audio", v.takes.single().audio)
        assertEquals(mapOf("L1" to "T1"), v.chosen)
        assertEquals(Seen("GET", "/v1/plays/open/invite", null, "TOKEN-0123456789012345"), seen.single())
    }

    @Test fun `a take plays with the same header and no bearer`() = runBlocking {
        answer = "abcd"
        val bytes = api().audio("TOKEN-0123456789012345", "T 1")
        assertEquals(4, bytes.size)
        assertEquals(Seen("GET", "/v1/plays/open/invite/takes/T%201/audio", null, "TOKEN-0123456789012345"), seen.single())
    }

    @Test fun `a revoked or expired invite is gone and an unknown one is not`() = runBlocking {
        status = HttpStatusCode.Gone
        answer = """{"error":"invite_gone"}"""
        try {
            api().openInvite("TOKEN-0123456789012345")
            fail("a 410 must throw")
        } catch (e: PlaysException) {
            assertTrue(e.isGone)
        }
        status = HttpStatusCode.NotFound
        answer = """{"error":"invite_not_found"}"""
        try {
            api().openInvite("TOKEN-0123456789012345")
            fail("a 404 must throw")
        } catch (e: PlaysException) {
            assertFalse(e.isGone)
            assertEquals("invite_not_found", e.code)
        }
    }

    @Test fun `the finished listing pages by cursor and keeps a gone performer unnamed`() = runBlocking {
        answer = """
            {"productions":[{"id":"F1","script_id":"s1","title":"A Play","source":null,
              "credits":[{"part":"role:HAMLET","name":"Pat"},{"part":"role:OPHELIA","name":""}],
              "archive_url":"https://archive.org/details/eardrama-F1","published_at":1800000000000}],
             "next_cursor":"1800000000000:F1"}
        """.trimIndent()
        val first = api().finished(limit = 20)
        assertEquals(listOf("F1"), first.productions.map { it.id })
        assertEquals(listOf(FinishedCredit("role:HAMLET", "Pat"), FinishedCredit("role:OPHELIA", "")), first.productions[0].credits)
        assertNull(first.productions[0].source)
        assertEquals(1_800_000_000_000L, first.productions[0].publishedAt)
        assertEquals("1800000000000:F1", first.nextCursor)
        api().finished(limit = 20, cursor = first.nextCursor)
        assertEquals(listOf("/v1/plays/finished?limit=20", "/v1/plays/finished?limit=20&cursor=1800000000000%3AF1"), seen.map { it.path })
        assertTrue(seen.all { it.bearer == null && it.method == "GET" })
    }

    @Test fun `one finished play by id`() = runBlocking {
        answer = """{"id":"F 1","title":"T","credits":[],"archive_url":"https://archive.org/details/x","published_at":1}"""
        assertEquals("F 1", api().finished("F 1").id)
        assertEquals("/v1/plays/finished/F%201", seen.single().path)
    }

    @Test fun `a placeholder Worker is not configured and calls nothing`() = runBlocking {
        try {
            api(WorkerConfig("REPLACE_WITH_WORKER_BASE_URL", "x", "y", "z")).finished()
            fail("expected not configured")
        } catch (e: PlaysException) {
            assertEquals(PlaysException.Kind.NotConfigured, e.kind)
        }
        assertTrue(seen.isEmpty())
    }
}
