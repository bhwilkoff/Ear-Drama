package com.example.appname.plays

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Cutting a script into pages from measured heights (R2 brief §4). A fake measurer wraps each block at a number of
 * characters per visual line, so the cut runs over real scripts without a device: two "text sizes" (characters per
 * line, lines per page), every line's pages, contiguous pages, and the position line kept and read back after a
 * re-layout, up and down.
 *
 * Seen to fail, 2026-11-14, then restored: `paginate` without keep-with-next (`a heading stays with what follows it`).
 */
class ReaderPaginationTest {
    private fun scripts(): List<PlayScript> {
        var dir: File? = File("").absoluteFile
        while (dir != null && !File(dir, "catalog/plays/castable-scripts.json").exists()) dir = dir.parentFile
        val bundle = CastableLibrary.decode(File(dir!!, "catalog/plays/castable-scripts.json").readText()).scripts
        val lib = File(dir, "catalog/out/plays-library/scripts").listFiles().orEmpty().sortedBy { it.name }.take(6)
            .map { PlayScriptFile.decode(it.readText()).scripts.first() }
        return bundle.take(4) + lib
    }

    private fun blocks(s: PlayScript, charsPerLine: Int): List<ReaderPagination.Block> =
        s.lines.mapIndexed { i, l ->
            val n = maxOf(1, (ScriptReading.lineText(l).length + charsPerLine - 1) / charsPerLine)
            ReaderPagination.Block(i, FloatArray(n) { 10f }, 6f)
        }

    @Test fun `every line has pages, they are contiguous, and a page is never over full`() {
        for (s in scripts()) for ((chars, perPage) in listOf(40 to 300f, 28 to 240f)) {
            val paged = ReaderPagination.paginate(blocks(s, chars), s.lines.size, perPage)
            for (i in s.lines.indices) assertTrue("${s.id} line $i", paged.starts[i] in 0..paged.ends[i] && paged.ends[i] < paged.count)
            for (i in 1 until s.lines.size) {
                assertTrue("${s.id}: starts never go back", paged.starts[i] >= paged.starts[i - 1])
                assertTrue("${s.id}: a line starts on or after the page the last one ended", paged.starts[i] >= paged.ends[i - 1] || paged.starts[i] == paged.ends[i - 1])
            }
            paged.pages.forEachIndexed { p, page ->
                assertTrue("${s.id} page $p holds something", page.segs.isNotEmpty())
                assertTrue("${s.id} page $p fits", page.segs.last().bottom <= perPage + 0.5f)
            }
        }
    }

    @Test fun `the position line is kept and read back across a re-layout, up and down`() {
        for (s in scripts()) {
            val a = ReaderPagination.paginate(blocks(s, 40), s.lines.size, 300f)
            val b = ReaderPagination.paginate(blocks(s, 28), s.lines.size, 240f)
            val per = 2
            for (page in listOf(a.count / 3, a.count / 2, a.count - 1)) {
                val top = ReaderMath.lineAtPage(a.starts, a.ends, ReaderMath.spreadStart(page, per))
                val pos = top
                // size up, then down, then up again: the kept line never drifts backward.
                repeat(3) {
                    val inB = ReaderMath.spreadStart(b.starts[pos], per)
                    assertTrue("${s.id}: B shows the line", b.starts[pos] in inB until inB + per)
                    val inA = ReaderMath.spreadStart(a.starts[pos], per)
                    assertTrue("${s.id}: A shows the line", a.starts[pos] in inA until inA + per)
                }
            }
        }
    }

    @Test fun `a heading stays with what follows it`() {
        val heading = ReaderPagination.Block(2, floatArrayOf(10f), 6f, keepWithNext = true)
        val body = ReaderPagination.Block(3, floatArrayOf(10f, 10f, 10f), 6f)
        val paged = ReaderPagination.paginate(
            listOf(ReaderPagination.Block(0, floatArrayOf(10f), 6f), ReaderPagination.Block(1, floatArrayOf(10f), 6f), heading, body), 4, 50f,
        )
        val headingPage = paged.pages.indexOfFirst { p -> p.segs.any { it.block == 2 } }
        assertEquals("the heading is on the page where its text begins", paged.starts[3], headingPage)
    }

