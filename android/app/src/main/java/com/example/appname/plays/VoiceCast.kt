package com.example.appname.plays

import java.util.Locale
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json

/**
 * The device voices' cast (PLAYS-DESIGN §2.8, Decision 076 S2), the same model as js/voice-cast.js:
 * which voice reads which part, one assignment for every player on this device (the recorder's
 * cues, the listen-through, the reader's Hear the cast), kept in this device's SharedPreferences
 * only and never synced (Q8).
 *
 * A part's casting is [VoiceCastEntry]: engine `system` (TextToSpeech), `kokoro` (the downloaded voices, S6d:
 * kokoro/KokoroReader.kt) or `none` (Not read); the voice is the engine's identifier (`Voice.getName()`, a Kokoro
 * voice id such as `af_heart`), never a language. The cast keeps only a person's choices; a part nobody cast reads its
 * Default, worked out at each read (never written) by auto-cast over the device's voice defaults (Settings > Voices,
 * Decision 086): downloaded Kokoro voices first, then the device's own, best first.
 * Auto-cast reads only the voices (quality, the person's language, a gender only where the
 * platform reports one for the VOICE, which Android never does, else the voice's measured register) and the register the
 * catalog publishes for a part (catalog DECISIONS 049); it never reads a part's name or the script's words (§2.8 rule 4).
 * No speech API here: plays/DeviceVoices.kt is the only file that touches TextToSpeech for casting.
 */
@Serializable
data class VoiceCastEntry(
    val engine: String,
    val voice: String? = null,
    val name: String? = null,
    val rate: Double = 1.0,
    val pitch: Double = 1.0,
) {
    companion object {
        const val SYSTEM = "system"
        const val KOKORO = "kokoro"
        const val NONE = "none"
        val NOT_READ = VoiceCastEntry(NONE)
    }
}

/** One engine voice as the platform reports it, before it is judged castable. */
data class RawVoice(
    val name: String,
    val localeTag: String,
    val quality: Int,
    val networkRequired: Boolean,
    val notInstalled: Boolean,
    val isDefault: Boolean = false,
    /** A stand-in for the locale's default voice (Android's `en-US-language`), not a speaker of its own (§2.8 rule 12). */
    val alias: Boolean = false,
)

/** A castable voice: [id] is the engine's stable name, [name] the label a person reads (never the raw name). */
data class CastVoice(
    val id: String,
    val name: String,
    val localeTag: String,
    val quality: Int,
    val gender: String? = null,
    val isDefault: Boolean = false,
    val engine: String = VoiceCastEntry.SYSTEM,
    /** Kokoro's own grade ("A", "C+"); null for a device voice. */
    val grade: String? = null,
    /** Kokoro's grades under C- start unticked in the defaults. */
    val offByDefault: Boolean = false,
    /** Lower or higher, measured from the voice's own pitch where the platform reports no gender (§2.8 rule 12). */
    val register: String? = null,
) {
    /** "engine:id", the key the voice defaults use. */
    val key: String get() = "$engine:$id"

    /** "High quality" as the engine reports it, only from 400 up; nothing otherwise. */
    val qualityNote: String? get() = if (quality >= HIGH_QUALITY) "High quality" else null

    companion object {
        const val HIGH_QUALITY = 400
    }
}

/** How a part is read now. */
data class Resolved(
    val read: Boolean,
    val entry: VoiceCastEntry,
    val voice: CastVoice? = null,
    val rate: Double = 1.0,
    val pitch: Double = 1.0,
    /** The cast voice's name when this device lacks it and [voice] reads instead. */
    val missing: String? = null,
    /** True when this device has no castable voice at all. */
    val none: Boolean = false,
    /** Nobody chose this part's voice: it reads its Default. */
    val isDefault: Boolean = false,
)

