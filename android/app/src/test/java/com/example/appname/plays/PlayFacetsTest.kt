package com.example.appname.plays

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Record's browsing (Decision 075): voices, minutes, bands, facet counts, sorts, and author lines. Values are js/plays.test.js's. */
class PlayFacetsTest {
    private fun play(id: String, title: String, kind: String, vararg words: Int, sortName: String? = null) =
        fixtureScript().copy(
            id = id, title = title, kind = kind, sortName = sortName,
            roles = words.mapIndexed { i, w -> PlayScript.Role("R$i", 1, w) },
        )

    @Test fun `voices and minutes come from the roles, in bands`() {
        val s = play("a", "A", "radio", 3000, 1500, 10)
        assertEquals(3, s.voices)
        assertEquals(30, s.minutes)
        assertEquals("3-5", s.voiceBand)
        assertEquals("mid", s.lengthBand)
        assertEquals("short", play("b", "B", "radio", 100).lengthBand)
        assertEquals(1, play("b", "B", "radio", 100).minutes)
        assertEquals("11+", play("c", "C", "radio", *IntArray(11) { 1 }).voiceBand)
    }

    @Test fun `a facet option is counted with the other two applied and hidden at none`() {
        val scripts = listOf(
            play("a", "A", "radio", 100, 100),
            play("b", "B", "stage", 100, 100, 100),
            play("c", "C", "stage", 9000, 9000),
        )
        val all = PlayFacets.Filter()
        assertEquals(2, PlayFacets.count(scripts, all, PlayFacets.Facet.Kind, "stage"))
        val stage = all.copy(kind = "stage")
        // With Kind chosen, Voices is counted over stage plays only.
        assertEquals(1, PlayFacets.count(scripts, stage, PlayFacets.Facet.Voices, "1-2"))
        assertEquals(1, PlayFacets.count(scripts, stage, PlayFacets.Facet.Voices, "3-5"))
        assertEquals(listOf("1-2", "3-5"), PlayFacets.options(scripts, stage, PlayFacets.Facet.Voices, PlayFacets.VOICES).map { it.first })
        // The chosen option stays even at zero, so it can be undone.
        val none = all.copy(voices = "6-10")
        assertEquals(listOf("1-2", "3-5", "6-10"), PlayFacets.options(scripts, none, PlayFacets.Facet.Voices, PlayFacets.VOICES).map { it.first })
        assertTrue(PlayFacets.matching(scripts, none).isEmpty())
    }

    @Test fun `sorts break ties A to Z`() {
        val scripts = listOf(
            play("a", "Zeta", "radio", 100, 100),
            play("b", "alpha", "radio", 100, 100),
            play("c", "Mid", "radio", 100, 100, 100, sortName = "aaa first"),
        )
        assertEquals(listOf("b", "a", "c"), PlayFacets.sorted(scripts, "voices").map { it.id })
        assertEquals(listOf("c", "b", "a"), PlayFacets.sorted(scripts, "name").map { it.id })
        assertEquals(listOf("b", "a", "c"), PlayFacets.sorted(scripts, "short").map { it.id })
    }

    @Test fun `an author reads by the record's display name, never the filed form`() {
        val s = fixtureScript().copy(
            authors = listOf(
                PlayScript.Author(name = "Baker, George M. (George Melville)", display = "George Melville Baker", born = 1832, died = 1890),
                PlayScript.Author(name = "Carlton, Henry Fisk"),
            ),
        )
        assertEquals("George Melville Baker, Henry Fisk Carlton", s.authorLine)
        assertEquals("George Melville Baker (1832–1890), Henry Fisk Carlton", s.authorWithYears)
    }
}
