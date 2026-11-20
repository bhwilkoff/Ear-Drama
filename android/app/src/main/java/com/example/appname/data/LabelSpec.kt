package com.example.appname.data

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull
import kotlin.math.PI
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

// The label (Decision 081, WEB-DESIGN 6.4r): the drawn art of anything without a picture, as a pure
// spec with no views, the web's `LabelCore.labelSpec` (js/label-core.js) with the same golden cases
// (catalog/tests/golden/label_spec.json). Every mark is a fact the item's published fields hold; nothing
// is hashed or random, and an undated show draws no arc. The geometry is design-tokens.json `art.label`
// (LabelTokens.kt is generated). Angles are degrees, 0 at three o'clock, counterclockwise positive; the
// dial runs clockwise, so an arc's `from` is larger than its `to`. Colors are token references
// (board.mystery, brand.text) that LabelDrawing resolves.

enum class LabelKind(val key: String) { Series("series"), Episode("episode"), Station("station"), Drama("drama"), Person("person"), Play("play") }

data class LabelPart(val lines: Int, val hue: String?)

data class LabelItem(
    val kind: LabelKind = LabelKind.Series,
    val name: String? = null,
    val genre: String? = null,
    val first: String? = null,
    val last: String? = null,
    val network: String? = null,
    val tickYear: String? = null,
    val date: String? = null,
    val num: String? = null,
    val parts: List<LabelPart> = emptyList(),
    val finished: String? = null,
    val voices: Int = 0,
    val opening: Boolean = false,
    val cast: List<Int> = emptyList(),
)

@Serializable data class LabelDisc(val r: Double, val opacity: Double)
@Serializable data class LabelGrooves(val radii: List<Double>, val width: Double, val opacity: Double)
@Serializable data class LabelTicks(val r0: Double, val r1: Double, val width: Double, val opacity: Double, val deg: List<Double>)
@Serializable data class LabelArc(val r: Double, val width: Double, val from: Double, val to: Double, val capFrom: String, val capTo: String)
@Serializable data class LabelEvening(val deg: Double, val r0: Double, val r1: Double, val width: Double)
@Serializable data class LabelSegment(val from: Double, val to: Double, val color: String)
@Serializable data class LabelBacking(val color: String, val width: Double)
@Serializable data class LabelParts(val r: Double, val width: Double, val backing: LabelBacking, val segments: List<LabelSegment>)
@Serializable data class LabelRing(val r: Double, val width: Double, val opacity: Double)
@Serializable data class LabelDot(val r: Double)
@Serializable data class LabelText(val s: String, val face: String, val size: Double, val x: Double, val y: Double, val anchor: String, val fill: String)
@Serializable data class LabelRim(val text: String, val r: Double, val size: Double, val tracking: Double, val opacity: Double, val centerDeg: Double)
@Serializable data class LabelRules(
    val count: Int, val x0: Double, val y: Double, val len: Double, val gap: Double, val width: Double, val opacity: Double, val foot: Double,
)
@Serializable data class LabelBar(val x: Double, val y: Double, val w: Double, val h: Double)
@Serializable data class LabelCast(val bars: List<LabelBar>)

@Serializable
data class LabelSpec(
    val kind: String,
    val shape: String,
    val tier: String,
    val viewBox: Double,
    val ground: String,
    val on: String,
    val disc: LabelDisc? = null,
    val grooves: LabelGrooves? = null,
    val ticks: LabelTicks? = null,
    val arc: LabelArc? = null,
    val evening: LabelEvening? = null,
    val parts: LabelParts? = null,
    val ring: LabelRing? = null,
    val label: LabelDot? = null,
    val text: List<LabelText> = emptyList(),
    val rim: LabelRim? = null,
    val rules: LabelRules? = null,
    val cast: LabelCast? = null,
) {
    companion object {
        fun isFull(from: Double, to: Double): Boolean = from - to >= 359.99

        /** What the label draws for [item] in a window [size] dp on a side (the size picks the tier). */
        fun make(item: LabelItem, size: Double): LabelSpec {
            val tier = LabelMath.tierOf(size)
            return when (item.kind) {
                LabelKind.Person -> LabelMath.person(item, tier)
                LabelKind.Play -> LabelMath.play(item, tier)
                else -> LabelMath.disc(item, tier, item.kind)
            }
        }

        /** The spec as JSON, the shape of the golden file's `want`. */
        fun toJson(spec: LabelSpec): JsonElement = LabelMath.json.encodeToJsonElement(serializer(), spec)
    }
}