/** The device's voice defaults (Settings > Voices, Decision 086): `ed.voices`, this device only, never synced. */
@Serializable
data class VoiceDefaults(
    /** "engine:voice id" keys, the person's order. */
    val order: List<String> = emptyList(),
    val off: Map<String, Boolean> = emptyMap(),
    val rate: Double = 1.0,
) {
    /** A broken or out-of-range row read as the nearest sound defaults. */
    fun normalized(): VoiceDefaults = VoiceDefaults(
        order.take(400),
        off,
        if (rate.isNaN() || rate.isInfinite()) 1.0 else Math.round(rate.coerceIn(VoiceCasting.RATE.start, VoiceCasting.RATE.endInclusive) * 100) / 100.0,
    )
}

object VoiceDefaultsStore {
    const val KEY = "ed.voices"
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    fun load(store: CastStore): VoiceDefaults =
        runCatching { store.read()?.let { json.decodeFromString(VoiceDefaults.serializer(), it).normalized() } }.getOrNull() ?: VoiceDefaults()

    fun save(store: CastStore, d: VoiceDefaults) {
        runCatching { store.write(json.encodeToString(VoiceDefaults.serializer(), d.normalized())) }
    }
}

/** Where the cast is kept: one string, this device's. */
interface CastStore {
    fun read(): String?
    fun write(text: String)
}

class MemoryCastStore(var text: String? = null) : CastStore {
    override fun read() = text
    override fun write(text: String) { this.text = text }
}

@Serializable
private data class CastRow(val parts: Map<String, VoiceCastEntry> = emptyMap(), val at: Long = 0, val v: Int = 0)

object VoiceCasting {
    const val KEY = "ed.cast"
    const val KEEP = 80
    /** Rows written before Decision 086 (no `v`) wrote auto-cast in as if chosen: they read as no choice. */
    const val VERSION = 2

    /** Voices repeat on a device with few of them; pitch tells two parts on one voice apart. */
    val PITCHES = doubleArrayOf(1.0, 0.86, 1.14, 0.93, 1.07)
    val RATE = 0.5..2.0
    val PITCH = 0.5..1.5
    const val STEP = 0.1

    /** Voices made for fun, not for reading a play (macOS's novelty set): never picked by Defaults, though a person may tick one. */
    val NOVELTY = setOf(
        "albert", "bad news", "bahh", "bells", "boing", "bubbles", "cellos", "deranged", "good news", "hysterical", "jester", "organ", "superstar", "trinoids", "whisper", "wobble", "zarvox",
    )

    fun isNovelty(name: String): Boolean = name.trim().lowercase(Locale.ROOT) in NOVELTY

    private val json = Json { ignoreUnknownKeys = true }
    private val all = MapSerializer(String.serializer(), CastRow.serializer())

    fun productionKey(id: String) = "p:$id"
    fun scriptKey(id: String) = "s:$id"

    /**
     * The castable voices, best first: English, local only, installed, no locale alias beside a voice of its own locale;
     * then quality (500 down to 100), the person's own locale exactly, the system default, the name. A voice is
     * labeled by what it sounds like, from [traits] (§2.8 rule 12: "Low, warm · US"), never by a number.
     */
    fun castable(raw: List<RawVoice>, here: Locale = Locale.getDefault(), traits: Map<String, VoiceTraits> = emptyMap()): List<CastVoice> {
        val own = here.toLanguageTag().lowercase()
        val usable = raw.filter { !it.networkRequired && !it.notInstalled && languageOf(it.localeTag) == "en" }
        val named = usable.filter { !it.alias }.map { it.localeTag.lowercase() }.toSet()
        val sorted = usable
            .filter { !it.alias || it.localeTag.lowercase() !in named }
            .sortedWith(
                compareByDescending<RawVoice> { it.quality }
                    .thenByDescending { it.localeTag.replace('_', '-').lowercase() == own }
                    .thenByDescending { it.isDefault }
                    .thenBy { it.name },
            )
        val labels = VoiceLabels.labels(sorted.map { it.name to it.localeTag }, traits)
        return sorted.map { v ->
            CastVoice(v.name, labels.getValue(v.name), v.localeTag, v.quality, null, v.isDefault, offByDefault = isNovelty(v.name), register = VoiceLabels.register(traits[v.name]))
        }
    }

