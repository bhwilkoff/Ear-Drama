package com.example.appname.playback

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * resilient-media-streaming: a failed load is retried once with jitter, then the next copy in rank
 * order, then the error. The same cases as apple/Tests/LoadRecoveryTests.swift.
 */
class LoadRecoveryTest {
    private val urls = listOf("a", "b", "c")

    /** The engine's loop, driven by a fake loader: a copy fails on the attempts [failures] names ("copy#nth"). */
    private fun run(chosen: String, ranked: List<String>, failures: Set<String>): Pair<String?, List<String>> {
        val plan = LoadRecovery(chosen, ranked)
        val attempts = mutableListOf<String>()
        var next = plan.current
        while (true) {
            attempts += next
            val nth = attempts.count { it == next }
            if ("$next#$nth" !in failures) return next to attempts
            when (val step = plan.failed(1.25)) {
                is LoadRecovery.Step.Retry -> assertEquals(LoadRecovery.RETRY_SECONDS * 1.25, step.seconds, 0.0001)
                is LoadRecovery.Step.Fallback -> next = step.url
                LoadRecovery.Step.GiveUp -> return null to attempts
            }
        }
    }

    @Test fun `a load that fails once is retried once and plays`() {
        val (loaded, attempts) = run("a", urls, setOf("a#1"))
        assertEquals("a", loaded)
        assertEquals(listOf("a", "a"), attempts)
    }

    @Test fun `a copy that keeps failing gives way to the next in rank order`() {
        val (loaded, attempts) = run("a", urls, setOf("a#1", "a#2"))
        assertEquals("b", loaded)
        assertEquals(listOf("a", "a", "b"), attempts)
    }

    @Test fun `when every copy fails the error is surfaced after one retry each`() {
        val (loaded, attempts) = run("a", listOf("a", "b"), setOf("a#1", "a#2", "b#1", "b#2"))
        assertNull(loaded)
        assertEquals(listOf("a", "a", "b", "b"), attempts)
    }

    @Test fun `a copy that loaded earns its next failure a retry`() {
        val plan = LoadRecovery("a", urls)
        assertEquals(LoadRecovery.Step.Retry(1.0), plan.failed(1.0))
        plan.loaded()
        assertEquals("a seek that fails after playback began is retried too", LoadRecovery.Step.Retry(1.0), plan.failed(1.0))
    }

    @Test fun `a lone copy is retried once and then given up`() {
        val plan = LoadRecovery("a", listOf("a"))
        plan.failed(1.0)
        assertEquals(LoadRecovery.Step.GiveUp, plan.failed(1.0))
    }
}
