package com.example.appname.plays

import java.io.File
import kotlin.math.log10
import kotlin.math.min
import kotlin.math.pow

/**
 * The mix as plain data (PLAYS-DESIGN §4.2): lines in script order, each a
 * chosen human take with its in and out points, a gap before it, and a stored
 * gain. Placement is relative, so a longer re-take ripples every later line.
 * A partial play has no timeline at all: it is never mixed into a file (§5
 * rule 3), and nothing but a take can be placed, so a stand-in cannot be.
 */
data class MixTimeline(val sampleRate: Double, val placements: List<Placement>, val totalFrames: Int) {
    data class Placement(
        val lineID: String,
        val takeID: String,
        val file: String,
        val start: Int,
        val inFrame: Int,
        val outFrame: Int,
        val gain: Float,
        val bleed: Boolean = false,
    ) {
        val frames: Int get() = outFrame - inFrame
    }

    data class Incomplete(val missing: List<String>) : Exception("${missing.size} lines still need a voice")
    data class Bleed(val lines: List<String>) : Exception("${lines.size} lines need a re-take with headphones")
    data class WrongSampleRate(val takeID: String) : Exception("take $takeID is not at the mix rate")

    companion object {
        const val TARGET = -16.0
        const val PEAK_CEILING = -1.0
        const val DEFAULT_GAP = 0.4

        fun build(
            script: PlayScript,
            production: Production,
            sampleRate: Double = TakeAudio.SAMPLE_RATE.toDouble(),
            gap: Double = DEFAULT_GAP,
        ): MixTimeline {
            val missing = Relay.missingSpeech(production, script)
            if (missing.isNotEmpty()) throw Incomplete(missing)
            val flagged = Relay.needsRetake(production, script)
            if (flagged.isNotEmpty()) throw Bleed(flagged)
            val placements = ArrayList<Placement>()
            var cursor = 0
            val gapFrames = (gap * sampleRate).toInt()
            for (line in script.lines) {
                val take = production.chosenTake(line.id) ?: continue
                if (take.sampleRate != sampleRate) throw WrongSampleRate(take.id)
                val start = if (placements.isEmpty()) 0 else cursor + gapFrames
                placements += Placement(line.id, take.id, take.file, start, 0, take.frames, gain(take.loudness, take.peak), take.bleed)
                cursor = start + take.frames
            }
            return MixTimeline(sampleRate, placements, cursor)
        }

        /**
         * The linear gain that brings a take to -16 LUFS, held so its peak stays
         * at or below -1 dBFS (sample peak stands in for true peak) and within
         * +-24 dB. An unmeasured or silent take plays at unity.
         */
        fun gain(loudness: Double?, peak: Float): Float {
            if (loudness == null || !loudness.isFinite()) return 1f
            var db = TARGET - loudness
            if (peak > 0) db = min(db, PEAK_CEILING - 20 * log10(peak.toDouble()))
            db = db.coerceIn(-24.0, 24.0)
            return 10.0.pow(db / 20).toFloat()
        }
    }
}

/**
 * Renders a finished play's timeline a chunk at a time into a [MixSink] (a
 * three-hour play never sits in memory whole). It reads only the take files
 * the timeline names, and a timeline holds only human takes, so a stand-in
 * cannot reach the mix (§5 rule 3). A take the bleed check flagged is
 * refused, never mixed (§8 rule 3).
 */
object MixRenderer {
    const val CHUNK = 4_096

    fun render(timeline: MixTimeline, takesFolder: File, sink: MixSink) {
        timeline.placements.firstOrNull { it.bleed }?.let { throw MixTimeline.Bleed(listOf(it.lineID)) }
        val buffer = FloatArray(CHUNK)
        var loadedIndex = -1
        var loaded = FloatArray(0)
        var first = 0
        var now = 0
        while (now < timeline.totalFrames) {
            val count = min(CHUNK, timeline.totalFrames - now)
            buffer.fill(0f, 0, count)
            while (first < timeline.placements.size && timeline.placements[first].let { it.start + it.frames } <= now) first++
            var i = first
            while (i < timeline.placements.size && timeline.placements[i].start < now + count) {
                val p = timeline.placements[i]
                if (loadedIndex != i) {
                    loaded = TakeAudio.read(File(takesFolder, p.file)).first
                    loadedIndex = i
                }
                val from = maxOf(now, p.start)
                val to = minOf(now + count, p.start + p.frames)
                for (t in from until to) {
                    val source = p.inFrame + (t - p.start)
                    if (source < loaded.size) buffer[t - now] += loaded[source] * p.gain
                }
                i++
            }
            sink.write(buffer, count)
            now += count
        }
    }
}
