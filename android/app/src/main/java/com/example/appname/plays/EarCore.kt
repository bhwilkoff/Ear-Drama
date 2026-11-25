package com.example.appname.plays

// Casting an episode by ear (PLAYS-DESIGN §13 item 10, ANDROID-DESIGN §4.23; Decision 088.3), the port of js/ear-core.js over
// OwnScript: which line is lit, what has been heard, what a tap does, what a key means. No Android import, no audio, no storage.
//
// NOTHING HERE PROPOSES A SPEAKER. A line is somebody's only by a tap, or by coming after one while the episode played
// (OwnScript.castOf). It is told where the audio is, and never hears it.

object EarCore {
    /** A first listen starts slow (R4 §2.4 rule 2); Back goes this far. */
    const val SPEED = 0.75f
    const val BACK_MS = 5_000L

    /** The shortest a line plays for on Hear it: a cue's share can be a tenth of a second. */
    const val LEAST_MS = 700L

    /** What tells this transcript from another: its words and its times. */
    fun signature(cues: List<OwnCue>): String =
        PlayScript.fnv1a64(cues.joinToString("\n") { "${it.at?.first}-${it.at?.second} ${it.text}" }).toString(16)

    /** null when these cues can be cast, or why not. */
    fun refusalOf(doc: OwnDoc): String? = when {
        doc.lines.isEmpty() -> "no_lines"
        doc.lines.size > OwnScript.MAX_LINES -> "too_many_lines"
        else -> null
    }

    /** One part: its name and how many lines are theirs. */
    data class Part(val name: String, val lines: Int)

    /** The parts in the order they were named, which is their number and their hue: [names], then any the lines hold. */
    fun partsOf(doc: OwnDoc, names: List<String>): List<Part> {
        val cast = OwnScript.castOf(doc)
        val n = LinkedHashMap<String, Int>()
        names.forEach { n[it] = 0 }
        for (l in doc.lines) (cast[l.k] as? OwnWho.Role)?.let { n[it.name] = (n[it.name] ?: 0) + 1 }
        return n.map { Part(it.key, it.value) }
    }

    /** A line as it is drawn; [named] says the speaker (or Left out) is not the line above's, so it is printed. */
    data class Row(val k: Int, val text: String, val kind: String, val who: OwnWho?, val named: Boolean)

    fun rows(doc: OwnDoc): List<Row> {
        val cast = OwnScript.castOf(doc)
        var before: OwnWho? = null
        return doc.lines.map { l ->
            val who = if (l.kind == "open" || l.kind == "speech") cast[l.k] else null
            Row(l.k, l.text, l.kind, who, who != null && who != before).also { before = who }
        }
    }

    /** How long a line is played for on its own, in milliseconds. */
    fun spanOf(at: Pair<Long, Long>): Pair<Long, Long> = at.first to maxOf(at.second, at.first + LEAST_MS)

    sealed interface Key {
        data class Part(val n: Int) : Key
        data object Toggle : Key
        data object Back : Key
        data object Undo : Key
    }

    /** What a key does here, or null. Keys held with another are the system's, but Undo's own. [key] is the web's name for it. */
    fun keyOf(key: String, ctrl: Boolean = false, meta: Boolean = false, alt: Boolean = false, shift: Boolean = false): Key? {
        if ((meta || ctrl) && !shift && !alt && key.lowercase(java.util.Locale.ROOT) == "z") return Key.Undo
        if (meta || ctrl || alt || shift) return null
        return when {
            key.length == 1 && key[0] in '1'..'9' -> Key.Part(key[0] - '1')
            key == " " -> Key.Toggle
            key == "ArrowLeft" -> Key.Back
            key == "u" || key == "U" -> Key.Undo
            else -> null
        }
    }

    /** Where casting is taken up again, in milliseconds: the place it was left, never past the last line. */
    fun placeOf(ear: OwnEar?, doc: OwnDoc): Long {
        val last = doc.lines.maxOfOrNull { it.at?.second ?: 0L } ?: 0L
        val p = ear?.place ?: 0L
        return if (p in 1 until last) p else 0L
    }

    /**
     * One sitting. [doc] is OwnScript's; every change makes a new one. [lit] is the line being said (0 before the first).
     * [tick] is told the audio's place as it plays; [jumped] that the place was moved by hand, so the lines between are not heard.
     */
    class Session(doc: OwnDoc, names: List<String> = emptyList(), var takes: Set<String> = emptySet()) {
        var doc: OwnDoc = doc
            private set
        private val named = names.toMutableList()
        val names: List<String> get() = named.toList()

        /** The order of the names before each rename, with the undo depth it left, for its Undo. */
        private val renames = ArrayList<Pair<Int, List<String>>>()
        var lit = 0
            private set

        /** The last line the audio reached without a jump. */
        private var from = 0
        private val played = HashMap<String, Int>()

