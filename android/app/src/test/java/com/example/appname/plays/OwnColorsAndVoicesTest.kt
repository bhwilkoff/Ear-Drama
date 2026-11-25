package com.example.appname.plays

import com.example.appname.ui.TabLabels
import com.example.appname.ui.screens.OwnPartsModel
import com.example.appname.ui.screens.partHues
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * R4-5's B26 follow-ups on Android: a part's color is the same on the parts page as on the script's page, the reader and the
 * studio (all read [PlayScript.partHue]); Defaults never pick a novelty voice; a tab bar's labels never break in a word.
 *
 * Seen to fail, 2026-11-24, each rule broken alone then restored: the parts page's order by first appearance only; its hues
 * counted from parts with no lines; NOVELTY empty; `uses` ignoring offByDefault for a device voice; the tab fit ignoring the
 * font scale; the tab fit ignoring the item count.
 */
class OwnColorsAndVoicesTest {
    private fun scriptOf(text: String): PlayScript {
        val doc = OwnScript.done(OwnScript.newDoc(OwnScript.parse(text).lines))
        val built = OwnScript.seal(OwnScript.toScript(doc, OwnMeta("own-00000000-0000-4000-8000-000000000001", "T")))
        return ProductionStore.json.decodeFromJsonElement(PlayScript.serializer(), OwnScripts.element(built))
    }

    private fun page(text: String): Map<String, String?> {
        val doc = OwnScript.newDoc(OwnScript.parse(text).lines)
        val rec = OwnRecord("own-00000000-0000-4000-8000-000000000001", "T", "", doc, created = 1, updated = 1)
        return partHues(OwnPartsModel(rec, emptySet()).parts())
    }

    private fun lines(vararg counts: Pair<String, Int>, firstSingles: List<String> = emptyList()) =
        (firstSingles.map { "$it: One." } + counts.flatMap { (who, n) -> List(n) { "$who: Line $it." } }).joinToString("\n") + "\n"

    @Test fun `a part's color is the same on the parts page as on the script's page`() {
        val texts = listOf(
            lines("ANNA" to 3, "BEN" to 3, "CY" to 2),
            lines("ANNA" to 1, "BEN" to 4, "CY" to 1, "DEE" to 4, firstSingles = listOf("ZED")),
            lines(*("ABCDEFGHIJ".map { "P$it" to (11 - ("ABCDEFGHIJ".indexOf(it))) }.toTypedArray())),
            "ANNA: Hello there.\n\n(A door.)\n\nBEN: Hi.\nSOUND: BELL\nBEN: Again.\nCY: Me.\nCY: Too.\nCY: Three.\n",
        )
        for (t in texts) {
            val script = scriptOf(t)
            val onScriptPage = script.castParts.filter { it.id.isSpeaking }.associate { it.id.roleName.orEmpty() to script.partHue(it.id) }
            assertEquals(t, onScriptPage, page(t))
        }
        assertTrue("ten parts: only the first seven have a mark", page(texts[2]).values.count { it != null } == 7)
    }

    // ---- Defaults never pick a novelty voice ----

    private fun raw(name: String, quality: Int = 400) = RawVoice(name, "en-US", quality, networkRequired = false, notInstalled = false)

    @Test fun `Defaults never pick a novelty voice, even where it would be the best, and a person may still tick one`() {
        val voices = VoiceCasting.castable(listOf(raw("Bahh", 500), raw("Zarvox", 500), raw("en-us-x-sfg#male_1-local", 300), raw("Boing", 500), raw("en-us-x-iom#female_2-local", 200)), Locale.US)
        val d = VoiceDefaults()
        val pool = VoiceCasting.pool(voices, d)
        assertEquals(listOf("en-us-x-sfg#male_1-local", "en-us-x-iom#female_2-local"), pool.map { it.id })
        val cast = VoiceCasting.autoCast(List(6) { PartID.role("P$it") }, pool)
        assertTrue("no part is given a novelty voice", cast.values.none { VoiceCasting.isNovelty(it.voice.orEmpty()) })
        val bahh = voices.first { it.id == "Bahh" }
        assertTrue("one the person ticks is in the pool", VoiceCasting.pool(voices, d.copy(off = mapOf(bahh.key to false))).any { it.id == "Bahh" })
        assertFalse("an ordinary voice is not novelty", VoiceCasting.isNovelty("en-us-x-sfg#male_1-local"))
    }

    // ---- A tab bar's labels ----

    @Test fun `a bar's labels show only while the widest word fits its tab`() {
        // 360 dp wide at density 3, five tabs: 216 px each less 48 px of padding leaves 168 px for a word.
        val width = 360f * 3
        assertTrue("a word that fits", TabLabels.fit(160, width, 5, 3f))
        assertFalse("one that does not", TabLabels.fit(170, width, 5, 3f))
        assertFalse("the same word in four more tabs' room", TabLabels.fit(168, width, 8, 3f).also { assertTrue(TabLabels.fit(168, width, 5, 3f)) })
        assertFalse("no tabs, no labels", TabLabels.fit(1, width, 0, 3f))
    }
}