    private fun languageOf(tag: String) = tag.replace('_', '-').substringBefore('-').lowercase()

    private fun entryOf(v: CastVoice, pitch: Double = 1.0, rate: Double = 1.0) = VoiceCastEntry(v.engine, v.id, v.name, rate, pitch)

    /** Whether the defaults use a voice: the person's tick, else the voice's own default. */
    fun uses(v: CastVoice, d: VoiceDefaults): Boolean = d.off[v.key]?.let { !it } ?: !v.offByDefault

    /**
     * Every voice in the defaults' order: downloaded (Kokoro) before the device's own, inside each engine the person's
     * order, then the rest as [voices] gave them (best first). Nothing is left out.
     */
    fun ordered(voices: List<CastVoice>, d: VoiceDefaults): List<CastVoice> {
        val at = HashMap<String, Int>()
        d.order.forEachIndexed { i, k -> at.putIfAbsent(k, i) }
        fun engineRank(v: CastVoice) = if (v.engine == VoiceCastEntry.KOKORO) 0 else 1
        return voices.withIndex()
            .sortedWith(compareBy<IndexedValue<CastVoice>>({ engineRank(it.value) }, { at[it.value.key] ?: Int.MAX_VALUE }, { it.index }))
            .map { it.value }
    }

    /** The auto-cast pool: [ordered] less the voices the defaults leave out; never empty while a voice exists. */
    fun pool(voices: List<CastVoice>, d: VoiceDefaults): List<CastVoice> {
        val all = ordered(voices, d)
        return all.filter { uses(it, d) }.ifEmpty { all }
    }

    /** The defaults with [voice] moved one place up (-1) or down (+1) among its engine's voices. */
    fun move(voices: List<CastVoice>, d: VoiceDefaults, voice: CastVoice, by: Int): VoiceDefaults {
        val list = ordered(voices, d).filter { it.engine == voice.engine }.toMutableList()
        val i = list.indexOfFirst { it.key == voice.key }
        val j = i + by
        if (i < 0 || j < 0 || j >= list.size) return d
        java.util.Collections.swap(list, i, j)
        val keys = list.map { it.key }
        return d.copy(order = keys + d.order.filter { it !in keys })
    }

    /** A voice's kind: high for a reported female gender or a measured "higher" register, low for male or "lower". */
    fun kindOf(v: CastVoice): String? = when (v.gender) {
        "female" -> HIGH
        "male" -> LOW
        null -> when (v.register) { VoiceLabels.HIGHER -> HIGH; VoiceLabels.LOWER -> LOW; else -> null }
        else -> null
    }

    const val HIGH = "high"
    const val LOW = "low"

    /** Pitch orders (catalog/tests/golden/voice_register_cast.json): a part of a register on a voice of its kind, on one not. */
    private val MATCHED = mapOf(HIGH to listOf(1.0, 1.14, 1.07, 0.93, 0.86), LOW to listOf(1.0, 0.86, 0.93, 1.07, 1.14))
    private val BIASED = mapOf(HIGH to listOf(1.14, 1.07, 1.0, 0.93, 0.86), LOW to listOf(0.86, 0.93, 1.0, 1.07, 1.14))

