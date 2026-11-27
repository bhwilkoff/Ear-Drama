package com.example.appname.plays

import java.io.File
import java.util.TreeMap
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

/**
 * The mix as plain data (PLAYS-DESIGN §4.2): lines in script order, each a
 * chosen human take with its in and out points, a gap before it, and a stored
 * gain. Placement is relative, so a longer re-take ripples every later line.
 * A partial play has no timeline at all: it is never mixed into a file (§5
 * rule 3), and nothing but a take can be placed, so a stand-in cannot be.
 * With sound (B32), [sounds] are the cue placements, [voice] where people
 * speak (the duck's input), and [left] the cues this device could not reach.
 */
data class MixTimeline(
    val sampleRate: Double,
    val placements: List<Placement>,
    val totalFrames: Int,
    val sounds: List<SoundPlacement> = emptyList(),
    val voice: List<Span> = emptyList(),
    val left: List<String> = emptyList(),
) {
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

    /** One cue on the timeline: where it starts, how long it lasts (a loop runs to fill it), its level, fades and duck depth. */
    data class SoundPlacement(
        val slotID: String,
        val soundID: String,
        val lineID: String,
        val at: String,
        val src: SoundSource,
        val file: String?,
        val lane: String,
        val start: Int,
        val frames: Int,
        val inFrame: Int,
        val outFrame: Int,
        val loop: Boolean,
        val gain: Double,
        val fadeIn: Int,
        val fadeOut: Int,
        val duck: Double,
    )

    /** A stretch of the timeline in frames. */
    data class Span(val start: Int, val end: Int)

    /** What a cue needs from its source: how long it is and how loud, as measured. [file] is a take's file in the takes folder. */
    data class SoundInfo(val frames: Int, val kind: String, val loudness: Double?, val peak: Float, val file: String? = null)

    data class Incomplete(val missing: List<String>) : Exception("${missing.size} lines still need a voice")
    data class Bleed(val lines: List<String>) : Exception("${lines.size} lines need a re-take with headphones")
    data class WrongSampleRate(val takeID: String) : Exception("take $takeID is not at the mix rate")
    data class MissingSounds(val ids: List<String>) : Exception("${ids.size} sounds are not on this device")
    data class SoundVersion(val v: Int) : Exception("sound block version $v is newer than this app reads")

    private class Entry(val slot: SoundSlot, val cue: SoundCue, val info: SoundInfo, val order: Int)

    companion object {
        const val TARGET = -16.0
        const val PEAK_CEILING = -1.0
        const val DEFAULT_GAP = 0.4

        fun build(
            whole: PlayScript,
            production: Production,
            sampleRate: Double = TakeAudio.SAMPLE_RATE.toDouble(),
            gap: Double = DEFAULT_GAP,
            resolveSound: ((SoundSource, SoundCue) -> SoundInfo?)? = null,
            withoutMissing: Boolean = false,
        ): MixTimeline {
            val script = production.scoped(whole)
            val missing = Relay.missingSpeech(production, script)
            if (missing.isNotEmpty()) throw Incomplete(missing)
            val flagged = Relay.needsRetake(production, script)
            if (flagged.isNotEmpty()) throw Bleed(flagged)
            val read = MixSound.readSound(production.sound)
            val here = if (script.scopedTo != null) script.lines.map { it.id }.toSet() else null
            val sound = if (read == null || here == null) read else read.slots.filter { it.line in here }.takeIf { it.isNotEmpty() }?.let { MixSound.Read(read.lanes, it) }
            val d = MixSound.Defaults

            val entries = ArrayList<Entry>()
            val left = ArrayList<String>()
            sound?.slots?.forEach { slot ->
                slot.sounds.forEach { cue ->
                    if (cue.at !in MixSound.PLACEMENTS) return@forEach
                    var info: SoundInfo? = null
                    val takeID = cue.src.take
                    if (takeID != null) {
                        val t = production.take(takeID)
                        if (t != null && t.bleed) throw Bleed(listOf(slot.line))
                        if (t != null && t.sampleRate != sampleRate) throw WrongSampleRate(t.id)
                        if (t != null) info = SoundInfo(t.frames, "effect", t.loudness, t.peak, t.file)
                    } else if (resolveSound != null) {
                        info = resolveSound(cue.src, cue)
                    }
                    if (info == null || info.frames <= 0) {
                        left += cue.id
                        return@forEach
                    }
                    entries += Entry(slot, cue, info, entries.size + left.size)
                }
            }
            if (sound != null && left.isNotEmpty() && !withoutMissing) throw MissingSounds(left.toList())
            val byLine = entries.groupBy { it.slot.line }

            val placements = ArrayList<Placement>()
            val voice = ArrayList<Span>()
            val out = TreeMap<Int, SoundPlacement>()
            val anchors = HashMap<String, Span>()
            val endAt = HashMap<String, Int>()
            var cursor = 0
            var placed = false
            var lastVoiceEnd = 0
            val gapFrames = floor(gap * sampleRate).toInt()
            fun nominal() = if (placed) cursor + gapFrames else 0
            fun startOf(e: Entry) = MixSound.msFrames(MixSound.clampNum(e.cue.startMs, d.START_MIN_MS, 600000.0, 0.0), sampleRate)
            fun place(e: Entry, start: Int, frames: Int) {
                val lane = if (e.cue.at == "bed" || e.info.kind == "music") "music" else "effects"
                val laneDb = sound?.lanes?.get(lane)?.duckDb
                val duck = e.cue.duckDb ?: laneDb ?: if (lane == "music") d.MUSIC_DUCK_DB else d.EFFECTS_DUCK_DB
                val level = gainLinear(e.info.loudness, e.info.peak.toDouble(), if (lane == "music") d.MUSIC_LUFS else d.EFFECTS_LUFS) *
                    10.0.pow(MixSound.clampNum(e.cue.gainDb, d.GAIN_MIN_DB, d.GAIN_MAX_DB, 0.0) / 20)
                out[e.order] = SoundPlacement(
                    slotID = e.slot.id, soundID = e.cue.id, lineID = e.slot.line, at = e.cue.at, src = e.cue.src, file = e.info.file,
                    lane = lane, start = start, frames = frames, inFrame = 0, outFrame = e.info.frames,
                    loop = (e.cue.at == "under" || e.cue.at == "bed") && e.cue.loop, gain = level,
                    fadeIn = MixSound.msFrames(MixSound.clampNum(e.cue.fadeInMs, 0.0, 600000.0, 0.0), sampleRate),
                    fadeOut = MixSound.msFrames(MixSound.clampNum(e.cue.fadeOutMs, 0.0, 600000.0, 0.0), sampleRate),
                    duck = min(0.0, max(-60.0, duck)),
                )
            }

            for (line in script.lines) {
                val mine = byLine[line.id].orEmpty()
                for (e in mine.filter { it.cue.at == "before" }) {
                    val s = max(0, nominal() + startOf(e))
                    place(e, s, e.info.frames)
                    cursor = max(cursor, s + e.info.frames)
                    placed = true
                }
                val take = production.chosenTake(line.id)
                val anchor: Span
                if (take != null) {
                    if (take.sampleRate != sampleRate) throw WrongSampleRate(take.id)
                    val start = nominal()
                    placements += Placement(line.id, take.id, take.file, start, 0, take.frames, gain(take.loudness, take.peak), take.bleed)
                    cursor = start + take.frames
                    placed = true
                    lastVoiceEnd = cursor
                    if (line.part != PartID.SOUND) voice += Span(start, cursor)
                    anchor = Span(start, cursor)
                } else {
                    val at = nominal()
                    anchor = Span(at, at)
                }
                anchors[line.id] = anchor
                endAt[line.id] = lastVoiceEnd
                for (e in mine.filter { it.cue.at == "after" }) {
                    val s = max(0, nominal() + startOf(e))
                    place(e, s, e.info.frames)
                    cursor = max(cursor, s + e.info.frames)
                    placed = true
                }
            }
            // Under and Bed move nothing, so they are placed once every line has its place.
            for (e in entries) {
                if (e.cue.at != "under" && e.cue.at != "bed") continue
                val anchor = anchors[e.slot.line] ?: continue
                val s = max(0, anchor.start + startOf(e))
                var frames: Int
                if (e.cue.at == "under") {
                    frames = if (e.cue.loop) anchor.end - s else e.info.frames
                } else {
                    val until = e.cue.until?.let { endAt[it] } ?: anchor.end
                    frames = until + MixSound.msFrames(MixSound.clampNum(e.cue.fadeOutMs, 0.0, 600000.0, 0.0), sampleRate) - s
                    if (!e.cue.loop) frames = min(frames, e.info.frames)
                }
                if (frames <= 0) frames = e.info.frames
                place(e, s, frames)
            }
            if (sound == null) return MixTimeline(sampleRate, placements, cursor)
            val sounds = out.values.toList()
            val merged = ArrayList<Span>()
            val hold = MixSound.msFrames(d.HOLD_MS, sampleRate)
            for (v in voice) {
                val last = merged.lastOrNull()
                if (last != null && v.start - last.end < hold) merged[merged.size - 1] = Span(last.start, max(last.end, v.end))
                else merged += v
            }
            val totalFrames = sounds.fold(cursor) { m, x -> max(m, x.start + x.frames) }
            return MixTimeline(sampleRate, placements, totalFrames, sounds, merged, left.toList())
        }

        /**
         * The linear gain that brings a take to -16 LUFS, held so its peak stays
         * at or below -1 dBFS (sample peak stands in for true peak) and within
         * +-24 dB. An unmeasured or silent take plays at unity.
         */
        fun gain(loudness: Double?, peak: Float): Float = gainLinear(loudness, peak.toDouble(), TARGET).toFloat()

        fun gainLinear(loudness: Double?, peak: Double, target: Double): Double {
            if (loudness == null || !loudness.isFinite()) return 1.0
            var db = target - loudness
            if (peak > 0) db = min(db, PEAK_CEILING - 20 * log10(peak))
            db = db.coerceIn(-24.0, 24.0)
            return 10.0.pow(db / 20)
        }
    }
}

