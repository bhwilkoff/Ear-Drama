package com.example.appname.radio

import com.example.appname.data.ApiClient
import com.example.appname.data.EpisodeDetail
import com.example.appname.data.EpisodeRow
import com.example.appname.data.Recording
import com.sun.net.httpserver.HttpServer
import java.io.IOException
import java.net.InetSocketAddress
import java.time.Instant
import java.time.ZoneId
import java.util.Locale
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Tonight in 19xx (contract §8; WEB-DESIGN §4.9; ANDROID-DESIGN §4.10; R9,
 * R10, R14): the one clock, the listener's own date, gaps that never play,
 * and listening live. Mirrors apple/Tests/RadioTests.swift.
 */
class RadioTests {
    private fun t(iso: String): Instant = Instant.parse(iso)

    /** ICU and the JDK write a narrow no-break space before "PM". */
    private fun plain(s: String?) = s?.replace(' ', ' ')?.replace(' ', ' ')

    private fun slot(start: String, end: String, episode: String? = null, length: Double? = null, withheld: Boolean = false) =
        RadioSlot(
            etStart = "19:00", etEnd = "19:30",
            lengthMin = ((t(end).epochSecond - t(start).epochSecond) / 60).toInt(),
            utcStart = t(start), utcEnd = t(end),
            episode = episode?.let { RadioSlot.Episode(it, "Series", null, length) },
            gap = episode == null, withheld = withheld,
        )

    /** js/api.test.js "onAir reads the one clock from the published instants". */
    private val golden = listOf(
        slot("2026-10-22T23:00:00Z", "2026-10-22T23:30:00Z"),
        slot("2026-10-22T23:30:00Z", "2026-10-23T00:00:00Z"),
        slot("2026-10-23T00:00:00Z", "2026-10-23T00:30:00Z"),
    )

    private fun at(iso: String) = RadioClock.onAir(golden, t(iso))

    // --- onAir, golden against the web

    @Test fun `onAir matches the web's cases`() {
        assertEquals(RadioClock.OnAir(RadioClock.Phase.Before, null), at("2026-10-22T22:59:59Z"))
        assertEquals(RadioClock.OnAir(RadioClock.Phase.During, 0), at("2026-10-22T23:00:00Z"))
        assertEquals(RadioClock.OnAir(RadioClock.Phase.During, 1), at("2026-10-22T23:45:00Z"))
        assertEquals(RadioClock.OnAir(RadioClock.Phase.During, 2), at("2026-10-23T00:29:59Z"))
        assertEquals(RadioClock.OnAir(RadioClock.Phase.After, null), at("2026-10-23T00:30:00Z"))
        assertEquals(RadioClock.OnAir(RadioClock.Phase.After, null), RadioClock.onAir(emptyList(), Instant.now()))
    }

    @Test fun `a slot boundary belongs to the slot that starts`() {
        assertEquals(0, at("2026-10-22T23:29:59Z").index)
        assertEquals(1, at("2026-10-22T23:30:00Z").index)
        assertEquals(2, at("2026-10-23T00:00:00Z").index)
    }

    // --- The listener's own date

    @Test fun `localDate is the device's own date, not UTC`() {
        val denver = ZoneId.of("America/Denver")
        // 03:30 UTC on the 23rd is 9:30 PM on the 22nd in Denver.
        assertEquals("2026-10-22", RadioClock.localDate(t("2026-10-23T03:30:00Z"), denver))
        // 20:00 UTC on the 22nd is 5 AM on the 23rd in Tokyo.
        assertEquals("2026-10-23", RadioClock.localDate(t("2026-10-22T20:00:00Z"), ZoneId.of("Asia/Tokyo")))
        // control: padding
        assertEquals("2026-01-05", RadioClock.localDate(t("2026-01-05T12:05:00Z"), denver))
    }

    // --- The file

