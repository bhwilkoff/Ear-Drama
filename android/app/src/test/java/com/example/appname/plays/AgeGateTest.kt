package com.example.appname.plays

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgeGateTest {
    @Test fun the13thYearCountsAsUnder13() {
        assertTrue(AgeGate.isUnder13(2013, 2026))
        assertTrue(AgeGate.isUnder13(2014, 2026))
        assertTrue(AgeGate.isUnder13(2026, 2026))
    }

    @Test fun anEarlierYearIs13AndOver() {
        assertFalse(AgeGate.isUnder13(2012, 2026))
        assertFalse(AgeGate.isUnder13(1950, 2026))
    }

    @Test fun theYearsRunNewestFirstForAHundredAndTwentyYears() {
        val years = AgeGate.years(2026)
        assertEquals(120, years.size)
        assertEquals(2026, years.first())
        assertEquals(1907, years.last())
    }

    @Test fun aClassDateIsNeverShiftedByATimeZone() {
        val saved = java.util.TimeZone.getDefault()
        try {
            for (zone in listOf("Pacific/Kiritimati", "Pacific/Pago_Pago")) {
                java.util.TimeZone.setDefault(java.util.TimeZone.getTimeZone(zone))
                assertTrue(ClassDates.text("2027-01-15", java.util.Locale.US).contains("15"))
            }
        } finally { java.util.TimeZone.setDefault(saved) }
    }
}
