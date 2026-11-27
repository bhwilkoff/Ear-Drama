package com.example.appname.plays

import java.net.URI
import java.text.Normalizer
import java.util.Locale
import java.util.UUID
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull

/**
 * The Sound part without a view (B32 §3, ANDROID-DESIGN §4.17; the mirror of `js/sound-core.js`, Decision 091 on the mix): the
 * slots a script offers (its cue rows, and any line a person adds a sound to), the edits a board makes to the production's
 * `sound` block, the pack manifest reader with its rights gate, search over the pack, and the cast sheet's words. Nothing here
 * fills a slot: a slot opens empty, and only the person's act puts a sound in it (§3.1 item 4). Tests: SoundCoreTest.
 */
object SoundCore {
    val PLACEMENTS = listOf("before", "under", "after", "bed")
    val PLACEMENT_LABEL = mapOf("before" to "Before", "under" to "Under", "after" to "After", "bed" to "Bed")
    val FADES_MS = listOf(0, 200, 500, 1000, 2000)
    const val BED_FADE_IN_MS = 1500
    const val BED_FADE_OUT_MS = 2000
    const val START_STEP_MS = 100

    /** The rights gate (B32 §5.2): the only licenses a pack row may carry, and hosts never taken from. */
    val LICENSES = mapOf("CC0-1.0" to "CC0", "PDM-1.0" to "Public domain", "US-pre-1926" to "Public domain")
    val REFUSED_HOSTS = listOf("freesound.org", "sonniss.com", "bbcrewind.co.uk", "sound-effects.bbcrewind.co.uk")

    /** Said before the publish consent when a production holds an own sound (§3.4 item 3). */
    const val OWN_STAY_HOME = "Your own sounds stay on this device. The published play leaves them out."

    /** Own sounds (§3.4): a recorded one up to 30 s; a brought file up to 10 minutes and 50 MB. */
    const val OWN_RECORD_MAX_S = 30
    const val OWN_FILE_MAX_S = 600
    const val OWN_FILE_MAX_BYTES = 50L * 1024 * 1024

    /** What a slot shows: its place, the cue's own words, and what it holds. [key] is the record id once touched, else the cue row's place. */
    data class Slot(
        val key: String,
        val id: String?,
        val line: String,
        val piece: Int?,
        val added: Boolean,
        val text: String,
        val silent: Boolean,
        val sounds: List<SoundCue>,
    )

    /** The block's slots as written. */
    fun recordSlots(p: Production): List<SoundSlot> = p.sound?.slots.orEmpty()

    /**
     * Every slot the Sound part shows, in script order: each cue row (with its record slot once touched) and every added slot.
     */
    fun slotsOf(script: PlayScript, p: Production): List<Slot> {
        val at = script.lines.withIndex().associate { (i, l) -> l.id to i }
        val rec = recordSlots(p)
        val used = HashSet<String>()
        val out = ArrayList<Slot>()
        for (row in script.cueRows) {
            val s = rec.firstOrNull { !it.added && it.line == row.line && it.piece == row.piece }
            if (s != null) used += s.id
            out += view(row.line, row.piece, false, row.text, s)
        }
        for (s in rec) {
            if (s.id in used || s.line !in at) continue
            val line = script.lines[at.getValue(s.line)]
            val text = s.piece?.let { line.parts?.getOrNull(it)?.text }.orEmpty()
            out += view(s.line, s.piece, s.added, text, s)
        }
        return out.sortedWith(
            compareBy<Slot> { at.getValue(it.line) }.thenBy { if (it.added) 1_000_000_000 else (it.piece ?: -1) },
        )
    }

    private fun view(line: String, piece: Int?, added: Boolean, text: String, s: SoundSlot?) = Slot(
        key = s?.id ?: "$line:${piece ?: ""}", id = s?.id, line = line, piece = piece, added = added, text = text,
        silent = s?.silent == true, sounds = s?.sounds.orEmpty(),
    )

    private fun block(p: Production): SoundBlock = p.sound ?: SoundBlock(
        v = MixSound.VERSION,
        lanes = mapOf(
            "effects" to SoundLane(MixSound.Defaults.EFFECTS_DUCK_DB),
            "music" to SoundLane(MixSound.Defaults.MUSIC_DUCK_DB),
        ),
    )