    private val file = """
    {"schemaVersion": 1, "zone": "America/New_York", "floor": 0.25, "floor_provisional": true, "days": {
      "2026-10-22": {"evening": "1942-10-22", "picked": "anniversary", "network": "CBS", "station": "WJSV",
        "coverage": 0.3, "witness": {"paper": "Washington Post", "url": "https://example.org/log.pdf",
          "via": "JJ's Newspaper Radio Logs (jjonz.us)"},
        "slots": [
          {"et_start": "19:00", "et_end": "19:15", "length_min": 15, "printed": "Amos W Andy", "gap": true,
           "known_series": "Amos 'n' Andy", "utc_start": "2026-10-22T23:00:00Z", "utc_end": "2026-10-22T23:15:00Z"},
          {"et_start": "19:15", "et_end": "19:45", "length_min": 30, "printed": "Suspense",
           "episode": {"id": "suspense|1942-10-22", "series": "Suspense", "title": "The Hitchhiker", "rights": "unclaimed",
                       "length_s": 1770, "match": 0.9},
           "utc_start": "2026-10-22T23:15:00Z", "utc_end": "2026-10-22T23:45:00Z"},
          {"et_start": "19:45", "et_end": "20:00", "length_min": 15, "printed": "Lux", "gap": true, "withheld": true,
           "known_series": "Lux Radio Theatre", "utc_start": "2026-10-22T23:45:00Z", "utc_end": "2026-10-23T00:00:00Z"}
        ]}}}
    """.trimIndent()

    @Test fun `the file decodes the contract shape`() {
        val tonight = TonightFile.decode(file)
        assertEquals("America/New_York", tonight.zone)
        assertNull(tonight.day("2026-10-23"))
        val day = tonight.day("2026-10-22")!!
        assertEquals("1942", day.year)
        assertEquals("CBS · WJSV", day.stationLine)
        assertEquals("Washington Post, via JJ's Newspaper Radio Logs", day.witnessLine)
        assertEquals(3, day.slots.size)
        assertTrue(day.slots[0].gap)
        assertEquals("Amos 'n' Andy", day.slots[0].knownSeries)
        assertEquals("suspense|1942-10-22", day.slots[1].playableEpisode?.id)
        assertEquals(1770.0, day.slots[1].playableEpisode?.lengthS)
        assertEquals(t("2026-10-22T23:45:00Z"), day.slots[1].utcEnd)
    }

    @Test fun `the paper's printed text is never decoded`() {
        val fields = listOf(RadioSlot::class.java, RadioSlot.Episode::class.java, TonightDay::class.java)
            .flatMap { c -> c.declaredFields.map { it.name.lowercase() } }
        assertTrue(fields.none { "printed" in it })
        assertTrue("control: the fields are read", "knownseries" in fields)
        assertTrue(TonightFile.decode(file).toString().let { "Amos W Andy" !in it && "Amos 'n' Andy" in it })
    }

    @Test fun `withheld and gap slots never play`() {
        val day = TonightFile.decode(file).day("2026-10-22")!!
        assertNull(day.slots[0].playableEpisode)
        assertNull(day.slots[2].playableEpisode)
        assertEquals("Not surviving", RadioClock.gapNote(day.slots[0]))
        assertEquals("Not in the catalog", RadioClock.gapNote(day.slots[2]))
        // A withheld slot that still names its episode is refused too.
        val named = slot("2026-10-22T23:00:00Z", "2026-10-22T23:30:00Z", episode = "x|1", withheld = true)
        assertNull(named.playableEpisode)
        val live = LiveListening(listOf(named), mapOf("x|1" to 1800.0))
        assertEquals(LiveListening.Action.None, live.tick(t("2026-10-22T23:05:00Z")))
    }

    @Test fun `each slot reads local time with Eastern beside`() {
        val s = TonightFile.decode(file).day("2026-10-22")!!.slots[0]
        val en = Locale.US
        val ny = RadioClock.timeLabel(s, "America/New_York", ZoneId.of("America/New_York"), en)
        assertEquals("7:00 PM ET", plain(ny.first))
        assertNull(ny.second)
        val denver = RadioClock.timeLabel(s, "America/New_York", ZoneId.of("America/Denver"), en)
        assertEquals("5:00 PM", plain(denver.first))
        assertEquals("7:00 PM ET", plain(denver.second))
    }