private class Node(val v: JsonElement?) {
    operator fun get(k: String) = Node((v as? JsonObject)?.get(k))
    fun d(tier: String? = null): Double {
        val o = v as? JsonObject
        if (o != null) return tier?.let { (o[it] as? JsonPrimitive)?.doubleOrNull } ?: 0.0
        return (v as? JsonPrimitive)?.doubleOrNull ?: 0.0
    }
    val s: String get() = (v as? JsonPrimitive)?.content ?: ""
    val list: List<Node> get() = (v as? JsonArray)?.map { Node(it) } ?: emptyList()
    fun glyph(ch: String): Double {
        val o = v as? JsonObject
        return ((o?.get(ch) ?: o?.get("default")) as? JsonPrimitive)?.doubleOrNull ?: 0.0
    }
}

internal object LabelMath {
    val json = Json { encodeDefaults = true; explicitNulls = true }
    private val T = Node(Json.parseToJsonElement(LabelTokens.JSON))
    private val MONTHS = listOf("JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC")

    private fun r2(v: Double): Double = floor(v * 100 + 0.5) / 100
    fun tierOf(size: Double): String = if (size >= T["tiers"]["L"].d()) "L" else if (size >= T["tiers"]["M"].d()) "M" else "S"
    private fun digits(s: String, from: Int, n: Int): Boolean = s.length >= from + n && s.substring(from, from + n).all { it in '0'..'9' }
    private fun yearOf(d: String?): Int? = if (d != null && digits(d, 0, 4)) d.substring(0, 4).toInt() else null
    private fun known(g: String?): Boolean = g != null && g in LabelTokens.genres
    private fun groundOf(g: String?) = if (known(g)) "board.$g" else T["colors"]["groundNone"].s
    private fun onOf(g: String?) = if (known(g)) "onBoard.$g" else T["colors"]["onNone"].s

    private val slot: Double get() = T["dial"]["sweepDeg"].d() / (T["dial"]["to"].d() - T["dial"]["from"].d() + 1)
    private fun yearDeg(y: Double) = T["dial"]["startDeg"].d() - (y - T["dial"]["from"].d()) * slot
    private fun clampYear(y: Int) = min(T["dial"]["to"].d(), max(T["dial"]["from"].d(), y.toDouble()))
    private fun offDial(y: Int) = y < T["dial"]["from"].d() || y > T["dial"]["to"].d()

    private fun runArc(first: String?, last: String?, r: Double, width: Double): LabelArc? {
        val a = yearOf(first) ?: return null
        var b = yearOf(last) ?: a
        if (b < a) b = a
        return LabelArc(r, width, r2(yearDeg(clampYear(a))), r2(yearDeg(clampYear(b) + 1)),
            if (offDial(a)) "butt" else "round", if (offDial(b)) "butt" else "round")
    }

    private fun cap(face: String) = T["glyphs"][face]["cap"].d()
    private fun em(s: String, face: String): Double =
        s.codePoints().toArray().sumOf { T["glyphs"][face].glyph(String(Character.toChars(it))) + T["glyphs"]["tracking"].d() }
    private fun fit(s: String, face: String, maxW: Double, maxCap: Double) = min(maxCap / cap(face), maxW / max(em(s, face), 0.01))

    private data class Line(val s: String, val face: String)

    private fun centered(lines: List<Line>, boxW: Double, boxH: Double, fill: String): List<LabelText> {
        val ls = lines.filter { it.s.isNotEmpty() }
        if (ls.isEmpty()) return emptyList()
        if (ls.size == 1) {
            val l = ls[0]
            val size = fit(l.s, l.face, boxW, boxH)
            return listOf(LabelText(l.s, l.face, r2(size), 50.0, r2(50 + size * cap(l.face) / 2), "middle", fill))
        }
        val (sm, bg) = ls
        val sSize = min(boxH * T["label"]["small"].d(), boxW / max(em(sm.s, sm.face), 0.01))
        val hs = sSize * cap(sm.face)
        val gap = hs * T["label"]["lead"].d()
        val bSize = fit(bg.s, bg.face, boxW, boxH - hs - gap)
        val hb = bSize * cap(bg.face)
        val top = 50 - (hs + gap + hb) / 2
        return listOf(
            LabelText(sm.s, sm.face, r2(sSize), 50.0, r2(top + hs), "middle", fill),
            LabelText(bg.s, bg.face, r2(bSize), 50.0, r2(top + hs + gap + hb), "middle", fill),
        )
    }

    private class Ymd(val y: String, val mo: Int, val day: Int)

