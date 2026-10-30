package com.example.appname.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The golden cases of js/api.test.js "grammar: the title block, ..." (WEB-DESIGN §6.4b), held on Android too. */
class GrammarTest {
    private fun at(w: Int?, h: Int?, face: FaceBox?) = Artwork("https://x/A.jpg", w, h, face = face)

    @Test fun `the monogram and its block size`() {
        listOf(
            Triple("The Shadow", "S", 104), Triple("Lux Radio Theatre", "LR", 82), Triple("X Minus One", "XM", 66),
            Triple("The Adventures of Sam Spade", "AS", 82), Triple("Mr. and Mrs. North", "MM", 55), Triple("Wild West", "WW", 53), Triple("Jack Johnson", "JJ", 91),
            Triple("El Dorado", "D", 104), Triple("The \"Lone Ranger\"", "LR", 82), Triple("2000 Plus", "P", 104),
            Triple("1949", "1", 104), Triple("", "", 104),
        ).forEach { (name, m, size) ->
            assertEquals("monogram of \"$name\"", m, monogram(name))
            assertEquals("block size of \"$m\"", size, blockSize(m))
        }
    }

    @Test fun `the type step`() {
        assertEquals("eight letters keep the size", 0, nameStep("Hopalong Cassidy"))
        assertEquals("a word past 10 letters steps down once", 1, nameStep("Extraordinary Tales"))
        assertEquals("past 14, twice", 2, nameStep("Supercalifragilistic"))
    }

    @Test fun `the window decides crop, whole or block`() {
        val face = FaceBox(0.4f, 0.1f, 0.2f, 0.15f)
        assertTrue("a face crop 240 px tall fills a 200 px window", windowFill(at(600, 800, face), 200f) is WindowFill.Crop)
        assertEquals("control: the same crop is under the floor at 300", WindowFill.Block, windowFill(at(600, 800, face), 300f))
        assertEquals("a wide picture with no face is drawn whole", WindowFill.Whole, windowFill(at(1000, 500, null), 200f))
        assertEquals("control: its short side under half the window is a block", WindowFill.Block, windowFill(at(300, 150, null), 400f))
        assertEquals("control: an unknown size is a block", WindowFill.Block, windowFill(at(null, null, null), 48f))
        assertEquals("control: no picture is a block", WindowFill.Block, windowFill(null, 48f))
    }

    @Test fun `the event line keeps each separator with the fact before it`() {
        assertEquals(listOf("1947 ·", "CBS ·", "30"), eventParts(listOf("1947", null, "CBS", " ", 30)))
        assertEquals("control: no facts, no line", emptyList<String>(), eventParts(emptyList()))
    }

    @Test fun `the run strip on the fixed axis`() {
        val span = runSpan("1947-03-01", "1952")!!
        assertTrue("1947 to 1952 on the 1930-1962 axis, got $span", Math.abs(span.from - 17.0 / 33) < 1e-9 && Math.abs(span.to - 23.0 / 33) < 1e-9)
        assertEquals("clamped to the axis", RunSpan(0.0, 1.0), runSpan("1925", "1970"))
        val one = runSpan("1940", null)!!
        assertTrue("a single year is one year wide", Math.abs(one.to - one.from - 1.0 / 33) < 1e-9)
        assertNull("control: undated is the baseline alone", runSpan(null, null))
    }

    @Test fun `the grade is the identity until one is published`() {
        assertEquals("no published grade: the identity levels", Grade(1.0, 0.0), gradeOf(at(10, 10, null)))
        assertEquals("a published grade replaces it", Grade(1.1, -0.05), gradeOf(Artwork("u", grade = listOf(1.1, -0.05))))
    }
}
