package com.example.appname.kokoro

import com.example.appname.plays.CastVoice
import com.example.appname.plays.VoiceCastEntry
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long

/**
 * Kokoro-82M, the downloadable voices (Decisions 076, 078; R2-kokoro-feasibility §6 S6d), the parts that need no
 * runtime: the 28 voices, the tokenizer over the catalog's published phonemes, the voice table's style rows, the
 * render guard, and the native manifest's acceptance. The Kotlin mirror of js/kokoro-voice.js and js/kokoro-model.js.
 * No phonemizer: a line arrives already as phonemes (contract §4.1 `phonemes/<id>.json`); a line without them is
 * read by the part's system voice.
 */
object Kokoro {
    data class Voice(val id: String, val name: String, val grade: String, val index: Int) {
        val localeTag: String get() = if (id[0] == 'b') "en-GB" else "en-US"

        /** The voice's own reported gender (its id says it), which auto-cast may read; never a part's. */
        val gender: String get() = if (id[1] == 'f') "female" else "male"
        val british: Boolean get() = id[0] == 'b'
    }

    /** The 28 English voices of Kokoro-82M v1.0 (VOICES.md), in the voice table's order. Grade is Kokoro's own. */
    val VOICES: List<Voice> = listOf(
        "af_heart" to "Heart" to "A", "af_alloy" to "Alloy" to "C", "af_aoede" to "Aoede" to "C+", "af_bella" to "Bella" to "A-",
        "af_jessica" to "Jessica" to "D", "af_kore" to "Kore" to "C+", "af_nicole" to "Nicole" to "B-", "af_nova" to "Nova" to "C",
        "af_river" to "River" to "D", "af_sarah" to "Sarah" to "C+", "af_sky" to "Sky" to "C-",
        "am_adam" to "Adam" to "F+", "am_echo" to "Echo" to "D", "am_eric" to "Eric" to "D", "am_fenrir" to "Fenrir" to "C+",
        "am_liam" to "Liam" to "D", "am_michael" to "Michael" to "C+", "am_onyx" to "Onyx" to "D", "am_puck" to "Puck" to "C+",
        "am_santa" to "Santa" to "D-",
        "bf_alice" to "Alice" to "D", "bf_emma" to "Emma" to "B-", "bf_isabella" to "Isabella" to "C", "bf_lily" to "Lily" to "D",
        "bm_daniel" to "Daniel" to "D", "bm_fable" to "Fable" to "C", "bm_george" to "George" to "C", "bm_lewis" to "Lewis" to "D+",
    ).mapIndexed { i, (idName, grade) -> Voice(idName.first, idName.second, grade, i) }

    private val TIER = mapOf("A" to 2, "A-" to 2, "B-" to 1)

    /** Symbols per render: Kokoro rushes past ~400 (VOICES.md) and stops at 510. */
    const val MAX_TOKENS = 400
    const val STYLE = 256
    const val ROWS = 510
    const val SAMPLE_RATE = 24_000

    /** The voice table's size for [VOICES]: voices x 510 rows x 256 floats, little-endian float32. */
    val VOICE_TABLE_BYTES: Long = VOICES.size.toLong() * ROWS * STYLE * 4

    fun voice(id: String?): Voice? = VOICES.firstOrNull { it.id == id }

    /** The castable Kokoro voices: none until the model is downloaded; best grade first, then the table's order. */
    fun castable(ready: Boolean): List<CastVoice> {
        if (!ready) return emptyList()
        return VOICES.sortedWith(compareByDescending<Voice> { TIER[it.grade] ?: 0 }.thenBy { it.index })
            .map { CastVoice(it.id, "${it.name} (Kokoro)", it.localeTag, 0, it.gender, false, VoiceCastEntry.KOKORO) }
    }

    /**
     * A phoneme string split into renders of at most [max] symbols, at the last sentence punctuation, else the last
     * comma, else the last space before the limit. Joined, they are the input (js/kokoro-voice.js `chunks`).
     */
    fun chunks(ps: String, max: Int = MAX_TOKENS): List<String> {
        val out = ArrayList<String>()
        var rest = ps
        while (rest.length > max) {
            val head = rest.substring(0, max)
            var cut = maxOf(head.lastIndexOf(". "), head.lastIndexOf("! "), head.lastIndexOf("? "), head.lastIndexOf("; "))
            if (cut < max / 4) cut = head.lastIndexOf(", ")
            if (cut < max / 4) cut = head.lastIndexOf(' ')
            if (cut <= 0) cut = max - 1
            out += rest.substring(0, cut + 1)
            rest = rest.substring(cut + 1)
        }
        if (rest.isNotEmpty()) out += rest
        return out
    }

    /** Phonemes to Kokoro's token ids (tokenizer.json's vocab), padded with 0 at both ends; unknown symbols dropped. */
    fun tokenize(ps: String, vocab: Map<String, Long>): LongArray {
        val ids = ArrayList<Long>(ps.length + 2)
        ids += 0L
        var i = 0
        while (i < ps.length) {
            val cp = ps.codePointAt(i)
            vocab[String(Character.toChars(cp))]?.let { ids += it }
            i += Character.charCount(cp)
        }
        ids += 0L
        return ids.toLongArray()
    }

