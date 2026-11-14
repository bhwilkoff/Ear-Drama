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
     * it opens a page; [keepWithNext] keeps a heading on the page of what follows it.
     */
    class Block(val owner: Int, val heights: FloatArray, val gapBefore: Float, val keepWithNext: Boolean = false)

    /** Visual lines [from, to) of block [block], drawn from [top] to [bottom] on its page. */
    class Seg(val block: Int, val from: Int, val to: Int, val top: Float, val bottom: Float)

    class Page(val segs: List<Seg>) {
        /** The segment under [y] (page coordinates), or the nearest one when [y] falls in a gap; null on an empty page. */
        fun segAt(y: Float): Seg? = segs.firstOrNull { y < it.bottom } ?: segs.lastOrNull()
    }

    class Paged(val pages: List<Page>, val starts: IntArray, val ends: IntArray) {
        val count: Int get() = pages.size

        /** The pages a script line is on, or an empty range for a line with no block. */
        fun spreadOf(line: Int, per: Int): Int = ReaderMath.spreadStart(starts[line.coerceIn(0, starts.size - 1)], per) / per
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
            if (block.keepWithNext && cur.isNotEmpty()) {
                val next = blocks.getOrNull(b + 1)
                val need = block.gapBefore + hs.sum() + (next?.let { it.gapBefore + it.heights.first() } ?: 0f)
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
                if (k == j) {
                    flush()
                    continue
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
        return Paged(pages, starts, ends)
    }

    private const val EPS = 0.5f
}