    /**
     * Auto-cast (§2.8 rule 4). [parts] in cast order (largest first), [voices] best first. Speaking parts take distinct
     * voices, the best first, until every voice is used once. A part [registers] names ("high" or "low", published by the
     * catalog from the play's own print: catalog DECISIONS 049) takes the least-used voice of that kind, else of no kind
     * pitched its way, else any pitched its way; a part without one takes the least-used voice, where voices report a
     * gender (else a measured register, §2.8 rule 12) the next of the other kind. A voice used again takes the next pitch
     * not yet used on it. Directions and sound are Not read. Reads nothing of a part but its place and its register.
     */
    fun autoCast(
        parts: List<PartID>,
        voices: List<CastVoice>,
        rate: Double = 1.0,
        registers: Map<PartID, String> = emptyMap(),
    ): Map<PartID, VoiceCastEntry> {
        val out = LinkedHashMap<PartID, VoiceCastEntry>()
        val uses = IntArray(voices.size)
        val pitched = List(voices.size) { ArrayList<Double>() }
        val kinds = voices.map(::kindOf)
        val all = voices.indices.toList()
        var last: String? = null
        fun least(idx: List<Int>): Int = idx.drop(1).fold(idx[0]) { m, i -> if (uses[i] < uses[m]) i else m }
        for (id in parts) {
            if (!id.isSpeaking) { out[id] = VoiceCastEntry.NOT_READ; continue }
            if (voices.isEmpty()) continue
            val want = registers[id]?.takeIf { it == HIGH || it == LOW }
            val k = if (want != null) {
                val mine = all.filter { kinds[it] == want }
                val none = all.filter { kinds[it] == null }
                least(mine.ifEmpty { none.ifEmpty { all } })
            } else {
                val low = uses.min()
                val pool = all.filter { uses[it] == low }
                val prev = last
                (if (prev != null) pool.firstOrNull { kinds[it] != null && kinds[it] != prev } else null) ?: pool[0]
            }
            val order = when {
                want == null -> PITCHES.toList()
                kinds[k] == want -> MATCHED.getValue(want)
                else -> BIASED.getValue(want)
            }
            val pitch = order.firstOrNull { it !in pitched[k] } ?: PITCHES[pitched[k].size % PITCHES.size]
            pitched[k].add(pitch)
            uses[k] += 1
            kinds[k]?.let { last = it }
            out[id] = entryOf(voices[k], pitch, clamp(rate, RATE, 1.0))
        }
        return out
    }


    private fun clamp(x: Double, r: ClosedFloatingPointRange<Double>, d: Double): Double =
        if (x.isNaN() || x.isInfinite()) d else Math.round(x.coerceIn(r.start, r.endInclusive) * 100) / 100.0

    /** An entry as read from storage: an unknown engine, or a system entry without a voice, is no entry. */
    fun normalize(e: VoiceCastEntry?): VoiceCastEntry? {
        if (e == null) return null
        return when (e.engine) {
            VoiceCastEntry.NONE -> VoiceCastEntry.NOT_READ
            VoiceCastEntry.SYSTEM, VoiceCastEntry.KOKORO ->
                if (e.voice.isNullOrEmpty()) null
                else VoiceCastEntry(e.engine, e.voice, e.name ?: e.voice, clamp(e.rate, RATE, 1.0), clamp(e.pitch, PITCH, 1.0))
            else -> null
        }
    }

    /**
     * How a part is read now: not read (Not read, or no voice on this device), or read with a voice,
     * where [Resolved.missing] names a cast voice this device lacks and the voice is then the part's
     * auto-cast voice (§2.8 rule 8).
     */
    fun resolve(
        entry: VoiceCastEntry?,
        part: PartID,
        voices: List<CastVoice>,
        auto: Map<PartID, VoiceCastEntry>,
        downloaded: List<CastVoice> = emptyList(),
    ): Resolved {
        val chosen = normalize(entry)
        val e = chosen ?: auto[part]
        val isDefault = chosen == null
        if (e == null || e.engine == VoiceCastEntry.NONE) {
            return Resolved(false, e ?: VoiceCastEntry.NOT_READ, none = voices.isEmpty() && downloaded.isEmpty(), isDefault = isDefault)
        }
        if (voices.isEmpty() && downloaded.isEmpty()) return Resolved(false, e, none = true, isDefault = isDefault)
        val found = when (e.engine) {
            VoiceCastEntry.SYSTEM -> voices.firstOrNull { it.id == e.voice }
            VoiceCastEntry.KOKORO -> downloaded.firstOrNull { it.engine == VoiceCastEntry.KOKORO && it.id == e.voice }
            else -> null
        }
        if (found != null) return Resolved(true, e, found, e.rate, e.pitch, isDefault = isDefault)
        val a = auto[part]
        val both = voices + downloaded
        val fb = both.firstOrNull { it.id == a?.voice } ?: both.first()
        val fe = a ?: entryOf(fb)
        return Resolved(true, e, fb, e.rate, fe.pitch, missing = e.name ?: e.voice, isDefault = isDefault)
    }