    private fun ymd(s: String?): Ymd? {
        if (s == null || yearOf(s) == null) return null
        val parts = s.split("-")
        fun two(i: Int): Int = if (parts.size > i && digits(parts[i], 0, 2)) parts[i].substring(0, 2).toInt() else 0
        val mo = two(1)
        return Ymd(s.substring(0, 4), mo, if (mo > 0) two(2) else 0)
    }

    private fun episodeLines(date: String?, num: String?, tier: String): List<Line>? {
        val m = ymd(date)
        val yy = m?.let { "’" + it.y.takeLast(2) } ?: ""
        val hasNum = !num.isNullOrEmpty()
        if (m != null) {
            if (tier == "S") return listOf(Line(yy, "display"))
            if (m.mo in 1..12 && m.day > 0) return listOf(Line("${MONTHS[m.mo - 1]} $yy", "body"), Line(m.day.toString(), "display"))
            if (m.mo in 1..12) return listOf(Line(yy, "body"), Line(MONTHS[m.mo - 1], "display"))
            return listOf(Line(m.y, "display"))
        }
        if (hasNum && tier == "S") return listOf(Line("No.$num", "display"))
        if (hasNum) return listOf(Line("No.", "body"), Line(num.orEmpty(), "display"))
        return null
    }

    private fun rimOf(text: String?): LabelRim? {
        if (text.isNullOrEmpty()) return null
        val rim = T["rim"]
        val maxLen = PI * rim["r"].d() * rim["maxSweepDeg"].d() / 180
        val perEm = em(text, "body") + text.codePointCount(0, text.length) * rim["tracking"].d()
        return LabelRim(text, rim["r"].d(), r2(min(rim["size"].d(), maxLen / perEm)), rim["tracking"].d(), rim["opacity"].d(), 90.0)
    }

    private fun grooves(tier: String): LabelGrooves? {
        if (tier == "S") return null
        val g = T["grooves"]
        val to = g["to"].d(tier)
        val step = g["step"].d(tier)
        val radii = mutableListOf<Double>()
        var i = 0
        while (g["from"].d() + i * step <= to + 1e-9) { radii += r2(g["from"].d() + i * step); i++ }
        return LabelGrooves(radii, g["width"].d(), g["opacity"].d())
    }

    fun disc(it: LabelItem, tier: String, kind: LabelKind): LabelSpec {
        val g = if (known(it.genre)) it.genre!! else if (kind == LabelKind.Drama) "drama" else ""
        val labelR = T["label"]["r"].d(tier)
        val dialed = kind != LabelKind.Drama
        val ticks = if (dialed && tier != "S") T["ticks"].let { k ->
            LabelTicks(k["r0"].d(), k["r1"].d(), k["width"].d(), k["opacity"].d(), T["dial"]["ticks"].list.map { y -> r2(yearDeg(y.d())) })
        } else null
        val arc = if (kind == LabelKind.Series || kind == LabelKind.Episode) runArc(it.first, it.last, T["arc"]["r"].d(tier), T["arc"]["width"].d(tier)) else null
        val ty = yearOf(it.tickYear)
        val evening = if (dialed && ty != null) T["evening"].let { e ->
            LabelEvening(r2(yearDeg(clampYear(ty)) - slot / 2), e["r0"].d(), e["r1"].d(), e["width"].d(tier))
        } else null
        var parts: LabelParts? = null
        if (kind == LabelKind.Drama) {
            val ps = it.parts.filter { p -> p.lines > 0 }
            val total = ps.sumOf { p -> p.lines }.toDouble()
            if (ps.isNotEmpty()) {
                val w = T["parts"]["width"].d(tier)
                val gap = if (ps.size > 1) T["parts"]["gapDeg"].d() else 0.0
                var a = T["parts"]["startDeg"].d()
                val segs = ps.map { p ->
                    val d = p.lines / total * 360
                    val seg = LabelSegment(r2(a), r2(a - max(d - gap, d / 2)), if (known(p.hue)) "genre.${p.hue}" else T["colors"]["partNone"].s)
                    a -= d
                    seg
                }
                parts = LabelParts(T["parts"]["r"].d(tier), w, LabelBacking(T["colors"]["partsBacking"].s, r2(w + T["parts"]["backing"].d())), segs)
            }
        }
        val box = 2 * labelR
        var lines = if (kind == LabelKind.Episode) episodeLines(it.date, it.num, tier) else null
        if (lines == null) lines = if (kind == LabelKind.Station && it.name.isNullOrEmpty()) emptyList() else listOf(Line(monogram(it.name), "display"))
        val text = centered(lines, box * T["label"]["fitW"].d(), box * T["label"]["fitH"].d(), "ground")
        var rim: LabelRim? = null
        if (tier == "L") {
            if (kind == LabelKind.Drama) {
                val m = ymd(it.finished)
                if (m != null && m.mo in 1..12 && (it.finished?.length ?: 0) >= 7) rim = rimOf("RECORDED · ${MONTHS[m.mo - 1]} ${m.y}")
            } else if (kind != LabelKind.Station) {
                val words = listOfNotNull(it.network?.takeIf { n -> n.isNotEmpty() }?.uppercase(), yearOf(it.first)?.let { y -> "${y / 10 * 10}s" })
                rim = rimOf(words.joinToString(" · "))
            }
        }
        return LabelSpec(kind.key, "square", tier, T["viewBox"].d(), groundOf(g), onOf(g),
            disc = LabelDisc(T["disc"]["r"].d(), T["disc"]["opacity"].d()), grooves = grooves(tier), ticks = ticks, arc = arc,
            evening = evening, parts = parts, label = LabelDot(labelR), text = text, rim = rim)
    }

