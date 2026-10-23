package com.example.appname.together

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** ANDROID-DESIGN §4.13 and Decision 065 against a Worker built from room-protocol.js's rules (FakeRooms). */
class ListenTogetherTest {
    private var clock = 1_761_200_000_000L
    private val worker = FakeRooms { clock }
    private val scope = CoroutineScope(Dispatchers.Unconfined)

    private val copy = RoomState(
        episodeId = "suspense|1948-03-11",
        archiveId = "OTRR_Suspense_Singles",
        file = "Suspense 48-03-11 The Lodger.mp3",
        position = 612.5,
        playing = true,
        rate = 1.0,
        updatedAt = 0,
    )

    private fun session(player: FakeRoomPlayer = FakeRoomPlayer(), api: RoomsApi = worker.api()) =
        ListenTogether(api, player, scope, now = { clock }, autoPoll = false)

    private fun hostAndGuest(): Triple<Pair<ListenTogether, FakeRoomPlayer>, Pair<ListenTogether, FakeRoomPlayer>, String> = runBlocking {
        val hostPlayer = FakeRoomPlayer().apply { host = copy; episode = copy.episodeId; position = copy.position; playing = true }
        val host = session(hostPlayer)
        host.create()
        val code = (host.status.value as RoomStatus.In).code
        clock += 1000
        val guestPlayer = FakeRoomPlayer()
        val guest = session(guestPlayer)
        // Typed as a person hears it: lower case, a dash, and the letter O for zero.
        guest.join(code.lowercase().replace("0", "o").let { it.take(3) + "-" + it.drop(3) })
        Triple(host to hostPlayer, guest to guestPlayer, code)
    }

    @Test fun `a guest joins by code, plays the host's copy, and leaves`() = runBlocking {
        val (host, guest, code) = hostAndGuest()
        assertEquals(RoomStatus.In(code, isHost = true, members = 1), host.first.status.value)
        assertEquals(RoomStatus.In(code, isHost = false, members = 2), guest.first.status.value)
        val loaded = guest.second.loads.single()
        assertEquals("the host's exact copy", copy.archiveId to copy.file, loaded.archiveId to loaded.file)
        assertEquals("a second into the room the host is a second on", 613.5, guest.second.position, 1e-6)
        guest.first.leave()
        assertEquals(RoomStatus.Out(), guest.first.status.value)
        assertEquals(1, worker.members(code))
        host.first.pollOnce()
        assertEquals(RoomStatus.In(code, isHost = true, members = 1), host.first.status.value)
    }

    @Test fun `a guest cannot drive`() = runBlocking {
        val (_, guest, code) = hostAndGuest()
        guest.second.host = copy.copy(position = 10.0, playing = false)
        guest.first.publishNow()
        guest.first.end()
        assertEquals("a guest's session sends no state and no end", 0, worker.count("PUT") + worker.count("DELETE"))
        // And the Worker refuses the guest's key outright, the room unchanged.
        val guestKey = worker.joinedKeys.single()
        val before = worker.state(code)
        try {
            worker.api().putState(code, guestKey, copy.copy(playing = false))
            fail("a guest's write was accepted")
        } catch (e: RoomException) {
            assertEquals(403, e.status)
            assertEquals("host_only", e.error)
        }
        assertEquals(before, worker.state(code))
        assertTrue(guest.first.inRoom)
    }

    @Test fun `guests follow the host's pause, seek, and speed`() = runBlocking {
        val (host, guest, code) = hostAndGuest()
        val (hostSession, hostPlayer) = host
        val (guestSession, guestPlayer) = guest
        guestPlayer.playing = true
        guestPlayer.position = 613.5

        clock += 2000
        hostPlayer.host = copy.copy(position = 615.0, playing = false)
        hostSession.publishNow()
        guestPlayer.position = 615.4
        guestSession.pollOnce()
        assertEquals(Correction.Pause(615.0), guestPlayer.applied.last())

        guestPlayer.playing = false
        hostPlayer.host = copy.copy(position = 30.0, playing = true, rate = 1.5)
        hostSession.publishNow()
        clock += 1000
        guestSession.pollOnce()
        assertEquals("far off: a seek, then play", Correction.Seek(31.5, play = true), guestPlayer.applied.last())

        guestPlayer.playing = true
        guestPlayer.position = 32.0
        guestSession.pollOnce()
        assertEquals("half a second ahead: the host's speed less 3%", Correction.Rate(1.5 * (1 - RoomProtocol.NUDGE)), guestPlayer.applied.last())
        assertEquals(code, (guestSession.status.value as RoomStatus.In).code)
    }

    @Test fun `when the host leaves the longest-present member takes over and drives`() = runBlocking {
        val (host, guest, code) = hostAndGuest()
        val third = session(FakeRoomPlayer())
        clock += 1000
        third.join(code)
        host.first.leave()
        guest.first.pollOnce()
        third.pollOnce()
        assertEquals(RoomStatus.In(code, isHost = true, members = 2), guest.first.status.value)
        assertEquals("the later joiner stays a guest", false, (third.status.value as RoomStatus.In).isHost)
        assertEquals("the new host's speed is the room's, never a nudge", Correction.Rate(1.0), guest.second.applied.last())
        guest.second.host = copy.copy(position = 700.0, playing = false)
        guest.first.publishNow()
        assertEquals(700.0, worker.state(code)!!.position, 1e-9)
        assertFalse(worker.state(code)!!.playing)
    }

    @Test fun `a host gone quiet for two minutes hands off too`() = runBlocking {
        val (_, guest, code) = hostAndGuest()
        clock += RoomProtocol.MEMBER_GONE_MS + 1
        guest.first.pollOnce()
        assertEquals(RoomStatus.In(code, isHost = true, members = 1), guest.first.status.value)
    }

    @Test fun `an ended room and a wrong code are one plain line`() = runBlocking {
        val (host, guest, _) = hostAndGuest()
        host.first.end()
        assertEquals(RoomStatus.Out(), host.first.status.value)
        guest.first.pollOnce()
        assertEquals(RoomStatus.Out(ListenTogether.ENDED), guest.first.status.value)

        val stranger = session()
        stranger.join("ZZZZZZ")
        assertEquals(RoomStatus.Out(ListenTogether.NO_SUCH_ROOM), stranger.status.value)
        val before = worker.calls.size
        stranger.join("7KQ2MU")
        assertEquals(RoomStatus.Out(ListenTogether.NO_SUCH_ROOM), stranger.status.value)
        assertEquals("a code that cannot be one is never sent", before, worker.calls.size)
    }

    @Test fun `a placeholder Worker URL is not available and sends nothing`() = runBlocking {
        val player = FakeRoomPlayer().apply { host = copy; episode = copy.episodeId }
        val off = session(player, worker.api("REPLACE_WITH_WORKER_BASE_URL"))
        assertEquals(RoomStatus.Unavailable, off.status.value)
        off.create()
        off.join("7KQ2MX")
        assertEquals(RoomStatus.Unavailable, off.status.value)
        assertEquals(0, worker.calls.size)
    }
}
