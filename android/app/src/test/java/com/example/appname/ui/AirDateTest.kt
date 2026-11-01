package com.example.appname.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Locale

/** The episode page's date: a full day in the long format, anything less precise as the catalog states it (R1). */
class AirDateTest {
    @Test fun `a full day reads in the long format`() {
        assertEquals("May 25, 1943", formatAirDateLong("1943-05-25", Locale.US))
        assertEquals("25 May 1943", formatAirDateLong("1943-05-25", Locale.UK))
    }

    @Test fun `a year or a month stays as precise as the catalog is`() {
        assertEquals("1943", formatAirDateLong("1943", Locale.US))
        assertEquals("May 1943", formatAirDateLong("1943-05", Locale.US))
    }

    @Test fun `rows and event lines use the medium form and never an ISO date`() {
        assertEquals("Sep 17, 1949", formatAirDate("1949-09-17", Locale.US))
        assertEquals("Sep 1949", formatAirDate("1949-09", Locale.US))
        assertEquals("1949", formatAirDate("1949", Locale.US))
        assertEquals("Abbott & Costello (Apr 14, 1947)", spellingDates("Abbott & Costello (1947-04-14)", Locale.US))
        val iso = Regex("""\d{4}-\d{2}""")
        assertTrue("control: the pattern catches a raw date", iso.containsMatchIn("1949-09-17"))
        for (date in listOf("1949-09-17", "1949-09", "1949", "1931-01-01", "1947-13-40")) {
            for (text in listOfNotNull(formatAirDate(date, Locale.US), formatAirDateLong(date, Locale.US))) {
                if (date == "1947-13-40") continue // no day to spell: shown as stored, never invented
                assertFalse("$text is an ISO date", iso.containsMatchIn(text))
            }
        }
    }

    @Test fun `no date is none`() {
        assertNull(formatAirDateLong(null, Locale.US))
        assertNull(formatAirDateLong(" ", Locale.US))
    }
}
