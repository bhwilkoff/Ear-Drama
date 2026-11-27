package com.example.appname.plays

import com.example.appname.data.Transcript
import java.text.Normalizer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.KSerializer

// Finding a play (B31 §3; ANDROID-DESIGN §4.9a, §4.5; the web's js/find-core.js and Apple's FindCore.swift, the same rules in
// the same words): the facets, the ways in and the search over the play library's index, as pure functions with no views.
// Every value and bound comes from the catalog (contract §4.1 "Finding a play": the rows' `form`, `era`, `balance`,
// `subjects`, `locc`, `oneAct`, `scenes`; the index's `facets`; `collections.json`; `characters.json`; `search/lines/` and
// `search/said/`); this file only counts and filters what the catalog computed. Nothing ranks by attention.

/** One collection of `collections.json` (contract §4.1): the editor's carry a credit and a note, the data's a rule and a kind. */
@Serializable
data class PlayCollection(
    val id: String,
    val title: String,
    @Serializable(with = LenientString::class) val by: String? = null,
    @Serializable(with = LenientString::class) val note: String? = null,
    @Serializable(with = LenientString::class) val rule: String? = null,
    @Serializable(with = LenientString::class) val kind: String? = null,
    @Serializable(with = LenientInt::class) val count: Int? = null,
    @Serializable(with = LenientStrings::class) val plays: List<String> = emptyList(),
)

/** An element-by-element list: a malformed collection is dropped and the rest kept. */
object LenientCollections : KSerializer<List<PlayCollection>> {
    private val inner = ListSerializer(PlayCollection.serializer())
    override val descriptor: SerialDescriptor get() = inner.descriptor
    override fun serialize(encoder: Encoder, value: List<PlayCollection>) = inner.serialize(encoder, value)
    override fun deserialize(decoder: Decoder): List<PlayCollection> {
        val json = decoder as? JsonDecoder ?: return inner.deserialize(decoder)
        val element = json.decodeJsonElement() as? JsonArray ?: return emptyList()
        return element.mapNotNull { e -> try { json.json.decodeFromJsonElement(PlayCollection.serializer(), e) } catch (x: Exception) { null } }
    }
}

/** The library's collections (contract §4.1 `collections.json`): the editor's, then the data's. */
@Serializable
data class PlayCollections(
    @Serializable(with = LenientCollections::class) val editor: List<PlayCollection> = emptyList(),
    @Serializable(with = LenientCollections::class) val data: List<PlayCollection> = emptyList(),
) {
    companion object {
        fun decode(text: String): PlayCollections = PlayIndex.json.decodeFromString(serializer(), text)
    }
}

/** `characters.json`: every speaking part's printed name, each with `[play number, lines]` pairs, a play number being the play's place in the index the file was built with. */
@Serializable
data class PlayCharacters(val names: Map<String, List<List<Int>>> = emptyMap()) {
    companion object {
        fun decode(text: String): PlayCharacters = PlayIndex.json.decodeFromString(serializer(), text)
    }
}

object FindCore {
    data class Option(val value: String, val label: String, val count: Int = 0)

    class Facet(
        val key: String,
        val label: String,
        /** True for the ones that live in Filters, not the chips. */
        val filter: Boolean = false,
        val values: List<Option>,
        val of: (PlayRow) -> List<String>,
    ) {
        fun withValues(v: List<Option>) = Facet(key, label, filter, v, of)
    }

    /** What a person chose: the facets' values by key, the sort, a collection or a scene count to show whole. */
    data class State(
        val picks: Map<String, String> = emptyMap(),
        val sort: String = "voices",
        val collection: String? = null,
        val scenes: Int = 0,
    ) {
        val isActive: Boolean get() = picks.isNotEmpty()
        val cleared: State get() = State(sort = sort)
        fun with(key: String, value: String?): State = copy(picks = if (value == null) picks - key else picks + (key to value))
    }

