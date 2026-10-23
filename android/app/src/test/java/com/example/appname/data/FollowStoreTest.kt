package com.example.appname.data

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * ANDROID-DESIGN §4.3: Follow and Following write the store sync already
 * carries (§2.3), so an unfollow is a marker that reaches the other devices,
 * and Library's Following lists the newest follow first.
 */
class FollowStoreTest {
    @get:Rule val tmp = TemporaryFolder()
    private var clock = 1_000L
    private val user by lazy { UserStore.open(tmp.newFile("user.sqlite").path) { clock } }

    @Test fun `follow, list, and unfollow as a marker that syncs`() = runBlocking {
        assertFalse(user.isFollowing("suspense"))
        val before = user.changes.value
        user.setFollowing("suspense", true)
        clock = 2_000
        user.setFollowing("lux", true)
        assertTrue("a write bumps the screens' key", user.changes.value > before)
        assertTrue(user.isFollowing("suspense"))
        assertEquals(listOf("lux", "suspense"), user.followed())

        val sent = user.localChanges(all = false)
        assertEquals(setOf("suspense", "lux"), sent.follows.map { it.seriesId }.toSet())
        user.markUploaded(sent)
        assertTrue(user.localChanges(all = false).follows.isEmpty())

        clock = 3_000
        user.setFollowing("suspense", false)
        assertFalse(user.isFollowing("suspense"))
        assertEquals(listOf("lux"), user.followed())
        val marker = user.localChanges(all = false).follows.single()
        assertEquals("suspense", marker.seriesId)
        assertFalse("an unfollow is sent as following = false, never dropped", marker.following)
        assertEquals(3_000L, marker.updatedAt)
    }
}