    private fun changed(p: Production, b: SoundBlock) = p.copy(sound = b, listenedThrough = false)

    private fun newId() = UUID.randomUUID().toString().uppercase()

    /** The production with the slot in its record: the slot's id. A cue row's slot is written on first touch. */
    fun ensure(p: Production, slot: Slot): Pair<Production, String> {
        if (slot.id != null && recordSlots(p).any { it.id == slot.id }) return p to slot.id
        val b = block(p)
        val id = newId()
        return changed(p, b.copy(slots = b.slots + SoundSlot(id, slot.line, slot.piece, slot.added, false, emptyList()))) to id
    }

    /** Add a sound here (§3.1 item 3): a slot at the line's end, or the one already there. */
    fun addSlot(p: Production, lineID: String): Pair<Production, String> {
        recordSlots(p).firstOrNull { it.added && it.line == lineID }?.let { return p to it.id }
        return ensure(p, Slot("", null, lineID, null, true, "", false, emptyList()))
    }

    private fun editSlot(p: Production, slotID: String, fn: (SoundSlot) -> SoundSlot): Production {
        val b = block(p)
        if (b.slots.none { it.id == slotID }) return p
        return changed(p, b.copy(slots = b.slots.map { if (it.id == slotID) fn(it) else it }))
    }

    /** Leave silent marks an empty slot done (§3.1 item 4); a slot holding a sound is never silent. */
    fun setSilent(p: Production, slotID: String, on: Boolean): Production =
        editSlot(p, slotID) { if (!on || it.sounds.isEmpty()) it.copy(silent = on) else it }

    /** Where a sound in a cue inside a speech starts by default (§3.3), and the share of the said words before it. */
    data class Placement(val at: String, val share: Double)

    fun defaultPlacement(script: PlayScript, slot: SoundSlot): Placement {
        val line = script.lines.firstOrNull { it.id == slot.line }
        val piece = slot.piece
        if (line == null || line.kind != ScriptLine.Kind.Speech || piece == null || slot.added) return Placement("after", 0.0)
        val parts = line.parts.orEmpty()
        fun words(pc: LinePart) = if (pc is LinePart.Say) pc.text.split(Regex("\\s+")).count { it.isNotEmpty() } else 0
        val total = parts.sumOf { words(it) }
        val before = parts.take(piece).sumOf { words(it) }
        if (total == 0 || before == 0) return Placement("before", 0.0)
        if (before >= total) return Placement("after", 1.0)
        return Placement("under", before.toDouble() / total)
    }

    /**
     * Adds a sound to a slot as the person chose it. [kind] is what the source says of itself (effect, ambience, music), [take]
     * the anchor line's chosen take when there is one (an Under start is its share of the take's length).
     */
    fun addSound(p: Production, script: PlayScript, slotID: String, src: SoundSource, kind: String = "effect", take: Take? = null): Pair<Production, String?> {
        val slot = recordSlots(p).firstOrNull { it.id == slotID } ?: return p to null
        val id = newId()
        val bed = kind == "music" || kind == "ambience"
        val def = defaultPlacement(script, slot)
        val at = if (bed && def.at != "under") "bed" else def.at
        val startMs = if (at == "under" && take != null) {
            ((def.share * take.frames * 1000) / take.sampleRate / START_STEP_MS).roundToInt() * START_STEP_MS.toDouble()
        } else {
            0.0
        }
        var sound = SoundCue(id = id, src = src, at = at, startMs = startMs)
        if (at == "bed") sound = sound.copy(until = slot.line, fadeInMs = BED_FADE_IN_MS.toDouble(), fadeOutMs = BED_FADE_OUT_MS.toDouble(), loop = true)
        return editSlot(p, slotID) { it.copy(silent = false, sounds = it.sounds + sound) } to id
    }

    private fun nearest(v: Double, list: List<Int>): Double = list.minByOrNull { abs(it - v) }!!.toDouble()

