package com.example.appname.data

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** ANDROID-DESIGN §4.1: Home's Following shelf is the store's follows, newest first, minus any the catalog lacks. */
class FollowingHomeTest {
    @get:Rule val tmp = TemporaryFolder()
    private var clock = 1_000L
    private val user by lazy { UserStore.open(tmp.newFile("user.sqlite").path) { clock } }

    private fun row(key: String) = SeriesRow(key, key.uppercase(), null, null, null, 3)

    @Test fun `the shelf is the newest follow first and skips what the catalog lacks`() = runBlocking {
        user.setFollowing("suspense", true)
        clock = 2_000
        user.setFollowing("gone", true)
        clock = 3_000
        user.setFollowing("lux", true)
        clock = 4_000
        user.setFollowing("suspense", false)
        val served = setOf("suspense", "lux")
        val shelf = resolveFollowing(user.followed()) { if (it in served) row(it) else null }
        assertEquals(listOf("lux"), shelf.map { it.key })
        clock = 5_000
        user.setFollowing("suspense", true)
        val again = resolveFollowing(user.followed()) { if (it in served) row(it) else null }
        assertEquals(listOf("suspense", "lux"), again.map { it.key })
    }

    @Test fun `nobody followed means no shelf`() = runBlocking {
        assertTrue(resolveFollowing(user.followed()) { row(it) }.isEmpty())
    }
}
