package com.example.appname.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ConnectivityTest {
    /** The status line above the mini player comes with no network and goes when it returns. */
    @Test
    fun offlineLineComesAndGoesWithTheNetwork() {
        assertEquals("You are offline.", offlineLine(online = false))
        assertNull(offlineLine(online = true))
    }
}