    /** What a board can change about one sound; null leaves it as it is. [duck] distinguishes "set to the lane's" ([DuckLane]) from a depth. */
    data class Patch(
        val at: String? = null,
        val startMs: Double? = null,
        val gainDb: Double? = null,
        val fadeInMs: Double? = null,
        val fadeOutMs: Double? = null,
        val loop: Boolean? = null,
        val duck: Duck? = null,
        val until: String? = null,
    )

    sealed interface Duck {
        data object Lane : Duck
        data class Depth(val db: Double) : Duck
    }

    /** One sound's settings changed, each held to what the board offers (§3.2 item 2). */
    fun updateSound(p: Production, slotID: String, soundID: String, patch: Patch): Production =
        editSlot(p, slotID) { s ->
            s.copy(sounds = s.sounds.map { x -> if (x.id == soundID) apply(x, s, patch) else x })
        }

    private fun apply(old: SoundCue, slot: SoundSlot, patch: Patch): SoundCue {
        var x = old
        val to = patch.at
        if (to != null && to in PLACEMENTS && to != x.at) {
            val was = x.at
            x = x.copy(at = to)
            if (to == "bed") {
                x = x.copy(until = x.until ?: slot.line, loop = true, fadeInMs = BED_FADE_IN_MS.toDouble(), fadeOutMs = BED_FADE_OUT_MS.toDouble())
            } else {
                x = x.copy(until = null)
                if (was == "bed") x = x.copy(loop = false, fadeInMs = 0.0, fadeOutMs = 0.0)
                if (to != "under") x = x.copy(loop = false)
            }
        }
        patch.startMs?.let { x = x.copy(startMs = max(MixSound.Defaults.START_MIN_MS, (it / START_STEP_MS).roundToInt() * START_STEP_MS.toDouble())) }
        patch.gainDb?.let { x = x.copy(gainDb = min(MixSound.Defaults.GAIN_MAX_DB, max(MixSound.Defaults.GAIN_MIN_DB, it.roundToInt().toDouble()))) }
        patch.fadeInMs?.let { x = x.copy(fadeInMs = nearest(it, if (x.at == "bed") FADES_MS + BED_FADE_IN_MS else FADES_MS)) }
        patch.fadeOutMs?.let { x = x.copy(fadeOutMs = nearest(it, FADES_MS)) }
        patch.loop?.let { if (x.at == "under" || x.at == "bed") x = x.copy(loop = it) }
        when (val d = patch.duck) {
            Duck.Lane -> x = x.copy(duckDb = null)
            is Duck.Depth -> x = x.copy(duckDb = min(0.0, max(-60.0, d.db.roundToInt().toDouble())))
            null -> Unit
        }
        patch.until?.let { if (x.at == "bed") x = x.copy(until = it) }
        return x
    }

    fun removeSound(p: Production, slotID: String, soundID: String): Production =
        editSlot(p, slotID) { s -> s.copy(sounds = s.sounds.filter { it.id != soundID }) }

    /** Record slots that hold nothing are dropped (an added slot is removed when left empty, §3.1 item 3); [keep] stays. */
    fun prune(p: Production, keep: String? = null): Production {
        val b = p.sound ?: return p
        val gone = b.slots.filter { it.id != keep && !it.silent && it.sounds.isEmpty() }
        if (gone.isEmpty()) return p
        val left = b.slots.filter { it !in gone }
        return p.copy(sound = if (left.isEmpty()) null else b.copy(slots = left))
    }

    /**
     * A performed cue joins the production (B32 §3.1 item 6, round 3: a take like any line): kept as a take on the slot's line
     * with [Take.cue] naming the slot, never a line's chosen take, and placed in the slot.
     */
    fun addPerformed(p: Production, script: PlayScript, slotID: String, take: Take): Production {
        val own = take.copy(part = PartID.SOUND, cue = slotID)
        val withTake = if (p.takes.any { it.id == take.id }) p.copy(takes = p.takes.map { if (it.id == take.id) own else it }) else p.copy(takes = p.takes + own)
        return addSound(withTake, script, slotID, SoundSource(take = take.id), "effect").first
    }

    // ---- What the cast sheet and the dock say ----

    data class Summary(val cues: Int, val chosen: Int, val silent: Int, val added: Int, val beds: Int, val sounds: Int)

