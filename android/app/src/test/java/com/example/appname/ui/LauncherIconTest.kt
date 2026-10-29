package com.example.appname.ui

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Decision 060: the launcher icon is the ring microphone on the master's red,
 * with a monochrome layer for themed icons, and the display face ships in res/font.
 */
class LauncherIconTest {
    private val res = File("src/main/res")

    private fun layerProblems(xml: String): List<String> = buildList {
        if (!xml.contains("""<background android:drawable="@color/icon_background"/>""")) add("background")
        if (!xml.contains("""<foreground android:drawable="@drawable/ic_launcher_foreground"/>""")) add("foreground")
        if (!xml.contains("""<monochrome android:drawable="@drawable/ic_launcher_monochrome"/>""")) add("monochrome")
    }

    @Test fun `both launcher icons carry the ground, the mark, and a monochrome layer`() {
        for (name in listOf("ic_launcher", "ic_launcher_round")) {
            val xml = File(res, "mipmap-anydpi/$name.xml").readText()
            assertEquals(name, emptyList<String>(), layerProblems(xml))
        }
        // The control: the template's placeholder (a white ground, no monochrome of its own) is caught.
        val placeholder = """<background android:drawable="@color/brand_background"/>
            <foreground android:drawable="@drawable/ic_launcher_foreground"/>
            <monochrome android:drawable="@drawable/ic_launcher_foreground"/>"""
        assertEquals(listOf("background", "monochrome"), layerProblems(placeholder))
    }

    @Test fun `the layers are the generated mark, and the ground is the icon red in both modes`() {
        for (name in listOf("ic_launcher_foreground", "ic_launcher_monochrome")) {
            val xml = File(res, "drawable/$name.xml").readText()
            assertTrue("$name is not the generated mark", xml.contains("tools/render-app-icon.py") && xml.contains("android:fillType=\"evenOdd\""))
        }
        val day = File(res, "values/colors.xml").readText()
        val night = File(res, "values-night/colors.xml").readText()
        val ground = Regex("""<color name="icon_background">(#\w+)</color>""")
        assertEquals("#FFB0152F", ground.find(day)?.groupValues?.get(1))
        assertEquals(ground.find(day)?.groupValues?.get(1), ground.find(night)?.groupValues?.get(1))
    }

    @Test fun `the display face is bundled`() {
        val font = File(res, "font/big_shoulders_bold.ttf")
        assertTrue("res/font/big_shoulders_bold.ttf is missing", font.isFile && font.length() > 10_000)
    }
}