    @Test fun `the API client reads the file, and a 404 is no evening`() {
        val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        server.createContext("/tonight.json") { ex ->
            val body = file.toByteArray()
            ex.sendResponseHeaders(200, body.size.toLong())
            ex.responseBody.use { it.write(body) }
        }
        server.createContext("/missing.json") { ex -> ex.sendResponseHeaders(404, -1); ex.close() }
        server.createContext("/broken.json") { ex -> ex.sendResponseHeaders(500, -1); ex.close() }
        server.start()
        try {
            val base = "http://127.0.0.1:${server.address.port}"
            val api = ApiClient()
            runBlocking {
                assertEquals(3, api.tonight("$base/tonight.json")?.day("2026-10-22")?.slots?.size)
                assertNull(api.tonight("$base/missing.json"))
                val thrown = runCatching { api.tonight("$base/broken.json") }.exceptionOrNull()
                assertTrue("a failed host is an error, not no evening", thrown is IOException)
            }
        } finally {
            server.stop(0)
        }
    }

    @Test fun `the load tells nothing from a failure`() = runBlocking {
        val failed = RadioLoad.load(fetch = { throw IOException("offline") }, db = { null }, date = "2026-10-22")
        assertEquals(RadioLoad.Failed, failed)
        assertEquals(RadioLoad.Nothing, RadioLoad.load(fetch = { null }, db = { null }, date = "2026-10-22"))
        val decoded = TonightFile.decode(file)
        assertEquals(RadioLoad.Nothing, RadioLoad.load(fetch = { decoded }, db = { null }, date = "2026-10-24"))
        // No catalog open: the evening still draws, every slot a gap that never plays.
        val evening = (RadioLoad.load(fetch = { decoded }, db = { null }, date = "2026-10-22") as RadioLoad.Evening).evening
        assertTrue(evening.day.slots.all { evening.detail(it) == null })
    }

    /** Decision 067: a listener may pick another published year for the same date. */
    @Test fun `another published year for the date is offered and loads whole`() = runBlocking {
        val withYears = TonightFile.decode("""
            {"zone": "America/New_York", "days": {"2026-10-22": {"evening": "1947-10-22", "network": "CBS",
              "slots": [{"et_start": "20:00", "et_end": "20:30", "length_min": 30, "gap": true,
                         "utc_start": "2026-10-23T00:00:00Z", "utc_end": "2026-10-23T00:30:00Z"}],
              "years": [{"evening": "1939-10-22", "network": "NBC", "station": "WRC",
                "slots": [{"et_start": "21:00", "et_end": "21:30", "length_min": 30, "gap": true, "known_series": "Lux",
                           "utc_start": "2026-10-23T01:00:00Z", "utc_end": "2026-10-23T01:30:00Z"}]}]}}}
        """.trimIndent())
        val base = (RadioLoad.load(fetch = { withYears }, db = { null }, date = "2026-10-22") as RadioLoad.Evening).evening
        assertEquals(listOf("1939-10-22", "1947-10-22"), base.choices)
        assertEquals("1947-10-22", base.day.evening)
        val picked = (RadioLoad.load(fetch = { withYears }, db = { null }, date = "2026-10-22", picked = "1939-10-22")
            as RadioLoad.Evening).evening
        assertEquals("1939-10-22", picked.day.evening)
        assertEquals("NBC · WRC", picked.day.stationLine)
        assertEquals("Lux", picked.day.slots.single().knownSeries)
        assertEquals("the choices stay the date's", base.choices, picked.choices)
        val unknown = (RadioLoad.load(fetch = { withYears }, db = { null }, date = "2026-10-22", picked = "1900-10-22")
            as RadioLoad.Evening).evening
        assertEquals("control: a year not offered falls back to the published evening", "1947-10-22", unknown.day.evening)
        val older = (RadioLoad.load(fetch = { TonightFile.decode(file) }, db = { null }, date = "2026-10-22")
            as RadioLoad.Evening).evening
        assertEquals("control: a file without years offers only its evening", listOf("1942-10-22"), older.choices)
    }

