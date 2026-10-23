package com.example.appname.plays

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sqrt
import kotlin.math.tan

/**
 * ITU-R BS.1770 integrated loudness of a mono signal: K-weighting (the
 * libebur128 filter design, valid at any sample rate), 400 ms blocks every
 * 100 ms, the -70 LUFS absolute gate and the -10 LU relative gate. The same
 * as apple/Core/Plays/PlayAudioMath.swift.
 */
object BS1770 {
    fun integratedLoudness(samples: FloatArray, sampleRate: Double): Double? {
        val weighted = kWeighted(samples, sampleRate)
        val block = (sampleRate * 0.4).toInt()
        val hop = (sampleRate * 0.1).toInt()
        if (block <= 0 || weighted.size < block) return null
        val powers = ArrayList<Double>()
        var start = 0
        while (start + block <= weighted.size) {
            var sum = 0.0
            for (i in start until start + block) sum += weighted[i] * weighted[i]
            powers += sum / block
            start += hop
        }
        fun loud(z: Double) = -0.691 + 10 * log10(z)
        val absolute = powers.filter { it > 0 && loud(it) > -70 }
        if (absolute.isEmpty()) return null
        val relative = loud(absolute.sum() / absolute.size) - 10
        val gated = absolute.filter { loud(it) > relative }
        if (gated.isEmpty()) return null
        return loud(gated.sum() / gated.size)
    }

    fun samplePeak(samples: FloatArray): Float {
        var peak = 0f
        for (s in samples) peak = max(peak, abs(s))
        return peak
    }

    private fun kWeighted(x: FloatArray, fs: Double): DoubleArray {
        // Stage 1: the head's high shelf.
        var k = tan(PI * 1681.974450955533 / fs)
        val vh = 10.0.pow(3.999843853973347 / 20)
        val vb = vh.pow(0.4996667741545416)
        var q = 0.7071752369554196
        var a0 = 1 + k / q + k * k
        val s1b = doubleArrayOf((vh + vb * k / q + k * k) / a0, 2 * (k * k - vh) / a0, (vh - vb * k / q + k * k) / a0)
        val s1a = doubleArrayOf(2 * (k * k - 1) / a0, (1 - k / q + k * k) / a0)
        // Stage 2: the RLB high-pass.
        k = tan(PI * 38.13547087602444 / fs)
        q = 0.5003270373238773
        a0 = 1 + k / q + k * k
        val s2b = doubleArrayOf(1.0, -2.0, 1.0)
        val s2a = doubleArrayOf(2 * (k * k - 1) / a0, (1 - k / q + k * k) / a0)
        return biquad(biquad(DoubleArray(x.size) { x[it].toDouble() }, s1b, s1a), s2b, s2a)
    }

    private fun biquad(x: DoubleArray, b: DoubleArray, a: DoubleArray): DoubleArray {
        val y = DoubleArray(x.size)
        var x1 = 0.0
        var x2 = 0.0
        var y1 = 0.0
        var y2 = 0.0
        for (i in x.indices) {
            val out = b[0] * x[i] + b[1] * x1 + b[2] * x2 - a[0] * y1 - a[1] * y2
            x2 = x1; x1 = x[i]; y2 = y1; y1 = out
            y[i] = out
        }
        return y
    }
}

/**
 * The bleed check (PLAYS-DESIGN §5 rule 2): how strongly a known signal (the
 * stand-in that played) appears inside another (a microphone window). The
 * peak normalized cross-correlation over every lag, on an 8 kHz copy of both.
 * 1 is the reference itself; unrelated audio stays near 0.
 */
object BleedCheck {
    /** UNVERIFIED: research 08a "To measure" 4 sets the real threshold on devices. */
    const val THRESHOLD = 0.5f