/**
 * Renders a finished play's timeline a chunk at a time into a [MixSink] (a
 * three-hour play never sits in memory whole). It reads only the take files
 * the timeline names, and a timeline holds only human takes, so a stand-in
 * cannot reach the mix (§5 rule 3). A take the bleed check flagged is
 * refused, never mixed (§8 rule 3). With sound, the mix renders twice: the
 * first pass measures the sum's sample peak and writes nothing, the second
 * writes every sample times one scalar (B32 §4.3).
 */
object MixRenderer {
    const val CHUNK = 4_096

    /** What a render measured: the float sum's sample peak (0 with no sound) and the scalar applied. */
    data class Measured(val peak: Double, val scalar: Double)

    fun render(timeline: MixTimeline, takesFolder: File, sink: MixSink, loadSound: ((MixTimeline.SoundPlacement) -> FloatArray?)? = null): Measured {
        val voice = { p: MixTimeline.Placement -> TakeAudio.read(File(takesFolder, p.file)).first }
        val cue = { x: MixTimeline.SoundPlacement ->
            val fromTake = if (x.src.take != null) x.file?.let { TakeAudio.read(File(takesFolder, it)).first } else null
            fromTake ?: loadSound?.invoke(x)
        }
        return renderWith(timeline, CHUNK, voice, cue, sink)
    }

