package com.example.appname.data

import java.text.Normalizer

/**
 * archive.org's automatic transcript of an episode (DECISIONS 058, contract
 * §3.1): shown only where `has_transcript = 1`, fetched from its own URL when
 * opened, never bundled or stored. The words match every other platform.
 */
object Transcript {
    /** The one label on every platform: what it is, and that no person wrote it. */
    const val LABEL = "Automatic transcript"

    /** The text as archive.org serves it (a sentence a line), blank lines and stray spaces dropped. */
    fun lines(text: String): List<String> = text.lines().map { it.trim() }.filter { it.isNotEmpty() }

    private val MARKS = Regex("\\p{M}+")
    private val NOT_WORD = Regex("[^\\p{L}\\p{N}]+")

    /** FTS5 unicode61's words: case and diacritics folded, split on anything not a letter or digit. */
    fun tokens(text: String): List<String> =
        Normalizer.normalize(text, Normalizer.Form.NFD).replace(MARKS, "").lowercase()
            .split(NOT_WORD).filter { it.isNotEmpty() }

    /** The words a search looks for in a transcript: three letters or more (contract §3.4). */
    fun searchWords(query: String): List<String> = tokens(query).filter { it.length >= 3 }.distinct()

    /**
     * The line where a search word is first said, verbatim, cut to about [max]
     * characters around it with an ellipsis at a cut; null when no line says
     * one. The same rule on every platform (catalog/tests/golden/search_text.json).
     */
    fun snippet(text: String, words: List<String>, max: Int = 120): String? {
        if (words.isEmpty()) return null
        val line = lines(text).firstOrNull { l -> tokens(l).any { t -> words.any { t.startsWith(it) } } } ?: return null
        if (line.length <= max) return line
        val lower = line.lowercase()
        var at = line.length
        if (lower.length == line.length) {
            for (w in words) {
                var i = lower.indexOf(w)
                while (i >= 0) {
                    if (i == 0 || !lower[i - 1].isLetterOrDigit()) {
                        at = minOf(at, i)
                        break
                    }
                    i = lower.indexOf(w, i + 1)
                }
            }
        }
        if (at == line.length) at = 0
        var start = maxOf(0, at - 40)
        if (start > 0) {
            val sp = line.indexOf(' ', start)
            start = if (sp in 0 until at) sp + 1 else at
        }
        var end = minOf(line.length, start + max)
        if (end < line.length) {
            val sp = line.lastIndexOf(' ', end)
            if (sp > at) end = sp
        }
        return (if (start > 0) "…" else "") + line.substring(start, end).trim() + (if (end < line.length) "…" else "")
    }
}
