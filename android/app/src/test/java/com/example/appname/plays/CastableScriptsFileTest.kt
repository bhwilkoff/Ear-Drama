package com.example.appname.plays

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The bundled file (`catalog/plays/castable-scripts.json`, copied into the
 * assets at build time) decodes, and every script in it can be cast. It reads
 * the file generically: the parser that writes it changes, and no test pins
 * which plays it holds.
 */
class CastableScriptsFileTest {
    private val castable = setOf(
        "script_gov_work", "script_pd_published_age", "script_registered_age",
        "script_source_cleared", "script_registered_not_renewed",
    )

    @Test fun `the bundled file decodes and every script can be cast`() {
        val library = CastableLibrary.decode(File("../../catalog/plays/castable-scripts.json").readText())
        assertEquals(1, library.format)
        assertFalse(library.scripts.isEmpty())
        for (script in library.scripts) {
            assertTrue("${script.id} is castable", script.rights.bucket in castable)
            assertTrue("${script.id} has parts", script.castParts.count { it.id.isSpeaking } >= 2)
            assertEquals("${script.id} line ids are unique", script.lines.size, script.lines.map { it.id }.toSet().size)
            val speaking = script.castParts.filter { it.id.isSpeaking }.map { it.lineCount }
            assertEquals("${script.id} largest part first", speaking.sortedDescending(), speaking)
            assertEquals("every line belongs to one part", script.lines.size, script.castParts.sumOf { it.lineCount })
        }
    }

    @Test fun `an unknown key is ignored and an unknown piece reads as a direction`() {
        val text = """{"format":1,"later":true,"scripts":[{"id":"x","revision":"r","kind":"stage","title":"T",
            "source":{"name":"S","url":"https://example.org"},"rights":{"bucket":"script_source_cleared","evidence":[]},
            "lines":[{"id":"L1","kind":"speech","role":"A","parts":[{"aside":"low"},{"say":"Hi"}],"new":1}]}]}"""
        val line = CastableLibrary.decode(text).scripts.single().lines.single()
        assertEquals(listOf(LinePart.Direction("low"), LinePart.Say("Hi")), line.parts)
        assertEquals("Hi", line.spokenText)
    }
}
