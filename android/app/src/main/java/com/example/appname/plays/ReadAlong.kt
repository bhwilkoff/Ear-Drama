package com.example.appname.plays

/**
 * The read-along's follow logic (PLAYS-DESIGN §2.11), shared by the phone reader and the TV panel. The line
 * heard comes from the listen plan; a rendered mix finds its line by its timeline.
 */
object ReadAlong {
    /** The line the plan's entry [index] speaks; null past either end. */
    fun line(plan: List<Relay.ListenEntry>, index: Int): String? = plan.getOrNull(index)?.lineID

    data class Span(val lineID: String, val start: Int, val frames: Int)

    /** The line a mix is speaking at [seconds]: the last span begun, null once the last has ended; a gap keeps the line before it. */
    fun line(spans: List<Span>, rate: Double, seconds: Double): String? {
        val frame = seconds * rate
        val at = spans.lastOrNull { it.start <= frame } ?: return null
        if (at == spans.last() && frame >= at.start + at.frames) return null
        return at.lineID
    }

    /**
     * Whether the reader turns itself to the line heard. A touch ([away]) stops it and offers Back to the line
     * while something plays; [back] returns the line now heard and follows again.
     */
    class Follow {
        data class Step(val turn: Boolean, val back: Boolean)

        var following = true
            private set
        private var now: String? = null

        fun line(id: String?): Step {
            now = id
            return Step(turn = following && id != null, back = !following && id != null)
        }

        fun away() { following = false }

        fun back(): String? {
            following = true
            return now
        }
    }

    /** The TV panel's three lines: before, the one heard, after (null at an end). */
    fun panel(lines: List<ScriptLine>, id: String): Triple<ScriptLine?, ScriptLine?, ScriptLine?> {
        val i = lines.indexOfFirst { it.id == id }
        if (i < 0) return Triple(null, null, null)
        return Triple(lines.getOrNull(i - 1), lines[i], lines.getOrNull(i + 1))
    }
}