    // The bins the catalog publishes (index.facets.voices / .minutes); these stand in only for a library built before B31 C3 or
    // the bundled scripts, and are the same numbers (B31 §3.1).
    val VOICE_BINS = listOf(PlayFacetsIndex.Bin(1, 2), PlayFacetsIndex.Bin(3, 4), PlayFacetsIndex.Bin(5, 6), PlayFacetsIndex.Bin(7, 10), PlayFacetsIndex.Bin(11, null))
    val MINUTE_BINS = listOf(PlayFacetsIndex.Bin(1, 10), PlayFacetsIndex.Bin(11, 20), PlayFacetsIndex.Bin(21, 40), PlayFacetsIndex.Bin(41, 90), PlayFacetsIndex.Bin(91, null))

    val FORM_LABEL = mapOf(
        "comedy" to "Comedy", "farce" to "Farce", "tragedy" to "Tragedy", "tragicomedy" to "Tragicomedy", "history" to "History",
        "fantasy" to "Fairy and fantasy", "religious" to "Religious", "melodrama" to "Melodrama", "libretto" to "Libretto",
    )
    val BALANCE_LABEL = mapOf("ensemble" to "Ensemble", "mixed" to "Mixed", "lead" to "A star part")

    // The Library of Congress's own class names for its P subclasses (the record's LoCC), shortened to the language.
    val LOCC_LABEL = mapOf(
        "PA" to "Greek and Latin", "PB" to "Celtic", "PC" to "Romance", "PD" to "Germanic", "PE" to "English language", "PF" to "Dutch and Frisian",
        "PG" to "Slavic", "PH" to "Finnish and Hungarian", "PJ" to "Middle Eastern", "PK" to "Indian and Iranian", "PL" to "East Asian",
        "PM" to "Indigenous American", "PN" to "General", "PQ" to "French, Italian, Spanish", "PR" to "English", "PS" to "American",
        "PT" to "German, Dutch, Scandinavian", "PZ" to "Children’s",
    )
    val SORTS = listOf("voices" to "Fewest voices", "short" to "Shortest", "name" to "A to Z")
    fun sortTitle(key: String): String = SORTS.firstOrNull { it.first == key }?.second ?: SORTS[0].second

    /** The data collections that lead, in this order, after the editor's (§3.1); the rest stay reachable by their id. */
    val RAIL_IDS = listOf("ten-minutes", "two-voices", "star-part", "one-act")

    private fun binKey(b: PlayFacetsIndex.Bin) = b.max?.let { "${b.min}-$it" } ?: "${b.min}+"
    private fun inBin(b: PlayFacetsIndex.Bin, n: Int) = n >= b.min && (b.max?.let { n <= it } ?: true)

    /** The facets this library offers, in the web's order: Voices, Length, then the ones the index carries. */
    fun facets(index: PlayFacetsIndex?): List<Facet> {
        val f = index ?: PlayFacetsIndex()
        val vb = f.voices?.takeIf { it.isNotEmpty() } ?: VOICE_BINS
        val mb = f.minutes?.takeIf { it.isNotEmpty() } ?: MINUTE_BINS
        fun vLabel(b: PlayFacetsIndex.Bin) = b.max?.let { if (it == b.min) "${b.min}" else "${b.min}-$it" } ?: "${b.min}+"
        fun mLabel(b: PlayFacetsIndex.Bin, i: Int): String {
            val max = b.max ?: return "Longer"
            return if (i == 0) "Up to $max min" else "${b.min - 1}-$max min"
        }
        val out = mutableListOf(
            Facet("voices", "Voices", values = vb.map { Option(binKey(it), vLabel(it)) }, of = { r -> vb.filter { inBin(it, r.voices) }.map(::binKey) }),
            Facet("length", "Length", values = mb.mapIndexed { i, b -> Option(binKey(b), mLabel(b, i)) }, of = { r -> mb.filter { inBin(it, r.minutes) }.map(::binKey) }),
        )
        f.balance?.let { balance ->
            out += Facet("balance", "How the lines are shared", filter = true,
                values = balance.mapNotNull { v -> v.value?.let { k -> BALANCE_LABEL[k]?.let { Option(k, it) } } },
                of = { r -> r.balance?.takeIf { it in BALANCE_LABEL }?.let { listOf(it) } ?: emptyList() })
        }
        f.form?.let { form ->
            val named = form.mapNotNull { it.value }.toSet()
            out += Facet("form", "Form",
                values = form.mapNotNull { v -> v.value?.let { k -> FORM_LABEL[k]?.let { Option(k, it) } } } + Option("none", "Not named"),
                // A form on fewer plays than the catalog's foldUnder is counted with Not named, as the index counts it.
                of = { r -> listOf(r.form?.takeIf { it in named } ?: "none") })
        }
        f.era?.let { era ->
            val named = era.mapNotNull { it.value }.toSet()
            out += Facet("era", "Era", values = era.mapNotNull { v -> v.value?.let { Option(it, it) } } + Option("none", "Undated"),
                of = { r -> listOf(r.era?.takeIf { it in named } ?: "none") })
        }
        f.subjects?.takeIf { it.isNotEmpty() }?.let { subjects ->
            out += Facet("subject", "Subject", filter = true, values = subjects.mapNotNull { v -> v.value?.let { Option(it, it) } }, of = { it.subjects })
        }
        f.locc?.takeIf { it.isNotEmpty() }?.let { locc ->
            out += Facet("locc", "Literature of the original", filter = true,
                values = locc.mapNotNull { v -> v.value?.let { k -> LOCC_LABEL[k.take(2)]?.let { Option(k, it) } } },
                of = { r -> r.locc?.let { listOf(it) } ?: emptyList() })
        }
        if ((f.oneAct ?: 0) > 0) {
            out += Facet("oneact", "One act", filter = true, values = listOf(Option("1", "One act")), of = { if (it.oneAct) listOf("1") else emptyList() })
        }
        return out
    }

