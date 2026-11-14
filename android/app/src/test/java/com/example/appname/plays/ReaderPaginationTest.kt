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
}
