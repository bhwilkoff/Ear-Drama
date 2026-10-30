package com.example.appname.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
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

    private data class Broadcast(val id: String, val date: String?, val title: String, val series: String)
    private data class Show(val genre: String, val episodes: Int)

    /** The golden cases of js/api.test.js "home and browse: ..." (WEB-DESIGN §6.4c). */
    @Test fun `home and browse - the show line, the day by year, the night, the decade field`() {
        assertTrue("five episodes is a show", isShow(5))
        assertFalse("control: four is a single recording", isShow(4))
        assertFalse("control: no count is not a show", isShow(null))
        val rows = listOf(
            Broadcast("a|1944-10-29", "1944-10-29", "Beloved Enemy", "a"),
            Broadcast("a2|1944-10-29", "1944-10-29", "Beloved  enemy!", "a"),
            Broadcast("b|1944-10-29", "1944-10-29", "On Train", "b"),
            Broadcast("c|1944-10-29", "1944-10-29", "Odd One", "c"),
            Broadcast("d|1938-10-29", "1938-10-29", "Early", "d"),
            Broadcast("e|", null, "No date", "d"),
        )
        val sr = mapOf("a" to Show("drama", 40), "b" to Show("comedy", 9), "c" to Show("", 2), "d" to Show("drama", 6))
        val dy = dayYears(rows, { it.date }, { sr.getValue(it.series).genre })
        assertEquals("broadcasts per year, an undated row left off the strip", listOf(1938 to 1, 1944 to 4), dy.years.map { it.year to it.total })
        assertEquals("the peak year is the one with most", 1944, dy.peak)
        assertEquals("the count is what the strip holds", 5, dy.count)
        assertEquals("a year stacked by genre, no genre as the empty key", mapOf("drama" to 2, "comedy" to 1, "" to 1), dy.years[1].genres)
        assertEquals("the legend lists genres seen, in the fixed order, never the empty one", listOf("drama", "comedy"), dy.genres)
        val tie = listOf(Broadcast("x", "1940-01-01", "x", "d"), Broadcast("y", "1941-01-01", "y", "d"))
        assertEquals("control: a tie goes to the earlier year", 1940, dayYears(tie, { it.date }, { "" }).peak)
        val night = nightShows(rows.filter { (it.date ?: "").startsWith("1944") }, { it.title }, { sr[it.series]?.episodes })
        assertEquals("a copy under the same title folds once; a single is not a show", listOf("a|1944-10-29", "b|1944-10-29"), night.shows.map { it.id })
        assertEquals("singles are counted", 1, night.singles)
        val f = decadeField(
            listOf(
                FieldShow("drama", "1944-01-01"), FieldShow("drama", "1949"), FieldShow("comedy", "1951"),
                FieldShow("", "1950"), FieldShow("news", null),
            ),
        )
        assertEquals("decades from the first year", listOf(1940, 1950), f.decades)
        assertEquals("a cell counts its shows", 2, f.count("drama", 1940))
        assertEquals("no genre and no first year are counted, not drawn", 2, f.none)
        assertEquals("rows only for genres that have a cell", listOf("drama", "comedy"), f.genres)
        assertEquals("the biggest cell is the full side", 32, fieldSide(98, 98))
        assertEquals("a one-show cell keeps the floor", 6, fieldSide(1, 98))
        assertEquals("control: an empty cell draws nothing", 0, fieldSide(0, 98))
        assertEquals("area carries the count (the square root)", 23, fieldSide(49, 98))
    }

    @Test fun `series and episode pages - the lead picture, who is on the air, the event line`() {
        fun art(u: String) = Artwork(u, 600, 800)
        fun credit(person: String, role: String, art: Artwork?) = Credit(person, person.uppercase(), role, null, art)
        fun show(kind: String?, picture: Artwork?) = SeriesRow("k", "K", null, null, null, 1, picture = picture, pictureKind = kind)
        val credits = listOf(
            credit("a", "cast", null), credit("b", "cast", art("b")), credit("c", "cast", art("c")),
            credit("d", "writer", art("d")), credit("b", "cast", art("b")),
        )
        assertEquals("a show picture leads over any star", "show", leadPicture(show("show", art("show")), credits, "c")?.url)
        assertEquals("a star picture on the series gives way to the episode's star", "c", leadPicture(show("star", art("s")), credits, "c")?.url)
        assertEquals("no star named: the first cast with a picture", "b", leadPicture(show("star", art("s")), credits, null)?.url)
        assertEquals("control: a writer is not a lead; the series picture", "s", leadPicture(show("star", art("s")), listOf(credit("w", "writer", art("w"))), null)?.url)
        assertNull("control: nothing to show is the title block", leadPicture(show(null, null), emptyList(), null))
        assertEquals("cast in billing order, once each, no writers", listOf("a", "b", "c"), onAirOf(credits).map { it.personId })
        assertEquals("at most the limit", 2, onAirOf(credits, 2).size)
        assertEquals(
            "the event line, in order",
            listOf("Jun 17, 1943", "CBS", "30 min", "Season 1943-44", "No. 4"),
            episodeFacts("CBS", null, "1943-44", "T", 4, "Jun 17, 1943", "30 min"),
        )
        assertEquals(
            "control: an undated bare file says only so; a number already naming it is not repeated",
            listOf("Undated"),
            episodeFacts(null, null, null, null, 4, null, null),
        )
    }

    @Test fun `series networks read from the published array`() {
        assertEquals(listOf("CBS", "NBC"), CatalogDatabase.networkList("[\"CBS\", \"\", \"NBC\"]"))
        assertEquals("control: malformed is none", emptyList<String>(), CatalogDatabase.networkList("CBS"))
        assertEquals("control: null is none", emptyList<String>(), CatalogDatabase.networkList(null))
    }

    @Test fun `A to Z letters`() {
        assertEquals("T", azLetter("The Shadow"))
        assertEquals("an accent folds", "E", azLetter("\u00c9clair"))
        assertEquals("a number goes under #", "#", azLetter("2000 Plus"))
        assertEquals("a symbol goes under #", "#", azLetter("\"Quoted\""))
        assertEquals(listOf("#", "A", "Z"), azLetters(listOf("Zero", "10 Days", "Adam", "Alan")))
        assertEquals("control: no # when no number", listOf("A"), azLetters(listOf("Adam")))
    }

    @Test fun `the histogram strip draws real years`() {
        val bars = runBars(listOf(1938, 1, 0, 4))!!
        assertEquals("a year with no episode draws nothing", 2, bars.size)
        assertEquals(0.25, bars[0].height, 1e-9)
        assertEquals("the peak year is full height", 1.0, bars[1].height, 1e-9)
        assertEquals(10.0 / 33.0, bars[1].from, 1e-9)
        assertNull("control: no histogram, the span draws", runBars(null))
        assertNull("control: all zero is none", runBars(listOf(1940, 0, 0)))
        assertEquals(listOf(1932, 3, 12, 0, 4), parseYearCounts("1932,3,12,0,4"))
        assertNull("control: a year alone is none", parseYearCounts("1932"))
        assertNull(parseYearCounts(null))
    }

    @Test fun `a bare undated row leads with the window`() {
        assertTrue(undatedBare(null, null))
        assertFalse("control: a number keeps its block", undatedBare(null, 7))
        assertFalse("control: a date keeps its block", undatedBare("1943-05-25", null))
    }
}
