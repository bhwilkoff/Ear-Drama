package com.example.appname.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
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
        assertEquals("1943-05", formatAirDateLong("1943-05", Locale.US))
    }

    @Test fun `no date is none`() {
        assertNull(formatAirDateLong(null, Locale.US))
        assertNull(formatAirDateLong(" ", Locale.US))
    }
}
