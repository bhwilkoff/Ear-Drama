package com.example.appname.plays

import android.content.SharedPreferences
import androidx.core.content.edit

/**
 * The neutral age question (Decision 084, PLAYS-DESIGN §12.12 item 8): before a first share, invite, take part from an invite,
 * or publish outside a class, a birth year with no default. Only "under 13 or not" is kept, on this device, never sent.
 * A year alone cannot tell a 12-year-old from a 13-year-old born the same year, so that year counts as under 13.
 * The rule mirrors `js/age-gate.js` and Apple's `AgeGate`.
 */
object AgeGate {
    const val KEY = "ed.over13"
    const val OLDEST = 120

    fun isUnder13(birthYear: Int, year: Int): Boolean = year - birthYear <= 13

    /** The years to pick from, this year back [OLDEST] years, newest first. */
    fun years(year: Int): List<Int> = List(OLDEST) { year - it }

    /** The stored answer: true is 13 and over, false is under 13, null is not asked yet. */
    class Store(private val prefs: SharedPreferences) {
        fun known(): Boolean? = if (prefs.contains(KEY)) prefs.getBoolean(KEY, false) else null
        fun keep(over13: Boolean) = prefs.edit { putBoolean(KEY, over13) }
    }
}

/** Class dates are days, shown in the person's date style and never shifted by a time zone (§12.12 item 1). */
object ClassDates {
    const val MAX_DAYS = 400L

    fun parse(ymd: String): java.time.LocalDate? = runCatching { java.time.LocalDate.parse(ymd) }.getOrNull()

    fun text(ymd: String, locale: java.util.Locale = java.util.Locale.getDefault()): String {
        val day = parse(ymd) ?: return ymd
        return java.time.format.DateTimeFormatter.ofLocalizedDate(java.time.format.FormatStyle.LONG).withLocale(locale).format(day)
    }
}
