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
     * A finished drama's line timeline (PLAYS-DESIGN §2.11 rule 11): the item holds one file per line, `0042-PART.wav`,
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

    // The word heard (PLAYS-DESIGN 2.11 rule 3): a voice's own timing mapped onto the printed words.

    /** A word on the page: UTF-16 offsets into the line's printed words ([ScriptReading.lineText]), end exclusive. */
    data class Word(val start: Int, val end: Int)

    /** The string a device voice is given for a line, and for each UTF-16 unit of it the offset in the printed words it came from. */
    class Spoken(val said: String, val toLine: IntArray)

    /**
     * The spoken string of [line] with its map back to the printed words: a speech's said parts joined by one space, a
     * direction's or a cue's whole block; italic marks dropped and the ends trimmed, as [CastSpeaker] says them.
     */
    fun spoken(line: ScriptLine): Spoken {
        val chars = ArrayList<Char>()
        val offs = ArrayList<Int>()
        if (line.kind == ScriptLine.Kind.Speech) {
            var at = 0
            var first = true
            for (part in line.parts.orEmpty()) {
                if (part is LinePart.Say) {
                    if (!first) { chars += ' '; offs += maxOf(0, at - 1) }
                    first = false
                    for ((i, ch) in part.text.withIndex()) { chars += ch; offs += at + i }
                }
                at += part.text.length + 1
            }
        } else {
            for ((i, ch) in line.source.orEmpty().withIndex()) { chars += ch; offs += i }
        }
        val keep = chars.indices.filter { chars[it] != '_' }
        var lo = 0
        var hi = keep.size
        while (lo < hi && chars[keep[lo]].isWhitespace()) lo++
        while (hi > lo && chars[keep[hi - 1]].isWhitespace()) hi--
        val sb = StringBuilder()
        val map = IntArray(hi - lo)
        for (k in lo until hi) { sb.append(chars[keep[k]]); map[k - lo] = offs[keep[k]] }
        return Spoken(sb.toString(), map)
    }

    /** The printed word a voice's range of [Spoken.said] (UTF-16 location and length) is; null when it falls outside. */
    fun word(spoken: Spoken, location: Int, length: Int): Word? {
        if (location < 0 || length <= 0 || location + length > spoken.toLine.size) return null
        return Word(spoken.toLine[location], spoken.toLine[location + length - 1] + 1)
    }

    /** The printed words of a spoken string: runs split at white space and dashes (an em or en dash, or two hyphens), each holding a letter or a digit, trimmed to its first and last. */
    fun textWords(said: String): List<Word> {
        fun separates(i: Int): Boolean {
            val c = said[i]
            if (c.isWhitespace() || c == '—' || c == '–') return true
            if (c == '-') return (i + 1 < said.length && said[i + 1] == '-') || (i > 0 && said[i - 1] == '-')
            return false
        }
        val out = ArrayList<Word>()
        var first = -1
        var last = -1
        fun close() {
            if (first >= 0) out += Word(first, last + 1)
            first = -1
            last = -1
        }
        for (i in said.indices) {
            if (separates(i)) { close(); continue }
            if (said[i].isLetterOrDigit()) {
                if (first < 0) first = i
                last = i
            }
        }
        close()
        return out
    }

    private val PHONEME_PUNCTUATION = setOf(
        ';', ':', ',', '.', '!', '?', '—', '…', '"', '(', ')', '“', '”', '«', '»', '¡', '¿',
        '-', '–', '\'', '’',
    )

    /** One rendered piece: the symbols that became tokens, and the duration model's frames per token, the padding token at both ends included. */
    class KokoroPiece(val symbols: String, val frames: IntArray)

    /** A word heard from [sample] of the line's audio (24 kHz before the pitch's playback rate). */
    data class TimedWord(val sample: Int, val word: Word)

    const val SAMPLES_PER_FRAME = 600

    /** The first sample of each phoneme word of the pieces, in order; null when a piece's frames do not fit its symbols. */
    fun phonemeWordStarts(pieces: List<KokoroPiece>, samplesPerFrame: Int = SAMPLES_PER_FRAME): List<Int>? {
        val starts = ArrayList<Int>()
        var base = 0
        for (piece in pieces) {
            if (piece.frames.size != piece.symbols.length + 2) return null
            var frame = piece.frames[0]
            var inWord = false
            for ((i, s) in piece.symbols.withIndex()) {
                if (s.isWhitespace()) inWord = false
                else if (!inWord && s !in PHONEME_PUNCTUATION) { inWord = true; starts += base + frame * samplesPerFrame }
                frame += piece.frames[i + 1]
            }
            base += piece.frames.sum() * samplesPerFrame
        }
        return starts
    }

    /** How many phoneme words a line's whole phoneme string holds (decided before the first piece plays). */
    fun phonemeWordCount(symbols: String): Int =
        phonemeWordStarts(listOf(KokoroPiece(symbols, IntArray(symbols.length + 2))))?.size ?: 0

    /** Where each word of a Kokoro line begins in its audio; the phoneme words pair with the printed words only when the counts agree, else null. */
    fun kokoroWords(said: String, pieces: List<KokoroPiece>, samplesPerFrame: Int = SAMPLES_PER_FRAME): List<TimedWord>? {
        val starts = phonemeWordStarts(pieces, samplesPerFrame) ?: return null
        val words = textWords(said)
        if (words.isEmpty() || words.size != starts.size) return null
        return starts.zip(words).map { (s, w) -> TimedWord(s, w) }
    }

    /** The word heard at [sample]: the last one begun, null before the first. */
    fun word(timed: List<TimedWord>, sample: Int): Word? = timed.lastOrNull { it.sample <= sample }?.word

    // Speed (rule 7)

    /** The transport's speeds: 0.5x to 2x in quarter steps, a multiplier on each part's own speed. */
    val SPEEDS = listOf(0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0)
    const val SPEED_KEY = "ed.along.speed"

    /** The nearest step to [x] (a stored value from another version, or none). */
    fun speed(x: Double?): Double =
        if (x == null || !x.isFinite()) 1.0 else SPEEDS.minByOrNull { kotlin.math.abs(it - x) } ?: 1.0

    /** "1.25x": the speed as the transport names it. */
    fun speedLabel(x: Double): String {
        var s = String.format(java.util.Locale.US, "%.2f", speed(x))
        while (s.endsWith("0")) s = s.dropLast(1)
        if (s.endsWith(".")) s = s.dropLast(1)
        return s + "×"
    }
}
