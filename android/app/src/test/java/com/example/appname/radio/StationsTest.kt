package com.example.appname.radio

import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Genre stations (contract §8, R10, Decision 068): the published schedule
 * decodes, and the client only looks up what is on now and where in it. The
 * cases are js/api.test.js "onNow" and apple/Tests/StationsTests.swift.
 */
class StationsTest {
    private fun t(iso: String): Instant = Instant.parse(iso)

    private val file = """
        {"schemaVersion": 1, "generatedAt": "2026-10-24T18:20:00Z", "stations": [
          {"genre": "mystery", "name": "Mystery", "slots": [
            {"utc_start": "2026-10-24T18:00:00Z", "utc_end": "2026-10-24T18:29:51Z", "length_s": 1791,
             "episode": {"id": "suspense|1947-10-16", "series": "Suspense", "title": "Self Defense"}},
            {"utc_start": "2026-10-24T18:29:51Z", "utc_end": "2026-10-24T18:44:51Z", "length_s": 900, "withheld": true},
            {"utc_start": "2026-10-24T18:44:51Z", "utc_end": "2026-10-24T19:14:51Z", "length_s": 1800,
             "episode": {"id": "whistler|1947-10-20", "series": "The Whistler"}}
          ]},
          {"genre": "western", "name": "Western", "slots": []}
        ]}
    """.trimIndent()

    private val mystery get() = StationsFile.decode(file)[0]

    @Test
    fun theFileDecodesTheContractShape() {
        val stations = StationsFile.decode(file)
        assertEquals(listOf("Mystery", "Western"), stations.map { it.name })
        val slots = mystery.slots
        assertEquals(3, slots.size)
        assertEquals("Suspense", slots[0].playableEpisode?.series)
        assertEquals("Self Defense", slots[0].playableEpisode?.title)
        assertEquals(1791.0, slots[0].playableEpisode?.lengthS)
        assertEquals(t("2026-10-24T18:29:51Z"), slots[0].utcEnd)
        assertTrue(slots[1].playableEpisode == null && slots[1].withheld)
        assertEquals("Not in the catalog", RadioClock.gapNote(slots[1]))
        assertNull(slots[2].playableEpisode?.title)
    }

    @Test
    fun onNowIsTheSlotWhoseInstantsHoldAndWhereInIt() {
        val slots = mystery.slots
        fun at(iso: String) = StationClock.onNow(slots, t(iso))
        assertNull("before the first slot", at("2026-10-24T17:59:59Z"))
        assertEquals(0, at("2026-10-24T18:00:00Z")?.index)
        assertEquals(600.0, at("2026-10-24T18:10:00Z")?.offsetSeconds)
        assertEquals(0, at("2026-10-24T18:29:50Z")?.index)
        assertEquals("a boundary belongs to the slot that starts", 1, at("2026-10-24T18:29:51Z")?.index)
        assertEquals(0.0, at("2026-10-24T18:44:51Z")?.offsetSeconds)
        assertEquals(2, at("2026-10-24T19:14:50Z")?.index)
        assertNull("after the last slot nothing is on", at("2026-10-24T19:14:51Z"))
        assertNull(StationClock.onNow(emptyList(), t("2026-10-24T18:10:00Z")))
    }

    @Test
    fun aheadIsTheSlotOnNowAndThoseStartingWithinTheSpan() {
        val slots = mystery.slots
        assertEquals(1, StationClock.ahead(slots, t("2026-10-24T18:10:00Z"), 600).size)
        assertEquals(3, StationClock.ahead(slots, t("2026-10-24T18:10:00Z"), 3600).size)
        assertEquals(t("2026-10-24T18:29:51Z"), StationClock.ahead(slots, t("2026-10-24T18:30:00Z")).first().utcStart)
        assertTrue(StationClock.ahead(slots, t("2026-10-24T20:00:00Z")).isEmpty())
    }

    /** A station plays through the one LiveListening: join, a withheld slot plays nothing, the next at its time. */
    @Test
    fun listeningLiveToAStationJoinsWaitsAndPlaysOn() {
        val live = LiveListening(mystery.slots, mapOf("suspense|1947-10-16" to 1791.0, "whistler|1947-10-20" to 1800.0))
        assertEquals(LiveListening.Action.Play("suspense|1947-10-16", 600.0), live.tick(t("2026-10-24T18:10:00Z")))
        assertEquals(LiveListening.Action.None, live.handle(TransportEvent.Ended))
        assertEquals(LiveListening.Action.None, live.tick(t("2026-10-24T18:35:00Z")))
        assertEquals(LiveListening.Action.Play("whistler|1947-10-20", 0.0), live.tick(t("2026-10-24T18:44:51Z")))
        live.handle(TransportEvent.Ended)
        assertEquals(LiveListening.Action.Stop, live.tick(t("2026-10-24T19:14:51Z")))
    }
}
