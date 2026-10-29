package com.example.appname.plays

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The CC0 consent as structure (F3): the Worker's real words, read from
 * worker/src/plays.js, become one lead and four items with no word changed;
 * text without "- " lines is paragraphs.
 */
class ConsentTextTest {
    private fun served(): String {
        val source = generateSequence(File("").absoluteFile) { it.parentFile }
            .map { File(it, "worker/src/plays.js") }.first { it.exists() }.readText()
        return Regex("CONSENT_TEXT = `([^`]*)`").find(source)!!.groupValues[1]
    }

    @Test
    fun `the served words become a lead and four items`() {
        val text = served()
        val blocks = ConsentText.blocks(text)
        assertEquals(1, blocks.count { it.kind == ConsentBlock.Kind.Lead })
        assertEquals(4, blocks.count { it.kind == ConsentBlock.Kind.Item })
        assertEquals(ConsentBlock.Kind.Lead, blocks.first().kind)
        val rebuilt = blocks.joinToString("\n") { (if (it.kind == ConsentBlock.Kind.Item) "- " else "") + it.text }
        assertEquals(text, rebuilt)
    }

    @Test
    fun `text without list lines is paragraphs`() {
        assertEquals(
            listOf(ConsentBlock.Kind.Paragraph, ConsentBlock.Kind.Paragraph),
            ConsentText.blocks("One thing.\nAnother thing.").map { it.kind },
        )
        assertTrue(ConsentText.blocks("").isEmpty())
    }
}