    fun score(signal: FloatArray, reference: FloatArray, sampleRate: Double): Float {
        val factor = max(1, (sampleRate / 8000).toInt())
        val s = decimate(signal, factor)
        val r = decimate(reference, factor)
        if (s.isEmpty() || r.isEmpty()) return 0f
        val (long, short) = if (s.size >= r.size) s to r else r to s
        var shortEnergy = 0.0
        for (v in short) shortEnergy += v * v
        val shortNorm = sqrt(shortEnergy)
        if (shortNorm <= 1e-6) return 0f
        // Slide the shorter across the longer, zero-padded so a partial overlap counts.
        val pad = short.size - 1
        val padded = FloatArray(long.size + 2 * pad)
        long.copyInto(padded, pad)
        val lags = padded.size - short.size + 1
        var window = 0.0
        for (i in 0 until short.size) window += padded[i] * padded[i]
        var best = 0.0
        for (lag in 0 until lags) {
            if (lag > 0) {
                val add = padded[lag + short.size - 1]
                val drop = padded[lag - 1]
                window += add * add - drop * drop
            }
            // A window that holds a sliver of the signal cannot vouch for a match.
            if (window <= shortEnergy * 0.05) continue
            var product = 0.0
            for (j in short.indices) product += padded[lag + j] * short[j]
            best = max(best, abs(product) / (shortNorm * sqrt(max(window, 1e-12))))
        }
        return min(best, 1.0).toFloat()
    }

    private fun decimate(x: FloatArray, factor: Int): FloatArray {
        if (factor <= 1) return x
        val n = x.size / factor
        return FloatArray(n) { i ->
            var sum = 0f
            for (j in 0 until factor) sum += x[i * factor + j]
            sum / factor
        }
    }
}

/**
 * Voice detection that ends a take (PLAYS-DESIGN §2.4, research 08a §5.1): an
 * energy detector on 20 ms frames, its floor from the session's room tone.
 * "Wait for me": it waits for the performer however long they take to begin.
 */
class LineEndDetector(val sampleRate: Double, roomToneRMS: Float, val trailingSilence: Double = 1.0) {
    sealed interface Event {
        data class Onset(val frame: Int) : Event
        data class End(val frame: Int) : Event
    }

    val threshold: Float = max(MINIMUM_THRESHOLD, roomToneRMS * 4)
    var onset: Int? = null
        private set
    var end: Int? = null
        private set
    private var position = 0
    private var loudRun = 0
    private var lastLoud = 0
    private var pending = FloatArray(0)
    private val frameLength = (sampleRate * 0.02).toInt()

    fun feed(samples: FloatArray): Event? {
        pending += samples
        var event: Event? = null
        var offset = 0
        while (pending.size - offset >= frameLength && end == null) {
            val frame = pending.copyOfRange(offset, offset + frameLength)
            offset += frameLength
            if (rms(frame) >= threshold) {
                loudRun += 1
                lastLoud = position + frameLength
                if (onset == null && loudRun >= 3) {
                    onset = position - 2 * frameLength
                    event = Event.Onset(onset!!)
                }
            } else {
                loudRun = 0
            }
            position += frameLength
            if (onset != null && (position - lastLoud) >= trailingSilence * sampleRate) {
                end = lastLoud
                event = Event.End(lastLoud)
            }
        }
        pending = pending.copyOfRange(offset, pending.size)
        return event
    }

    companion object {
        const val MINIMUM_THRESHOLD = 0.003f // about -50 dBFS RMS

        /** The kept window: from onset less 250 ms to the end plus 250 ms (§4.2). Without an onset the whole capture is kept. */
        fun window(onset: Int?, end: Int?, total: Int, sampleRate: Double): IntRange {
            if (onset == null) return 0 until total
            val handle = (sampleRate * 0.25).toInt()
            val lower = max(0, onset - handle)
            val upper = min(total, (end ?: total) + handle)
            return lower until max(lower, upper)
        }

        fun rms(samples: FloatArray): Float {
            if (samples.isEmpty()) return 0f
            var sum = 0.0
            for (s in samples) sum += s * s
            return sqrt(sum / samples.size).toFloat()
        }
    }
}

object Resample {
    /** Mono float samples at any rate to the take rate, in memory, by linear interpolation. */
    fun toTakeRate(samples: FloatArray, rate: Double): FloatArray {
        val target = TakeAudio.SAMPLE_RATE.toDouble()
        if (rate == target || samples.isEmpty()) return samples
        val n = (samples.size * target / rate).toInt()
        val step = rate / target
        return FloatArray(n) { i ->
            val x = i * step
            val a = x.toInt().coerceAtMost(samples.size - 1)
            val b = (a + 1).coerceAtMost(samples.size - 1)
            val t = (x - a).toFloat()
            samples[a] * (1 - t) + samples[b] * t
        }
    }
}
