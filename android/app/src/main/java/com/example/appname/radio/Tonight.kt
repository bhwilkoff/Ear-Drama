package com.example.appname.radio

import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json

// Tonight in 19xx (docs/CATALOG-CONTRACT.md §8): the evenings are published;
// the client only reads the clock. Mirrors js/api.js (localDate, tonight,
// onAir) and apple/Core/Radio/Tonight.swift, so every platform puts the same
// slot on the air at the same instant.

/** An ISO 8601 instant ("2026-10-22T23:00:00Z"), the file's own. */
object InstantSerializer : KSerializer<Instant> {
    override val descriptor = PrimitiveSerialDescriptor("Instant", PrimitiveKind.STRING)
    override fun deserialize(decoder: Decoder): Instant = Instant.parse(decoder.decodeString())
    override fun serialize(encoder: Encoder, value: Instant) = encoder.encodeString(value.toString())
}

/** `tonight.json`: evenings keyed by the listener's own calendar date. */
@Serializable
data class TonightFile(
    val zone: String,
    val days: Map<String, TonightDay> = emptyMap(),
) {
    /** The evening published for [date] (YYYY-MM-DD, the person's own), or null. */
    fun day(date: String): TonightDay? = days[date]

    companion object {
        private val json = Json { ignoreUnknownKeys = true }
        fun decode(text: String): TonightFile = json.decodeFromString(serializer(), text)
    }
}

@Serializable
data class TonightDay(
    /** The broadcast evening, YYYY-MM-DD. */
    val evening: String,
    val network: String? = null,
    val station: String? = null,
    val witness: Witness? = null,
    val slots: List<RadioSlot> = emptyList(),
    /** Decision 067: the same date's other published years, each a whole evening on tonight's clock. */
    val years: List<TonightDay> = emptyList(),
) {
    /** This evening and the date's other published years, oldest first: what a listener may pick between. */
    val choices: List<TonightDay> get() = (listOf(this) + years).sortedBy { it.evening }

    @Serializable
    data class Witness(val paper: String? = null, val url: String? = null, val via: String? = null)

    /** "1942" from the evening's date. */
    val year: String get() = evening.take(4)

    /** "CBS · WJSV". */
    val stationLine: String?
        get() = listOfNotNull(network, station).filter { it.isNotEmpty() }.joinToString(" · ").ifEmpty { null }

    /** "Washington Post, via JJ's Newspaper Radio Logs": the credit, without the parenthesized host. */
    val witnessLine: String?
        get() {
            val w = witness ?: return null
            if (w.url.isNullOrEmpty()) return null
            val paper = w.paper ?: "newspaper listing"
            val via = w.via?.takeIf { it.isNotEmpty() } ?: return paper
            return "$paper, via ${via.replace(Regex("""\s*\(.*\)$"""), "")}"
        }
}

/**
 * One slot of the evening: an episode the catalog serves, or a gap stated as
 * a gap (R9): its time and, when the listing matched a series, that series'
 * name. The newspaper's printed text is never drawn (Decision 067); the file
 * no longer carries it, and this type never decoded it.
 */
@Serializable
data class RadioSlot(
    @SerialName("et_start") val etStart: String,
    @SerialName("et_end") val etEnd: String,
    @SerialName("length_min") val lengthMin: Int,
    @Serializable(with = InstantSerializer::class) @SerialName("utc_start") val utcStart: Instant,
    @Serializable(with = InstantSerializer::class) @SerialName("utc_end") val utcEnd: Instant,
    val episode: Episode? = null,
    val gap: Boolean = false,
    @SerialName("known_series") val knownSeries: String? = null,
    val withheld: Boolean = false,
) {
    @Serializable
    data class Episode(
        val id: String,
        val series: String,
        val title: String? = null,
        @SerialName("length_s") val lengthS: Double? = null,
    )

    /** The episode this slot may play: never a gap, never a withheld slot. */
    val playableEpisode: Episode? get() = if (gap || withheld) null else episode
}

/** The one clock (R10, R14): where an evening stands at an instant. */
object RadioClock {
    enum class Phase { Before, During, After }

    /** [index] is the slot whose instants hold now; null outside the evening. */
    data class OnAir(val phase: Phase, val index: Int?)

    /** The person's own calendar date, YYYY-MM-DD, in the device's time zone. */
    fun localDate(now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): String =
        now.atZone(zone).toLocalDate().toString()

    /** js/api.js `onAir`: every instant is the file's own; nothing is computed from a time zone here. */
    fun onAir(slots: List<RadioSlot>, now: Instant): OnAir {
        val first = slots.firstOrNull() ?: return OnAir(Phase.After, null)
        if (now < first.utcStart) return OnAir(Phase.Before, null)
        if (now >= end(slots)!!) return OnAir(Phase.After, null)
        val index = slots.indexOfFirst { it.utcStart <= now && now < it.utcEnd }
        return OnAir(Phase.During, index.takeIf { it >= 0 })
    }

    /** The last slot's end: the evening is over then, and nothing plays after. */
    fun end(slots: List<RadioSlot>): Instant? = slots.maxOfOrNull { it.utcEnd }

    /**
     * Seconds into the recording where the clock stands, or null when the
     * recording already ended inside its slot (within its last 5 seconds).
     */
    fun liveOffset(slot: RadioSlot, recordingLength: Double?, now: Instant): Double? {
        val at = (now.toEpochMilli() - slot.utcStart.toEpochMilli()) / 1000.0
        val length = recordingLength ?: slot.episode?.lengthS ?: (slot.lengthMin * 60).toDouble()
        if (at >= length - 5) return null
        return at.coerceAtLeast(0.0)
    }

    /** Why a slot holds no episode: a recording this catalog does not serve, or none that survives. */
    fun gapNote(slot: RadioSlot): String =
        if (slot.withheld || slot.episode != null) "Not in the catalog" else "Not surviving"

    /**
     * A slot's time as the listener reads it: local time, with the paper's
     * Eastern time beside it as a fact, or "7:00 PM ET" alone where the two agree.
     */
    fun timeLabel(
        slot: RadioSlot,
        zone: String,
        local: ZoneId = ZoneId.systemDefault(),
        locale: Locale = Locale.getDefault(),
    ): Pair<String, String?> {
        val here = clock(slot.utcStart, local, locale)
        val eastern = runCatching { clock(slot.utcStart, ZoneId.of(zone), locale) }.getOrNull()
        if (here == eastern) return "$here ET" to null
        return here to "${printedClock(slot.etStart, locale)} ET"
    }

    /** "7:00 PM" (or "19:00" where the locale says so) at an instant in a zone. */
    fun clock(at: Instant, zone: ZoneId = ZoneId.systemDefault(), locale: Locale = Locale.getDefault()): String =
        DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withLocale(locale).format(at.atZone(zone))

    /** The paper's "19:30" drawn in the listener's clock style. */
    fun printedClock(hhmm: String, locale: Locale = Locale.getDefault()): String {
        val parts = hhmm.split(":").mapNotNull { it.toIntOrNull() }
        if (parts.size != 2) return hhmm
        val time = runCatching { LocalTime.of(parts[0], parts[1]) }.getOrNull() ?: return hhmm
        return DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withLocale(locale).format(time)
    }

    /** "Thursday, October 22, 1942" for the evening's date. */
    fun longDate(evening: String, locale: Locale = Locale.getDefault()): String =
        runCatching {
            DateTimeFormatter.ofLocalizedDate(FormatStyle.FULL).withLocale(locale).format(LocalDate.parse(evening))
        }.getOrDefault(evening)
}
