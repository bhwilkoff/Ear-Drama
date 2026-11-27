package com.example.appname.plays

import org.junit.Assert.assertEquals
import org.junit.Test

/** js/plays.test.js "an author's years" and apple PlayFactsTests: the same golden table. */
class AuthorYearsTest {
    @Test
    fun anAuthorsYearsReadAsPrinted() {
        val golden = listOf(
            Triple(1856, 1950, "1856–1950"), Triple(-450, -388, "450–388 BCE"), Triple(-4, 65, "4 BCE–65"),
            Triple(1901, null, "b. 1901"), Triple(-450, null, "b. 450 BCE"), Triple(null, 1950, "d. 1950"),
            Triple(null, -388, "d. 388 BCE"), Triple(null, null, ""),
        )
        for ((born, died, want) in golden) assertEquals("$born, $died", want, lifeYears(born, died))
    }

    @Test
    fun aLifeBeforeTheEraIsNeverNegativeYears() {
        val script = fixtureScript().copy(authors = listOf(PlayScript.Author(name = "Aristophanes", display = "Aristophanes", born = -450, died = -388)))
        assertEquals("Aristophanes (450–388 BCE)", script.authorWithYears)
    }
}
