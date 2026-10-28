package com.example.appname.playback

import com.google.android.gms.cast.framework.CastState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CastRouteTest {

    @Test
    fun offeredOnlyOnAPhoneWithPlayServices() {
        assertTrue(CastRoute.offers(playServices = true, television = false))
        assertFalse("Fire TV and phones without Play services", CastRoute.offers(playServices = false, television = false))
        assertFalse("a TV is a receiver", CastRoute.offers(playServices = true, television = true))
        assertFalse(CastRoute.offers(playServices = false, television = true))
    }

    @Test
    fun buttonShowsOnlyWhileAReceiverIsOnTheNetwork() {
        assertFalse(CastRoute.showsButton(offered = true, castState = CastState.NO_DEVICES_AVAILABLE))
        assertTrue(CastRoute.showsButton(offered = true, castState = CastState.NOT_CONNECTED))
        assertTrue(CastRoute.showsButton(offered = true, castState = CastState.CONNECTING))
        assertTrue(CastRoute.showsButton(offered = true, castState = CastState.CONNECTED))
        assertFalse("not offered: never", CastRoute.showsButton(offered = false, castState = CastState.CONNECTED))
    }

    @Test
    fun theReceiverPlaysTheCatalogCopyNeverAPhoneFile() {
        val copy = "https://archive.org/download/OTRR_X_Minus_One/XMinusOne_56-04-24.mp3"
        assertEquals(copy, CastRoute.receiverUrl("file:///data/user/0/app.eardrama/files/downloads/a.mp3", copy))
        assertEquals(copy, CastRoute.receiverUrl(copy, copy))
        assertEquals("no catalog copy: what plays", copy, CastRoute.receiverUrl(copy, null))
        assertEquals("a non-web copy is never handed over", copy, CastRoute.receiverUrl(copy, "content://x/y.mp3"))
    }

    @Test
    fun contentTypeFromTheExtension() {
        assertEquals("audio/mpeg", CastRoute.mimeTypeFor("https://archive.org/download/a/b.mp3"))
        assertEquals("audio/mpeg", CastRoute.mimeTypeFor("https://archive.org/download/a/B.MP3?x=1"))
        assertEquals("audio/ogg", CastRoute.mimeTypeFor("https://archive.org/download/a/b.ogg"))
        assertEquals("audio/mp4", CastRoute.mimeTypeFor("https://archive.org/download/a/b.m4a"))
        assertEquals("audio/flac", CastRoute.mimeTypeFor("https://archive.org/download/a/b.flac"))
        assertEquals("audio/mpeg", CastRoute.mimeTypeFor("https://archive.org/download/a.dir/b"))
    }
}