    // Storage: this device only, the newest KEEP casts.

    private fun readAll(store: CastStore): MutableMap<String, CastRow> =
        runCatching { store.read()?.let { json.decodeFromString(all, it).toMutableMap() } }.getOrNull() ?: HashMap()

    private fun writeAll(store: CastStore, rows: MutableMap<String, CastRow>) {
        if (rows.size > KEEP) rows.entries.sortedBy { it.value.at }.take(rows.size - KEEP).forEach { rows.remove(it.key) }
        runCatching { store.write(json.encodeToString(all, rows)) }
    }

    fun load(key: String, store: CastStore): Map<PartID, VoiceCastEntry>? =
        readAll(store)[key]?.takeIf { it.v == VERSION }?.parts?.mapKeys { PartID(it.key) }

    fun save(key: String, parts: Map<PartID, VoiceCastEntry>, store: CastStore, now: Long = System.currentTimeMillis()) {
        val rows = readAll(store)
        rows[key] = CastRow(parts.mapKeys { it.key.raw }, now, VERSION)
        writeAll(store, rows)
    }

    fun forget(key: String, store: CastStore) {
        val rows = readAll(store)
        if (rows.remove(key) != null) writeAll(store, rows)
    }
}

/**
 * The one cast for a production (or a play): every player on this device reads parts through
 * this. [parts] in cast order; [voices] the device's own voices now (best first); [downloaded] the Kokoro voices when
 * the model is here (the Default pool is both); [seed] a key to start from (the play's cast) when this one has never
 * been made. The store holds only the person's choices: a part without one reads its Default, never written.
 */
class VoiceCast(
    val key: String,
    val parts: List<PartID>,
    private val voices: () -> List<CastVoice>,
    private val store: CastStore,
    private val seed: String? = null,
    private val clock: () -> Long = System::currentTimeMillis,
    private val downloaded: () -> List<CastVoice> = { emptyList() },
    private val defaults: () -> VoiceDefaults = { VoiceDefaults() },
    /** Each part's stand-in register where the catalog publishes one (catalog DECISIONS 049): auto-cast only, never shown. */
    val registers: Map<PartID, String> = emptyMap(),
) {
    fun voices(): List<CastVoice> = voices.invoke()

    /** The downloaded (Kokoro) voices now: none until the model is on this device. */
    fun downloadedVoices(): List<CastVoice> = downloaded.invoke()

    fun defaults(): VoiceDefaults = defaults.invoke()

    private fun chosen(): Map<PartID, VoiceCastEntry> {
        val base = VoiceCasting.load(key, store) ?: seed?.let { VoiceCasting.load(it, store) } ?: emptyMap()
        return base.mapNotNull { (k, e) -> VoiceCasting.normalize(e)?.let { k to it } }.toMap()
    }

    /** Every part's Default now: auto-cast over the defaults' pool (downloaded first), at the defaults' speed. */
    private fun auto(): Map<PartID, VoiceCastEntry> {
        val d = defaults()
        return VoiceCasting.autoCast(parts, VoiceCasting.pool(downloadedVoices() + voices(), d), d.rate, registers)
    }

    /** How [part] is read now. */
    fun resolve(part: PartID): Resolved = VoiceCasting.resolve(chosen()[part], part, voices(), auto(), downloadedVoices())

    /**
     * The system voice that reads a Kokoro part's line Kokoro cannot read (no phonemes for the play, a refused render):
     * the part's Default among the device's own voices, at the part's speed (§2.8 rule 10). Null when not read.
     */
    fun systemFallback(part: PartID): Resolved? {
        val r = resolve(part)
        val voice = r.voice
        if (!r.read || voice == null) return null
        if (voice.engine == VoiceCastEntry.SYSTEM) return r
        val v = voices()
        val d = defaults()
        val a = VoiceCasting.autoCast(parts, VoiceCasting.pool(v, d), d.rate, registers)[part]
        val fb = v.firstOrNull { it.id == a?.voice } ?: v.firstOrNull() ?: return null
        return Resolved(true, r.entry, fb, r.rate, a?.pitch ?: 1.0, isDefault = r.isDefault)
    }

    /** The part's casting now: the choice, else its Default. */
    fun entry(part: PartID): VoiceCastEntry? = chosen()[part] ?: auto()[part]

    /** The person's own choice for [part], or null when it reads its Default. */
    fun choice(part: PartID): VoiceCastEntry? = chosen()[part]

    /** What the part's Default reads now, chosen or not. */
    fun defaultEntry(part: PartID): VoiceCastEntry? = auto()[part]

    /** Merges a change into the part's choice, else into its Default entry, and keeps it as a choice. */
    @Synchronized
    fun set(part: PartID, change: VoiceCastEntry.() -> VoiceCastEntry) {
        val cast = chosen()
        val before = cast[part] ?: auto()[part] ?: VoiceCastEntry.NOT_READ
        val next = VoiceCasting.normalize(before.change()) ?: return
        VoiceCasting.save(key, cast + (part to next), store, clock())
    }

    /** Back to the Default: the part's choice is dropped. */
    @Synchronized
    fun reset(part: PartID) {
        val cast = chosen()
        if (part !in cast) return
        VoiceCasting.save(key, cast - part, store, clock())
    }

    /** Recast all: every part back to its Default. */
    @Synchronized
    fun recast() { VoiceCasting.save(key, emptyMap(), store, clock()) }
}