    /** The whole render over loaders, so a test can run it without files. A cue the loader returns null for is named, never dropped. */
    fun renderWith(
        timeline: MixTimeline,
        chunk: Int,
        loadVoice: (MixTimeline.Placement) -> FloatArray,
        loadSound: (MixTimeline.SoundPlacement) -> FloatArray?,
        sink: MixSink,
    ): Measured {
        timeline.placements.firstOrNull { it.bleed }?.let { throw MixTimeline.Bleed(listOf(it.lineID)) }
        val buffer = FloatArray(chunk)
        var peak = 0.0
        var scalar = 1.0
        if (timeline.sounds.isNotEmpty()) {
            val pass = Pass(timeline, loadVoice, loadSound)
            var now = 0
            while (now < timeline.totalFrames) {
                val count = min(chunk, timeline.totalFrames - now)
                pass.fill(now, count, buffer)
                for (i in 0 until count) peak = max(peak, abs(buffer[i]).toDouble())
                now += count
            }
            scalar = MixSound.mixScalar(peak)
        }
        val pass = Pass(timeline, loadVoice, loadSound)
        val scale = scalar.toFloat()
        var now = 0
        while (now < timeline.totalFrames) {
            val count = min(chunk, timeline.totalFrames - now)
            pass.fill(now, count, buffer)
            if (scalar != 1.0) for (i in 0 until count) buffer[i] *= scale
            sink.write(buffer, count)
            now += count
        }
        return Measured(peak, scalar)
    }

