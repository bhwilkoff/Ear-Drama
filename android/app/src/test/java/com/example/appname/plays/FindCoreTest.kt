package com.example.appname.plays

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Finding a play (B31 §3), FindCore held to js/find.test.js's own fixture (and Apple's FindCoreTests): an index shaped as contract
 * §4.1 publishes it (never the real catalog's contents), the facets and their counts against each other, rails that never repeat a
 * play, search by title, character and spoken line (the words in order before scattered ones), a library built before B31 decoding
 * with none of it, and negative controls.
 *
 * Seen to fail, 2026-11-26, then restored: `rails` taking a play a rail above already holds (`theRepeatCheckSeesARepeat` runs the
 * naive builder), `counts` dropping the skip (a facet counting against its own pick), `lineHit` with no phrase test, the lenient
 * decode of a malformed field (the junk index lost its row).
 */
class FindCoreTest {
    private fun row(id: String, title: String, extra: String = "", author: String = "Ann Writer", voices: Int = 2, minutes: Int = 10): String =
        """{"id":"$id","revision":"r","title":"$title","sort_name":"${title.replace(Regex("^(The|A) "), "")}","authors":["$author"],
            "voices":$voices,"minutes":$minutes,"cast":[10,8]${if (extra.isEmpty()) "" else ",$extra"}}"""

    private val indexText = """{"format":1,"plays":[
        ${row("a", "Alpha", """"form":"comedy","hue":"comedy","era":"1900-1930","balance":"ensemble","oneAct":true,"subjects":["Ireland"],"locc":"PR",
            "scenes":[{"line":"L0003","heading":"Scene I","voices":2,"minutes":4,"parts":["JACK","JILL"]}]""", voices = 2, minutes = 8)},
        ${row("b", "Beta", """"form":"tragedy","era":"1800s","balance":"lead","locc":"PT"""", voices = 4, minutes = 35)},
        ${row("c", "The Gamma", """"era":"1800s","balance":"mixed","locc":"PR",
            "scenes":[{"line":"L0010","heading":"Act II","voices":2,"minutes":6,"parts":["ANN","BOB"]},
                      {"line":"L0090","heading":"Act III","voices":3,"minutes":3,"parts":["A","B","C"]},{"line":7,"voices":"two"}]""", voices = 2, minutes = 15)},
        ${row("d", "Delta", """"form":"melodrama","balance":"ensemble","locc":"PS"""", voices = 12, minutes = 120)},
        ${row("e", "Epsilon", """"form":"comedy","era":"1600s","balance":"mixed","locc":"PR"""", author = "Ben Bard", voices = 6, minutes = 50)},
        ${row("f", "Zeta", """"form":"comedy","era":"1600s","balance":"mixed","locc":"PR",
            "picture":{"url":"https://example.org/w.jpg","width":800,"height":600,"kind":"work"},
            "titlePage":{"url":"https://example.org/t.jpg","width":800,"height":1200}""", author = "Ben Bard", voices = 3, minutes = 9)}],
        "facets":{
          "voices":[{"min":1,"max":2,"count":2},{"min":3,"max":4,"count":2},{"min":5,"max":6,"count":1},{"min":7,"max":10,"count":0},{"min":11,"max":null,"count":1}],
          "minutes":[{"min":1,"max":10,"count":2},{"min":11,"max":20,"count":1},{"min":21,"max":40,"count":1},{"min":41,"max":90,"count":1},{"min":91,"max":null,"count":1}],
          "form":[{"value":"comedy","count":3},{"value":"tragedy","count":1},{"value":null,"count":2}],
          "era":[{"value":"1600s","count":2},{"value":"1800s","count":2},{"value":"1900-1930","count":1},{"value":null,"count":1}],
          "balance":[{"value":"ensemble","count":2},{"value":"mixed","count":3},{"value":"lead","count":1}],
          "subjects":[{"value":"Ireland","count":1}],
          "locc":[{"value":"PR","count":4},{"value":"PT","count":1},{"value":"PS","count":1}],"oneAct":1}}"""

    private val index = PlayIndex.decode(indexText)
    private val rows = index.plays
    private val facets = FindCore.facets(index.facets)
    private val collections = PlayCollections(data = listOf(
        PlayCollection("two-voices", "Plays for two voices", count = 2, plays = listOf("a", "c")),
        PlayCollection("ten-minutes", "Ten minutes or less", count = 2, plays = listOf("a", "f")),
        PlayCollection("one-act", "One Act Plays", count = 1, plays = listOf("a")),
        PlayCollection("author-bard", "Ben Bard", kind = "author", count = 2, plays = listOf("e", "f")),
    ))

    @Test fun `the facets are the index's`() {
        assertEquals(listOf("voices", "length", "balance", "form", "era", "subject", "locc", "oneact"), facets.map { it.key })
        val form = facets.first { it.key == "form" }
        assertEquals(listOf("Comedy", "Tragedy", "Not named"), form.values.map { it.label })
        assertEquals("a folded form (melodrama, under five) counts as Not named", listOf("none"), form.of(rows[3]))
        assertEquals("an old band is dropped", mapOf("form" to "comedy"), FindCore.offered(mapOf("voices" to "3-5", "form" to "comedy", "nope" to "x"), facets))
        assertEquals(listOf("Up to 10 min", "10-20 min", "20-40 min", "40-90 min", "Longer"), facets.first { it.key == "length" }.values.map { it.label })
        assertEquals(listOf("1-2", "3-4", "5-6", "7-10", "11+"), facets.first { it.key == "voices" }.values.map { it.label })
    }

    @Test fun `counts run against the other picks and no choice yields nothing`() {
        val c = FindCore.counts(rows, facets, mapOf("form" to "comedy"))
        assertEquals(listOf("1-2:1", "3-4:1", "5-6:1"), c.first { it.key == "voices" }.values.map { "${it.value}:${it.count}" })
        val form = c.first { it.key == "form" }.values
        assertTrue("form counts ignore the form pick", form.first { it.value == "comedy" }.count == 3 && form.first { it.value == "tragedy" }.count == 1)
        val chosen = FindCore.counts(rows, facets, mapOf("voices" to "7-10")).first { it.key == "voices" }.values
        assertTrue("a chosen empty value stays", chosen.any { it.value == "7-10" && it.count == 0 })
        for (f in FindCore.counts(rows, facets, mapOf("era" to "1600s"))) for (x in f.values) {
            assertEquals("${f.key}=${x.value}", x.count, FindCore.filter(rows, facets, mapOf("era" to "1600s", f.key to x.value)).size)
        }
    }

    @Test fun `the ways in never repeat a play`() {
        val rs = FindCore.rails(rows, collections)
        assertEquals(listOf("scenes-2", "ten-minutes"), rs.map { it.id })
        assertEquals("Ten minutes drops Alpha, which the scenes rail holds", listOf("f"), rs.last().plays.map { it.id })
        val seen = HashSet<String>()
        for (r in rs) for (id in r.plays.map { it.id } + r.scenes.map { it.row.id }) assertTrue("$id twice", seen.add(id))
        assertEquals("the scenes rail counts every play with a scene for two", 2, rs.first().count)
        assertFalse("no editor rail from an empty file", rs.any { it.kind == FindCore.RailKind.Editor })
        val ed = collections.copy(editor = listOf(PlayCollection("ed1", "For a pair", by = "Ben", plays = listOf("c", "a", "gone"))))
        val first = FindCore.rails(rows, ed).first()
        assertTrue("the editor's rail leads, ids that do not resolve dropped",
            first.kind == FindCore.RailKind.Editor && first.by == "Ben" && first.plays.map { it.id } == listOf("c", "a"))
        assertEquals("no collections file: the scenes rail alone", listOf("scenes-2"), FindCore.rails(rows, null).map { it.id })
        assertTrue("the TV has no scenes", FindCore.rails(rows, collections, withScenes = false).none { it.kind == FindCore.RailKind.Scenes })
    }

    /** Negative control: a rail builder that forgets what it has shown repeats a play the test above would catch. */
    @Test fun `the repeat check sees a repeat`() {
        val shown = FindCore.rails(rows, collections).flatMap { r -> r.plays.map { it.id } + r.scenes.map { it.row.id } }
        val naive = listOf("a", "c") + collections.data.first { it.id == "ten-minutes" }.plays
        assertTrue(shown.toSet().size == shown.size && naive.toSet().size != naive.size)
    }

    @Test fun `a collection keeps its order and the plays neighbors`() {
        assertEquals(listOf("a", "f"), FindCore.collection(rows, collections, "ten-minutes")?.second?.map { it.id })
        assertNull(FindCore.collection(rows, collections, "nope"))
        assertEquals(listOf("c", "f"), FindCore.sameShape(rows, rows[0]).map { it.id })
        val by = FindCore.byAuthor(rows, collections, rows[4])
        assertTrue(by.id == "author-bard" && by.plays.map { it.id } == listOf("f"))
        assertEquals("the TV's shelves leave the authors out", FindCore.RAIL_IDS, FindCore.tvIds(PlayCollections(data = collections.data.filter { it.kind == "author" })))
        assertTrue(FindCore.tvIds(PlayCollections(data = listOf(PlayCollection("christmas", "Christmas plays")))).last() == "christmas")
    }

    @Test fun `search by title author and character`() {
        assertEquals(listOf("c"), FindCore.titleHits(rows, "gam").map { it.id })
        assertEquals(listOf("e", "f"), FindCore.titleHits(rows, "ben").map { it.id })
        val names = mapOf("CANDIDA" to listOf(listOf(0, 141), listOf(3, 77)), "LADY CANDIDA" to listOf(listOf(1, 5)), "BOB" to listOf(listOf(2, 9)), "OUT OF RANGE" to listOf(listOf(99, 4)))
        assertEquals(listOf("a:141", "d:77", "b:5"), FindCore.characterHits(rows, names, "candida").map { "${it.row.id}:${it.lines}" })
        assertTrue(FindCore.titleCase("LADY BRACKNELL") == "Lady Bracknell" && FindCore.titleCase("1 AVOC") == "1 Avoc")
    }

    @Test fun `said shards intersect every word`() = runBlocking {
        val shards = mapOf("qu" to mapOf("quality" to listOf(0, 2), "qualityless" to listOf(1)), "me" to mapOf("mercy" to listOf(2, 1), "mercyful" to listOf(1), "merry" to listOf(0)))
        val got = FindCore.saidPlays("quality of mercy") { shards[it] ?: emptyMap() }
        assertTrue(got.exact == listOf(2) && got.all == listOf(1, 2))
        assertTrue(FindCore.saidPlays("the quality") { shards[it] ?: emptyMap() }.all.isEmpty())
        assertTrue(FindCore.saidPlays("of") { emptyMap() }.all.isEmpty())
    }

    @Test fun `line shards intersect at the line`() = runBlocking {
        val shards = mapOf("qu" to mapOf("quality" to listOf(0, 2, 3, 4, 2, 1, 1)), "me" to mapOf("mercy" to listOf(0, 1, 7, 2, 1, 4, 3, 1, 0)))
        assertEquals(listOf(0 to listOf(7), 2 to listOf(4), 5 to listOf(0)), FindCore.decodeLines(shards.getValue("me").getValue("mercy")))
        val got = FindCore.lineCandidates("quality of mercy") { shards[it] ?: emptyMap() }!!
        assertEquals(listOf(FindCore.Candidate(0, listOf(7))), got.cands)
        assertNull("no line shards: null, and the caller falls back", FindCore.lineCandidates("quality") { null })
        val pre = FindCore.lineCandidates("qual") { shards[it] ?: emptyMap() }!!
        assertTrue(pre.prefix.contains("qual") && pre.cands.size == 2)
        assertTrue(FindCore.termFile("quality") == "qu" && FindCore.termFile("élan") == "xe96c")
    }

    private fun script(vararg lines: ScriptLine) = fixtureScript().copy(lines = lines.toList())
    private fun say(id: String, role: String, text: String) = ScriptLine(id, ScriptLine.Kind.Speech, role = role, parts = listOf(LinePart.Say(text)))

    /** The two lines the web's first build showed for "quality of mercy" (Landor's Citation, The Two Noble Kinsmen), and Portia. */
    @Test fun `a line holds every word and the phrase leads`() {
        val row = rows[0]
        val q = "quality of mercy"
        val citation = script(say("L1", "SIR THOMAS", "on another of very different quality; that the plain sense"), say("L2", "SIR THOMAS", "Have mercy upon us."))
        val kinsmen = script(say("L1", "EMILIA", "alters to The quality of his thoughts, and mercy follows"))
        val merchant = script(say("L9", "PORTIA", "The quality of mercy is not strain’d, It droppeth as the gentle rain"))
        assertNull("the words in different lines are no hit", FindCore.lineHit(citation, row, q, null))
        val k = FindCore.lineHit(kinsmen, row, q, null)!!
        assertFalse(k.phrase)
        val m = FindCore.lineHit(merchant, row, q, null)!!
        assertTrue(m.phrase && m.line == "L9" && m.role == "Portia")
        assertEquals(listOf(m), FindCore.shownHits(listOf(k, m)))
        assertEquals(listOf(k), FindCore.shownHits(listOf(k)))
        assertTrue(FindCore.lineHit(script(say("L1", "A", "QUALITY -- of... Mercy!")), row, q, null)?.phrase == true)
        val candidate = script(say("L1", "A", "He is a candidate."))
        assertNull("a whole word, not a prefix", FindCore.lineHit(candidate, row, "candida", null))
        assertNotNull(FindCore.lineHit(candidate, row, "candida", null, setOf("candida")))
        assertNull("never a direction", FindCore.lineHit(script(ScriptLine("L1", ScriptLine.Kind.Direction, source = q)), row, q, null))
        assertNull("only the line places the shards name", FindCore.lineHit(script(say("L0", "A", q), say("L1", "A", "x")), row, q, listOf(1)))
        assertTrue(FindCore.snippet("word ".repeat(60) + "mercy " + "tail ".repeat(40), "mercy", 60).startsWith("…"))
        assertEquals("beside Geltrude and Candida", FindCore.snippet("beside _Geltrude_ and _Candida_", "candida"))
    }

    /** Negative control: with no phrase test every line is only "every word", and Portia would not lead. */
    @Test fun `the phrase test is what makes Portia lead`() {
        val kinsmen = FindCore.LineHit(rows[0], "L1", "Emilia", "alters to The quality of his thoughts, and mercy follows", false)
        val merchant = FindCore.LineHit(rows[0], "L9", "Portia", "The quality of mercy is not strain’d", true)
        assertEquals(listOf(merchant), FindCore.shownHits(listOf(kinsmen, merchant)))
        assertEquals("without the phrase flag both show", 2, FindCore.shownHits(listOf(kinsmen, merchant.copy(phrase = false))).size)
    }

    @Test fun `the budget and the reading order`() {
        fun r(id: String, title: String, words: Int) = PlayRow(id = id, title = title, words = words)
        val rs = listOf(r("x", "Mercy Me", 20000), r("y", "Y", 300000), r("z", "Z", 10000))
        val o = FindCore.orderCandidates(listOf(FindCore.Candidate(1, listOf(1, 2, 3)), FindCore.Candidate(2, listOf(1)), FindCore.Candidate(0, listOf(5))), rs, "mercy")
        assertEquals(listOf("x", "y", "z"), o.map { it.row.id })
        assertEquals(1, FindCore.nextBatch(o, 0, 200000))
        assertEquals("one script over the budget is still read alone", 2, FindCore.nextBatch(o, 1, 200000))
    }

    /** An old library: rows and an index with none of the new fields decode, and the facets fall back to voices and length. */
    @Test fun `a library built before B31 still reads`() {
        val old = PlayIndex.decode("""{"format":1,"plays":[{"id":"o","title":"Old","voices":3,"minutes":20,"cast":[5,4,1]}]}""")
        assertTrue(old.facets == null && old.plays.first().form == null && old.plays.first().scenes.isEmpty())
        val fs0 = FindCore.facets(null)
        assertEquals(listOf("voices", "length"), fs0.map { it.key })
        assertEquals(rows.size, FindCore.counts(rows, fs0, emptyMap()).first { it.key == "voices" }.values.sumOf { it.count })
        // A malformed scene is dropped, the rest kept; a picture of the play leads the window, a title page only the page.
        assertEquals(listOf("L0010", "L0090"), rows[2].scenes.map { it.line })
        assertTrue(rows[5].windowPicture?.url?.endsWith("w.jpg") == true && rows[0].windowPicture == null)
        val titleOnly = PlayIndex.decode("""{"plays":[{"id":"t","title":"T","picture":{"url":"https://e.org/t.jpg","kind":"titlePage"},"titlePage":{"url":"https://e.org/t.jpg"}}]}""").plays.first()
        assertTrue("a title page never leads a window", titleOnly.windowPicture == null && titleOnly.pageLead?.url?.endsWith("t.jpg") == true)
        val junk = PlayIndex.decode("""{"plays":[{"id":"j","title":"J","form":7,"life":"x","picture":3,"scenes":"x","subjects":5}],"facets":"x"}""")
        assertTrue("a field the client does not understand never loses the row", junk.plays.size == 1 && junk.facets == null)
    }

    @Test fun `the collections file reads whole or in part`() {
        val c = PlayCollections.decode("""{"format":1,"editor":[],"data":[{"id":"two-voices","title":"Two","count":2,"plays":["a","c"]},{"nope":1},{"id":"x","title":"X","plays":7}]}""")
        assertEquals(listOf("two-voices", "x"), c.data.map { it.id })
        assertTrue(c.editor.isEmpty() && c.data[1].plays.isEmpty())
        assertTrue(PlayCharacters.decode("""{"names":{"BOB":[[2,9]]}}""").names["BOB"] == listOf(listOf(2, 9)))
    }

    @Test fun `the kicker and the label item say only what the record says`() {
        assertEquals("Stage play · Comedy · One act", FindCore.kicker("stage", "comedy", true))
        assertEquals("Stage play", FindCore.kicker("stage", null, false))
        assertEquals("Radio play", FindCore.kicker("radio", "nope", false))
        val item = rows[0].labelItem
        assertTrue(item.hue == "comedy" && item.era == "1900-1930" && item.author == "Ann Writer" && item.cast == listOf(10, 8))
    }
}
