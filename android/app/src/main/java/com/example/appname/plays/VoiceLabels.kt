package com.example.appname.plays

import java.util.Locale
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * What a device voice sounds like, measured from one fixed sentence (PLAYS-DESIGN §2.8 rule 12): median pitch in Hz,
 * pitch range (90th over 10th percentile), tone (spectral centroid in Hz) and pace (seconds from first to last sound).
 * Only these numbers are kept; the audio they came from is dropped as soon as it is measured.
 */
data class VoiceTraits(val f0: Double, val range: Double, val tone: Double, val pace: Double) {
    fun encode(): String = String.format(Locale.US, "%.1f,%.3f,%.0f,%.2f", f0, range, tone, pace)

    companion object {
        fun decode(s: String?): VoiceTraits? {
            val p = s?.split(',')?.mapNotNull { it.toDoubleOrNull() } ?: return null
            if (p.size != 4 || p.any { it.isNaN() || it <= 0 }) return null
            return VoiceTraits(p[0], p[1], p[2], p[3])
        }
    }
}

object VoiceMeasure {
    /** The sentence every voice reads to be measured: never a play's words, never stored as sound. */
    const val SENTENCE = "I never thought I would see you again, not after what happened at the station last winter."

    private const val SILENCE = 0.02f

    /** The four measures of [pcm] (mono, -1..1) at [rate] Hz, or null when it holds too little voiced sound to judge. */
    fun measure(pcm: FloatArray, rate: Int): VoiceTraits? {
        if (rate <= 0 || pcm.size < rate / 4) return null
        val first = pcm.indexOfFirst { kotlin.math.abs(it) > SILENCE }
        val last = pcm.indexOfLast { kotlin.math.abs(it) > SILENCE }
        if (first < 0 || last <= first) return null
        val f0s = pitchTrack(pcm, rate)
        if (f0s.size < 10) return null
        f0s.sort()
        val median = f0s[f0s.size / 2]
        val p10 = f0s[(f0s.size * 0.1).toInt()]
        val p90 = f0s[(f0s.size * 0.9).toInt().coerceAtMost(f0s.size - 1)]
        val tone = centroid(pcm, rate) ?: return null
        return VoiceTraits(median, p90 / p10, tone, (last - first).toDouble() / rate)
    }

    /** Autocorrelation pitch over 40 ms windows every 10 ms, 60 to 400 Hz, voiced windows only. */
    private fun pitchTrack(x: FloatArray, sr: Int): DoubleArray {
        val win = (0.04 * sr).toInt()
        val hop = (0.01 * sr).toInt()
        val lo = sr / 400
        val hi = sr / 60
        val out = ArrayList<Double>()
        val seg = DoubleArray(win)
        var i = 0
        while (i + win + hi < x.size) {
            var mean = 0.0
            var energy = 0.0
            for (k in 0 until win) { seg[k] = x[i + k].toDouble(); mean += seg[k] }
            mean /= win
            for (k in 0 until win) { seg[k] -= mean; energy += seg[k] * seg[k] }
            if (sqrt(energy / win) >= SILENCE && energy > 0) {
                var best = 0.0
                var bestLag = 0
                for (lag in lo..hi) {
                    var s = 0.0
                    for (k in 0 until win - lag) s += seg[k] * seg[k + lag]
                    if (s > best) { best = s; bestLag = lag }
                }
                if (bestLag > 0 && best / energy > 0.5) out += sr.toDouble() / bestLag
            }
            i += hop
        }
        return out.toDoubleArray()
    }

    /** The mean magnitude spectrum's centroid over 2048-sample frames of sound. */
    private fun centroid(x: FloatArray, sr: Int): Double? {
        val n = 2048
        val mags = DoubleArray(n / 2)
        val re = DoubleArray(n)
        val im = DoubleArray(n)
        var frames = 0
        var i = 0
        while (i + n <= x.size) {
            var e = 0.0
            for (k in 0 until n) { re[k] = x[i + k].toDouble(); im[k] = 0.0; e += re[k] * re[k] }
            if (sqrt(e / n) >= SILENCE) {
                fft(re, im)
                for (k in 0 until n / 2) mags[k] += sqrt(re[k] * re[k] + im[k] * im[k])
                frames++
            }
            i += n
        }
        if (frames == 0) return null
        var num = 0.0
        var den = 0.0
        for (k in 0 until n / 2) { num += k.toDouble() * sr / n * mags[k]; den += mags[k] }
        return if (den > 0) num / den else null
    }

    private fun fft(re: DoubleArray, im: DoubleArray) {
        val n = re.size
        var j = 0
        for (i in 1 until n) {
            var bit = n shr 1
            while (j and bit != 0) { j = j xor bit; bit = bit shr 1 }
            j = j xor bit
            if (i < j) { var t = re[i]; re[i] = re[j]; re[j] = t; t = im[i]; im[i] = im[j]; im[j] = t }
        }
        var len = 2
        while (len <= n) {
            val ang = -2 * PI / len
            for (s in 0 until n step len) {
                for (k in 0 until len / 2) {
                    val wr = cos(ang * k)
                    val wi = sin(ang * k)
                    val ar = re[s + k + len / 2] * wr - im[s + k + len / 2] * wi
                    val ai = re[s + k + len / 2] * wi + im[s + k + len / 2] * wr
                    re[s + k + len / 2] = re[s + k] - ar
                    im[s + k + len / 2] = im[s + k] - ai
                    re[s + k] += ar
                    im[s + k] += ai
                }
            }
            len = len shl 1
        }
    }
}

