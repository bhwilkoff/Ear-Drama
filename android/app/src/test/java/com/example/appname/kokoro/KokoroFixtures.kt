package com.example.appname.kokoro

import com.example.appname.plays.PlayScript
import java.io.File
import java.io.IOException
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.sin
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject
import kotlinx.serialization.json.add

// Fixtures for the Kokoro tests: a small vocabulary, a model folder that reads as downloaded, a phoneme file made from a
// script, a renderer that never runs a model, and a Release that serves bytes with or without Range.

/** A slice of tokenizer.json's vocab (the real ids for these symbols). */
val FIXTURE_VOCAB: Map<String, Long> = mapOf(
    ";" to 1, ":" to 2, "," to 3, "." to 4, "!" to 5, "?" to 6, " " to 16, "a" to 43, "b" to 44, "d" to 46, "e" to 47,
    "h" to 50, "i" to 51, "k" to 53, "l" to 54, "m" to 55, "n" to 56, "o" to 57, "s" to 61, "t" to 62, "u" to 63, "w" to 65,
    "ɑ" to 69, "ə" to 83, "ɛ" to 86, "ɪ" to 102, "ɹ" to 123, "ˈ" to 156, "ˌ" to 157, "ː" to 158, "A" to 24, "O" to 31, "Q" to 32,
)

fun vocabJson(vocab: Map<String, Long> = FIXTURE_VOCAB): String = buildJsonObject {
    putJsonObject("model") { putJsonObject("vocab") { vocab.forEach { (k, v) -> put(k, v) } } }
}.toString()

fun manifestJson(files: List<KokoroManifest.ModelFile>, voices: List<String> = Kokoro.VOICES.map { it.id }, precision: String = "q8f16"): String =
    buildJsonObject {
        put("format", 1)
        put("version", 1)
        put("precision", precision)
        putJsonArray("voices") { voices.forEach { add(it) } }
        putJsonArray("voiceShape") { add(Kokoro.ROWS); add(Kokoro.STYLE) }
        putJsonArray("files") {
            files.forEach { f ->
                add(buildJsonObject { put("path", f.path); put("role", f.role); put("bytes", f.bytes); put("sha256", f.sha256); put("license", f.license) })
            }
        }
    }.toString()

/** The three model files' bytes: a stand-in model, a zero voice table of the real size, the vocabulary. */
fun modelFiles(): Map<String, Pair<String, ByteArray>> = linkedMapOf(
    "kokoro-v1-model_q8f16.onnx" to ("model" to ByteArray(70_001) { (it * 31).toByte() }),
    "kokoro-v1-voices-en.bin" to ("voices" to ByteArray(Kokoro.VOICE_TABLE_BYTES.toInt())),
    "kokoro-v1-tokenizer.json" to ("vocab" to vocabJson().toByteArray()),
)

fun sha(bytes: ByteArray): String =
    java.security.MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

fun fixtureManifest(files: Map<String, Pair<String, ByteArray>> = modelFiles(), license: String = "Apache-2.0"): String =
    manifestJson(files.map { (path, rb) -> KokoroManifest.ModelFile(path, rb.first, rb.second.size.toLong(), sha(rb.second), license) })

/** A model folder as a finished download leaves it. */
fun downloadedRoot(root: File): File {
    root.mkdirs()
    val files = modelFiles()
    files.forEach { (path, rb) -> File(root, path).writeBytes(rb.second) }
    File(root, "manifest.json").writeText(fixtureManifest(files))
    return root
}

val NO_NETWORK = RangeFetch { url, _, _ -> throw IOException("no network in this test: $url") }

/** `phonemes/<id>.json` for a script: every speech line, `us` from its words, `gb` with a length mark. */
fun phonemeFile(script: PlayScript): String = Json.encodeToString(
    PhonemeFile.serializer(),
    PhonemeFile(
        1, script.id, script.revision,
        script.lines.filter { it.spokenText.isNotBlank() && it.role != null }.map {
            val us = it.spokenText.lowercase().filter { c -> c.toString() in FIXTURE_VOCAB }
            PhonemeLine(it.id, Kokoro.keyOf(it.spokenText), us, "$us ː")
        },
    ),
)

/**
 * Renders a chirp whose start depends on the tokens, so each line's render can be found again in any file; or NaN, or
 * silence, when told to. Records each call.
 */
class FakeRenderer(var mode: String = "chirp") : KokoroRenderer {
    val calls = ArrayList<Triple<LongArray, Int, Float>>()
    var closed = false
    override fun render(tokens: LongArray, voiceIndex: Int, speed: Float): FloatArray {
        calls += Triple(tokens, voiceIndex, speed)
        return when (mode) {
            "nan" -> FloatArray(12_000) { if (it == 6_000) Float.NaN else 0.1f }
            "silent" -> FloatArray(12_000)
            "throw" -> throw IllegalStateException("model failed")
            else -> {
                val f0 = 400.0 + abs(tokens.contentHashCode() % 400) + voiceIndex * 7
                FloatArray(12_000) { i -> val t = i / 24_000.0; 0.3f * sin(2 * PI * (f0 * t + 2_000 * t * t)).toFloat() }
            }
        }
    }
    override fun close() { closed = true }
}

/** A Release on a fake server: serves [files] by name, honoring Range unless [ignoreRange]; [breakAfter] bytes then drops. */
class FakeRelease(val files: Map<String, ByteArray>) : RangeFetch {
    var ignoreRange = false
    var breakAfter: Long? = null
    val requests = ArrayList<Pair<String, Long>>()

    override suspend fun get(url: String, from: Long, onBytes: suspend (Int, ByteArray, Int) -> Unit): Int {
        val name = url.substringAfterLast('/')
        requests += name to from
        val body = files[name] ?: return 404
        val start = if (ignoreRange) 0L else from
        val status = if (from > 0 && !ignoreRange) 206 else 200
        var at = start.toInt()
        var sent = 0L
        while (at < body.size) {
            val n = minOf(8_192, body.size - at)
            val limit = breakAfter
            if (limit != null && sent + n > limit) {
                val k = (limit - sent).toInt()
                if (k > 0) onBytes(status, body.copyOfRange(at, at + k), k)
                breakAfter = null
                throw IOException("connection dropped")
            }
            onBytes(status, body.copyOfRange(at, at + n), n)
            at += n
            sent += n
        }
        return status
    }
}
