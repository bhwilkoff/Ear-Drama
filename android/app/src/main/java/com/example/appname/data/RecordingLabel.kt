package com.example.appname.data

/**
 * A copy of a broadcast is named from data, never from the archive.org upload text (AGENTS.md: raw
 * upload text never shows). [Recording.label] is the catalog's clean collection or uploader name when
 * it publishes one; otherwise the copy is "Recording 2" by position. The identifier stays in the
 * "View on archive.org" link target only.
 */
object RecordingLabel {
    fun title(rec: Recording, position: Int): String {
        val label = rec.label?.trim().orEmpty()
        return if (label.isNotEmpty() && !looksLikeIdentifier(label)) label else "Recording $position"
    }

    /** "Best copy · 128 kbps · 29 min" under the title. */
    fun facts(rec: Recording, isBest: Boolean, length: String?, notes: List<String>): String =
        (listOfNotNull("Best copy".takeIf { isBest }, rec.kbps?.let { "$it kbps" }, length) + notes)
            .joinToString(" \u00B7 ")

    /** An archive.org identifier: underscores, or a long unspaced run of letters and numerals. */
    fun looksLikeIdentifier(text: String): Boolean = text.split(Regex("\\s+")).any { w ->
        w.contains('_') ||
            (w.length >= 10 && w.any { it.isLetter() } && w.any { it.isDigit() }) ||
            (w.length >= 24 && w.any { it.isLetter() } && w.count { it.isUpperCase() } >= 4)
    }

}
