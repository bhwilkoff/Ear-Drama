package com.example.appname.data

/**
 * A copy of a broadcast is named from data, never from the archive.org upload text (AGENTS.md: raw
 * upload text never shows). [Recording.label] is the catalog's clean collection or uploader name when
 * it publishes one; otherwise the copy is named by its kbps and length. The identifier stays in the
 * "View on archive.org" link target only.
 */
object RecordingLabel {
    /**
     * The catalog's clean label, else what tells the copies apart ("128 kbps · 29 min"); never
     * "Recording 2" (owner 2026-11-09). A copy with neither shows its format, else "Another copy".
     */
    fun title(rec: Recording, length: String?): String {
        val label = rec.label?.trim().orEmpty()
        if (label.isNotEmpty() && !looksLikeIdentifier(label)) return label
        return distinguishing(rec, length).ifEmpty { rec.format?.takeIf { it.isNotBlank() } ?: "Another copy" }
    }

    private fun hasLabel(rec: Recording): Boolean {
        val label = rec.label?.trim().orEmpty()
        return label.isNotEmpty() && !looksLikeIdentifier(label)
    }

    private fun distinguishing(rec: Recording, length: String?): String =
        listOfNotNull(rec.kbps?.let { "$it kbps" }, length).joinToString(" \u00B7 ")

    /** "Best copy · 128 kbps · 29 min" under a labeled title; a title that already says the numbers does not repeat them. */
    fun facts(rec: Recording, isBest: Boolean, length: String?, notes: List<String>): String {
        val numbers = if (hasLabel(rec) || distinguishing(rec, length).isEmpty()) listOfNotNull(rec.kbps?.let { "$it kbps" }, length) else emptyList()
        return (listOfNotNull("Best copy".takeIf { isBest }) + numbers + notes).joinToString(" \u00B7 ")
    }

    /** An archive.org identifier: underscores, or a long unspaced run of letters and numerals. */
    fun looksLikeIdentifier(text: String): Boolean = text.split(Regex("\\s+")).any { w ->
        w.contains('_') ||
            (w.length >= 10 && w.any { it.isLetter() } && w.any { it.isDigit() }) ||
            (w.length >= 24 && w.any { it.isLetter() } && w.count { it.isUpperCase() } >= 4)
    }

}