    fun person(it: LabelItem, tier: String): LabelSpec {
        val g = if (known(it.genre)) it.genre else null
        val box = 2 * T["person"]["fitR"].d()
        val ring = T["person"]["ring"]
        return LabelSpec("person", "circle", tier, T["viewBox"].d(), groundOf(g), onOf(g),
            arc = if (tier == "L") runArc(it.first, it.last, T["person"]["arc"]["r"].d(), T["person"]["arc"]["width"].d()) else null,
            ring = LabelRing(ring["r"].d(), ring["width"].d(tier), ring["opacity"].d()),
            text = centered(listOf(Line(monogram(it.name), "display")), box * T["label"]["fitW"].d(), box * T["label"]["fitH"].d(), "on"))
    }

    fun play(it: LabelItem, tier: String): LabelSpec {
        val p = T["play"]
        if (it.opening) {
            val bands = p["bands"].list.map { b -> b.d() }
            val v = it.voices.toDouble()
            val count = if (v <= 0) 0 else if (v <= bands[0]) 1 else if (v <= bands[1]) 2 else if (v <= bands[2]) 3 else 4
            val r = p["rule"]
            return LabelSpec("play", "square", tier, T["viewBox"].d(), T["colors"]["playGround"].s, T["colors"]["playInk"].s,
                rules = if (count > 0) LabelRules(count, r["x0"].d(), r["y"].d(), r["len"].d(), r["gap"].d(), r["width"].d(), r["opacity"].d(), r["foot"].d()) else null)
        }
        val c = p["cast"]
        val g = p["board"].s
        val all = it.cast.filter { n -> n > 0 }
        val shown = all.take(c["max"].d().toInt())
        val most = (shown.firstOrNull() ?: 1).toDouble()
        val total = if (shown.isEmpty()) 0.0 else c["hFirst"].d() + (shown.size - 1) * (c["h"].d() + c["gap"].d())
        var y = 50 - total / 2
        val bars = shown.mapIndexed { i, n ->
            val h = if (i > 0) c["h"].d() else c["hFirst"].d()
            val pct = max(c["minW"].d(), (100 * n / most).roundToInt().toDouble())
            val bar = LabelBar(c["x"].d(), r2(y), r2(c["w"].d() * pct / 100), h)
            y += h + c["gap"].d()
            bar
        }
        val more = all.size - shown.size
        val m = c["more"]
        return LabelSpec("play", "square", tier, T["viewBox"].d(), groundOf(g), onOf(g),
            cast = if (bars.isEmpty()) null else LabelCast(bars),
            text = if (more > 0) listOf(LabelText("+$more", "body", m["size"].d(), m["x"].d(), m["y"].d(), "end", "on")) else emptyList())
    }
}

/** The show's label: its run on the dial and, at the large tier, its network. */
fun SeriesRow.labelItem(): LabelItem = LabelItem(LabelKind.Series, name, genre, firstDate, lastDate, networks.firstOrNull())

/** The episode's own label: its show's disc with this broadcast's date on it (its number when undated). */
fun EpisodeRow.labelItem(series: SeriesRow? = null): LabelItem = LabelItem(
    LabelKind.Episode, seriesName, seriesGenre, series?.firstDate, series?.lastDate, network ?: series?.networks?.firstOrNull(),
    date = airDate, num = num?.toString(),
)
