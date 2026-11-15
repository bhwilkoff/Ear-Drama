package com.example.appname

import android.app.Activity
import android.os.Bundle
import android.os.Debug
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import android.widget.ScrollView
import android.widget.TextView
import com.example.appname.app.AppNameApplication
import com.example.appname.kokoro.Kokoro
import ai.onnxruntime.OrtSession
import com.example.appname.kokoro.KokoroModelStore
import com.example.appname.kokoro.KokoroReader
import com.example.appname.kokoro.OrtKokoroRenderer
import com.example.appname.plays.PlayLibraryFeed
import com.example.appname.plays.ScriptLine
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * DEBUG only: the S6a bench for Kokoro on this phone (R2-kokoro-feasibility §6; gate RTF <= 0.7 and memory under
 * 600 MB). Renders real lines from three published plays in a loop, MUTED: nothing is played, no AudioTrack is opened;
 * each render is measured and dropped. Logs every line and a summary each minute under the tag `KokoroBench`.
 *
 *   adb shell am start -n app.eardrama.debug/com.example.appname.KokoroBenchActivity --ei minutes 10 --ei lines 50
 *
 * Downloads the model first when this device does not have it (the same store the picker uses).
 */
class KokoroBenchActivity : Activity() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var job: Job? = null
    private lateinit var out: TextView
    private val text = StringBuilder()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        out = TextView(this).apply { textSize = 12f; setPadding(32, 96, 32, 32) }
        setContentView(ScrollView(this).apply { addView(out) })
        val minutes = intent.getIntExtra("minutes", 10)
        val count = intent.getIntExtra("lines", 50)
        job = scope.launch { runCatching { bench(minutes, count) }.onFailure { say("FAILED ${it::class.simpleName}: ${it.message}") } }
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    private fun say(line: String) {
        Log.i(TAG, line)
        text.append(line).append('\n')
        out.text = text
    }

    private class Line(val play: String, val text: String)

    private suspend fun bench(minutes: Int, count: Int) {
        val container = (application as AppNameApplication).container
        val threads = intent.getIntExtra("threads", 4)
        val level = when (intent.getStringExtra("opt")) {
            "none" -> OrtSession.SessionOptions.OptLevel.NO_OPT
            "basic" -> OrtSession.SessionOptions.OptLevel.BASIC_OPT
            "extended" -> OrtSession.SessionOptions.OptLevel.EXTENDED_OPT
            else -> OrtSession.SessionOptions.OptLevel.ALL_OPT
        }
        val xnnpack = intent.getBooleanExtra("xnnpack", false)
        val arena = intent.getBooleanExtra("arena", true)
        val piece = intent.getIntExtra("piece", Kokoro.MAX_TOKENS)
        // The app's store and phonemes, with the session options under test.
        val reader = KokoroReader(container.kokoro.store, { id -> container.plays.phonemes(id) }, { p, table ->
            OrtKokoroRenderer.load(intent.getStringExtra("model")?.let { java.io.File(getExternalFilesDir(null), it).path } ?: p.model.path, table, threads, level, xnnpack, arena)
        }, maxSymbols = piece)
        val store = reader.store
        say("device ${android.os.Build.MODEL} sdk ${android.os.Build.VERSION.SDK_INT} cores ${Runtime.getRuntime().availableProcessors()} threads $threads opt $level xnnpack $xnnpack arena $arena piece $piece model ${intent.getStringExtra("model") ?: "q8f16"}")
        if (store.state.value !is KokoroModelStore.State.Ready) {
            say("downloading the model")
            val watch = scope.launch {
                var last = -1L
                store.state.collect { s ->
                    if (s is KokoroModelStore.State.Downloading && s.done / 10_000_000 != last) { last = s.done / 10_000_000; say("  ${s.done / 1_000_000} of ${s.total / 1_000_000} MB") }
                }
            }
            store.download()
            watch.cancel()
            if (store.state.value !is KokoroModelStore.State.Ready) { say("download: ${store.state.value}"); return }
        }
        val plays = container.plays
        plays.loadRows()
        val rows = (plays.rows.first { it !is PlayLibraryFeed.Rows.Loading } as? PlayLibraryFeed.Rows.Ready)?.rows.orEmpty()
            .filter { it.phonemes != null && it.lines >= 60 }.sortedBy { it.id }
        if (rows.size < 3) { say("library has ${rows.size} plays with phonemes"); return }
        val chosen = listOf(rows[rows.size / 7], rows[rows.size / 2], rows[rows.size * 6 / 7])
        val lines = ArrayList<Line>()
        for ((k, row) in chosen.withIndex()) {
            val script = plays.script(row.id) ?: continue
            reader.prepare(row.id)
            val candidates = script.lines.filter { it.kind == ScriptLine.Kind.Speech && it.spokenText.length >= 12 && reader.canRead(row.id, it.spokenText) }
            val want = count / chosen.size + if (k < count % chosen.size) 1 else 0
            val step = (candidates.size / want.coerceAtLeast(1)).coerceAtLeast(1)
            candidates.filterIndexed { i, _ -> i % step == 0 }.take(want).forEach { lines += Line(row.id, it.spokenText) }
            say("play ${row.id} \"${row.title}\": ${candidates.size} readable lines")
        }
        say("lines ${lines.size}, chars mean ${lines.sumOf { it.text.length } / lines.size.coerceAtLeast(1)}")
        val power = getSystemService(PowerManager::class.java)
        val pssBefore = Debug.getPss()
        val t0 = SystemClock.elapsedRealtime()
        val ok = reader.warm()
        val loadMs = SystemClock.elapsedRealtime() - t0
        say("model load ${loadMs} ms ok=$ok pss before ${pssBefore / 1024} MB after ${Debug.getPss() / 1024} MB")
        if (!ok) return

        val rtfs = ArrayList<Double>()
        val firsts = ArrayList<Long>()
        var peakPss = 0L
        // PSS between renders hides a render's own peak when buffers are freed after it: sample all the time, off the loop.
        val sampled = java.util.concurrent.atomic.AtomicLong(0)
        val sampler = scope.launch(Dispatchers.IO) { while (true) { sampled.accumulateAndGet(Debug.getPss(), ::maxOf); kotlinx.coroutines.delay(200) } }
        var peakNative = 0L
        var thermalMax = power.currentThermalStatus
        var audioSec = 0.0
        val end = SystemClock.elapsedRealtime() + minutes * 60_000L
        var nextSummary = SystemClock.elapsedRealtime() + 60_000L
        var n = 0
        while (SystemClock.elapsedRealtime() < end) {
            val line = lines[n % lines.size]
            val voice = Kokoro.VOICES[n % Kokoro.VOICES.size]
            val start = SystemClock.elapsedRealtime()
            var first = -1L
            var samples = 0L
            val read = withContext(Dispatchers.Default) {
                reader.renderPieces(line.play, line.text, voice.id, 1f) { piece ->
                    if (first < 0) first = SystemClock.elapsedRealtime() - start
                    samples += piece.size
                }
            }
            val ms = SystemClock.elapsedRealtime() - start
            val sec = samples / Kokoro.SAMPLE_RATE.toDouble()
            val pss = Debug.getPss()
            peakPss = maxOf(peakPss, pss, sampled.get())
            peakNative = maxOf(peakNative, Debug.getNativeHeapAllocatedSize())
            val thermal = power.currentThermalStatus
            thermalMax = maxOf(thermalMax, thermal)
            if (read && sec > 0) {
                rtfs += ms / 1000.0 / sec
                firsts += first
                audioSec += sec
            }
            Log.i(TAG, "line $n ${voice.id} chars ${line.text.length} audio ${"%.2f".format(sec)} s render $ms ms rtf ${"%.3f".format(if (sec > 0) ms / 1000.0 / sec else -1.0)} first $first ms pss ${pss / 1024} MB thermal $thermal read $read${if (!read) " (" + reader.lastRefusal + ")" else ""}")
            n += 1
            if (SystemClock.elapsedRealtime() >= nextSummary) {
                nextSummary += 60_000L
                say(summary("minute", rtfs, firsts, peakPss, peakNative, thermalMax, thermal, power, audioSec, n))
            }
        }
        sampler.cancel()
        peakPss = maxOf(peakPss, sampled.get())
        say(summary("FINAL", rtfs, firsts, peakPss, peakNative, thermalMax, power.currentThermalStatus, power, audioSec, n))
        val pass = (rtfs.average() <= 0.7) && peakPss / 1024 < 600
        say("GATE (RTF <= 0.7 mean, PSS < 600 MB): ${if (pass) "PASS" else "FAIL"}; model load $loadMs ms")
    }

    private fun pct(xs: List<Double>, p: Double): Double = if (xs.isEmpty()) -1.0 else xs.sorted()[((xs.size - 1) * p).toInt()]

    private fun summary(tag: String, rtfs: List<Double>, firsts: List<Long>, pss: Long, native: Long, tMax: Int, tNow: Int, power: PowerManager, audio: Double, n: Int): String {
        val f = firsts.map { it.toDouble() }
        return "SUMMARY $tag renders ${rtfs.size}/$n audio ${"%.0f".format(audio)} s | RTF mean ${"%.3f".format(rtfs.average())} p50 ${"%.3f".format(pct(rtfs, 0.5))} p95 ${"%.3f".format(pct(rtfs, 0.95))} max ${"%.3f".format(rtfs.maxOrNull() ?: -1.0)}" +
            " | first-audio ms p50 ${pct(f, 0.5).toLong()} p95 ${pct(f, 0.95).toLong()} max ${f.maxOrNull()?.toLong()}" +
            " | peak PSS ${pss / 1024} MB native heap ${native / 1_048_576} MB | thermal now $tNow max $tMax headroom ${if (android.os.Build.VERSION.SDK_INT >= 30) "%.2f".format(power.getThermalHeadroom(10)) else "n/a"}"
    }

    private companion object {
        const val TAG = "KokoroBench"
    }
}
