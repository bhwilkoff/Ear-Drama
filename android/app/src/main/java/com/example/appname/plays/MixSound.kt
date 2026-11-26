package com.example.appname.plays

import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * Sound in the mix (B32 §3.3, §4.2, §5.1), line for line from `js/plays-core.js` and held to
 * `catalog/tests/golden/mix_sound.json`. The duck is computed from where voice takes sit, never
 * detected from audio, so every device and every export computes the same envelope.
 */
object MixSound {
    const val VERSION = 1

    /** Unverified depths and times (B32 §4.2 item 3): to set on a listening pass before the board ships. */
    object Defaults {
        const val EFFECTS_DUCK_DB = -6.0
        const val MUSIC_DUCK_DB = -12.0
        const val ATTACK_MS = 120.0
        const val RELEASE_MS = 600.0
        const val HOLD_MS = 1000.0
        const val EFFECTS_LUFS = -19.0
        const val MUSIC_LUFS = -20.0
        const val START_MIN_MS = -2000.0
        const val GAIN_MIN_DB = -12.0
        const val GAIN_MAX_DB = 6.0
    }

    val PLACEMENTS = listOf("before", "under", "after", "bed")

    /** A duck breakpoint: frame and dB. */
    typealias Point = Pair<Int, Double>

    /** The block as the timeline reads it: lanes, and only the slots that are not silent and hold a cue. */
    class Read(val lanes: Map<String, SoundLane>, val slots: List<SoundSlot>)

    /** Frames for a time in ms, rounded half up the same way on every stack. */
    fun msFrames(ms: Double, rate: Double): Int = floor(ms * rate / 1000 + 0.5).toInt()

    fun clampNum(v: Double, lo: Double, hi: Double, d: Double): Double = if (v.isFinite()) min(hi, max(lo, v)) else d

    /** The block as the timeline reads it, or null when it places nothing. A newer version is refused, never guessed. */
    fun readSound(block: SoundBlock?): Read? {
        if (block == null) return null
        if (block.v > VERSION) throw MixTimeline.SoundVersion(block.v)
        val slots = block.slots.filter { !it.silent && it.sounds.isNotEmpty() }
        return if (slots.isEmpty()) null else Read(block.lanes, slots)
    }

    fun hasSound(p: Production): Boolean = try {
        readSound(p.sound) != null
    } catch (_: MixTimeline.SoundVersion) {
        true
    }

    private val canonicalJson = Json { encodeDefaults = true }

    /** The block as JSON with sorted keys: what the fingerprint holds, so any change to a placed sound reads as a change. */
    fun canonical(block: SoundBlock): String = stringify(canonicalJson.encodeToJsonElement(SoundBlock.serializer(), block))

    private fun stringify(e: JsonElement): String = when (e) {
        is JsonArray -> e.joinToString(",", "[", "]") { stringify(it) }
        is JsonObject -> e.entries.sortedBy { it.key }.joinToString(",", "{", "}") { "${JsonPrimitive(it.key)}:${stringify(it.value)}" }
        else -> e.toString()
    }

    /**
     * The duck as breakpoints for one depth: full level outside voice, [depthDb] inside, ramping linearly in dB over
     * the attack before each voice interval and the release after it. Empty for Off (0 dB).
     */
    fun duckEnvelope(voice: List<MixTimeline.Span>, depthDb: Double, sampleRate: Double): List<Point> {
        if (!(depthDb < 0)) return emptyList()
        val a = msFrames(Defaults.ATTACK_MS, sampleRate)
        val r = msFrames(Defaults.RELEASE_MS, sampleRate)
        val out = ArrayList<Point>()
        for (v in voice) {
            out += (v.start - a) to 0.0
            out += v.start to depthDb
            out += v.end to depthDb
            out += (v.end + r) to 0.0
        }
        return out
    }

    /** The envelope's linear gain for each of [count] frames from [from]. */
    fun duckGains(points: List<Point>, from: Int, count: Int): DoubleArray {
        val g = DoubleArray(count) { 1.0 }
        if (points.isEmpty()) return g
        var lo = 0
        var hi = points.size
        while (lo < hi) {
            val mid = (lo + hi) ushr 1
            if (points[mid].first <= from) lo = mid + 1 else hi = mid
        }
        var j = lo
        var lastDb = 0.0
        var lastLin = 1.0
        for (i in 0 until count) {
            val f = from + i
            while (j < points.size && points[j].first <= f) j++
            val db = if (j == 0 || j == points.size) {
                0.0
            } else {
                val (f0, d0) = points[j - 1]
                val (f1, d1) = points[j]
                if (f1 == f0) d1 else d0 + ((d1 - d0) * (f - f0)) / (f1 - f0)
            }
            if (db != lastDb) {
                lastDb = db
                lastLin = 10.0.pow(db / 20)
            }
            g[i] = lastLin
        }
        return g
    }

    /**
     * One sound placement's samples over timeline frames [from, from + count), added into [into]: the source (looped
     * when the placement loops), times its gain, the duck, and its fades (linear in amplitude).
     */
    fun renderSound(x: MixTimeline.SoundPlacement, samples: FloatArray, points: List<Point>, from: Int, count: Int, into: FloatArray) {
        val a = max(from, x.start)
        val b = min(from + count, x.start + x.frames)
        if (a >= b) return
        val end = min(x.outFrame, samples.size)
        val span = end - x.inFrame
        if (span <= 0) return
        val duck = duckGains(points, a, b - a)
        for (f in a until b) {
            val k = f - x.start
            if (!x.loop && k >= span) break
            val src = x.inFrame + if (x.loop) k % span else k
            var g = x.gain * duck[f - a]
            if (x.fadeIn > 0 && k < x.fadeIn) g *= k.toDouble() / x.fadeIn
            if (x.fadeOut > 0 && x.frames - k < x.fadeOut) g *= (x.frames - k).toDouble() / x.fadeOut
            into[f - from] = (into[f - from] + samples[src].toDouble() * g).toFloat()
        }
    }

    /** The one scalar that holds a mix with sound at or below -1 dBFS sample peak (no limiter, B32 §4.3). */
    fun mixScalar(peak: Double): Double {
        val ceiling = 10.0.pow(MixTimeline.PEAK_CEILING / 20)
        return if (peak > ceiling) ceiling / peak else 1.0
    }
}
