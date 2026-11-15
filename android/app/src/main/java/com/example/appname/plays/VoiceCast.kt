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
 * voice id such as `af_heart`), never a language. Auto-cast casts system voices only, so downloading voices never
 * recasts a play; a Kokoro voice is a person's choice in the picker.
 * Auto-cast reads only the voices (quality, the person's language, a gender only where the
 * platform reports one for the VOICE, which Android never does); it never reads a part's name or
 * the script (§2.8 rule 4). No speech API here: plays/DeviceVoices.kt is the only file that
 * touches TextToSpeech for casting.
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
) {
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
)

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
private data class CastRow(val parts: Map<String, VoiceCastEntry> = emptyMap(), val at: Long = 0)

object VoiceCasting {
    const val KEY = "ed.cast"
    const val KEEP = 80

    /** Voices repeat on a device with few of them; pitch tells two parts on one voice apart. */
    val PITCHES = doubleArrayOf(1.0, 0.86, 1.14, 0.93, 1.07)
    val RATE = 0.5..2.0
    val PITCH = 0.5..1.5
    const val STEP = 0.1

    private val json = Json { ignoreUnknownKeys = true }
    private val all = MapSerializer(String.serializer(), CastRow.serializer())

    fun productionKey(id: String) = "p:$id"
    fun scriptKey(id: String) = "s:$id"

    /**
     * The castable voices, best first: English, local only, installed; then quality (500 down to
     * 100), the person's own locale exactly, the system default, the name. A voice is labelled by
     * its locale ("English (United States)"), numbered in this order when two share one.
     */
    fun castable(raw: List<RawVoice>, here: Locale = Locale.getDefault()): List<CastVoice> {
        val own = here.toLanguageTag().lowercase()
        val sorted = raw
            .filter { !it.networkRequired && !it.notInstalled && languageOf(it.localeTag) == "en" }
            .sortedWith(
                compareByDescending<RawVoice> { it.quality }
                    .thenByDescending { it.localeTag.replace('_', '-').lowercase() == own }
                    .thenByDescending { it.isDefault }
                    .thenBy { it.name },
            )
        val shared = sorted.groupingBy { it.localeTag }.eachCount()
        val seen = HashMap<String, Int>()
        return sorted.map { v ->
            val n = (seen[v.localeTag] ?: 0) + 1
            seen[v.localeTag] = n
            val place = Locale.forLanguageTag(v.localeTag.replace('_', '-')).getDisplayName(Locale.US).ifEmpty { v.localeTag }
            CastVoice(v.name, if ((shared[v.localeTag] ?: 1) > 1) "$place $n" else place, v.localeTag, v.quality, null, v.isDefault)
        }
    }

    private fun languageOf(tag: String) = tag.replace('_', '-').substringBefore('-').lowercase()

    private fun entryOf(v: CastVoice, pitch: Double = 1.0) = VoiceCastEntry(v.engine, v.id, v.name, 1.0, pitch)