/** What a player sets on its engine before one utterance: the engine-wide voice, pitch and speed. */
interface VoiceSetter {
    fun setVoice(id: String): Boolean
    fun setPitch(pitch: Float)
    fun setSpeechRate(rate: Float)
}

/**
 * The one seam every player reads a part through: its cast voice, the part's speed times the
 * session's, and its pitch, set on the engine before each utterance. False when [part] is not read.
 */
fun VoiceCast.prepare(part: PartID, setter: VoiceSetter, sessionRate: Float = 1f): Boolean {
    val r = systemFallback(part) ?: return false
    val v = r.voice

    if (!r.read || v == null) return false
    if (!setter.setVoice(v.id)) return false
    setter.setPitch(r.pitch.toFloat())
    setter.setSpeechRate((r.rate * sessionRate).toFloat().coerceIn(0.1f, 10f))
    return true
}

private val PLACE = Regex("\\(([^)]+)\\)")

/**
 * A voice's name as a chip reads it: a region of several words is its initials ("English (United States) 3" is
 * "English (US) 3"), and an accent every device voice shares is dropped ("High, lively · US" is "High, lively" when
 * [soleAccent] is "US"), so the words that tell two voices apart lead a narrow chip at a large font (§2.8 rule 12).
 */
fun chipVoiceName(name: String, soleAccent: String? = null): String {
    val short = PLACE.replace(name) { m ->
        val words = m.groupValues[1].trim().split(Regex("\\s+"))
        if (words.size > 1) "(" + words.joinToString("") { it.take(1).uppercase() } + ")" else m.value
    }
    return if (soleAccent != null) short.replace(" · $soleAccent", "") else short
}

/** The accent every device voice here shares, or null when they differ (the chip then keeps it). */
fun VoiceCast.soleAccent(): String? = voices().map { VoiceLabels.accent(it.localeTag) }.distinct().singleOrNull()

/** A voice's speed as the chip and picker say it: "1.0×", "1.25×". */
fun speedText(v: Double): String {
    val twoPlaces = Math.round(v * 100) % 10 != 0L
    return String.format(Locale.US, if (twoPlaces) "%.2f×" else "%.1f×", v)
}

/** A voice's pitch in steps of 0.1 from normal: "0", "+1", "−1". */
fun pitchText(v: Double): String {
    val s = Math.round((v - 1) * 10).toInt()
    return when { s == 0 -> "0"; s > 0 -> "+$s"; else -> "−${-s}" }
}
