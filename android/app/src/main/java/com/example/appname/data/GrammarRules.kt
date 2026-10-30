package com.example.appname.data

// The grammar's decisions (WEB-DESIGN §6.4b, ANDROID-DESIGN R11b): pure functions with the same
// rules and golden cases as the web (`API.monogram` and friends in js/api.js) and Apple.

private val MONO_STOP = setOf("the", "a", "an", "of", "and", "&", "in", "on", "to", "for", "el", "la", "le", "de", "der", "die")
private val NAME_BREAKS = Regex("[\\s\\-\\u2013/]+")

private fun String.leadingTrimmed(): String = dropWhile { !it.isLetterOrDigit() }

/** The title block's monogram: the initials of the first two words that start with a letter, else the first letter or number. */
fun monogram(name: String?): String {
    val text = name ?: ""
    val words = text.split(NAME_BREAKS).map { it.leadingTrimmed() }.filter { it.isNotEmpty() }
    val lettered = words.filter { it.first().isLetter() && it.lowercase() !in MONO_STOP }
    val m = lettered.take(2).joinToString("") { it.take(1).uppercase() }
    if (m.isNotEmpty()) return m
    return text.firstOrNull { it.isLetterOrDigit() }?.uppercase() ?: ""
}

/** The monogram's size in hundredths of the window, so it stands inside it; at most 104. */
fun blockSize(m: String?): Int {
    var w = 0.0
    for (c in m ?: "") w += (when (c) { 'M' -> 0.76; 'W' -> 0.78; 'J' -> 0.45; 'I', '1' -> 0.27; else -> 0.5 }) + 0.02
    return if (w > 0) minOf(104, Math.floor(86 / w).toInt()) else 104
}

/** A name's type step: 0 as set, 1 one level down (a word past 10 letters), 2 two (past 14). */
fun nameStep(name: String?): Int {
    val longest = (name ?: "").split(Regex("[\\s\\-\\u2013]+")).maxOfOrNull { it.codePointCount(0, it.length) } ?: 0
    return if (longest > 14) 2 else if (longest > 10) 1 else 0
}

/** What a window holds. */
sealed interface WindowFill {
    data class Crop(val rect: CropRect) : WindowFill
    data object Whole : WindowFill
    data object Block : WindowFill
}

/**
 * What a window of [slot] dp holds: a crop around the face, a wide picture with no face whole, or
 * the title block for no picture or one under the size floor (the crop's pixel height at least the
 * slot; a whole picture's short side at least half of it). An unknown size is a block.
 */
fun windowFill(art: Artwork?, slot: Float): WindowFill {
    if (art == null || art.url.isEmpty()) return WindowFill.Block
    val w = art.width ?: return WindowFill.Block
    val h = art.height ?: return WindowFill.Block
    if (w <= 0 || h <= 0) return WindowFill.Block
    val rect = art.cropRect()
        ?: return if (minOf(w, h) >= slot / 2) WindowFill.Whole else WindowFill.Block
    return if (rect.h * h >= slot) WindowFill.Crop(rect) else WindowFill.Block
}

/** An event line's pieces: each fact with the separator kept at its end; empty facts drop out. */
fun eventParts(facts: List<Any?>?): List<String> {
    val v = (facts ?: emptyList()).filter { it != null && it.toString().trim() != "" }.map { it.toString() }
    return v.mapIndexed { i, x -> if (i < v.size - 1) "$x ·" else x }
}

/** The run strip's fixed axis: every show's strip is the same object. */
val RUN_AXIS = 1930 to 1962

/** The strip's bar as fractions of the axis. */
data class RunSpan(val from: Double, val to: Double)

/** The bar from the first to the last broadcast year; null when undated (the baseline alone). */
fun runSpan(first: String?, last: String?): RunSpan? {
    fun year(d: String?): Int? = if (d != null && Regex("^\\d{4}").containsMatchIn(d)) d.take(4).toInt() else null
    val a = year(first) ?: return null
    val b = year(last) ?: a
    val (lo, hi) = RUN_AXIS
    val n = hi - lo + 1
    fun c(v: Int) = minOf(hi, maxOf(lo, v))
    return RunSpan((c(a) - lo).toDouble() / n, (c(maxOf(a, b)) - lo + 1).toDouble() / n)
}

/** One bar of the run strip: its span on the axis and its height (0..1) against the busiest year. */
data class RunBar(val from: Double, val to: Double, val height: Double)

/**
 * The strip's bars from the run histogram (`series.year_counts`: the first year, then one count
 * per year): a bar per year on the fixed axis, its height the count over the busiest year; a year
 * with no episode draws nothing; a year off the axis is held at the nearest edge. Null when the
 * show has no histogram (the strip then draws the first-to-last span).
 */