    // --- Listening live

    private val evening = listOf(
        slot("2026-10-22T23:00:00Z", "2026-10-22T23:30:00Z", episode = "a|1"),
        slot("2026-10-22T23:30:00Z", "2026-10-22T23:45:00Z"),
        slot("2026-10-22T23:45:00Z", "2026-10-23T00:15:00Z", episode = "b|1"),
    )
    private val lengths = mapOf<String, Double?>("a|1" to 1770.0, "b|1" to 1790.0)

    @Test fun `live offset is where the clock stands`() {
        val s = evening[0]
        assertEquals(750.0, RadioClock.liveOffset(s, 1770.0, t("2026-10-22T23:12:30Z")))
        assertEquals(0.0, RadioClock.liveOffset(s, 1770.0, t("2026-10-22T23:00:00Z")))
        // The recording ended inside its slot: nothing to join.
        assertNull(RadioClock.liveOffset(s, 1500.0, t("2026-10-22T23:26:00Z")))
        assertNull(RadioClock.liveOffset(s, 1500.0, t("2026-10-22T23:24:56Z")))
        assertEquals(1494.0, RadioClock.liveOffset(s, 1500.0, t("2026-10-22T23:24:54Z")))
        // No length known: the slot's own minutes.
        assertEquals(1740.0, RadioClock.liveOffset(s, null, t("2026-10-22T23:29:00Z")))
    }

    @Test fun `live joins, then waits, then plays the next surviving slot at its own time`() {
        val live = LiveListening(evening, lengths)
        assertEquals(LiveListening.Action.Play("a|1", 600.0), live.tick(t("2026-10-22T23:10:00Z")))
        assertEquals(LiveListening.Action.None, live.handle(TransportEvent.Loaded("a|1")))
        assertEquals(LiveListening.Action.None, live.tick(t("2026-10-22T23:10:01Z")))
        assertEquals(LiveListening.Action.None, live.handle(TransportEvent.Ended))
        // The gap plays nothing.
        assertEquals(LiveListening.Action.None, live.tick(t("2026-10-22T23:35:00Z")))
        assertEquals(LiveListening.Action.Play("b|1", 0.0), live.tick(t("2026-10-22T23:45:00Z")))
    }

    @Test fun `a recording still playing is not cut off by the next slot`() {
        val live = LiveListening(evening, lengths)
        live.tick(t("2026-10-22T23:10:00Z"))
        assertEquals(LiveListening.Action.None, live.tick(t("2026-10-22T23:45:01Z")))
    }

    @Test fun `a pause, another episode, the sleep timer, or a stop ends listening live`() {
        for (event in listOf(TransportEvent.Paused, TransportEvent.Loaded("other|1"), TransportEvent.SleepFired, TransportEvent.Stopped)) {
            val live = LiveListening(evening, lengths)
            live.tick(t("2026-10-22T23:10:00Z"))
            assertEquals("$event", LiveListening.Action.Stop, live.handle(event))
            assertTrue(live.isOver)
            // Nothing plays afterward, even when the next slot's time comes.
            assertEquals("$event", LiveListening.Action.None, live.tick(t("2026-10-22T23:50:00Z")))
        }
    }

    @Test fun `the evening's end stops listening and nothing plays after`() {
        val live = LiveListening(evening, lengths)
        live.tick(t("2026-10-22T23:10:00Z"))
        live.handle(TransportEvent.Ended)
        live.tick(t("2026-10-22T23:45:00Z"))
        live.handle(TransportEvent.Ended)
        assertEquals(LiveListening.Action.Stop, live.tick(t("2026-10-23T00:15:00Z")))
        assertEquals(LiveListening.Action.None, live.tick(t("2026-10-23T00:30:00Z")))
        assertEquals(LiveListening.Action.None, live.tick(t("2026-10-23T23:10:00Z")))
    }

