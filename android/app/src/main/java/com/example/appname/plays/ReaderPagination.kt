package com.example.appname.plays

/**
 * Cutting a script into pages from measured heights (R2 brief §4). Pure: the screen measures each block's visual
 * lines with TextMeasurer and hands the heights here, so the cut is tested without a device. A page is never
 * stored: [Paged.starts] and [Paged.ends] say which pages each script line begins and ends on, and the reading
 * position is a line that [ReaderMath.lineAtPage] finds again after any re-layout.
 */
object ReaderPagination {
    /**
     * One drawn block: a script line, or a printed heading drawn before it. [owner] is the script line it belongs to;
     * [heights] are its visual lines' heights, top to bottom (at least one); [gapBefore] is the space above it unless
     * it opens a page; [keepWithNext] keeps a block on the page of what follows it (a name, a heading); [breakBefore]
     * opens a page (an act, the first speech after the front). A block of a speech has its [speech] id, and
     * [speechStart] when it is the speech's first, so a page that opens inside a speech can head itself "NAME (cont'd)".
     * With [keepSpeech] (the studio's part: PLAYS-DESIGN §2.9) a speech's blocks stay on one page, so the line being
     * recorded is whole on screen; a speech longer than a page still breaks.
     * A verse block's [rowStarts] are the visual lines its printed rows begin on: it splits only between rows,
     * keeping two rows at either side; any other block keeps two lines at either side.
     */
    class Block(
        val owner: Int,
        val heights: FloatArray,
        val gapBefore: Float,
        val keepWithNext: Boolean = false,
        val breakBefore: Boolean = false,
        val speech: Int = -1,
        val speechStart: Boolean = false,
        val rowStarts: IntArray? = null,
        val keepSpeech: Boolean = false,
    )

    /** Visual lines [from, to) of block [block], drawn from [top] to [bottom] on its page. */
    class Seg(val block: Int, val from: Int, val to: Int, val top: Float, val bottom: Float)

    class Page(val segs: List<Seg>) {
        /** The segment under [y] (page coordinates), or the nearest one when [y] falls in a gap; null on an empty page. */
        fun segAt(y: Float): Seg? = segs.firstOrNull { y < it.bottom } ?: segs.lastOrNull()
    }

    /** [contd] is, per page, the block a page that opens inside a speech begins with (its speaker is named above the text), else -1. */
    class Paged(val pages: List<Page>, val starts: IntArray, val ends: IntArray, val contd: IntArray) {
        val count: Int get() = pages.size

        /** The pages a script line is on, or an empty range for a line with no block. */
        fun spreadOf(line: Int, per: Int): Int = ReaderMath.spreadStart(starts[line.coerceIn(0, starts.size - 1)], per) / per
    }

    /** Whether visual lines [j, s) of [b] may end a page with lines [s, end) carried on. */
    private fun splitOk(b: Block, j: Int, s: Int): Boolean {
        val n = b.heights.size
        val rows = b.rowStarts
        if (rows != null && rows.size > 1) {
            if (s !in rows) return false
            val before = rows.count { it in j until s }
            val after = rows.count { it >= s }
            return before >= 2 && after >= 2
        }
        return s - j >= 2 && n - s >= 2
    }

    /** The fewest leading visual lines a block can be cut to (its whole height when it cannot be split). */
    private fun leadLines(b: Block): Int {
        for (s in 1 until b.heights.size) if (splitOk(b, 0, s)) return s
        return b.heights.size
    }

    fun paginate(blocks: List<Block>, lineCount: Int, pageHeight: Float): Paged {
        val pages = ArrayList<Page>()
        var cur = ArrayList<Seg>()
        var y = 0f
        val starts = IntArray(lineCount) { -1 }
        val ends = IntArray(lineCount) { -1 }
        fun flush() {
            pages += Page(cur)
            cur = ArrayList()
            y = 0f
        }
        for ((b, block) in blocks.withIndex()) {
            val hs = block.heights
            if (block.breakBefore && cur.isNotEmpty()) flush()
            if (block.keepSpeech && block.speechStart && block.speech >= 0 && cur.isNotEmpty()) {
                var whole = block.gapBefore
                var n = b
                while (n < blocks.size && blocks[n].speech == block.speech) {
                    whole += (if (n == b) 0f else blocks[n].gapBefore) + blocks[n].heights.sum()
                    n++
                }
                if (y + whole > pageHeight && whole <= pageHeight) flush()
            }
            if (block.keepWithNext && cur.isNotEmpty()) {
                val next = blocks.getOrNull(b + 1)
                val need = block.gapBefore + hs.sum() + (next?.let { it.gapBefore + it.heights.take(leadLines(it)).sum() } ?: 0f)
                if (y + need > pageHeight) flush()
            }
            var j = 0
            while (j < hs.size) {
                val lead = if (j == 0 && cur.isNotEmpty()) block.gapBefore else 0f
                val top = y + lead
                var yy = top
                var k = j
                while (k < hs.size) {
                    if (yy + hs[k] > pageHeight + EPS && !(cur.isEmpty() && k == j)) break
                    yy += hs[k]
                    k++
                }
                if (k < hs.size) {
                    var s = k
                    while (s > j && !splitOk(block, j, s)) s--
                    if (s <= j) {
                        if (cur.isNotEmpty()) {
                            flush()
                            continue
                        }
                        s = maxOf(k, j + 1)
                    }
                    k = s
                    yy = top + hs.slice(j until k).sum()
                }
                val page = pages.size
                if (starts[block.owner] < 0 || page < starts[block.owner]) starts[block.owner] = page
                if (page > ends[block.owner]) ends[block.owner] = page
                cur += Seg(b, j, k, top, yy)
                y = yy
                j = k
                if (j < hs.size) flush()
            }
        }
        if (cur.isNotEmpty() || pages.isEmpty()) flush()
        // A line with no block (nothing to draw) sits where the line before it ended.
        for (i in 0 until lineCount) {
            if (starts[i] < 0) {
                val p = if (i > 0) ends[i - 1].coerceAtLeast(0) else 0
                starts[i] = p
                ends[i] = p
            }
        }
        val contd = IntArray(pages.size) { p ->
            val seg = pages[p].segs.firstOrNull()
            val blk = seg?.let { blocks[it.block] }
            if (seg != null && blk != null && blk.speech >= 0 && !(blk.speechStart && seg.from == 0)) seg.block else -1
        }
        return Paged(pages, starts, ends, contd)
    }

    private const val EPS = 0.5f
}
