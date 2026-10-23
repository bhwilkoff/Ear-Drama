package com.example.appname.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ComponentsTest {
    @Test fun `dates show as the catalog stores them (R1)`() {
        assertEquals("1943-02-24", formatAirDate("1943-02-24"))
        assertNull(formatAirDate(null))
        assertNull(formatAirDate(""))
    }

    @Test fun `with no catalog and no network the line is the neutral offline one`() {
        assertEquals("You are offline.", catalogProblem(Loadable.NoCatalog, online = false))
        assertEquals("No catalog on this device yet.", catalogProblem(Loadable.NoCatalog, online = true))
        assertEquals("The catalog could not be read.", catalogProblem(Loadable.Failed, online = false))
        assertNull(catalogProblem(Loadable.Ready(1), online = false))
    }
}