    /** tokenizer.json's `model.vocab`. */
    fun parseVocab(text: String): Map<String, Long> {
        val root = Json.parseToJsonElement(text).jsonObject
        val vocab = (root["model"] as JsonObject)["vocab"] as JsonObject
        return vocab.mapValues { it.value.jsonPrimitive.long }
    }

    /** The words as the phoneme file keys them: printed italic marks dropped, whitespace folded. */
    fun keyOf(text: String): String = text.replace("_", "").replace(Regex("\\s+"), " ").trim()

    /** Where a voice's style row for [tokenCount] padded tokens starts in the voice table (the row is the unpadded length). */
    fun styleOffset(voiceIndex: Int, tokenCount: Int): Int {
        val n = (tokenCount - 2).coerceIn(0, ROWS - 1)
        return (voiceIndex * ROWS + n) * STYLE
    }

    fun style(table: FloatArray, voiceIndex: Int, tokenCount: Int): FloatArray {
        val at = styleOffset(voiceIndex, tokenCount)
        return table.copyOfRange(at, at + STYLE)
    }

    /** The model's speed for a part's rate and pitch: pitch is played back by sample rate, so the tempo is [rate]. */
    fun speedFor(rate: Double, pitch: Double): Float = (rate / pitch).coerceIn(0.5, 2.0).toFloat()

    /**
     * A render is played only when every sample is finite and something is louder than near-silence (fp16 renders NaN;
     * R2-kokoro-feasibility §3). Otherwise the part's system voice reads the line.
     */
    fun audible(samples: FloatArray): Boolean {
        if (samples.isEmpty()) return false
        var peak = 0f
        for (s in samples) {
            if (!s.isFinite()) return false
            val a = if (s < 0) -s else s
            if (a > peak) peak = a
        }
        return peak >= SILENCE
    }

    const val SILENCE = 1e-3f

    /** The phonemes a voice reads for one line: a British voice reads `gb` where the file has it. */
    fun phonemesFor(row: PhonemeLine, voice: Voice): String = if (voice.british) row.gb ?: row.us else row.us
}

/** One line of `phonemes/<id>.json` (contract §4.1). */
@Serializable
data class PhonemeLine(val id: String, val t: String = "", val us: String, val gb: String? = null)

@Serializable
data class PhonemeFile(val format: Int = 1, val id: String = "", val revision: String = "", val lines: List<PhonemeLine> = emptyList()) {
    companion object {
        private val json = Json { ignoreUnknownKeys = true }
        fun decode(text: String): PhonemeFile = json.decodeFromString(serializer(), text)
    }
}

/** The native model manifest (`kokoro-vN-manifest.json`, tools/publish_kokoro_model.py). */
@Serializable
data class KokoroManifest(
    val format: Int,
    val version: Int = 1,
    val name: String = "",
    val attribution: String = "",
    val voices: List<String> = emptyList(),
    val voiceShape: List<Int> = emptyList(),
    val sampleRate: Int = Kokoro.SAMPLE_RATE,
    val precision: String = "",
    val files: List<ModelFile> = emptyList(),
) {
    @Serializable
    data class ModelFile(val path: String, val role: String, val bytes: Long, val sha256: String, val license: String)

    val totalBytes: Long get() = files.sumOf { it.bytes }
    fun file(role: String): ModelFile? = files.firstOrNull { it.role == role }

    companion object {
        /** Licenses a model file may carry (tools/fetch_kokoro_model.py LICENSES): permissive only. */
        val LICENSES = setOf("Apache-2.0", "MIT", "BSD-2-Clause", "BSD-3-Clause")
        private val PATH = Regex("^[\\w.-]+$")
        private val SHA = Regex("^[0-9a-f]{64}$")
        private val json = Json { ignoreUnknownKeys = true }

        /**
         * The manifest when the app can use it: format 1, a model, a voice table and a vocabulary, each with a plain
         * file name, a size, a SHA-256 and a permissive license, the voices this app knows in its order, never fp16.
         * Throws [IllegalArgumentException] naming what is wrong.
         */
        fun accept(text: String): KokoroManifest {
            val m = runCatching { json.decodeFromString(serializer(), text) }.getOrElse { throw IllegalArgumentException("not a model manifest") }
            require(m.format == 1) { "format ${m.format}" }
            require(m.precision != "fp16") { "fp16 renders NaN" }
            for (role in listOf("model", "voices", "vocab")) requireNotNull(m.file(role)) { "no $role file" }
            for (f in m.files) {
                require(PATH.matches(f.path)) { "path ${f.path}" }
                require(f.license in LICENSES) { "${f.path}: license ${f.license} is not permissive" }
                require(SHA.matches(f.sha256)) { "${f.path}: sha256" }
                require(f.bytes > 0) { "${f.path}: size" }
            }
            require(m.voices == Kokoro.VOICES.map { it.id }) { "voices differ from the app's" }
            require(m.voiceShape == listOf(Kokoro.ROWS, Kokoro.STYLE)) { "voice shape ${m.voiceShape}" }
            require(m.file("voices")!!.bytes == Kokoro.VOICE_TABLE_BYTES) { "voice table size" }
            return m
        }
    }
}
