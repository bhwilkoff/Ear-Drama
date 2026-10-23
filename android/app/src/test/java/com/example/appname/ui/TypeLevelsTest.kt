package com.example.appname.ui

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** AGENTS.md and ANDROID-DESIGN §6.2: six type levels, and no screen reaches for a seventh. */
class TypeLevelsTest {
    private val six = setOf("displaySmall", "headlineSmall", "titleMedium", "bodyMedium", "labelMedium", "bodySmall")

    private fun stylesOutsideTheSix(source: String): Set<String> =
        Regex("""typography\.(\w+)""").findAll(source).map { it.groupValues[1] }.filter { it !in six }.toSet()

    @Test fun `every style the app names is one of the six`() {
        val sources = File("src/main/java").walkTopDown().filter { it.extension == "kt" }.toList()
        assertTrue("no sources found from ${File(".").absolutePath}", sources.size > 10)
        val found = sources.associate { it.name to stylesOutsideTheSix(it.readText()) }.filterValues { it.isNotEmpty() }
        assertEquals(emptyMap<String, Set<String>>(), found)
        // The control: the transcript's old seventh style is caught.
        assertEquals(setOf("bodyLarge"), stylesOutsideTheSix("style = MaterialTheme.typography.bodyLarge,"))
    }
}
