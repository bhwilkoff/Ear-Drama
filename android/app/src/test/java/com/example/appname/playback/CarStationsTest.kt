package com.example.appname.playback

import com.example.appname.data.CatalogDatabase
import com.example.appname.data.CatalogFixture
import com.example.appname.radio.LiveRadio
import com.example.appname.radio.RadioSlot
import com.example.appname.radio.Station
import java.time.Instant
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** The car's Stations: the app's one clock and one live listening, tuned at the clock's position. */
class CarStationsTest {
    @get:Rule val tmp = TemporaryFolder()
    private lateinit var db: CatalogDatabase
    private val now = Instant.parse("2026-11-24T20:10:00Z")
    private val played = mutableListOf<Pair<String, Long>>()

    @Before fun open() {
        db = CatalogDatabase.open(CatalogFixture.build(tmp.root).path) ?: error("fixture did not open")
    }

    @After fun close() = db.close()

    private fun slot(start: String, end: String, id: String?) = RadioSlot(
        etStart = "", etEnd = "", lengthMin = 30,
        utcStart = Instant.parse(start), utcEnd = Instant.parse(end),
        episode = id?.let { RadioSlot.Episode(it, "suspense", null, 1800.0) },
        gap = id == null, withheld = id == null,
    )

    private val mystery = Station(
        "mystery", "Mystery",
        listOf(
            slot("2026-11-24T19:30:00Z", "2026-11-24T20:00:00Z", "sus|1942-06-17"),
            slot("2026-11-24T20:00:00Z", "2026-11-24T20:30:00Z", "sus|1943-01-07"),
            slot("2026-11-24T20:30:00Z", "2026-11-24T21:00:00Z", "sus|1943-05-25"),
        ),
    )
    private val gapped = Station("comedy", "Comedy", listOf(slot("2026-11-24T20:00:00Z", "2026-11-24T20:30:00Z", null)))

    private fun carStations(list: List<Station>, clock: Instant = now): CarStations = CarStations(
        tonight = { null },
        stations = { list },
        db = { db },
        live = LiveRadio(
            play = { d, ms -> played += d.episode.id to ms },
            pause = {},
            now = { clock },
            scope = CoroutineScope(Job() + Dispatchers.Unconfined),
        ),
        now = { clock },
    )

    @Test fun `only a station with a recording on the air is offered, with what is on`() = runBlocking {
        val list = carStations(listOf(mystery, gapped)).list()
        assertEquals(listOf("station:mystery"), list.map { it.id })
        assertEquals("Mystery", list.single().name)
        assertEquals("Suspense · The Hitchhiker", list.single().line)
        assertEquals("sus|1943-01-07", list.single().artEpisodeId)
    }

    @Test fun `tuning in starts the slot on the air at the clock's position, once, through the app's live listening`() = runBlocking {
        val tuned = carStations(listOf(mystery)).tune("station:mystery")
        assertEquals(CarStations.Tuned("sus|1943-01-07", 600_000), tuned)
        assertEquals(emptyList<Pair<String, Long>>(), played) // the session sets the item; the engine is not asked twice
    }

    @Test fun `an unknown station or a gap on the air tunes nothing`() = runBlocking {
        assertNull(carStations(listOf(mystery)).tune("station:nowhere"))
        assertNull(carStations(listOf(gapped)).tune("station:comedy"))
    }

    @Test fun `offline with no stations and no evening throws, so the car says so`() {
        val c = CarStations({ throw java.io.IOException("x") }, { throw java.io.IOException("x") }, { db },
            LiveRadio({ _, _ -> }, {}, scope = CoroutineScope(Job() + Dispatchers.Unconfined)))
        val failed = runCatching { runBlocking { c.list() } }.exceptionOrNull()
        assertEquals(java.io.IOException::class, failed!!::class)
    }
}
