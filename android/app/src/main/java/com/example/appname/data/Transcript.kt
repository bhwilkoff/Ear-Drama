package com.example.appname.data

/**
 * archive.org's automatic transcript of an episode (DECISIONS 058, contract
 * §3.1): shown only where `has_transcript = 1`, fetched from its own URL when
 * opened, never bundled or stored. The words match every other platform.
 */
object Transcript {
    /** The one label on every platform: what it is, and that no person wrote it. */
    const val LABEL = "Automatic transcript"

    /** A search row found only by words in its transcript. */
    const val SEARCH_NOTE = "In the transcript"

    /** The text as archive.org serves it (a sentence a line), blank lines and stray spaces dropped. */
    fun lines(text: String): List<String> = text.lines().map { it.trim() }.filter { it.isNotEmpty() }
}