    @Test fun `a block taller than a page is split, and an empty script has one page`() {
        val tall = ReaderPagination.Block(0, FloatArray(25) { 10f }, 6f)
        val paged = ReaderPagination.paginate(listOf(tall), 1, 100f)
        assertEquals(3, paged.count)
        assertEquals(0, paged.starts[0])
        assertEquals(2, paged.ends[0])
        assertEquals(1, ReaderPagination.paginate(emptyList(), 0, 100f).count)
    }

    private fun b(owner: Int, lines: Int, gap: Float = 6f, keep: Boolean = false, breakBefore: Boolean = false, speech: Int = -1, start: Boolean = false, rows: IntArray? = null) =
        ReaderPagination.Block(owner, FloatArray(lines) { 10f }, gap, keep, breakBefore, speech, start, rows)

    @Test fun `a name is never alone at a page foot`() {
        // Page of 50: a 3-line block (y 30), a name (to 46), then 4 lines that cannot start under it with fewer than two.
        val paged = ReaderPagination.paginate(listOf(b(0, 3), b(1, 1, keep = true, speech = 1, start = true), b(1, 4, gap = 0f, speech = 1)), 2, 50f)
        val namePage = paged.pages.indexOfFirst { p -> p.segs.any { it.block == 1 } }
        val bodyFirst = paged.pages.indexOfFirst { p -> p.segs.any { it.block == 2 } }
        assertEquals(namePage, bodyFirst)
    }

    @Test fun `prose keeps two lines at either side of a break`() {
        // Room for four of five lines would leave one: cut at three.
        val widow = ReaderPagination.paginate(listOf(b(0, 1), b(1, 5)), 2, 60f)
        // Room for one line of three would strand it: the block moves whole.
        val orphan = ReaderPagination.paginate(listOf(b(0, 2), b(1, 3)), 2, 40f)
        for (paged in listOf(widow, orphan)) for (p in paged.pages) for (seg in p.segs) {
            if (seg.block == 1) assertTrue("two lines each side: ${seg.from}..${seg.to}", seg.to - seg.from >= 2)
        }
        assertEquals(2, widow.pages.sumOf { p -> p.segs.count { it.block == 1 } })
    }

    @Test fun `verse splits only between rows, two rows at either side`() {
        // Six rows of two lines: room for seven lines would end mid-row; the cut is between rows.
        val rows = intArrayOf(0, 2, 4, 6, 8, 10)
        val paged = ReaderPagination.paginate(listOf(b(0, 12, gap = 0f, rows = rows)), 1, 70f)
        for (p in paged.pages) for (seg in p.segs) {
            assertTrue("a cut on a row start: ${seg.from}..${seg.to}", seg.to == 12 || seg.to in rows)
            assertTrue("two rows each side", seg.to - seg.from >= 4)
        }
        assertEquals(2, paged.count)
    }

    @Test fun `an act opens a page, and a page opening inside a speech names its speaker`() {
        val blocks = listOf(
            b(0, 1, speech = 1, start = true), b(0, 6, gap = 0f, speech = 1),
            b(1, 1, breakBefore = true, keep = true), b(2, 1, speech = 2, start = true),
        )
        val paged = ReaderPagination.paginate(blocks, 3, 40f)
        assertEquals("the act heading is first on its page", 2, paged.pages.first { p -> p.segs.any { it.block == 2 } }.segs.first().block)
        val contd = paged.contd.toList()
        assertTrue("a page that opens in the speech's words is headed: $contd", contd.any { it == 1 })
        assertEquals("the page that opens on the speech start is not", -1, contd[0])
        assertEquals("the act page is not", -1, contd[paged.pages.indexOfFirst { p -> p.segs.any { it.block == 2 } }])
    }

