package com.example.appname.ui

import com.example.appname.data.EpisodeRow
import com.example.appname.data.Progress
import com.example.appname.plays.PlaysShare
import com.example.appname.plays.Production
import com.example.appname.ui.screens.LibraryModel
import org.junit.Assert.assertEquals
import org.junit.Test

class LibraryModelTest {
    private fun ep(id: String) = EpisodeRow(id, "s", "Show", null, null, null, id, 60.0)
    private fun prod(id: String, script: String, title: String) = Production(id, script, "r", title, 0.0)
    private fun row(p: Production) = PlaysShare.LibraryRow(p, null)

    @Test fun sideDefaultsToListening() {
        assertEquals(LibraryModel.LISTENING, LibraryModel.side(null))
        assertEquals(LibraryModel.LISTENING, LibraryModel.side("junk"))
        assertEquals(LibraryModel.MAKING, LibraryModel.side("making"))
    }

    @Test fun upNextIsStartedThenQueueWithoutRepeats() {
        val started = listOf(ep("a") to Progress("a", 1000, 5000, false))
        val up = LibraryModel.upNext(started, listOf(ep("b"), ep("a"), ep("c")))
        assertEquals(listOf("a", "b", "c"), up.map { it.row.id })
        assertEquals(listOf(true, false, false), up.map { it.progress != null })
    }

    @Test fun nineProductionsOfOnePlayAreOneGroup() {
        val rows = (1..9).map { row(prod("p$it", "albany", "The Albany Depot")) } + row(prod("q", "other", "Other"))
        val groups = LibraryModel.groups(rows)
        assertEquals(2, groups.size)
        assertEquals(9, groups[0].count)
        assertEquals("9 productions · newest in progress", groups[0].line)
        assertEquals("In progress", groups[1].line)
    }
}