/**
 * A device voice's label, composed from what it sounds like and where it is from (PLAYS-DESIGN §2.8 rule 12):
 * "Low, warm · US". Never a persona, never a bare number; the engine's code shows only when every measure ties.
 */
object VoiceLabels {
    /** Lower and higher, the register auto-cast alternates where a voice reports no gender (rule 12). */
    const val LOWER = "lower"
    const val HIGHER = "higher"
    private const val SPLIT = 165.0

    private enum class Trait(val words: List<String>) {
        TONE(listOf("warm", "clear", "bright")),
        RANGE(listOf("even", "varied", "lively")),
        PACE(listOf("quick", "steady", "unhurried"));

        fun of(t: VoiceTraits) = when (this) { TONE -> t.tone; RANGE -> t.range; PACE -> t.pace }
    }

    fun band(f0: Double): String = when {
        f0 < 115 -> "Deep"
        f0 < 150 -> "Low"
        f0 < 180 -> "Middle"
        f0 < 220 -> "High"
        else -> "Very high"
    }

    fun register(t: VoiceTraits?): String? = t?.let { if (it.f0 < SPLIT) LOWER else HIGHER }

    /** "US", "UK", else the region's English name ("Australia"); the language's name when the tag has no region. */
    fun accent(localeTag: String): String {
        val l = Locale.forLanguageTag(localeTag.replace('_', '-'))
        return when (l.country.uppercase()) {
            "US" -> "US"
            "GB" -> "UK"
            "" -> l.getDisplayLanguage(Locale.US).ifEmpty { localeTag }
            else -> l.getDisplayCountry(Locale.US).ifEmpty { l.country }
        }
    }

    /** The engine's own short code for a voice ("sfg" of "en-us-x-sfg-local"), shown only when measures tie. */
    fun code(id: String): String =
        Regex("-x-([a-z0-9]+)").find(id)?.groupValues?.get(1) ?: id.replace(Regex("^[a-zA-Z]{2,3}([-_][a-zA-Z]{2})?[-_]"), "").ifEmpty { id }

    /**
     * Labels for [voices] (id to locale tag), unique among them. A voice not yet measured reads "US voice (sfg)" until
     * its numbers arrive.
     */
    fun labels(voices: List<Pair<String, String>>, traits: Map<String, VoiceTraits>): Map<String, String> {
        val out = LinkedHashMap<String, String>()
        val measured = voices.filter { traits[it.first] != null }
        voices.filter { traits[it.first] == null }.forEach { (id, tag) -> out[id] = "${accent(tag)} voice (${code(id)})" }
        measured.groupBy { accent(it.second) to band(traits.getValue(it.first).f0) }.forEach { (key, group) ->
            val words = HashMap<String, MutableList<String>>()
            name(group.map { it.first }, traits, Trait.entries.toList(), words)
            group.forEach { (id, _) ->
                val w = words[id].orEmpty()
                val (plain, codes) = w.partition { !it.startsWith("(") }
                val head = (listOf(key.second) + plain).joinToString(", ")
                out[id] = "$head · ${key.first}" + codes.joinToString("") { " $it" }
            }
        }
        return voices.associate { it.first to out.getValue(it.first) }
    }

    private fun name(ids: List<String>, traits: Map<String, VoiceTraits>, left: List<Trait>, words: MutableMap<String, MutableList<String>>) {
        if (ids.size < 2) return
        val pick = left.maxByOrNull { t -> minGap(ids.map { t.of(traits.getValue(it)) }) }
        if (pick == null || ids.map { traits.getValue(it) }.distinct().size == 1) {
            ids.forEach { words.getOrPut(it) { ArrayList() } += "(${code(it)})" }
            return
        }
        val sorted = ids.sortedWith(compareBy<String> { pick.of(traits.getValue(it)) }.thenBy { it })
        val n = sorted.size
        val buckets = sorted.withIndex().groupBy({ if (n == 2) it.index * 2 else it.index * 3 / n }, { it.value })
        buckets.forEach { (b, members) ->
            members.forEach { words.getOrPut(it) { ArrayList() } += pick.words[b] }
            name(members, traits, left - pick, words)
        }
    }

    /** The smallest step between neighbors, as a fraction of the lower: how well a trait tells these voices apart. */
    private fun minGap(values: List<Double>): Double {
        val s = values.sorted()
        return (1 until s.size).minOfOrNull { (s[it] - s[it - 1]) / s[it - 1] } ?: 0.0
    }

    /**
     * Google's speech engine's US voices, measured once on a Pixel 8a (2026-11-23, engine 20261026) with [VoiceMeasure]
     * over [VoiceMeasure.SENTENCE], so a Pixel shows its labels at once; any other voice is measured on the device.
     */
    val SEED: Map<String, VoiceTraits> = mapOf(
        "en-us-x-iob-local" to VoiceTraits(193.5, 1.725, 1752.0, 4.40),
        "en-us-x-iog-local" to VoiceTraits(230.8, 1.409, 2067.0, 4.22),
        "en-us-x-iol-local" to VoiceTraits(140.4, 1.775, 2244.0, 4.24),
        "en-us-x-iom-local" to VoiceTraits(136.4, 1.777, 1931.0, 4.46),
        "en-us-x-sfg-local" to VoiceTraits(212.4, 1.381, 1810.0, 4.31),
        "en-us-x-tpc-local" to VoiceTraits(157.9, 1.619, 1898.0, 4.66),
        "en-us-x-tpd-local" to VoiceTraits(130.4, 1.570, 1825.0, 4.42),
        "en-us-x-tpf-local" to VoiceTraits(210.5, 1.614, 1701.0, 4.69),
    )
}
