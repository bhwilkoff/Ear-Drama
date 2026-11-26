package com.example.appname.plays

import com.example.appname.kokoro.KokoroModelStore
import com.example.appname.kokoro.KokoroModule
import com.example.appname.navigation.LaunchDoors
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** The Better voices step's record (PLAYS-DESIGN §2.8 rule 13; ANDROID-DESIGN §4.6b). */
class VoicesOfferTest {
    private class Mem(var value: Int = VoicesOffer.NEVER, var writes: Int = 0) : VoicesOffer.Store {
        override fun read() = value
        override fun write(stage: Int) { value = stage; writes++ }
    }

    @Test fun firstLaunchShowsOnce() {
        val m = Mem()
        val o = VoicesOffer(m)
        assertTrue(o.atLaunch(true))
        assertEquals(VoicesOffer.AT_LAUNCH, m.value)
        assertFalse("a second launch never shows it", o.atLaunch(true))
    }

    @Test fun skipIsRememberedAndOfferedOnceAtFirstRead() {
        val m = Mem()
        val o = VoicesOffer(m)
        o.atLaunch(true)
        val relaunched = VoicesOffer(m)
        assertFalse(relaunched.atLaunch(true))
        assertTrue("offered again at the first Read", relaunched.atFirstUse(true))
        assertFalse("never a third time", relaunched.atFirstUse(true))
        assertFalse(relaunched.atLaunch(true))
        assertEquals(VoicesOffer.DONE, m.value)
    }

    @Test fun launchThatCouldNotOfferStillOffersAtFirstUseOnce() {
        val o = VoicesOffer(Mem())
        assertFalse(o.atLaunch(false))
        assertTrue(o.atFirstUse(true))
        assertFalse(o.atFirstUse(true))
    }

    @Test fun neverAfterADownload() {
        val m = Mem()
        val o = VoicesOffer(m)
        o.downloadBegan()
        assertFalse(o.atLaunch(true))
        assertFalse(o.atFirstUse(true))
        val skipped = VoicesOffer(Mem())
        skipped.atLaunch(true)
        skipped.downloadBegan()
        assertFalse(skipped.atFirstUse(true))
    }

    @Test fun doorsReadAndWriteNothing() {
        val done = Mem(VoicesOffer.DONE)
        assertTrue("the forcing door shows it even when done", VoicesOffer(done).atLaunch(false, force = true, skip = false))
        assertEquals(0, done.writes)
        val fresh = Mem()
        assertTrue(VoicesOffer(fresh).atLaunch(true, force = true, skip = false))
        assertFalse("the skip door keeps it away", VoicesOffer(fresh).atLaunch(true, force = false, skip = true))
        assertEquals(0, fresh.writes)
        assertEquals(VoicesOffer.NEVER, fresh.value)
    }

    @Test fun ineligibleWritesNothing() {
        val m = Mem()
        val o = VoicesOffer(m)
        assertFalse(o.atLaunch(false))
        assertFalse(o.atFirstUse(false))
        assertEquals(0, m.writes)
    }

    @Test fun eligibilityFollowsTheDownload() {
        val absent = KokoroModelStore.State.Absent
        assertTrue(VoicesOffer.eligible(true, absent, KokoroModule.State.Absent))
        assertTrue(VoicesOffer.eligible(true, KokoroModelStore.State.Failed("x"), KokoroModule.State.Absent))
        assertFalse("unsupported", VoicesOffer.eligible(false, absent, KokoroModule.State.Absent))
        assertFalse("here", VoicesOffer.eligible(true, KokoroModelStore.State.Ready, KokoroModule.State.Installed))
        assertFalse("downloading", VoicesOffer.eligible(true, KokoroModelStore.State.Downloading(1, 2), KokoroModule.State.Installed))
        assertFalse("module coming", VoicesOffer.eligible(true, absent, KokoroModule.State.Pending))
        assertFalse("module downloading", VoicesOffer.eligible(true, absent, KokoroModule.State.Downloading(1, 2)))
        assertTrue(VoicesOffer.begun(KokoroModelStore.State.Ready, KokoroModule.State.Absent))
        assertFalse(VoicesOffer.begun(absent, KokoroModule.State.Absent))
    }

    @Test fun lowSpaceIsSizePlusTwentyPercent() {
        assertTrue(VoicesOffer.lowSpace(119_000_000, 100_000_000))
        assertFalse(VoicesOffer.lowSpace(120_000_000, 100_000_000))
        assertFalse("no size known", VoicesOffer.lowSpace(0, 0))
    }

    @Test fun systemVoicesLineOnlyWithoutAHighQualityVoice() {
        val low = CastVoice("a", "A", "en-US", 300)
        val high = CastVoice("b", "B", "en-US", 400)
        assertTrue(VoicesOffer.wantsSystemVoices(listOf(low)))
        assertFalse(VoicesOffer.wantsSystemVoices(listOf(low, high)))
        assertFalse("voices not listed yet", VoicesOffer.wantsSystemVoices(emptyList()))
    }

    @Test fun doorsAreDebugOnlyAndNamedFromTheHook() {
        val extras = mapOf(LaunchDoors.EXTRA_SKIP_ONBOARD to "1", LaunchDoors.EXTRA_VOICES_STEP to true)
        val d = LaunchDoors.from(extras, debug = true)
        assertTrue(d.skipOnboard)
        assertTrue(d.voicesStep)
        val release = LaunchDoors.from(extras, debug = false)
        assertFalse(release.skipOnboard)
        assertFalse(release.voicesStep)
        assertEquals("appname_skip_onboard", LaunchDoors.EXTRA_SKIP_ONBOARD)
    }
}
