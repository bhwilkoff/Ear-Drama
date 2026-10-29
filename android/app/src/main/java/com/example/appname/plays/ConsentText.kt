package com.example.appname.plays

/**
 * The Worker's consent words as structure, none changed: with "- " lines the
 * first plain line leads and each "- " line is an item; without them every
 * line is a paragraph.
 */
data class ConsentBlock(val kind: Kind, val text: String) {
    enum class Kind { Lead, Item, Paragraph }
}

object ConsentText {
    fun blocks(text: String): List<ConsentBlock> {
        val lines = text.lines().map { it.trim() }.filter { it.isNotEmpty() }
        val listed = lines.any { it.startsWith("- ") }
        return lines.mapIndexed { index, line ->
            if (listed && line.startsWith("- ")) ConsentBlock(ConsentBlock.Kind.Item, line.removePrefix("- ").trim())
            else ConsentBlock(if (listed && index == 0) ConsentBlock.Kind.Lead else ConsentBlock.Kind.Paragraph, line)
        }
    }
}
