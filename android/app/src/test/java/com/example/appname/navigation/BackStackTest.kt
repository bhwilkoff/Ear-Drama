package com.example.appname.navigation

import androidx.navigation3.runtime.NavKey
import org.junit.Assert.assertEquals
import org.junit.Test

/** ANDROID-DESIGN §3.5: a route already on the tab's stack is popped back to, never stacked again. */
class BackStackTest {
    private fun stack(vararg routes: Route): MutableList<NavKey> = mutableListOf<NavKey>(*routes)

    @Test fun `Detail's series link returns to the series page it came from`() {
        val s = stack(Route.SeriesBrowse, Route.Series("suspense"), Route.Episode("sus|1"))
        s.navigateTo(Route.Series("suspense"))
        assertEquals(listOf(Route.SeriesBrowse, Route.Series("suspense")), s)
    }

    @Test fun `the transcript is pushed once, and a second replaces it`() {
        val s = stack(Route.SeriesBrowse, Route.Series("suspense"), Route.Episode("sus|1"))
        s.navigateTo(Route.Transcript("sus|1"))
        s.navigateTo(Route.Transcript("sus|1"))
        assertEquals(listOf(Route.SeriesBrowse, Route.Series("suspense"), Route.Episode("sus|1"), Route.Transcript("sus|1")), s)
        s.navigateTo(Route.Transcript("sus|2"))
        assertEquals(Route.Transcript("sus|2"), s.last())
        assertEquals(4, s.size)
    }

    @Test fun `the player's Open episode from the transcript pops back to Detail`() {
        val s = stack(Route.Listen, Route.Episode("sus|1"), Route.Transcript("sus|1"))
        s.navigateTo(Route.Episode("sus|1"))
        assertEquals(listOf(Route.Listen, Route.Episode("sus|1")), s)
    }

    @Test fun `a new route is pushed`() {
        val s = stack(Route.Search)
        s.navigateTo(Route.Episode("sus|1"))
        s.navigateTo(Route.Series("suspense"))
        assertEquals(listOf(Route.Search, Route.Episode("sus|1"), Route.Series("suspense")), s)
    }
}
