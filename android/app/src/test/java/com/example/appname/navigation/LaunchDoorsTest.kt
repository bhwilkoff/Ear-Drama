package com.example.appname.navigation

import org.junit.Assert.assertEquals
import org.junit.Test

class LaunchDoorsTest {
    private val extras = mapOf<String, Any?>(
        LaunchDoors.EXTRA_START_TAB to "library",
        LaunchDoors.EXTRA_START_ITEM to "item-42",
        LaunchDoors.EXTRA_MUTE to true,
        LaunchDoors.EXTRA_DOOR_SECONDS to 180,
    )

    @Test
    fun alongDoorNamesAProductionOrARehearsal() {
        assertEquals(listOf<InboxRequest>(InboxRequest.Along("p1")), LaunchDoors(startAlong = "p1").requests())
        assertEquals("door-along:auto", LaunchDoors.alongPid("rehearsal"))
        assertEquals("door-along:s9", LaunchDoors.alongPid("rehearsal:s9"))
        assertEquals(LaunchDoors(), LaunchDoors.from(mapOf(LaunchDoors.EXTRA_START_ALONG to "p1"), debug = false))
    }

    @Test
    fun releaseBuildIgnoresEveryDoor() {
        assertEquals(LaunchDoors(), LaunchDoors.from(extras, debug = false))
    }

    @Test
    fun debugBuildOpensTheDoors() {
        val doors = LaunchDoors.from(extras, debug = true)
        assertEquals(LaunchDoors("library", "item-42", mute = true, doorSeconds = 180), doors)
        assertEquals(
            listOf(InboxRequest.Tab("library"), InboxRequest.Item("item-42")),
            doors.requests(),
        )
    }

    /** Decision 075: five tabs; Stations and Surprise are Home pushes, and the old names still open. */
    @Test
    fun tabsAreActionsAndOldNamesStillOpen() {
        assertEquals(listOf("Home", "Browse", "Record", "Search", "Library"), Tab.entries.map { it.label })
        assertEquals(Tab.Home, Tab.named("listen"))
        assertEquals(Tab.Browse, Tab.named("series"))
        assertEquals(null, Tab.named("radio"))
        assertEquals(Route.Radio, Tab.pushedFromHome("radio"))
        assertEquals(Tab.Record, Tab.named("plays"))
        assertEquals(Route.Radio, Tab.pushedFromHome("stations"))
        assertEquals(Route.Surprise, Tab.pushedFromHome("surprise"))
        assertEquals(null, Tab.pushedFromHome("library"))
        assertEquals(null, Tab.named("surprise"))
    }

    @Test
    fun stringTypedExtrasAreAccepted() {
        val doors = LaunchDoors.from(
            mapOf(LaunchDoors.EXTRA_MUTE to "1", LaunchDoors.EXTRA_DOOR_SECONDS to "30"),
            debug = true,
        )
        assertEquals(LaunchDoors(mute = true, doorSeconds = 30), doors)
    }

    @Test
    fun forceOfflineDoorOpensOnlyInDebug() {
        val extras = mapOf<String, Any?>(LaunchDoors.EXTRA_FORCE_OFFLINE to "1")
        assertEquals(true, LaunchDoors.from(extras, debug = true).forceOffline)
        assertEquals(false, LaunchDoors.from(extras, debug = false).forceOffline)
    }
}