    fun summary(script: PlayScript, p: Production): Summary {
        val slots = slotsOf(script, p)
        val cues = slots.filter { !it.added }
        val sounds = slots.flatMap { it.sounds }
        return Summary(
            cues = cues.size, chosen = cues.count { it.sounds.isNotEmpty() }, silent = cues.count { it.silent },
            added = slots.count { it.added && it.sounds.isNotEmpty() }, beds = sounds.count { it.at == "bed" }, sounds = sounds.size,
        )
    }

    private fun num(n: Int) = String.format(Locale.US, "%,d", n)

    /** The Sound row's words on the cast sheet (§3.1 item 1). */
    fun partLine(script: PlayScript, p: Production, taken: Boolean): String {
        val m = summary(script, p)
        val beds = if (m.beds > 0) " · " + if (m.beds == 1) "1 bed" else "${num(m.beds)} beds" else ""
        if (m.cues == 0) return if (m.sounds > 0) (if (m.sounds == 1) "1 sound" else "${num(m.sounds)} sounds") + beds else "Add sounds"
        val cues = if (m.cues == 1) "1 cue" else "${num(m.cues)} cues"
        if (!taken && m.sounds == 0) return "$cues · none chosen"
        return "${num(m.chosen)} of $cues$beds"
    }

    /** The Sound card's count line on a cast sheet before anything is taken: "N cues", or "Add sounds". */
    fun cuesText(n: Int): String = if (n == 0) "Add sounds" else if (n == 1) "1 cue" else "${num(n)} cues"

    /** Stage directions read by a person (§2 item 3): "6 of 22 recorded · the rest silent". */
    fun directionsLine(script: PlayScript, p: Production): String {
        val lines = script.lines(PartID.DIRECTIONS)
        val kept = lines.count { p.usableTake(it.id) != null }
        val of = "${num(kept)} of ${num(lines.size)} recorded"
        return if (kept < lines.size) "$of · the rest silent" else of
    }

    /** "after the line · +0.0 s", the sound's place in words (§3.2 item 2). */
    fun placeLine(x: SoundCue, untilLabel: String? = null): String {
        val ms = x.startMs
        val start = (if (ms < 0) "−" else "+") + String.format(Locale.US, "%.1f", abs(ms) / 1000) + " s"
        if (x.at == "bed") return if (untilLabel != null) "bed to $untilLabel" else "bed"
        val word = mapOf("before" to "before the line", "under" to "under the line", "after" to "after the line")[x.at] ?: x.at
        return "$word · $start"
    }

    fun clock(ms: Double): String {
        val s = (ms / 1000).roundToInt()
        return "${s / 60}:${(s % 60).toString().padStart(2, '0')}"
    }

    // ---- The pack (B32 §5.2) ----

    data class Category(val id: String, val title: String, val bytes: Long)

    data class PackSource(val name: String, val page: String, val file: String?, val maker: String?)

    data class PackLicense(val id: String, val url: String?, val evidence: String, val checked: String)

    data class PackCue(
        val id: String,
        val title: String,
        val category: String,
        val tags: List<String>,
        val kind: String,
        val ms: Double,
        val loop: Boolean,
        val file: String,
        val bytes: Long,
        val sha256: String,
        val lufs: Double?,
        val peak: Double?,
        val source: PackSource,
        val license: PackLicense,
    )

    data class Refusal(val id: String?, val why: String)

    data class Pack(val pack: String, val built: String?, val categories: List<Category>, val cues: List<PackCue>, val refused: List<Refusal>)

    private fun host(u: String?): String = try { URI(u ?: "").host?.lowercase(Locale.US).orEmpty() } catch (_: Exception) { "" }

    private fun httpURL(u: String?): Boolean = u != null && Regex("^https?://", RegexOption.IGNORE_CASE).containsMatchIn(u) && host(u).isNotEmpty()

    private fun refusedHost(u: String?): Boolean {
        val h = host(u)
        return h.isNotEmpty() && REFUSED_HOSTS.any { h == it || h.endsWith(".$it") }
    }

    private fun str(o: JsonObject?, k: String): String? = (o?.get(k) as? JsonPrimitive)?.takeIf { it.isString }?.content

    private fun obj(o: JsonObject?, k: String): JsonObject? = o?.get(k) as? JsonObject