    /** The picks this library offers: a value its facets do not hold (an older choice, another library's band) is dropped, as the web drops an old link's. */
    fun offered(picks: Map<String, String>, facets: List<Facet>): Map<String, String> =
        picks.filter { (key, value) -> facets.firstOrNull { it.key == key }?.values?.any { it.value == value } ?: false }

    /** The rows that pass every pick but [skip]'s. */
    fun filter(rows: List<PlayRow>, facets: List<Facet>, picks: Map<String, String>, skip: String? = null): List<PlayRow> {
        val fs = facets.filter { it.key != skip && picks[it.key] != null }
        if (fs.isEmpty()) return rows
        return rows.filter { r -> fs.all { f -> picks.getValue(f.key) in f.of(r) } }
    }

    /** Each facet's values with their counts against the other picks (WEB-DESIGN §10.5: no choice yields nothing); a value with no plays is left out unless it is the one chosen. */
    fun counts(rows: List<PlayRow>, facets: List<Facet>, picks: Map<String, String>): List<Facet> = facets.map { f ->
        val c = HashMap<String, Int>()
        for (r in filter(rows, facets, picks, skip = f.key)) for (v in f.of(r)) c[v] = (c[v] ?: 0) + 1
        f.withValues(f.values.map { it.copy(count = c[it.value] ?: 0) }.filter { it.count > 0 || picks[f.key] == it.value })
    }

    private fun nameKey(r: PlayRow) = r.sortName ?: r.title
    private val byNameOrder = Comparator<PlayRow> { a, b -> collate(nameKey(a), nameKey(b)) }
    private fun collate(a: String, b: String): Int {
        fun fold(s: String) = Normalizer.normalize(s, Normalizer.Form.NFD).replace(Regex("\\p{M}"), "").lowercase()
        return fold(a).compareTo(fold(b))
    }

    fun byName(a: PlayRow, b: PlayRow): Int = byNameOrder.compare(a, b)

    fun sorted(rows: List<PlayRow>, sort: String): List<PlayRow> = when (sort) {
        "short" -> rows.sortedWith(compareBy<PlayRow> { it.minutes }.then(byNameOrder))
        "name" -> rows.sortedWith(byNameOrder)
        else -> rows.sortedWith(compareBy<PlayRow> { it.voices }.thenBy { it.minutes }.then(byNameOrder))
    }

    // ---- The ways in (B31 §3.1, §3.2) ----

    data class SceneHit(val row: PlayRow, val scene: PlayRow.Scene) {
        val id: String get() = "${row.id}|${scene.line}"
    }

    enum class RailKind { Editor, Scenes, Data }

