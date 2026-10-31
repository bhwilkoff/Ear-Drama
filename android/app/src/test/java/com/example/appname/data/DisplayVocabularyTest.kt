package com.example.appname.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** docs/CATALOG-CONTRACT.md §5.5, word for word. */
class DisplayVocabularyTest {
    @Test fun `unclaimed reads exactly as the contract says`() {
        assertEquals("No rights claim known. Removed on request.", DisplayVocabulary.rightsLine("unclaimed", null))
        assertEquals(
            "No rights claim known. Removed on request.",
            DisplayVocabulary.rightsLine("unclaimed", "rec_orphan_unclaimed"),
        )
    }

    @Test fun `no input ever yields public domain`() {
        val bases = listOf(null, "rec_gov_work", "rec_librivox", "rec_pd_published_age", "rec_orphan_unclaimed",
            "rec_cc_corroborated", "public_domain", "")
        listOf("clean", "unclaimed", "public_domain", "").forEach { rights ->
            bases.forEach { basis ->
                val line = DisplayVocabulary.rightsLine(rights, basis).orEmpty()
                assertFalse("$rights/$basis -> $line", line.contains("public domain", ignoreCase = true))
            }
        }
    }

    @Test fun `clean rows name their basis, and an unknown basis shows nothing`() {
        assertEquals("Government recording", DisplayVocabulary.rightsLine("clean", "rec_gov_work"))
        assertEquals("LibriVox recording", DisplayVocabulary.rightsLine("clean", "rec_librivox"))
        assertEquals("Published before 1926", DisplayVocabulary.rightsLine(
            "clean", "rec_pd_published_age", DisplayVocabulary.contractRightsLines(2026)))
        assertEquals("Published before 1927", DisplayVocabulary.contractRightsLines(2027)["rec_pd_published_age"])
        assertEquals("Creative Commons recording", DisplayVocabulary.rightsLine("clean", "rec_cc_corroborated"))
        assertNull(DisplayVocabulary.rightsLine("clean", "rec_unknown_basis"))
    }

    @Test fun `no client source types the rights year`() {
        val root = java.io.File("src/main/java")
        val files = root.walkTopDown().filter { it.extension == "kt" }.toList()
        assertTrue("no sources found from ${java.io.File(".").absolutePath}", files.isNotEmpty())
        val typed = Regex("Published before [0-9]{4}")
        files.forEach { assertFalse("${it.name} types the rights year", typed.containsMatchIn(it.readText())) }
    }

    @Test fun `the eight genre codes have names and nothing else does`() {
        assertEquals("Science fiction", DisplayVocabulary.genreName("scifi"))
        assertEquals("Serials", DisplayVocabulary.genreName("serial"))
        assertNull(DisplayVocabulary.genreName("OTR-Variety"))
    }

    @Test fun `versions use the contract's words`() {
        assertEquals("Armed Forces Radio rebroadcast", DisplayVocabulary.variantLine("AFRS"))
        assertEquals("Armed Forces Radio rebroadcast", DisplayVocabulary.variantLine("AFRTS"))
        assertNull(DisplayVocabulary.variantLine(null))
        assertEquals("Incomplete copy", DisplayVocabulary.PARTIAL)
    }
}