fun runBars(years: List<Int>?): List<RunBar>? {
    if (years == null || years.size < 2) return null
    val counts = years.drop(1)
    if (counts.none { it > 0 }) return null
    val (lo, hi) = RUN_AXIS
    val n = (hi - lo + 1).toDouble()
    val bySlot = sortedMapOf<Int, Int>()
    counts.forEachIndexed { i, c ->
        if (c > 0) {
            val slot = minOf(hi, maxOf(lo, years[0] + i)) - lo
            bySlot[slot] = (bySlot[slot] ?: 0) + c
        }
    }
    val top = bySlot.values.max().toDouble()
    return bySlot.map { (slot, c) -> RunBar(slot / n, (slot + 1) / n, c / top) }
}

/** Parses `series.year_counts` ("1932,3,12,0,4"); null when absent or malformed. */
fun parseYearCounts(text: String?): List<Int>? {
    if (text.isNullOrEmpty()) return null
    val parts = text.split(",").map { it.trim().toIntOrNull() }
    if (parts.size < 2 || parts.any { it == null }) return null
    return parts.filterNotNull()
}

/** An episode with neither a date nor a number: its row's leading slot shows the series' window. */
fun undatedBare(date: String?, num: Int?): Boolean =
    !(date != null && Regex("^\\d{4}").containsMatchIn(date)) && num == null

/** Browse's A to Z letter: the sort key's first letter without accents, A to Z, else "#". */
fun azLetter(key: String?): String {
    val c = java.text.Normalizer.normalize(key.orEmpty().trim(), java.text.Normalizer.Form.NFD)
        .firstOrNull()?.uppercaseChar()
    return if (c != null && c in 'A'..'Z') c.toString() else "#"
}

/** The letters that have shows, "#" first (the sort puts numbers and symbols before A). */
fun azLetters(keys: List<String?>): List<String> {
    val have = keys.mapTo(HashSet()) { azLetter(it) }
    return (listOf("#") + ('A'..'Z').map { it.toString() }).filter { it in have }
}

private val MONTHS = listOf("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")

/**
 * The date block's two lines (the web's `dateBlock`): month and year small over the day, the year
 * small over the month, the year alone, or an undated numbered episode's "No." over its number.
 */
fun dateBlockParts(date: String?, num: Int?): Pair<String, String> {
    val d = date ?: ""
    val y = d.take(4)
    val mo = d.drop(5).take(2).toIntOrNull() ?: 0
    val day = d.drop(8).take(2).toIntOrNull() ?: 0
    return when {
        day != 0 && mo != 0 -> "${MONTHS[mo - 1]} ’${y.drop(2)}" to day.toString()
        mo != 0 -> "’${y.drop(2)}" to MONTHS[mo - 1]
        y.isNotEmpty() -> "" to y
        num != null -> "No." to num.toString()
        else -> "" to ""
    }
}

/** The levels a picture takes after the monochrome: `k * v + o`. */
data class Grade(val k: Double, val o: Double)

private val DEFAULT_GRADE = Grade(1.0, 0.0)

/** The grade a picture takes; the projection publishes none yet, so the identity default. */
fun gradeOf(art: Artwork?): Grade {
    val g = art?.grade
    return if (g != null && g.size == 2) Grade(g[0], g[1]) else DEFAULT_GRADE
}

// Home and Browse (WEB-DESIGN §6.4c, ANDROID-DESIGN R11c): the rules every platform mirrors.

/** A show is a series of at least this many episodes (owner, 2026-10-29); the rest are single recordings, counted. */
const val SHOW_MIN = 5

fun isShow(episodes: Int?): Boolean = (episodes ?: 0) >= SHOW_MIN

/** The genre order of every stacked mark and legend; a series with no genre stacks last, in no hue. */
val GENRE_ORDER = listOf("drama", "mystery", "comedy", "serial", "western", "scifi", "documentary", "news")

/** One year of a day's broadcasts: [genres] maps a genre (empty for none) to its count. */
data class DayYear(val year: Int, val total: Int, val genres: Map<String, Int>)

data class DayYears(val years: List<DayYear>, val peak: Int?, val count: Int, val genres: List<String>)

private val YEAR_PREFIX = Regex("^\\d{4}")

private fun yearOf(date: String?): Int? = if (date != null && YEAR_PREFIX.containsMatchIn(date)) date.take(4).toInt() else null

/**
 * One day's broadcasts by year, oldest first; the year with the most (the earlier on a tie) is the
 * peak; the legend is the genres seen in [GENRE_ORDER]. Rows without a four-digit year are not on
 * the strip.
 */
