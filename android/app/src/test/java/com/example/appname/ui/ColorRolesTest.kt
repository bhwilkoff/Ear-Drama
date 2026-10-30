package com.example.appname.ui

import com.example.appname.ui.theme.BrandRecordDark
import com.example.appname.ui.theme.BrandRecordLight
import com.example.appname.ui.theme.genreColor
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** DECISIONS 064 and ANDROID-DESIGN §6.1a: red means recording, ink is the primary action, blue for the rest, genre marks from the tokens. */
class ColorRolesTest {
    private val sources = File("src/main/java").walkTopDown().filter { it.extension == "kt" }.toList()

    /** A screen that reaches the red any way but `OnAir.colors.record` (or M3's red `tertiary`) decorates with it. */
    private fun redOutsideTheRoles(source: String): Set<String> =
        Regex("""\bBrandRecord\w*|\bBrandOnRecord\w*|colorScheme\.(tertiary|onTertiary)\b""").findAll(source).map { it.value }.toSet()

    /** The red's own role, reached by name. */
    private fun recordRole(source: String): Set<String> =
        Regex("""OnAir\.colors\.(record|onRecord)\b|\brecordButtonColors\(\)""").findAll(source).map { it.value }.toSet()

    @Test fun `the record red is reached only through OnAir`() {
        assertTrue(sources.size > 10)
        val found = sources.filter { it.parentFile?.name != "theme" }
            .associate { it.name to redOutsideTheRoles(it.readText()) }
            .filterValues { it.isNotEmpty() }
        assertEquals(emptyMap<String, Set<String>>(), found)
        assertEquals(setOf("colorScheme.tertiary"), redOutsideTheRoles("tint = MaterialTheme.colorScheme.tertiary"))
    }

    /** Owner, 2026-10-29: "Red means recording." Only the recording screen and its views in Recorder.kt (and the helper that defines the button) use it. */
    @Test fun `the record red appears only where recording happens`() {
        val found = sources.filter { it.name !in setOf("RecordingScreen.kt", "Recorder.kt") && it.parentFile?.name != "theme" }
            .associate { it.name to recordRole(it.readText()).minus(if (it.name == "Components.kt") setOf("OnAir.colors.record", "OnAir.colors.onRecord", "recordButtonColors()") else emptySet()) }
            .filterValues { it.isNotEmpty() }
        assertEquals(emptyMap<String, Set<String>>(), found)
        assertTrue(recordRole(File("src/main/java/com/example/appname/ui/screens/RecordingScreen.kt").readText()).isNotEmpty())
        assertEquals(setOf("OnAir.colors.record"), recordRole("Icon(Icons.Filled.PlayArrow, tint = OnAir.colors.record)"))
    }

    /** M3 components default to `primary`, so its slot holds the blue, never the ink or the red. */
    @Test fun `the Material primary slot is the blue`() {
        val theme = File("src/main/java/com/example/appname/ui/theme/Theme.kt").readText()
        val primaries = Regex("""\n\s+primary = (\w+),""").findAll(theme).map { it.groupValues[1] }.toList()
        assertEquals(listOf("BrandSecondaryLight", "BrandSecondaryDark"), primaries)
    }

    @Test fun `every genre the tokens name has its mark, in both modes`() {
        val json = File("../../design-tokens.json").readText()
        val group = json.substringAfter("\"genre\"").substringBefore("\n    }")
        val keys = Regex("""\n\s{6}"([a-z]+)"\s*:""").findAll(group).map { it.groupValues[1] }.toList()
        assertTrue("genre keys from design-tokens.json: $keys", keys.size >= 8)
        keys.forEach { key ->
            assertNotNull(key, genreColor(key, dark = false))
            assertNotNull(key, genreColor(key, dark = true))
            assertTrue(key, genreColor(key, false) != BrandRecordLight && genreColor(key, true) != BrandRecordDark)
        }
        assertNull(genreColor("opera", dark = false))
        assertNull(genreColor(null, dark = true))
    }
}
