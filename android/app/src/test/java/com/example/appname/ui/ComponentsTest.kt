package com.example.appname.ui

import com.example.appname.data.EpisodeDetail
import com.example.appname.data.EpisodeRow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ComponentsTest {
    @Test fun `dates show as the catalog stores them (R1)`() {
        assertEquals("1943-02-24", formatAirDate("1943-02-24"))
        assertNull(formatAirDate(null))
        assertNull(formatAirDate(""))
    }

    @Test fun `Detail's facts line carries the sponsor and opens with Undated when there is no date`() {
        val row = EpisodeRow("sus|1", "suspense", "Suspense", "1943-05-25", "1942-43", null, "Sorry, Wrong Number", 1800.0)
        val d = EpisodeDetail(row, "clean", null, "CBS", null, emptyList(), emptyList(), null, sponsor = "Roma Wines")
        assertEquals("CBS · Roma Wines · 30 min", detailFacts(d))
        assertEquals("Undated · CBS · 30 min", detailFacts(d.copy(episode = row.copy(airDate = null), sponsor = null)))
        assertNull(detailFacts(d.copy(network = null, sponsor = null, episode = row.copy(lengthSeconds = null))))
        assertEquals("Sorry, Wrong Number (1943-05-25)", episodeShareTitle(row))
        assertEquals("Sorry, Wrong Number (undated)", episodeShareTitle(row.copy(airDate = null)))
    }

    @Test fun `with no catalog and no network the line is the neutral offline one`() {
        assertEquals("You are offline.", catalogProblem(Loadable.NoCatalog, online = false))
        assertEquals("No catalog on this device yet.", catalogProblem(Loadable.NoCatalog, online = true))
        assertEquals("The catalog could not be read.", catalogProblem(Loadable.Failed, online = false))
        assertNull(catalogProblem(Loadable.Ready(1), online = false))
    }
}