    @Test fun `in the studio my speech stays whole on a page, one longer than a page still breaks`() {
        fun speech(owner: Int, id: Int, lines: Int, keep: Boolean) = listOf(
            ReaderPagination.Block(owner, FloatArray(1) { 10f }, 6f, keepWithNext = true, speech = id, speechStart = true, keepSpeech = keep),
            ReaderPagination.Block(owner, FloatArray(lines) { 10f }, 0f, speech = id, keepSpeech = keep),
        )
        // Page 100 tall: a two-line speech (30), then a six-line one (76): with the studio off it splits across the
        // pages, with it on it moves whole to the next; one longer than a page (130) breaks either way.
        for (keep in listOf(false, true)) {
            val blocks = speech(0, 1, 2, keep) + speech(1, 2, 6, keep)
            val paged = ReaderPagination.paginate(blocks, 2, 100f)
            val pagesOfSecond = paged.pages.indices.filter { p -> paged.pages[p].segs.any { blocks[it.block].speech == 2 } }
            if (keep) assertEquals("whole on one page", 1, pagesOfSecond.size) else assertTrue("splits when the studio is off", pagesOfSecond.size > 1)
        }
        val long = speech(0, 1, 12, true)
        assertTrue("a speech longer than a page still breaks", ReaderPagination.paginate(long, 1, 100f).count > 1)
    }

    /**
     * B29 (owner 2026-11-26, the open Duo: "the first few pages go back and forth between the opening page and the second
     * page as the different characters read their lines"). The screen's blocks: the front (title, author, Parts, the
     * parts) owned by line 1, the first line opening a page after it; per line its headings set before it, a name kept
     * with its words, the words. The read-along turns to `followPage` and then to each page its words reach: that page
     * holds the line's first words, and it never goes back while lines advance.
     * Seen to fail 2026-11-26 with `followPage` returning `starts` (line 1 turned to the front, its words on page 2).
     */
    @Test fun `the read-along turns to the page holding the words heard and never goes back`() {
        var checked = 0
        for (s in scripts()) for ((chars, perPage) in listOf(40 to 300f, 28 to 240f, 40 to 280f)) {
            val blocks = ArrayList<ReaderPagination.Block>()
            listOf(1, 1, 1, 3).forEachIndexed { k, n ->
                blocks += ReaderPagination.Block(0, FloatArray(n) { 10f }, 6f, keepWithNext = k < 3, breakBefore = k == 0, lead = true)
            }
            var opens = true
            s.lines.forEachIndexed { i, l ->
                if (i > 0 && i % 37 == 0) blocks += ReaderPagination.Block(i, FloatArray(1) { 14f }, 12f, keepWithNext = true, lead = true)
                val n = maxOf(1, (ScriptReading.lineText(l).length + chars - 1) / chars)
                if (l.kind == ScriptLine.Kind.Speech) {
                    blocks += ReaderPagination.Block(i, FloatArray(1) { 9f }, 6f, keepWithNext = true, breakBefore = opens, speech = i, speechStart = true, lead = true)
                    blocks += ReaderPagination.Block(i, FloatArray(n) { 10f }, 0f, speech = i)
                } else {
                    blocks += ReaderPagination.Block(i, FloatArray(n) { 10f }, 6f, breakBefore = opens)
                }
                opens = false
            }
            val paged = ReaderPagination.paginate(blocks, s.lines.size, perPage)
            fun wordPages(i: Int) = paged.pages.indices.filter { p -> paged.pages[p].segs.any { blocks[it.block].owner == i && !blocks[it.block].lead } }
            var shown = -1
            var from = -1
            for (i in s.lines.indices.take(60)) {
                val words = wordPages(i)
                if (words.isEmpty()) continue
                val turn = paged.followPage(i)
                assertEquals("${s.id} $chars/$perPage line ${s.lines[i].id}: turns to page ${turn + 1}, its words begin on ${words.first() + 1}", words.first(), turn)
                for (p in listOf(turn) + words) {
                    assertTrue("${s.id} $chars/$perPage: line ${s.lines[i].id} went back to page ${p + 1} from ${shown + 1} (line $from)", p >= shown)
                    shown = p
                    from = i
                }
                checked++
            }
            assertEquals("${s.id}: the play opens on its front", 0, paged.spreadOf(0, 1))
        }
        assertTrue(checked > 300)
    }
}
