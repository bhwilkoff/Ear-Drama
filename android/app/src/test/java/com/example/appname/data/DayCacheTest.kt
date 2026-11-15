package com.example.appname.data

import java.time.LocalDate
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class DayCacheTest {
    @Test
    fun `loads once a day, again the next day`() = runTest {
        var day = LocalDate.of(2026, 11, 14)
        var loads = 0
        val cache = DayCache<String> { day }
        assertEquals("a1", cache.get { loads += 1; "a$loads" })
        assertEquals("a1", cache.get { loads += 1; "a$loads" })
        assertEquals(1, loads)
        day = day.plusDays(1)
        assertEquals("a2", cache.get { loads += 1; "a$loads" })
    }

    @Test
    fun `a failed or empty load is not kept`() = runTest {
        val cache = DayCache<String> { LocalDate.of(2026, 11, 14) }
        assertNull(cache.get { null })
        try { cache.get { error("offline") } } catch (_: IllegalStateException) {}
        assertEquals("ok", cache.get { "ok" })
    }
}
