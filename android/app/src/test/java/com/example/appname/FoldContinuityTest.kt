package com.example.appname

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * "Folding during a take" (Decision 080, PLAYS-DESIGN §2.9 rule 11): the studio's session is held by the composition
 * (`rememberStudio`, above the compact and the supporting-pane layouts), not by an Activity that a resize would rebuild,
 * so a take survives a fold, an unfold, a rotation and a window resize only while MainActivity handles those changes
 * itself. This holds that declaration; the same change on the Pixel with the stub take is the device check.
 */
class FoldContinuityTest {
    private val manifest = File("src/main/AndroidManifest.xml").readText()

    private fun handled(): Set<String> =
        Regex("""android:name="\.MainActivity"[^>]*?android:configChanges="([^"]+)"""", RegexOption.DOT_MATCHES_ALL)
            .find(manifest)!!.groupValues[1].split('|').toSet()

    @Test fun theActivityHandlesEveryChangeAFoldOrResizeReports() {
        val have = handled()
        for (change in listOf("orientation", "screenSize", "smallestScreenSize", "screenLayout")) {
            assertTrue("MainActivity must handle $change itself or a fold rebuilds it and a take is lost", change in have)
        }
    }
}
