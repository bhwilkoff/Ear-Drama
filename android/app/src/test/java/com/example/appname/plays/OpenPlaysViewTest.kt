package com.example.appname.plays

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** What the open screens decide: the listing's order, the credit line, the order takes play in. */
class OpenPlaysViewTest {
    private fun play(id: String, at: Long, vararg names: String) = FinishedPlay(
        id = id, title = id, archiveUrl = "https://archive.org/details/$id", publishedAt = at,
        credits = names.mapIndexed { i, n -> FinishedCredit("role:P$i", n) },
    )

    @Test fun `newest first, ties by id descending`() {
        val got = OpenPlaysView.newestFirst(listOf(play("a", 1), play("c", 5), play("b", 5), play("d", 3)))
        assertEquals(listOf("c", "b", "d", "a"), got.map { it.id })
    }

    @Test fun `credits are the chosen names, once each, and a gone performer is never named`() {
        val p = play("x", 1, "Pat", "", "Sam", "Pat", "  ")
        assertEquals(listOf("Pat", "Sam"), OpenPlaysView.names(p))
        assertEquals("Pat, Sam", OpenPlaysView.creditLine(p))
    }

    @Test fun `a long cast shows three names and how many more`() {
        assertEquals("A, B, C +2", OpenPlaysView.creditLine(play("x", 1, "A", "B", "C", "D", "E")))
    }

    @Test fun `an uncredited drama has no credit line`() {
        assertNull(OpenPlaysView.creditLine(play("x", 1, "", "")))
    }

    @Test fun `the publish month is read in UTC`() {
        assertEquals("October 2026", OpenPlaysView.published(1_793_000_000_000))
        assertNull(OpenPlaysView.published(0))
    }

    private fun take(id: String, line: String, part: String) = OpenTake(id, line, part)
    private val invite = OpenInvite(
        id = "P", scriptID = "s", scriptRevision = "r", title = "T",
        takes = listOf(take("t3", "L3", "role:A"), take("t1", "L1", "role:A"), take("t2", "L2", "role:B"), take("tx", "LX", "role:B")),
    )

    @Test fun `takes play in the script's order, unknown lines last`() {
        val order = listOf("L1", "L2", "L3")
        assertEquals(listOf("t1", "t2", "t3", "tx"), OpenPlaysView.playOrder(invite, order).map { it.id })
        assertEquals(listOf("t1", "t3"), OpenPlaysView.playOrder(invite, order, "role:A").map { it.id })
    }

    @Test fun `a part is hearable only when it has a take`() {
        assertTrue(OpenPlaysView.hearable(invite, "role:A"))
        assertFalse(OpenPlaysView.hearable(invite, "role:C"))
    }

    private fun meta(vararg f: String) = """{"files":[${f.joinToString(",")}]}"""
    private fun file(name: String, format: String, extra: String = "") = """{"name":"$name","format":"$format"$extra}"""

    @Test fun `the item id is the last path segment`() {
        assertEquals("ed-abc", ArchivePick.itemId("https://archive.org/details/ed-abc"))
        assertEquals("ed-abc", ArchivePick.itemId("https://archive.org/details/ed-abc/?x=1"))
        assertNull(ArchivePick.itemId(""))
    }

    @Test fun `an MP3 is picked, never a private file or an old revision`() {
        val m = meta(
            file("play.wav", "WAV"), file("secret.mp3", "VBR MP3", ""","private":"true""""),
            file("history/files/a.mp3~1~", "VBR MP3"), file("b side.mp3", "VBR MP3"),
        )
        assertEquals("https://archive.org/download/it/b%20side.mp3", ArchivePick.pick("it", m))
    }

    @Test fun `a whole-play file comes before numbered per-line ones`() {
        val m = meta(file("0001-A.mp3", "VBR MP3"), file("whole.mp3", "128Kbps MP3"), file("0002-B.mp3", "VBR MP3"))
        assertEquals("https://archive.org/download/it/whole.mp3", ArchivePick.pick("it", m))
        assertEquals("https://archive.org/download/it/0001-A.mp3", ArchivePick.pick("it", meta(file("0002-B.mp3", "VBR MP3"), file("0001-A.mp3", "VBR MP3"))))
    }

    @Test fun `no MP3 yet is no file, not a broken one`() {
        assertNull(ArchivePick.pick("it", meta(file("0001-A.wav", "WAV"))))
        assertNull(ArchivePick.pick("it", "not json"))
    }
}
