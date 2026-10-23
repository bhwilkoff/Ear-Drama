package com.example.appname.playback

import com.example.appname.data.EpisodeDetail
import com.example.appname.data.EpisodeRow
import com.example.appname.data.Recording
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test
import kotlin.math.min
import kotlin.math.pow

/** DECISIONS 061, the same cases as js/api.test.js `playbackVolume`. */
class LoudnessLevelTest {
    private fun db(gain: Double) = 10.0.pow(gain / 20).toFloat()

    @Test fun `reaches -21 LUFS by cutting, clamped at -1 dBTP`() {
        assertEquals("a loud episode is cut 6 dB", db(-6.0), LoudnessLevel.volume(-15.0, -6.0), 1e-6f)
        assertEquals("-18 LUFS is cut 3 dB", db(-3.0), LoudnessLevel.volume(-18.0, -1.3), 1e-6f)
        assertEquals("a quiet episode is never boosted", 1f, LoudnessLevel.volume(-25.0, -10.0))
        assertEquals(
            "a hot peak pulls the gain below the loudness target (clamp)",
            db(-2.0), LoudnessLevel.volume(-20.0, 1.0), 1e-6f,
        )
        assertEquals("unmeasured plays at unity", 1f, LoudnessLevel.volume(null, null))
        assertEquals("no loudness, no change", 1f, LoudnessLevel.volume(null, -3.0))
    }

    /** Negative control: a version without the true-peak clamp gets the clamp case wrong. */
    @Test fun `the clamp case rejects an unclamped version`() {
        fun unclamped(i: Double) = db(min(LoudnessLevel.TARGET - i, 0.0))
        assertNotEquals(db(-2.0), unclamped(-20.0), 1e-3f)
        assertEquals(db(-6.0), unclamped(-15.0), 1e-6f)
    }

    @Test fun `only the default copy carries the measurement`() {
        fun copy(rank: Int, url: String) = Recording(rank, "x", url, null, null, null, null, false)
        val detail = EpisodeDetail(
            episode = EpisodeRow("x|1950-01-01", "x", "X", "1950-01-01", null, null, null, null),
            rights = "unclaimed", rightsBasis = null, network = null, noRecommend = null, credits = emptyList(),
            recordings = listOf(copy(0, "https://a/main.mp3"), copy(1, "https://a/afrs.mp3")),
            detailJson = null, loudnessI = -15.0, loudnessTp = -6.0,
        )
        assertEquals(db(-6.0), LoudnessLevel.volume(detail, "https://a/main.mp3"), 1e-6f)
        assertEquals(1f, LoudnessLevel.volume(detail, "https://a/afrs.mp3"))
    }
}