    data class Rail(
        val kind: RailKind,
        val id: String,
        val title: String,
        val count: Int,
        val by: String? = null,
        val note: String? = null,
        val plays: List<PlayRow> = emptyList(),
        val scenes: List<SceneHit> = emptyList(),
        val voices: Int = 0,
    )

    /**
     * The rails: the editor's collections, then Scenes for two voices, then the data rails [ids] names. A play appears once on the
     * screen: a rail drops a play a rail above it holds (Decision 081 rule 5), and a rail left with nothing is absent. [per] is how
     * many a rail shows. The TV, which has no scenes, passes `withScenes = false` and [tvIds].
     */
    fun rails(rows: List<PlayRow>, collections: PlayCollections?, per: Int = 12, withScenes: Boolean = true, ids: List<String> = RAIL_IDS): List<Rail> {
        val byId = HashMap<String, PlayRow>().apply { rows.forEach { putIfAbsent(it.id, it) } }
        val seen = HashSet<String>()
        val out = mutableListOf<Rail>()
        fun take(list: List<String>): List<PlayRow> {
            val got = mutableListOf<PlayRow>()
            for (id in list) {
                if (got.size >= per) break
                val r = byId[id]
                if (r != null && seen.add(id)) got += r
            }
            return got
        }
        val c = collections ?: PlayCollections()
        for (e in c.editor) {
            val plays = take(e.plays)
            if (plays.isNotEmpty()) out += Rail(RailKind.Editor, e.id, e.title, e.plays.count { it in byId }, by = e.by, note = e.note, plays = plays)
        }
        val all = if (withScenes) sceneRows(rows, 2) else emptyList()
        val shown = mutableListOf<SceneHit>()
        for (s in all) {
            if (shown.size >= per) break
            if (s.row.id !in seen) { shown += s; seen += s.row.id }
        }
        if (shown.isNotEmpty()) out += Rail(RailKind.Scenes, "scenes-2", "Scenes for two voices", all.map { it.row.id }.toSet().size, scenes = shown, voices = 2)
        val data = HashMap<String, PlayCollection>().apply { c.data.forEach { putIfAbsent(it.id, it) } }
        for (id in ids) {
            val d = data[id] ?: continue
            val plays = take(d.plays)
            if (plays.isNotEmpty()) out += Rail(RailKind.Data, d.id, d.title, d.count ?: d.plays.size, plays = plays)
        }
        return out
    }

    /** The TV's data shelves: [RAIL_IDS] first, then every other data collection but an author's, in the file's order. */
    fun tvIds(collections: PlayCollections?): List<String> =
        RAIL_IDS + collections?.data.orEmpty().filter { it.kind != "author" && it.id !in RAIL_IDS }.map { it.id }

    /** One collection by id, editor's or data's, its plays in the collection's own order. */
    fun collection(rows: List<PlayRow>, collections: PlayCollections?, id: String): Pair<PlayCollection, List<PlayRow>>? {
        val c = collections ?: PlayCollections()
        val found = (c.editor + c.data).firstOrNull { it.id == id } ?: return null
        val byId = HashMap<String, PlayRow>().apply { rows.forEach { putIfAbsent(it.id, it) } }
        return found to found.plays.mapNotNull { byId[it] }
    }

    /** Every scene for [voices] voices, a play's first one per play (text order), plays A to Z. */
    fun sceneRows(rows: List<PlayRow>, voices: Int): List<SceneHit> =
        rows.mapNotNull { r -> r.scenes.firstOrNull { it.voices == voices && it.line.isNotEmpty() }?.let { SceneHit(r, it) } }
            .sortedWith { a, b -> byName(a.row, b.row) }

    /** Same voices and length (B31 §3.5): within one voice and 15 minutes of the play, closest first, the play left out. */
    fun sameShape(rows: List<PlayRow>, play: PlayRow, n: Int = 12): List<PlayRow> {
        fun d(r: PlayRow) = Math.abs(r.voices - play.voices).toDouble() + Math.abs(r.minutes - play.minutes) / 15.0
        return rows.filter { it.id != play.id && Math.abs(it.voices - play.voices) <= 1 && Math.abs(it.minutes - play.minutes) <= 15 }
            .sortedWith(compareBy<PlayRow> { d(it) }.then(byNameOrder)).take(n)
    }