    /**
     * Reads `sounds.json`: the categories and every cue that passes the rights gate. A row whose license is not CC0-1.0, PDM-1.0
     * or US-pre-1926, that lacks an evidence URL or a checked date, comes from a refused host, or lacks its file, length or
     * checksum, is never listed; [Pack.refused] names each with why. Throws on a format this client does not read.
     */
    fun readManifest(json: JsonElement): Pack {
        val root = json as? JsonObject ?: throw IllegalArgumentException("manifest: not an object")
        val format = (root["format"] as? JsonPrimitive)?.intOrNull
        require(format == 1) { "manifest: format $format" }
        val pack = str(root, "pack")?.takeIf { it.isNotEmpty() } ?: throw IllegalArgumentException("manifest: no pack")
        val categories = (root["categories"] as? JsonArray).orEmpty().mapNotNull { c ->
            val o = c as? JsonObject
            val id = str(o, "id")
            val title = str(o, "title")
            if (id == null || title == null) null else Category(id, title, ((o?.get("bytes") as? JsonPrimitive)?.doubleOrNull ?: 0.0).toLong())
        }
        val ids = categories.map { it.id }.toSet()
        val cues = ArrayList<PackCue>()
        val refused = ArrayList<Refusal>()
        val seen = HashSet<String>()
        for (row in (root["cues"] as? JsonArray).orEmpty()) {
            val o = row as? JsonObject
            val why = refusal(o, ids, seen)
            if (why != null) {
                refused += Refusal(str(o, "id"), why)
                continue
            }
            o!!
            val id = str(o, "id")!!
            seen += id
            val src = obj(o, "source")!!
            val lic = obj(o, "license")!!
            cues += PackCue(
                id = id, title = str(o, "title")!!, category = str(o, "category")!!,
                tags = (o["tags"] as? JsonArray).orEmpty().mapNotNull { (it as? JsonPrimitive)?.content?.lowercase(Locale.US) },
                kind = str(o, "kind")?.takeIf { it in listOf("effect", "ambience", "music") } ?: "effect",
                ms = (o["ms"] as JsonPrimitive).doubleOrNull ?: 0.0,
                loop = (o["loop"] as? JsonPrimitive)?.booleanOrNull == true,
                file = str(o, "file")!!, bytes = ((o["bytes"] as? JsonPrimitive)?.doubleOrNull ?: 0.0).toLong(),
                sha256 = str(o, "sha256")!!.lowercase(Locale.US),
                lufs = (o["lufs"] as? JsonPrimitive)?.doubleOrNull, peak = (o["peak"] as? JsonPrimitive)?.doubleOrNull,
                source = PackSource(str(src, "name")!!, str(src, "page")!!, str(src, "file"), str(src, "maker")),
                license = PackLicense(str(lic, "id")!!, str(lic, "url"), str(lic, "evidence")!!, str(lic, "checked")!!),
            )
        }
        return Pack(pack, str(root, "built"), categories.filter { c -> cues.any { it.category == c.id } }, cues, refused)
    }

    private fun refusal(c: JsonObject?, cats: Set<String>, seen: Set<String>): String? {
        val id = str(c, "id")
        if (c == null || id.isNullOrEmpty()) return "no id"
        if (id in seen) return "a second row with this id"
        if (str(c, "title")?.isBlank() != false) return "no title"
        if (str(c, "category") !in cats) return "no such category"
        val lic = obj(c, "license")
        val licId = str(lic, "id")
        if (licId == null || licId !in LICENSES) return "license ${licId ?: "none"}"
        if (!httpURL(str(lic, "evidence"))) return "no evidence"
        if (str(lic, "checked")?.let { Regex("^\\d{4}-\\d{2}-\\d{2}").containsMatchIn(it) } != true) return "no checked date"
        val src = obj(c, "source")
        if (str(src, "name").isNullOrEmpty() || !httpURL(str(src, "page"))) return "no source page"
        if (listOf(str(src, "page"), str(src, "file"), str(lic, "evidence")).any { refusedHost(it) }) return "refused host ${host(str(src, "page"))}"
        val file = str(c, "file")
        if (file.isNullOrEmpty() || file.startsWith("/") || file.contains("..")) return "no file"
        if (str(c, "sha256")?.let { Regex("^[0-9a-f]{64}$", RegexOption.IGNORE_CASE).matches(it) } != true) return "no checksum"
        if (((c["ms"] as? JsonPrimitive)?.doubleOrNull ?: 0.0) <= 0.0) return "no length"
        return null
    }