    /** One walk down the timeline. Cues overlap, so samples are cached by source and let go once every placement using them has ended. */
    private class Pass(
        private val timeline: MixTimeline,
        private val loadVoice: (MixTimeline.Placement) -> FloatArray,
        private val loadSound: (MixTimeline.SoundPlacement) -> FloatArray?,
    ) {
        private val loaded = HashMap<String, FloatArray>()
        private val lastEnd = HashMap<String, Int>()
        private val points = HashMap<Double, List<MixSound.Point>>()
        private var first = 0

        init {
            for (p in timeline.placements) lastEnd.merge(voiceKey(p), p.start + p.frames) { a, b -> max(a, b) }
            for (x in timeline.sounds) lastEnd.merge(soundKey(x), x.start + x.frames) { a, b -> max(a, b) }
        }

        private fun voiceKey(p: MixTimeline.Placement) = "t:${p.takeID}"

        private fun soundKey(x: MixTimeline.SoundPlacement): String {
            val s = x.src
            return when {
                s.take != null -> "t:${s.take}"
                s.own != null -> "o:${s.own}"
                else -> "p:${s.pack}/${s.cue}"
            }
        }

        fun fill(now: Int, count: Int, buffer: FloatArray) {
            buffer.fill(0f, 0, count)
            val placements = timeline.placements
            while (first < placements.size && placements[first].let { it.start + it.frames } <= now) first++
            var i = first
            while (i < placements.size && placements[i].start < now + count) {
                val p = placements[i]
                val samples = loaded.getOrPut(voiceKey(p)) { loadVoice(p) }
                val from = max(now, p.start)
                val to = min(now + count, p.start + p.frames)
                for (t in from until to) {
                    val source = p.inFrame + (t - p.start)
                    if (source < samples.size) buffer[t - now] += samples[source] * p.gain
                }
                i++
            }
            for (x in timeline.sounds) {
                if (x.start + x.frames <= now || x.start >= now + count) continue
                val samples = loaded[soundKey(x)] ?: (loadSound(x) ?: throw MixTimeline.MissingSounds(listOf(x.soundID))).also { loaded[soundKey(x)] = it }
                val envelope = points.getOrPut(x.duck) { MixSound.duckEnvelope(timeline.voice, x.duck, timeline.sampleRate) }
                MixSound.renderSound(x, samples, envelope, now, count, buffer)
            }
            val end = now + count
            loaded.keys.removeAll { (lastEnd[it] ?: 0) <= end }
        }
    }
}
