package com.example.appname.data

/**
 * A show at most once per Home (WEB-DESIGN §4.2r rule 5; js/api.js `homeShows`, with the same cases in HomeShowsTest):
 * Home draws its rows in order, and a row keeps an episode only when its series is not in [seen] (the shows drawn
 * higher up) and not already kept in this row. Episode ids are "series|date", so a published shelf is filtered
 * before its episodes load. Continue is exempt.
 */
fun homeShows(ids: List<String>, seen: MutableSet<String>): List<String> {
    val out = mutableListOf<String>()
    for (id in ids) {
        val key = id.substringBefore('|')
        if (key.isEmpty() || key in seen) continue
        seen += key
        out += id
    }
    return out
}

/** The chips of one row filtered against the shows above it; the first chip left standing feeds the rows below. */
data class HomeChips(val shelves: List<HomeShelf>, val seen: Set<String>)

/**
 * Each chip skips only what is above; the chip shown first adds its shows to the set the rows below skip; a chip left
 * empty is dropped.
 */
fun homeChips(shelves: List<HomeShelf>, above: Set<String>): HomeChips {
    var after = above
    val out = mutableListOf<HomeShelf>()
    for (shelf in shelves) {
        val seen = above.toMutableSet()
        val kept = homeShows(shelf.ids, seen)
        if (kept.isEmpty()) continue
        if (out.isEmpty()) after = seen
        out += shelf.copy(ids = kept)
    }
    return HomeChips(out, after)
}

private val UPLOAD_TAG = Regex("""(^|\s)#\s?\d+\b""")

/** A title that still carries an upload's catalog number ("AbyM #026 ...") or an identifier, or is a placeholder: raw upload text, which never shows. */
fun uploadTagged(title: String?): Boolean {
    if (title.isNullOrEmpty()) return false
    return UPLOAD_TAG.containsMatchIn(title) || RecordingLabel.looksLikeIdentifier(title) || placeholderTitle(title)
}

private val PLACEHOLDER_TITLE = Regex(
    """(?:.*\s)?[?*\s.\-–]*(?:title\s+(?:unknown|not\s+known)|unknown\s+title|no\s+title(?:\s+given)?)[?*\s.\-–]*""" +
        """|[?*\s.\-–]*(?:untitled(?:\s+episode)?|unknown|n/a|tba|tbd)[?*\s.\-–]*""",
    RegexOption.IGNORE_CASE,
)

/**
 * A log's or an uploader's stand-in for a title it did not have ("?? Title Unknown ??", "Ceiling Unlimited Title Unknown",
 * "No Title Given", "Untitled"): never a title (owner 2026-11-27). The same rule as js/api.js and display_text.py.
 */
fun placeholderTitle(title: String?): Boolean {
    val t = title?.trim().orEmpty()
    return t.isNotEmpty() && PLACEHOLDER_TITLE.matches(t)
}

/** The On the air hero's line under the show's name: the title, or the broadcast's date when the title is raw. */
fun heroTitle(title: String?, id: String, date: (String) -> String): String? {
    if (!title.isNullOrEmpty() && !uploadTagged(title)) return title
    val air = id.substringAfter('|', "")
    return if (air.length >= 4 && air.take(4).all { it.isDigit() }) date(air) else null
}
