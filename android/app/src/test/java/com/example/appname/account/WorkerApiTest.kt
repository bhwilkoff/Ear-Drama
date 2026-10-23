package com.example.appname.account

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** AGENTS.md: refresh before every Worker call, one refresh at a time, through the one client (DECISIONS 063). */
class WorkerApiTest {
    private var clock = 1_000_000_000L
    private val fake = FakeWorker { clock }

    private fun api(account: StoredAccount?) = MemorySessionStore(account).let { store ->
        store to WorkerApi(fake.client, fake.config, store) { clock }
    }

    @Test fun `refreshes before a call when under five minutes remain`() = runBlocking {
        val (store, api) = api(fake.account(expiresInMs = 4 * 60 * 1000L))
        val before = store.saved!!
        api.read(since = 0)
        assertEquals(listOf("POST /v1/auth/refresh", "GET /v1/sync?since=0"), fake.calls.map { "${it.method} ${it.path}" })
        val after = store.saved!!
        assertTrue("the new pair is stored", after.refreshToken != before.refreshToken)
        assertEquals("the call carried the refreshed token", after.accessToken, fake.last("GET", "/v1/sync").token)
    }

    @Test fun `a token with more than five minutes left is used as it is`() = runBlocking {
        val (store, api) = api(fake.account(expiresInMs = 6 * 60 * 1000L))
        api.read(since = 0)
        assertEquals(0, fake.count("POST", "/v1/auth/refresh"))
        assertEquals(store.saved!!.accessToken, fake.last("GET", "/v1/sync").token)
    }

    @Test fun `concurrent calls share one refresh`() = runBlocking(Dispatchers.Default) {
        val (store, api) = api(fake.account(expiresInMs = 60 * 1000L))
        val gate = CompletableDeferred<Unit>()
        fake.refreshGate = gate
        val reads = (1..5).map { async { api.read(since = 0) } }
        delay(300) // every caller is now waiting on the one refresh
        gate.complete(Unit)
        reads.awaitAll()
        assertEquals("one refresh for five calls", 1, fake.count("POST", "/v1/auth/refresh"))
        assertEquals(5, fake.count("GET", "/v1/sync"))
        assertNotNull("still signed in", store.saved)
    }

    @Test fun `a 401 refreshes once and retries once, then surfaces`() = runBlocking {
        val (store, api) = api(fake.account())
        fake.syncAlwaysUnauthorized = true
        try {
            api.read(since = 0)
            fail("a second 401 must surface")
        } catch (e: WorkerException) {
            assertEquals(401, e.status)
        }
        assertEquals(1, fake.count("POST", "/v1/auth/refresh"))
        assertEquals(2, fake.count("GET", "/v1/sync"))
        assertNotNull("a refused call does not sign out", store.saved)
    }

    @Test fun `a refused refresh ends the session on the device`() = runBlocking {
        val spent = fake.account(expiresInMs = 0).copy(refreshToken = "never-issued")
        val (store, api) = api(spent)
        try {
            api.read(since = 0)
            fail("expected signed out")
        } catch (e: SignedOutException) {
            // expected
        }
        assertNull(store.saved)
        assertNull(api.account.value)
    }

    @Test fun `deletion clears stored tokens and account state`() = runBlocking {
        val (store, api) = api(fake.account().copy(lastSyncAt = 5, cursor = 99, lastError = "x"))
        api.deleteAccount()
        assertNotNull("sent with the bearer", fake.last("DELETE", "/v1/account").token)
        assertNull(store.saved)
        assertNull(api.account.value)
    }

    @Test fun `a failed deletion keeps the account so it can be tried again`() = runBlocking {
        val (store, api) = api(fake.account())
        fake.failNext["/v1/account"] = 503
        try {
            api.deleteAccount()
            fail("expected the 503")
        } catch (e: WorkerException) {
            assertEquals(503, e.status)
        }
        assertNotNull(store.saved)
    }

    @Test fun `the Apple return link is read from its fragment`() {
        assertEquals(
            AppleWebSignIn.Callback(state = "s1", idToken = "a.b.c", code = "c/1", error = null),
            AppleWebSignIn.parse("eardrama://oauth/apple#state=s1&code=c%2F1&id_token=a.b.c"),
        )
        assertEquals("user_cancelled_authorize", AppleWebSignIn.parse("eardrama://oauth/apple?error=user_cancelled_authorize")?.error)
        assertNull(AppleWebSignIn.parse("eardrama://series/suspense"))
    }

    @Test fun `sign-in stores the session and marks the merge pending`() = runBlocking {
        val (store, api) = api(null)
        api.signIn("google", "id-token", "raw-nonce", "android")
        val body = fake.last("POST", "/v1/auth/google").body!!
        assertTrue(body, body.contains("\"nonce\":\"raw-nonce\"") && body.contains("\"id_token\":\"id-token\""))
        assertEquals(true, store.saved?.mergePending)
    }
}