    fun licenseLabel(cue: PackCue): String = LICENSES[cue.license.id].orEmpty()

    /** "0:06 · OpenGameArt · CC0", or "0:38 loop · ..." (§3.2 item 5). */
    fun cueLine(cue: PackCue): String = "${clock(cue.ms)}${if (cue.loop) " loop" else ""} · ${cue.source.name} · ${licenseLabel(cue)}"

    fun megabytes(bytes: Long): String = String.format(Locale.US, "%.1f MB", bytes / 1_048_576.0)

    private fun fold(s: String?): String = Normalizer.normalize(s.orEmpty(), Normalizer.Form.NFD).replace(Regex("\\p{Mn}+"), "").lowercase(Locale.US)

    private fun wordsOf(s: String?): List<String> = Regex("[a-z0-9]+").findAll(fold(s)).map { it.value }.toList()

    /** The search field's first words (§3.2 item 3): the first word of the cue that is a tag in the pack, else empty. */
    fun seedQuery(text: String, cues: List<PackCue>): String {
        val tags = cues.flatMap { it.tags }.toSet()
        for (w in wordsOf(text)) {
            if (w in tags) return w
            val one = w.replace(Regex("(?:es|s)$"), "")
            if (one != w && one in tags) return one
            if (w.endsWith("s") && w.dropLast(1) in tags) return w.dropLast(1)
        }
        return ""
    }

    /** Cues whose title or tags hold every word of the query (a word's start), in the pack's order; in one category when given. */
    fun search(cues: List<PackCue>, query: String, category: String? = null): List<PackCue> {
        val q = wordsOf(query)
        return cues.filter { c ->
            (category == null || c.category == category) && q.all { w ->
                val have = wordsOf(c.title) + c.tags.flatMap { wordsOf(it) }
                have.any { it.startsWith(w) || (w.length > 3 && w.endsWith("s") && it.startsWith(w.dropLast(1))) }
            }
        }
    }

    /** Own sounds by name, the same way. */
    fun <T> searchMine(mine: List<T>, query: String, name: (T) -> String): List<T> {
        val q = wordsOf(query)
        return mine.filter { m -> q.all { w -> wordsOf(name(m)).any { it.startsWith(w) } } }
    }

    /** The sources a block names, by kind. */
    data class Sources(val pack: List<String>, val own: List<String>, val take: List<String>)

    fun sources(p: Production): Sources {
        val pack = ArrayList<String>()
        val own = ArrayList<String>()
        val take = ArrayList<String>()
        for (s in recordSlots(p)) for (x in s.sounds) {
            val src = x.src
            when {
                src.pack != null -> pack += src.cue.orEmpty()
                src.own != null -> own += src.own
                src.take != null -> take += src.take
            }
        }
        return Sources(pack, own, take)
    }

    /** The block a published play may carry (§3.4 item 3): own sounds removed, a slot left holding nothing dropped unless silent. */
    fun withoutOwn(block: SoundBlock?): SoundBlock? {
        if (block == null) return null
        return block.copy(
            slots = block.slots.map { s -> s.copy(sounds = s.sounds.filter { it.src.own == null }) }.filter { it.silent || it.sounds.isNotEmpty() },
        )
    }

    /**
     * "2 sounds are on another device: Owl at night, Gate creak." (B32 §7). A timeline names a sound by its id; only a
     * person's own words for it (or a pack title) are shown.
     */
    fun missingLine(names: List<String>): String {
        val known = names.filter { it.isNotBlank() && !Regex("^[0-9A-F]{8}-[0-9A-F]{4}-", RegexOption.IGNORE_CASE).containsMatchIn(it) }
        val n = names.size
        val head = if (n == 1) "1 sound is" else "$n sounds are"
        return "$head on another device${if (known.isNotEmpty()) ": ${known.joinToString(", ")}" else ""}."
    }
}