    /**
     * Auto-cast (§2.8 rule 4). [parts] in cast order (largest first), [voices] best first. Speaking
     * parts take distinct voices, the best first; where voices report a gender, each next part takes
     * the best remaining voice of the other one. When voices run out the list starts again at the
     * next pitch. Directions and sound are Not read. Reads nothing of a part but its place in the list.
     */
    fun autoCast(parts: List<PartID>, voices: List<CastVoice>): Map<PartID, VoiceCastEntry> {
        val out = LinkedHashMap<PartID, VoiceCastEntry>()
        val pool = ArrayList<CastVoice>()
        var round = -1
        var last: String? = null
        for (id in parts) {
            if (!id.isSpeaking) { out[id] = VoiceCastEntry.NOT_READ; continue }
            if (voices.isEmpty()) continue
            if (pool.isEmpty()) { pool.addAll(voices); round += 1 }
            var k = 0
            if (last != null) {
                val j = pool.indexOfFirst { it.gender != null && it.gender != last }
                if (j >= 0) k = j
            }
            val v = pool.removeAt(k)
            if (v.gender != null) last = v.gender
            out[id] = entryOf(v, PITCHES[round % PITCHES.size])
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
        val e = normalize(entry) ?: auto[part]
        if (e == null || e.engine == VoiceCastEntry.NONE) return Resolved(false, e ?: VoiceCastEntry.NOT_READ, none = voices.isEmpty())
        if (voices.isEmpty()) return Resolved(false, e, none = true)
        val found = when (e.engine) {
            VoiceCastEntry.SYSTEM -> voices.firstOrNull { it.id == e.voice }
            VoiceCastEntry.KOKORO -> downloaded.firstOrNull { it.engine == VoiceCastEntry.KOKORO && it.id == e.voice }
            else -> null
        }
        if (found != null) return Resolved(true, e, found, e.rate, e.pitch)
        val a = auto[part]
        val fb = voices.firstOrNull { it.id == a?.voice } ?: voices.first()
        val fe = a ?: entryOf(fb)
        return Resolved(true, e, fb, e.rate, fe.pitch, missing = e.name ?: e.voice)
    }

    // Storage: this device only, the newest KEEP casts.

    private fun readAll(store: CastStore): MutableMap<String, CastRow> =
        runCatching { store.read()?.let { json.decodeFromString(all, it).toMutableMap() } }.getOrNull() ?: HashMap()

    private fun writeAll(store: CastStore, rows: MutableMap<String, CastRow>) {
        if (rows.size > KEEP) rows.entries.sortedBy { it.value.at }.take(rows.size - KEEP).forEach { rows.remove(it.key) }
        runCatching { store.write(json.encodeToString(all, rows)) }
    }

    fun load(key: String, store: CastStore): Map<PartID, VoiceCastEntry>? =
        readAll(store)[key]?.parts?.mapKeys { PartID(it.key) }

    fun save(key: String, parts: Map<PartID, VoiceCastEntry>, store: CastStore, now: Long = System.currentTimeMillis()) {
        val rows = readAll(store)
        rows[key] = CastRow(parts.mapKeys { it.key.raw }, now)
        writeAll(store, rows)
    }

    fun forget(key: String, store: CastStore) {
        val rows = readAll(store)
        if (rows.remove(key) != null) writeAll(store, rows)
    }
}

/**
 * The one cast for a production (or a play): every player on this device reads parts through
 * this. [parts] in cast order; [voices] the device's voices now (best first); [seed] a key to start
 * from (the play's cast) when this one has never been made.
 */
class VoiceCast(
    val key: String,
    val parts: List<PartID>,
    private val voices: () -> List<CastVoice>,
    private val store: CastStore,
    private val seed: String? = null,
    private val clock: () -> Long = System::currentTimeMillis,
    private val downloaded: () -> List<CastVoice> = { emptyList() },
) {
    fun voices(): List<CastVoice> = voices.invoke()

    /** The downloaded (Kokoro) voices now: none until the model is on this device. */
    fun downloadedVoices(): List<CastVoice> = downloaded.invoke()

    /** Fills any part without a casting by auto-cast, once there is a voice to cast; keeps every choice made. */
    @Synchronized
    private fun ensure(): Map<PartID, VoiceCastEntry> {
        val v = voices()
        val have = VoiceCasting.load(key, store)
        val base = have ?: seed?.let { VoiceCasting.load(it, store) } ?: emptyMap()
        if (v.isEmpty()) return base
        val auto = VoiceCasting.autoCast(parts, v)
        var changed = have == null
        val next = LinkedHashMap(base)
        for (id in parts) {
            if (VoiceCasting.normalize(next[id]) == null) auto[id]?.let { next[id] = it; changed = true }
        }
        if (changed) VoiceCasting.save(key, next, store, clock())
        return next
    }

    /** How [part] is read now. */
    fun resolve(part: PartID): Resolved {
        val v = voices()
        val cast = ensure()
        return VoiceCasting.resolve(cast[part], part, v, VoiceCasting.autoCast(parts, v), downloadedVoices())
    }

    /**
     * The system voice that reads a Kokoro part's line Kokoro cannot read (no phonemes for the play, a refused render):
     * the part's auto-cast system voice, at the part's speed (§2.8; R2-kokoro-feasibility §6). Null when not read.
     */
    fun systemFallback(part: PartID): Resolved? {
        val r = resolve(part)
        val voice = r.voice
        if (!r.read || voice == null) return null
        if (voice.engine == VoiceCastEntry.SYSTEM) return r
        val v = voices()
        val a = VoiceCasting.autoCast(parts, v)[part]
        val fb = v.firstOrNull { it.id == a?.voice } ?: v.firstOrNull() ?: return null
        return Resolved(true, r.entry, fb, r.rate, a?.pitch ?: 1.0)
    }

    fun entry(part: PartID): VoiceCastEntry? = VoiceCasting.normalize(ensure()[part])

    /** Merges a change into the part's casting and keeps it at once. */
    @Synchronized
    fun set(part: PartID, change: VoiceCastEntry.() -> VoiceCastEntry) {
        val cast = ensure()
        val before = VoiceCasting.normalize(cast[part]) ?: VoiceCastEntry.NOT_READ
        val next = VoiceCasting.normalize(before.change()) ?: return
        VoiceCasting.save(key, cast + (part to next), store, clock())
    }

    /** Recast all: auto-cast again over the voices on this device now. */
    @Synchronized
    fun recast() {
        val v = voices()
        if (v.isNotEmpty()) VoiceCasting.save(key, VoiceCasting.autoCast(parts, v), store, clock())
    }
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
 * "English (US) 3"), so the part that tells two voices apart (the number) is still there on a narrow chip and a large font.
 */
fun chipVoiceName(name: String): String = PLACE.replace(name) { m ->
    val words = m.groupValues[1].trim().split(Regex("\\s+"))
    if (words.size > 1) "(" + words.joinToString("") { it.take(1).uppercase() } + ")" else m.value
}

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