        private fun env() = OwnEnv(takes)
        private fun take(r: OwnResult): String? {
            if (r.refusal == null) doc = r.doc
            return r.refusal
        }

        data class Tick(val moved: Boolean, val heard: Boolean)

        /** Where the audio is now. While [playing], the line and those since the last tick are heard. Answers what changed. */
        fun tick(ms: Long, playing: Boolean): Tick {
            val k = OwnScript.lineAt(doc, ms)
            val moved = k != lit
            lit = k
            if (!playing || k == 0) return Tick(moved, false)
            val next = OwnScript.hear(doc, k, from)
            from = k
            if (next === doc) return Tick(moved, false)
            // A carried part never reaches a line that was recorded as something else.
            if (takes.isNotEmpty()) {
                val was = OwnScript.castOf(doc)
                val now = OwnScript.castOf(next)
                if (doc.lines.any { it.id != null && it.id in takes && was[it.k] != now[it.k] }) {
                    from = 0
                    return Tick(moved, false)
                }
            }
            doc = next
            return Tick(moved, true)
        }

        fun jumped() { from = 0 }

        /** The lit line, and those after it as they are heard, are [name]'s. A refusal, or null. */
        fun give(name: String): String? = if (lit != 0) take(OwnScript.tap(doc, lit, OwnWho.Role(name), env())) else "no_such_line"

        fun leaveOut(): String? = if (lit != 0) take(OwnScript.tap(doc, lit, OwnWho.Out, env())) else "no_such_line"

        data class Added(val name: String, val refusal: String?)

        /** Names a voice. With a line lit it is theirs, as a tap is. */
        fun add(raw: String): Added {
            val name = OwnScript.partName(OwnScript.normalize(raw))
            OwnScript.partNameRefusal(name)?.let { return Added(name, it) }
            val known = parts().any { it.name == name }
            val refusal = if (lit != 0) give(name) else null
            if (refusal == null && !known) named.add(name)
            return Added(name, refusal)
        }

        fun undo(): String? {
            val why = take(OwnScript.apply(doc, OwnOp("undo")))
            while (why == null && renames.isNotEmpty() && renames.last().first > doc.undo.size) {
                val back = renames.removeAt(renames.lastIndex).second
                named.clear()
                named.addAll(back)
            }
            return why
        }

        data class Renamed(val name: String, val refusal: String?)

        /** A part's name on every line of theirs, and in its place in the order; a name another part has joins the two. One step. */
        fun rename(from: String, raw: String): Renamed {
            val name = OwnScript.partName(OwnScript.normalize(raw))
            val all = parts()
            val held = all.firstOrNull { it.name == from }
            val why = OwnScript.partNameRefusal(name) ?: if (held == null) "no_such_part" else null
            if (why != null) return Renamed(name, why)
            if (name == from) return Renamed(name, null)
            val before = names
            if (held!!.lines > 0) {
                val refusal = take(OwnScript.apply(doc, OwnOp("rename", part = from, rename = name), env()))
                if (refusal != null) return Renamed(name, refusal)
                renames += doc.undo.size to before
            }
            val order = all.map { it.name }
            named.clear()
            named.addAll(if (name in order) order.filter { it != from } else order.map { if (it == from) name else it })
            return Renamed(name, null)
        }

        /** One line alone, from its sheet: a part, Direction or Sound. The line after it keeps the cast it had. */
        fun assign(k: Int, to: OwnTarget): String? = take(OwnScript.apply(doc, OwnOp("assign", line = k, to = to), env()))

        fun leaveOutLine(k: Int): String? = take(OwnScript.leaveOutHeard(doc, k, env()))

        fun apply(op: OwnOp): String? = take(OwnScript.apply(doc, op, env()))

        /** The lines as Done makes them, or as they were when it could not be kept. */
        fun replace(with: OwnDoc) { doc = with }

        fun line(k: Int): OwnLine? = doc.lines.firstOrNull { it.k == k }
        fun parts(): List<Part> = partsOf(doc, named)
        fun who(k: Int): OwnWho? = OwnScript.castOf(doc)[k]
        fun count(): EarCount = OwnScript.castCount(doc).let { (n, of) -> EarCount(n, of) }
        val canUndo: Boolean get() = doc.undo.isNotEmpty()

        /** The next of a part's lines to play, after the one played last: how a person checks whether two voices are one. */
        fun sample(name: String): OwnLine? {
            val cast = OwnScript.castOf(doc)
            val mine = doc.lines.filter { it.at != null && (cast[it.k] as? OwnWho.Role)?.name == name }
            if (mine.isEmpty()) return null
            val i = mine.indexOfFirst { it.k == played[name] }
            return mine[(i + 1) % mine.size].also { played[name] = it.k }
        }
    }
}
