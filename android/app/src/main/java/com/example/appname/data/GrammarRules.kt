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
