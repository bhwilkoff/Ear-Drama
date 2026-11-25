package com.example.appname.navigation

import android.content.Intent
import android.net.Uri
import com.example.appname.plays.OwnDoc
import com.example.appname.plays.OwnLine
import com.example.appname.plays.OwnOp
import com.example.appname.plays.OwnRecord
import com.example.appname.plays.OwnScript
import com.example.appname.plays.OwnText
import com.example.appname.ui.screens.OwnIncoming
import com.example.appname.ui.screens.OwnPartsModel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * What a text handed over by another app becomes (ANDROID-DESIGN §4.23 item 1), and the parts page's own rules over the core.
 * Seen to fail, 2026-11-24: a `file:` address accepted; any text type accepted; words past the cap read; Next starting over
 * from the top after a step.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class OwnIntentsTest {
    private fun send(type: String? = "text/plain", fill: Intent.() -> Unit) = OwnIntents.incoming(Intent(Intent.ACTION_SEND).setType(type).apply(fill))

    @Test fun `words and files are taken, and nothing else`() {
        assertEquals(OwnIncoming.Words(OwnText.Read("ANNA: Hi", "A play")), send { putExtra(Intent.EXTRA_TEXT, "ANNA: Hi"); putExtra(Intent.EXTRA_SUBJECT, "A play") })
        val file = Uri.parse("content://files/play.txt")
        assertEquals(OwnIncoming.File(file), send { putExtra(Intent.EXTRA_STREAM, file) })
        assertEquals(OwnIncoming.File(file), OwnIntents.incoming(Intent(Intent.ACTION_VIEW).setDataAndType(file, "text/plain")))
        assertEquals("with a character set too", OwnIncoming.Words(OwnText.Read("x")), send("text/plain; charset=utf-8") { putExtra(Intent.EXTRA_TEXT, "x") })
        assertEquals("too long is refused before it is read", OwnIncoming.Words(OwnText.Refused("too_long")), send { putExtra(Intent.EXTRA_TEXT, "x".repeat(OwnScript.MAX_BYTES + 1)) })
        assertNull("a path in this app's own files", send { putExtra(Intent.EXTRA_STREAM, Uri.parse("file:///data/data/app.eardrama/files/Plays/x")) })
        assertNull(OwnIntents.incoming(Intent(Intent.ACTION_VIEW).setDataAndType(Uri.parse("file:///sdcard/x.txt"), "text/plain")))
        assertNull("a picture", send("image/png") { putExtra(Intent.EXTRA_STREAM, file) })
        assertNull("a link is the links' own", OwnIntents.incoming(Intent(Intent.ACTION_VIEW, Uri.parse("https://eardrama.org/parts"))))
        assertNull(send { })
        assertNull(OwnIntents.incoming(null))
    }

    private fun model(vararg kinds: String): OwnPartsModel {
        val lines = kinds.mapIndexed { i, k -> OwnLine(i + 1, null, if (k == "open") "open" else "speech", k.takeIf { it != "open" }, "Words $i") }
        return OwnPartsModel(OwnRecord("own-x", "T", "", OwnDoc(lines, lines.size + 1), created = 0, updated = 0), emptySet()).apply { current = 1 }
    }

    @Test fun `Next goes to the first line with no part, then on from where the person is, and around`() {
        val m = model("A", "open", "B", "open")
        assertEquals(2, m.nextOpen())
        m.current = 2; m.edited = true
        assertEquals(4, m.nextOpen())
        m.current = 4
        assertEquals(2, m.nextOpen())
        assertNull(model("A", "B").nextOpen())
        assertEquals("the first line itself", 1, model("open", "A").nextOpen())
    }

    @Test fun `the parts are largest first, then those with no line yet`() {
        val m = model("B", "A", "A", "open")
        assertEquals("NEW" to null, m.addPart("new"))
        assertEquals("a name twice is one part", "NEW" to null, m.addPart("New"))
        assertEquals(listOf("A" to 2, "B" to 1, "NEW" to 0), m.parts())
        assertEquals("Add a name.", m.addPart(" ").second)
        assertNull(m.apply(OwnOp("words", line = 1, text = "Other"), "Words changed"))
        assertEquals("Words changed" to 1, m.said)
        assertEquals("no_such_line", m.apply(OwnOp("words", line = 99, text = "x"), "y"))
        assertEquals("a refused step says nothing", "Words changed" to 1, m.said)
    }
}
