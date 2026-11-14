package com.example.appname.radio

import com.example.appname.data.EpisodeDetail
import com.example.appname.data.EpisodeRow
import com.example.appname.data.Recording
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Home's On the air (Decision 075): the evening first, else the first station with something on, else nothing. */
class HomeLiveTest {
    private fun t(iso: String): Instant = Instant.parse(iso)

    private fun slot(start: String, end: String, id: String?, withheld: Boolean = false) = RadioSlot(
        etStart = "", etEnd = "", lengthMin = 30, utcStart = t(start), utcEnd = t(end),
        episode = id?.let { RadioSlot.Episode(it, "Show $it", "Title $it", 1800.0) },
        gap = id == null, withheld = withheld,
    )

    private fun detail(id: String) = EpisodeDetail(
        episode = EpisodeRow(id, "series", "Series", "1942-10-22", null, null, null, 1800.0),
        rights = "unclaimed", rightsBasis = null, network = null, noRecommend = null,
        credits = emptyList(),
        recordings = listOf(Recording(0, "item", "https://example.org/$id.mp3", null, null, 1800.0, null, false)),
        detailJson = null,
    )

    private fun evening(vararg slots: RadioSlot) = RadioEvening(
        TonightDay(evening = "1942-10-22", slots = slots.toList()),
        "America/New_York",
        slots.mapNotNull { it.playableEpisode?.id }.associateWith(::detail),
    )

    private val station = Station("mystery", "Mystery", listOf(slot("2026-11-14T18:00:00Z", "2026-11-14T18:30:00Z", "sus|1")))
    private val withheldStation = Station("western", "Western", listOf(slot("2026-11-14T18:00:00Z", "2026-11-14T18:30:00Z", "w|1", withheld = true)))

    @Test
    fun theEveningLeadsWhenASlotOfItIsOn() {
        val e = evening(slot("2026-11-14T18:00:00Z", "2026-11-14T18:30:00Z", "cbs|1"))
        val on = HomeLive.now(e, listOf(station), t("2026-11-14T18:10:00Z"))
        assertEquals("Tonight in 1942", on?.kicker)
        assertEquals(e, on?.evening)
        assertNull(on?.station)
    }

    @Test
    fun aStationStandsInWhenThereIsNoEvening() {
        val on = HomeLive.now(null, listOf(withheldStation, station), t("2026-11-14T18:10:00Z"))
        assertEquals("Mystery", on?.kicker)
        assertEquals("mystery", on?.station?.genre)
        assertNull(on?.evening)
        assertEquals(10L, on?.minutesIn(t("2026-11-14T18:10:00Z")))
    }

    @Test
    fun nothingOnMeansNoBlock() {
        assertNull(HomeLive.now(null, listOf(withheldStation), t("2026-11-14T18:10:00Z")))
        assertNull("after the last slot", HomeLive.now(null, listOf(station), t("2026-11-14T19:00:00Z")))
        assertNull(HomeLive.now(null, emptyList(), t("2026-11-14T18:10:00Z")))
    }

    @Test
    fun anEveningNotYetStartedNamesItsStartBesideTheStation() {
        val e = evening(slot("2026-11-14T23:00:00Z", "2026-11-14T23:30:00Z", "cbs|1"))
        val on = HomeLive.now(e, listOf(station), t("2026-11-14T18:10:00Z"))
        assertEquals("Mystery", on?.kicker)
        assertEquals(true, on?.note?.startsWith("Tonight in 1942 · Starts at "))
    }
}