fun <R> dayYears(rows: List<R>, dateOf: (R) -> String?, genreOf: (R) -> String?): DayYears {
    val by = sortedMapOf<Int, MutableMap<String, Int>>()
    for (r in rows) {
        val y = yearOf(dateOf(r)) ?: continue
        val g = genreOf(r) ?: ""
        val m = by.getOrPut(y) { linkedMapOf() }
        m[g] = (m[g] ?: 0) + 1
    }
    val years = by.map { (y, m) -> DayYear(y, m.values.sum(), m) }
    var peak: DayYear? = null
    for (y in years) if (peak == null || y.total > peak.total) peak = y
    val seen = years.flatMap { it.genres.keys }.toSet()
    return DayYears(years, peak?.year, years.sumOf { it.total }, GENRE_ORDER.filter { it in seen })
}

data class Night<R>(val shows: List<R>, val singles: Int)

private val NON_ALNUM = Regex("[^a-z0-9]+")

/**
 * One night's rows as shows: the first row of a title only (the same title the same night folds
 * once); rows of a series under the show line are counted as singles and left out. [episodesOf] is
 * the row's series episode count, or null for none.
 */
fun <R> nightShows(rows: List<R>, titleOf: (R) -> String?, episodesOf: (R) -> Int?): Night<R> {
    val seen = HashSet<String>()
    val shows = ArrayList<R>()
    var singles = 0
    for (r in rows) {
        if (!isShow(episodesOf(r))) { singles++; continue }
        if (!seen.add((titleOf(r) ?: "").lowercase().replace(NON_ALNUM, ""))) continue
        shows.add(r)
    }
    return Night(shows, singles)
}

/** A show as the field sees it: its genre and the date it first aired. */
data class FieldShow(val genre: String?, val first: String?)

/** Browse's decade by genre field: the shows per cell, decades in order; [none] shows are counted, not drawn. */
class DecadeField(
    val decades: List<Int>,
    val genres: List<String>,
    private val cells: Map<Pair<String, Int>, Int>,
    val max: Int,
    val none: Int,
) {
    fun count(genre: String, decade: Int): Int = cells[genre to decade] ?: 0
}

fun decadeField(shows: List<FieldShow>): DecadeField {
    val cells = HashMap<Pair<String, Int>, Int>()
    val decades = sortedSetOf<Int>()
    var none = 0
    for (s in shows) {
        val y = yearOf(s.first)
        if (s.genre.isNullOrEmpty() || y == null) { none++; continue }
        val d = Math.floorDiv(y, 10) * 10
        decades.add(d)
        cells.merge(s.genre to d, 1, Int::plus)
    }
    val ds = decades.toList()
    val genres = GENRE_ORDER.filter { g -> ds.any { (g to it) in cells } }
    return DecadeField(ds, genres, cells, cells.values.maxOrNull() ?: 0, none)
}

/** A cell's mark side in dp: the square root of its share of the biggest cell, 6 to 32; 0 for an empty cell. */
fun fieldSide(n: Int, max: Int): Int =
    if (n > 0 && max > 0) maxOf(6, Math.round(32 * Math.sqrt(n.toDouble() / max)).toInt()) else 0
/**
 * The picture that leads an episode's head board: the show's own image when the series picture is of
 * the show, else the episode's star (the credit the row names, else the first cast with a picture),
 * else the series' picture, else none (the title block).
 */
fun leadPicture(series: SeriesRow?, credits: List<Credit>, star: String?): Artwork? {
    val own = series?.picture
    if (own != null && series.pictureKind == "show") return own
    val cast = credits.filter { it.art != null && (it.role ?: "cast") == "cast" }
    val pick = (if (star != null) cast.firstOrNull { it.personId == star } else null) ?: cast.firstOrNull()
    return pick?.art ?: own
}

/** Who is "On the air": the cast in billing order, each person once, at most [limit]. */
fun onAirOf(credits: List<Credit>, limit: Int = 6): List<Credit> {
    val seen = HashSet<String>()
    val out = ArrayList<Credit>()
    for (c in credits) {
        if ((c.role ?: "cast") != "cast") continue
        if (!seen.add(c.personId.ifEmpty { c.name })) continue
        out += c
        if (out.size >= limit) break
    }
    return out
}

/**
 * The facts of an episode's event line: its date (or Undated), network, sponsor, length, season, and
 * its number when the title does not already say it. [date] and [length] arrive formatted.
 */
fun episodeFacts(
    network: String?,
    sponsor: String?,
    season: String?,
    title: String?,
    num: Int?,
    date: String?,
    length: String?,
): List<String> = listOf(
    date ?: "Undated", network, sponsor, length,
    season?.let { "Season $it" },
    if (!title.isNullOrEmpty() && num != null) "No. $num" else null,
).filterNotNull().filter { it.trim().isNotEmpty() }