    @Test fun `an episode the catalog does not hold never plays`() {
        val live = LiveListening(evening, mapOf("b|1" to 1790.0))
        assertEquals(LiveListening.Action.None, live.tick(t("2026-10-22T23:10:00Z")))
        assertEquals(LiveListening.Action.Play("b|1", 300.0), live.tick(t("2026-10-22T23:50:00Z")))
    }

    // --- LiveRadio: the clock loop and the player, with nothing after

    private fun detail(id: String, length: Double) = EpisodeDetail(
        episode = EpisodeRow(id, "series", "Series", "1942-10-22", null, null, null, length),
        rights = "unclaimed", rightsBasis = null, network = null, noRecommend = null,
        credits = emptyList(),
        recordings = listOf(Recording(0, "item", "https://example.org/$id.mp3", null, null, length, null, false)),
        detailJson = null,
    )

    private val tonight = RadioEvening(
        TonightDay(evening = "1942-10-22", slots = evening),
        "America/New_York",
        mapOf("a|1" to detail("a|1", 1770.0), "b|1" to detail("b|1", 1790.0)),
    )

    @OptIn(ExperimentalCoroutinesApi::class)
    @Test fun `each live-stopping event leaves nothing to play after it`() {
        for (event in listOf(TransportEvent.Paused, TransportEvent.Loaded("other|1"), TransportEvent.SleepFired, TransportEvent.Stopped)) {
            var clock = t("2026-10-22T23:10:00Z")
            val played = mutableListOf<Pair<String, Long>>()
            val scope = TestScope(StandardTestDispatcher())
            val radio = LiveRadio(play = { d, ms -> played += d.episode.id to ms }, pause = {}, now = { clock }, scope = scope)
            radio.tuneIn(tonight)
            assertEquals(listOf("a|1" to 600_000L), played)
            assertEquals(tonight.day, radio.day.value)
            radio.handle(TransportEvent.Loaded("a|1"))
            radio.handle(event)
            assertNull("$event", radio.day.value)
            clock = t("2026-10-22T23:50:00Z")
            scope.advanceTimeBy(5_000)
            scope.runCurrent()
            assertEquals("$event", listOf("a|1" to 600_000L), played)
        }
    }

    @OptIn(ExperimentalCoroutinesApi::class)
    @Test fun `the clock loop starts the next slot with nothing queued, then stops at the end`() {
        var clock = t("2026-10-22T23:10:00Z")
        val played = mutableListOf<Pair<String, Long>>()
        val scope = TestScope(StandardTestDispatcher())
        val radio = LiveRadio(play = { d, ms -> played += d.episode.id to ms }, pause = {}, now = { clock }, scope = scope)
        radio.tuneIn(tonight)
        radio.handle(TransportEvent.Loaded("a|1"))
        radio.handle(TransportEvent.Ended)
        clock = t("2026-10-22T23:45:00Z")
        scope.advanceTimeBy(1_500)
        assertEquals(listOf("a|1" to 600_000L, "b|1" to 0L), played)
        radio.handle(TransportEvent.Loaded("b|1"))
        radio.handle(TransportEvent.Ended)
        clock = t("2026-10-23T00:15:00Z")
        scope.advanceTimeBy(1_500)
        assertNull(radio.day.value)
        clock = t("2026-10-23T23:10:00Z")
        scope.advanceTimeBy(5_000)
        assertEquals(2, played.size)
    }

    @Test fun `listening live's own button pauses and ends it`() {
        var paused = 0
        val radio = LiveRadio(play = { _, _ -> }, pause = { paused++ }, now = { t("2026-10-22T23:10:00Z") }, scope = TestScope())
        radio.tuneIn(tonight)
        radio.pauseAndStop()
        assertEquals(1, paused)
        assertNull(radio.day.value)
    }
}
