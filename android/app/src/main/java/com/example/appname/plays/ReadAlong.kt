package com.example.appname.plays

/**
 * The read-along's follow logic (PLAYS-DESIGN §2.11), shared by the phone reader and the TV panel. The line
 * heard comes from the listen plan; a rendered mix finds its line by its timeline.
 */
object ReadAlong {
    /** The line the plan's entry [index] speaks; null past either end. */
    fun line(plan: List<Relay.ListenEntry>, index: Int): String? = plan.getOrNull(index)?.lineID

    /** A line file of a published item: its `/download/` URL and its number. */
    data class DramaFile(val url: String, val seq: Int)

    /** A line file and the script line it speaks. */
    data class DramaLine(val url: String, val lineId: String, val seq: Int)

    /**
     * A finished drama's line timeline (PLAYS-DESIGN §2.11 rule 6): the item holds one file per line, `0042-PART.wav`,
     * its number the line's 1-based place in the script, so the file playing names the line heard. Null when the
     * numbering cannot be vouched for: no [revision] from the Worker, a script of another revision, a number the
     * script does not have, or no files.
     */
    fun dramaPlan(files: List<DramaFile>, script: PlayScript, revision: String?): List<DramaLine>? {
        if (revision == null || revision != script.revision || files.isEmpty()) return null
        return files.map { f ->
            val line = script.lines.getOrNull(f.seq - 1) ?: return null
            DramaLine(f.url, line.id, f.seq)
        }
    }

    /** The line a finished drama's file [index] speaks; null past either end. */
    fun fileLine(files: List<DramaLine>, index: Int): String? = files.getOrNull(index)?.lineId

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
