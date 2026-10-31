package com.example.appname.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** The person page's per-show years and run strip: the person's own episodes, as the web's `stripOf`. */
class PersonShowsTest {
    private fun credit(date: String?) =
        PersonEpisode(EpisodeRow("s|${date ?: "x"}", "s", "S", date, null, null, null, null), emptyList())

    @Test fun theStripCountsTheirEpisodesPerYear() {
        val eps = listOf(credit("1946-02-06"), credit("1946-02-27"), credit("1948-01-01"), credit(null))
        assertEquals(listOf(1946, 2, 0, 1), PersonShows.yearCounts(eps))
        assertEquals("1946", PersonShows.first(eps))
        assertEquals("1948", PersonShows.last(eps))
    }

    @Test fun undatedEpisodesDrawNoStrip() {
        assertNull(PersonShows.yearCounts(listOf(credit(null))))
        assertNull(PersonShows.first(listOf(credit(null))))
    }

    @Test fun theTileTakesThePersonsYearsAndTheSeriesPicture() {
        val art = Artwork("https://x/a.jpg", 600, 800)
        val series = SeriesRow("s", "S", "drama", "1930-01-01", "1960-01-01", 500, picture = art)
        val tile = PersonShows.tile(series, "s", "S", listOf(credit("1946-02-06"), credit("1948-01-01")))
        assertEquals(2, tile.episodes)
        assertEquals("1946", tile.firstDate)
        assertEquals(art, tile.picture)
        assertEquals("drama", tile.genre)
    }
}
