package com.example.appname.data

/**
 * Item pages wear Home's hero (WEB-DESIGN §6.4g, ANDROID-DESIGN §4.3g, Decision 081, Round 3 V7): which picture leads a page,
 * which further pictures draw as a row, and how big the head's window is. The web's `API.seriesLead`, `galleryOf`,
 * `playLead` and `heroArt`, with the same golden cases (ItemLeadTest).
 */
object ItemLead {
    /** A picture whose short side is under this many pixels is not shown in a head window (it gives way to the label). */
    const val FLOOR = 160

    /** Past this board width (dp) the window stands beside the words (Home's hero, 560); under it, across the top. */
    const val BESIDE_FROM = 560f

    /** A plate narrower than this share of the board stands beside the words, not alone over them (a TV's capped plate). */
    const val PLATE_SPAN_MIN = 0.7f

    /** True when a plate is capped so far under the board's width that it stands left of the words like an upright picture. */
    fun cappedPlate(frame: Window, width: Float): Boolean = frame.plate && width >= BESIDE_FROM && frame.width < width * PLATE_SPAN_MIN

    /** The window's column beside the words, and the tallest an upright picture stands (dp). */
    const val COLUMN = 320f
    const val UPRIGHT_HEIGHT = 400f

    /** The picture that leads a series page: its landscape hero when it is wide, else its picture; null is the label. */
    fun seriesLead(hero: Artwork?, picture: Artwork?): Artwork? = if (hero != null && hero.isWide) hero else picture

    /**
     * A series' further pictures, each with its own evidence and a size, without the lead and without repeats; a row draws
     * only from two.
     */
    fun gallery(pictures: List<Artwork>, lead: Artwork?): List<Artwork> {
        val seen = mutableSetOf<String>().apply { lead?.let { add(it.url) } }
        val out = mutableListOf<Artwork>()
        for (a in pictures) {
            if (a.evidence == null || (a.width ?: 0) <= 0 || (a.height ?: 0) <= 0 || a.url in seen) continue
            seen += a.url
            out += a
        }
        return if (out.size >= 2) out else emptyList()
    }

    /** The picture that leads a play's page: its title page, else a photograph of its production, else its author's portrait; null is its page as the label. */
    fun playLead(titlePage: Artwork?, authorArt: Artwork?, production: Artwork? = null): Artwork? = titlePage ?: production ?: authorArt

    /** The picture a head window can show: its size is known and its short side holds the floor. */
    fun shown(art: Artwork?): Artwork? {
        val w = art?.width ?: return null
        val h = art.height ?: return null
        return art.takeIf { w > 0 && h > 0 && minOf(w, h) >= FLOOR }
    }

    /** A head window's frame in dp; [plate] is a wide picture lying across the board over the words. */
    data class Window(val width: Float, val height: Float, val plate: Boolean)

    /**
     * The window's frame inside a board [width] dp wide: a label is a square (the column's width on a phone, 320 beside the
     * words); a picture keeps its own shape. A wide one is a plate over the words at the board's full width, at most 360
     * tall (440 beside); an upright or square one stands in the window's place, at most 400 tall and 320 wide beside the
     * words. The picture is never cropped. [plateMax] caps a plate further: a TV passes 30% of its screen's height, so the
     * name and the button row stay on the first screen under a wide picture (V8, Google TV 2026-11-20).
     */
    fun window(art: Artwork?, width: Float, plateMax: Float? = null): Window {
        val beside = width >= BESIDE_FROM
        val shown = shown(art)
        val a = shown?.aspectRatio
        if (shown == null || a == null) {
            val side = if (beside) COLUMN else width
            return Window(side, side, false)
        }
        if (shown.isWide) {
            val h = minOf(width / a, if (beside) 440f else 360f, plateMax ?: Float.MAX_VALUE)
            return Window(h * a, h, true)
        }
        val h = minOf(UPRIGHT_HEIGHT, (if (beside) minOf(COLUMN, width) else width) / a)
        return Window(h * a, h, false)
    }

    /**
     * An episode's heading: its own title, or, when the title still carries an upload's tag, the broadcast's date, else its
     * number, else its show (raw upload text never shows). [date] formats an ISO day.
     */
    fun episodeTitle(row: EpisodeRow, titleOf: (EpisodeRow) -> String, date: (String) -> String?): String {
        val title = row.title
        if (title != null && uploadTagged(title)) {
            return row.airDate?.let(date) ?: row.num?.let { "No. $it" } ?: row.seriesName
        }
        return titleOf(row)
    }

    /** True for a bar that is not the marked year's: [from] is the bar's start on the fixed 1930 to 1962 axis. */
    fun dimmed(from: Double, markYear: Int?): Boolean {
        if (markYear == null) return false
        val n = (RUN_AXIS.second - RUN_AXIS.first + 1).toDouble()
        return RUN_AXIS.first + Math.round(from * n).toInt() != markYear
    }
}