    data class ByAuthor(val plays: List<PlayRow>, val id: String?, val total: Int)

    /** More by the author: the author's collection when the catalog published one, else the rows that name them first. */
    fun byAuthor(rows: List<PlayRow>, collections: PlayCollections?, play: PlayRow, n: Int = 12): ByAuthor {
        val name = play.firstAuthor
        if (name.isEmpty()) return ByAuthor(emptyList(), null, 0)
        val c = collections?.data.orEmpty().firstOrNull { it.kind == "author" && it.title.endsWith(name) }
        val list = c?.let { collection(rows, collections, it.id)?.second } ?: rows.filter { it.firstAuthor == name }.sortedWith(byNameOrder)
        val others = list.filter { it.id != play.id }
        return ByAuthor(others.take(n), c?.id, others.size)
    }

    // ---- Search (B31 §3.3): titles and authors, characters, spoken lines ----

    fun tokens(text: String): List<String> = Transcript.tokens(text)

    private fun prefixed(words: List<String>, text: String): Boolean {
        val have = tokens(text)
        return words.all { w -> have.any { it.startsWith(w) } }
    }

    /** Plays whose title or author has every query word as a word prefix, A to Z. */
    fun titleHits(rows: List<PlayRow>, q: String): List<PlayRow> {
        val words = tokens(q)
        if (words.isEmpty()) return emptyList()
        return rows.filter { prefixed(words, "${it.title} ${it.authors.joinToString(" ")}") }.sortedWith(byNameOrder)
    }

    data class CharacterHit(val row: PlayRow, val role: String, val lines: Int) {
        val id: String get() = "${row.id}|$role"
    }

    /** Characters: a role whose printed name has every query word as a word prefix, most lines first. [rows] is the index the file was built with (play numbers are places in it). */
    fun characterHits(rows: List<PlayRow>, names: Map<String, List<List<Int>>>?, q: String, n: Int = 20): List<CharacterHit> {
        val words = tokens(q)
        if (words.isEmpty() || names == null) return emptyList()
        val out = mutableListOf<CharacterHit>()
        for ((name, plays) in names) {
            if (!prefixed(words, name)) continue
            for (pair in plays) if (pair.size >= 2 && pair[0] >= 0 && pair[0] < rows.size) out += CharacterHit(rows[pair[0]], name, pair[1])
        }
        return out.sortedWith(Comparator<CharacterHit> { a, b ->
            if (a.lines != b.lines) return@Comparator b.lines - a.lines
            val c = byName(a.row, b.row)
            if (c != 0) c else a.role.compareTo(b.role)
        }).take(n)
    }

    /** The words a line search reads: three letters or more, as the shards file them, each once. */
    fun saidWords(q: String): List<String> = tokens(q).filter { it.length >= 3 }.distinct()

    /** The shard a word is filed in (contract §4.1, the web projection's `term_file`): its first two letters, or "x" and their code points in hex when either is not a-z or 0-9. */
    fun termFile(word: String): String {
        val cps = word.codePoints().toArray().take(2)
        val p = String(cps.toIntArray(), 0, cps.size)
        if (cps.size == 2 && cps.all { it in 'a'.code..'z'.code || it in '0'.code..'9'.code }) return p
        return "x" + cps.joinToString("") { Integer.toHexString(it) }
    }

    /** Reads one shard by its file name: null when the library has no such directory (an older library), empty when the shard holds no word. */
    fun interface ShardRead {
        suspend fun get(file: String): Map<String, List<Int>>?
    }

    data class Said(val all: List<Int>, val exact: List<Int>)

    /** Play numbers whose spoken words hold every query word (search/said, delta-coded); `exact` where every word is whole. */
    suspend fun saidPlays(q: String, get: ShardRead): Said {
        val words = saidWords(q)
        if (words.isEmpty()) return Said(emptyList(), emptyList())
        var all: Set<Int>? = null
        var exact: Set<Int>? = null
        for (w in words) {
            val terms = get.get(termFile(w)).orEmpty()
            val pre = HashSet<Int>()
            val ex = HashSet<Int>()
            for ((t, deltas) in terms) {
                if (!t.startsWith(w)) continue
                var n = 0
                for (d in deltas) { n += d; pre += n; if (t == w) ex += n }
            }
            all = all?.intersect(pre) ?: pre
            exact = exact?.intersect(ex) ?: ex
            if (all.isEmpty()) return Said(emptyList(), emptyList())
        }
        return Said(all.orEmpty().sorted(), exact.orEmpty().sorted())
    }

    /** A word's line postings (search/lines) as play number to its line places, in play order. */
    fun decodeLines(flat: List<Int>): List<Pair<Int, List<Int>>> {
        val out = mutableListOf<Pair<Int, List<Int>>>()
        var i = 0
        var play = 0
        while (i + 1 < flat.size) {
            play += flat[i]
            val n = flat[i + 1]
            val lines = mutableListOf<Int>()
            var line = 0
            for (k in 0 until n) if (i + 2 + k < flat.size) { line += flat[i + 2 + k]; lines += line }
            out += play to lines
            i += 2 + n
        }
        return out
    }

    /** [lines] are the places to check; null checks every speech (the search/said fallback). */
    data class Candidate(val play: Int, val lines: List<Int>?)

    data class LineCandidates(val cands: List<Candidate>, val prefix: Set<String>)

    /**
     * The plays with one speech line holding every query word, from the line shards, the rarest word intersected first. A word the
     * shards hold whole is matched whole, else as a prefix (`prefix` names those). Null when the library has no line shards.
     */
    suspend fun lineCandidates(q: String, get: ShardRead): LineCandidates? {
        val words = saidWords(q)
        if (words.isEmpty()) return LineCandidates(emptyList(), emptySet())
        class Postings(val m: Map<Int, Set<Int>>, val size: Int)
        val sets = mutableListOf<Postings>()
        val prefix = HashSet<String>()
        for (w in words) {
            val terms = get.get(termFile(w)) ?: return null
            val whole = terms[w] != null
            if (!whole) prefix += w
            val keys = if (whole) listOf(w) else terms.keys.filter { it.startsWith(w) }
            val m = HashMap<Int, MutableSet<Int>>()
            var size = 0
            for (k in keys) for ((play, lines) in decodeLines(terms[k].orEmpty())) { m.getOrPut(play) { HashSet() }.addAll(lines); size += lines.size }
            sets += Postings(m, size)
        }
        sets.sortBy { it.size }
        var cur: Map<Int, Set<Int>> = sets[0].m
        for (s in sets.drop(1)) {
            val next = HashMap<Int, Set<Int>>()
            for ((play, lines) in cur) {
                val other = s.m[play] ?: continue
                val both = lines.intersect(other)
                if (both.isNotEmpty()) next[play] = both
            }
            cur = next
            if (cur.isEmpty()) break
        }
        return LineCandidates(cur.map { (play, lines) -> Candidate(play, lines.sorted()) }.sortedBy { it.play }, prefix)
    }

    /** About how many bytes a script costs over the wire, from its spoken words (measured 2026-11-26: 3.3 gzipped bytes a word on average over a tenth of the library). */
    fun scriptBytes(row: PlayRow): Int = Math.round(3.3 * (if (row.words > 0) row.words else 3000) + 2000).toInt()

    data class Ordered(val row: PlayRow, val lines: List<Int>?, val named: Boolean, val play: Int)

    /** The order scripts are read in: a play whose title or author holds the words first, then the plays with the most lines holding them, then the index's order. */
    fun orderCandidates(cands: List<Candidate>, rows: List<PlayRow>, q: String): List<Ordered> {
        val words = tokens(q)
        return cands.filter { it.play >= 0 && it.play < rows.size }.map { c ->
            val r = rows[c.play]
            Ordered(r, c.lines, prefixed(words, "${r.title} ${r.authors.joinToString(" ")}"), c.play)
        }.sortedWith(Comparator { a, b ->
            if (a.named != b.named) return@Comparator if (a.named) -1 else 1
            val la = a.lines?.size ?: 0
            val lb = b.lines?.size ?: 0
            if (la != lb) lb - la else a.play - b.play
        })
    }

    /** The end of the next batch to read within [budget] bytes (at least one script). */
    fun nextBatch(ordered: List<Ordered>, from: Int, budget: Int): Int {
        var i = from
        var used = 0
        while (i < ordered.size && (i == from || used + scriptBytes(ordered[i].row) <= budget)) {
            used += scriptBytes(ordered[i].row)
            i += 1
        }
        return i
    }

    data class LineHit(val row: PlayRow, val line: String, val role: String, val text: String, val phrase: Boolean) {
        val id: String get() = "${row.id}|$line"
    }

    /**
     * A play's best line for a query: one holding the exact phrase (every word in order, case and punctuation aside), else one
     * holding every word. [places] limits the check to those line places (from the line shards); null checks every speech. A word
     * in [prefix] matches as a word prefix.
     */
    fun lineHit(script: PlayScript, row: PlayRow, q: String, places: List<Int>?, prefix: Set<String> = emptySet()): LineHit? {
        val words = tokens(q)
        if (words.isEmpty()) return null
        fun matches(w: String, h: String) = h == w || (w in prefix && h.startsWith(w))
        val at = places?.mapNotNull { script.lines.getOrNull(it) } ?: script.lines
        var any: LineHit? = null
        for (l in at) {
            if (l.kind != ScriptLine.Kind.Speech) continue
            val text = l.spokenText
            if (text.isEmpty()) continue
            val have = tokens(text)
            if (!words.all { w -> have.any { matches(w, it) } }) continue
            val role = titleCase(l.role.orEmpty())
            if (have.size >= words.size) {
                for (i in 0..(have.size - words.size)) if (words.withIndex().all { (k, w) -> matches(w, have[i + k]) }) {
                    return LineHit(row, l.id, role, text, true)
                }
            }
            if (any == null) any = LineHit(row, l.id, role, text, false)
        }
        return any
    }

    /** What the Lines section shows: only the exact-phrase hits when there is one, else every hit. */
    fun shownHits(hits: List<LineHit>): List<LineHit> = if (hits.any { it.phrase }) hits.filter { it.phrase } else hits

    /** The matched line cut near [max] characters around the words, with "…" where it was cut, emphasis marks dropped. */
    fun snippet(text: String, q: String, max: Int = 120): String {
        val t = text.replace("_", "").split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ")
        if (t.length <= max) return t
        val w = tokens(q).maxByOrNull { it.length } ?: ""
        var at = 0
        if (w.isNotEmpty()) {
            val folded = Normalizer.normalize(t, Normalizer.Form.NFD).replace(Regex("\\p{M}"), "").lowercase()
            if (folded.length == t.length) {
                var i = folded.indexOf(w)
                while (i >= 0) {
                    if (i == 0 || !folded[i - 1].isLetterOrDigit()) { at = i; break }
                    i = folded.indexOf(w, i + 1)
                }
            }
        }
        var from = Math.max(0, at - max / 4)
        if (from > 0) { val sp = t.indexOf(' ', from); if (sp in 0 until at) from = sp + 1 }
        var to = Math.min(t.length, from + max)
        if (to < t.length) { val sp = t.lastIndexOf(' ', to); if (sp > from + max / 2) to = sp }
        return (if (from > 0) "…" else "") + t.substring(from, to) + (if (to < t.length) "…" else "")
    }

    /** A role's printed name in capitals read as a name: "LADY BRACKNELL" is "Lady Bracknell". */
    fun titleCase(name: String): String {
        if (name != name.uppercase()) return name
        val out = StringBuilder()
        var up = true
        for (ch in name.lowercase()) {
            out.append(if (up && ch.isLetter()) ch.uppercaseChar() else ch)
            up = ch.isWhitespace() || ch in "-'’("
        }
        return out.toString()
    }

    /** "Jack and Jill", "A, B and C". */
    fun names(parts: List<String>): String {
        val p = parts.map(::titleCase)
        return if (p.size > 1) p.dropLast(1).joinToString(", ") + " and " + p.last() else p.joinToString("")
    }

    /** A play's kicker (B31 §3.5): its kind, then its form and One act, each only when the record says it. */
    fun kicker(kind: String, form: String?, oneAct: Boolean): String =
        listOfNotNull(if (kind == "radio") "Radio play" else "Stage play", form?.let { FORM_LABEL[it] }, if (oneAct) "One act" else null).joinToString(" · ")
}
