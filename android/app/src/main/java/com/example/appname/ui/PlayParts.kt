package com.example.appname.ui

import androidx.compose.material3.ButtonDefaults
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.example.appname.plays.CastPart
import com.example.appname.plays.PartID
import com.example.appname.plays.PartState
import com.example.appname.plays.PlayListing
import com.example.appname.plays.PlayRow
import com.example.appname.plays.PlayScript
import com.example.appname.plays.Production
import com.example.appname.ui.theme.OnAir
import com.example.appname.ui.theme.Spacing
import com.example.appname.ui.theme.genreColor
import com.example.appname.ui.theme.boardColor
import com.example.appname.ui.theme.onBoardColor
import com.example.appname.ui.theme.onGenreColor
import androidx.compose.ui.text.font.FontWeight
import com.example.appname.data.Artwork
import com.example.appname.data.ItemLead
import com.example.appname.data.LabelItem
import com.example.appname.data.LabelKind

// An ear drama in direction D's grammar (ANDROID-DESIGN §4.9a, PLAYS-DESIGN §2): a play stands on the
// drama board, a part's face and strip carry its hue, the cast fingerprint fills the mark slot.

/** The outlined button of wayfinding (blue, ink and red are the other two roles): Cue, With cue, Take part, Discard the run. */
@Composable
fun wayColors() = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.primary)

/** The board every play stands on: scripts carry no genre, but every castable script is a play, and the genre is never named on screen. */
const val PLAY_BOARD = "drama"

/** Who holds a part: a person, who may or may not have given a name, or the device voice. */
sealed interface Holder {
    data class Person(val name: String?) : Holder
    data object DeviceVoice : Holder
}

fun holderOf(production: Production, part: PartID): Holder {
    val state = production.state(part)
    return when (state.status) {
        PartState.Status.Recording, PartState.Status.Done -> Holder.Person(state.performer)
        PartState.Status.Open, PartState.Status.Silent -> Holder.DeviceVoice
    }
}

/** The part's mark color in this mode, or null for neutral. */
@Composable
fun partMark(script: PlayScript, part: PartID): Color? = genreColor(script.partHue(part), OnAir.colors.dark)

/** What stands on the part's mark: the glyph color the palette pairs with it. */
@Composable
private fun onPartMark(script: PlayScript, part: PartID): Color? = script.partHue(part)?.let { onGenreColor(it, OnAir.colors.dark) }

/**
 * A part's face: a filled circle in its mark color (surface and muted text for the neutral parts),
 * the performer's initial when a person holds it, a waveform glyph in a dashed ring for the device
 * voice, and a check when it is recorded. Hidden from accessibility, as the card or row around it speaks.
 */
@Composable
fun PartFace(script: PlayScript, part: PartID, holder: Holder, recorded: Boolean, modifier: Modifier = Modifier, size: Dp = 32.dp) {
    val mark = partMark(script, part)
    val on = onPartMark(script, part)
    val neutral = MaterialTheme.colorScheme.surfaceContainerHigh
    val muted = MaterialTheme.colorScheme.onSurfaceVariant
    Box(modifier.size(size).clearAndSetSemantics {}, contentAlignment = Alignment.Center) {
        when (holder) {
            is Holder.Person -> {
                Box(Modifier.size(size).clip(CircleShape).background(mark ?: neutral), contentAlignment = Alignment.Center) {
                    val initial = holder.name?.trim()?.firstOrNull()?.uppercase()
                    if (initial != null) {
                        Text(initial, style = MaterialTheme.typography.headlineSmall, color = on ?: muted, maxLines = 1)
                    } else {
                        Icon(Icons.Filled.Person, contentDescription = null, tint = on ?: muted, modifier = Modifier.size(size * 0.6f))
                    }
                }
            }
            Holder.DeviceVoice -> {
                val ring = mark ?: muted
                Canvas(Modifier.size(size)) {
                    val stroke = 1.5.dp.toPx()
                    drawCircle(
                        ring,
                        radius = (this.size.minDimension - stroke) / 2f,
                        style = Stroke(stroke, pathEffect = PathEffect.dashPathEffect(floatArrayOf(3.dp.toPx(), 2.5f.dp.toPx()))),
                    )
                }
                Icon(Icons.Filled.GraphicEq, contentDescription = null, tint = ring, modifier = Modifier.size(size * 0.5f))
            }
        }
        if (recorded) {
            Box(
                Modifier
                    .align(Alignment.BottomEnd)
                    .offset(x = 3.dp, y = 3.dp)
                    .size(size * 0.46f)
                    .clip(CircleShape)
                    .background(MaterialTheme.colorScheme.surface),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.Check, contentDescription = null, tint = OnAir.colors.link, modifier = Modifier.size(size * 0.3f))
            }
        }
    }
}

/**
 * Where a part speaks: [PlayScript.PRESENCE_BINS] bars across the script, each as tall as the part's share of
 * that stretch's lines (against the part's busiest stretch), in the part's mark; a silent stretch is a hairline.
 */
@Composable
fun PresenceStrip(script: PlayScript, part: PartID, modifier: Modifier = Modifier, height: Dp = 18.dp) {
    val shares = remember(script, part) { script.presence(part) }
    val mark = partMark(script, part) ?: MaterialTheme.colorScheme.onSurfaceVariant
    val rest = MaterialTheme.colorScheme.outline
    Canvas(
        modifier
            .fillMaxWidth()
            .height(height)
            .semantics { contentDescription = "Where ${part.title} speaks" },
    ) {
        val gap = 1.dp.toPx()
        val width = (size.width - gap * (shares.size - 1)) / shares.size
        val peak = shares.max().coerceAtLeast(0.001f)
        shares.forEachIndexed { i, share ->
            val x = i * (width + gap)
            if (share <= 0f) {
                drawRect(rest, Offset(x, size.height - 1.dp.toPx()), Size(width, 1.dp.toPx()))
            } else {
                val h = maxOf(3.dp.toPx(), size.height * share / peak)
                drawRect(mark, Offset(x, size.height - h), Size(width, h))
            }
        }
    }
}

/**
 * The cast fingerprint: one bar, each speaking part a segment whose width is its share of the play's
 * lines, largest first, with a 1 px gap between. On a board it is the board's one onBoard color ([onBoard]);
 * off a board ([onBoard] null) each segment is its part's mark.
 */
@Composable
fun CastFingerprint(script: PlayListing, modifier: Modifier = Modifier, onBoard: Color? = null, height: Dp = 10.dp) {
    val speaking = script.cast
    val total = remember(script) { speaking.sum().coerceAtLeast(1) }
    val dark = OnAir.colors.dark
    val marks = speaking.indices.map { genreColor(PlayScript.PART_HUES.getOrNull(it), dark) ?: MaterialTheme.colorScheme.onSurfaceVariant }
    Canvas(
        modifier
            .fillMaxWidth()
            .height(height)
            .semantics { contentDescription = "${speaking.size} parts by size" },
    ) {
        val gap = 1.dp.toPx()
        val room = size.width - gap * (speaking.size - 1).coerceAtLeast(0)
        var x = 0f
        speaking.forEachIndexed { i, lines ->
            val w = maxOf(1f, room * lines / total)
            drawRect(onBoard ?: marks[i], Offset(x, 0f), Size(w, size.height))
            x += w + gap
        }
    }
}

private const val CAST_SHOWN = 7

/**
 * The cast window (Decision 075): a play's picture slot draws its cast, one bar per speaking part,
 * largest first up to seven, stacked top to bottom, each as wide as its lines over the largest
 * part's (at least 6 %), the first thicker, all in the board's one onBoard color; "+N" at the
 * bottom right when there are more. It replaces the monogram wherever a play wears a window.
 */
@Composable
fun CastWindow(script: PlayListing, modifier: Modifier = Modifier) {
    val parts = script.cast
    val shown = parts.take(CAST_SHOWN)
    val most = (parts.firstOrNull() ?: 1).coerceAtLeast(1)
    val on = onBoardColor(PLAY_BOARD, OnAir.colors.dark)
    val shape = RoundedCornerShape(4.dp)
    Box(
        modifier
            .clip(shape)
            .background(boardColor(PLAY_BOARD, OnAir.colors.dark))
            .border(1.dp, on.copy(alpha = 0.32f), shape)
            .clearAndSetSemantics {},
    ) {
        Canvas(Modifier.fillMaxSize()) {
            if (shown.isEmpty()) return@Canvas
            val pad = size.width * 0.12f
            val room = size.height - pad * 2
            // The first bar is 1.6 units thick, the rest 1, with 0.7 between.
            val unit = room / (1.6f + (shown.size - 1) + 0.7f * (shown.size - 1))
            var y = pad
            shown.forEachIndexed { i, lines ->
                val h = if (i == 0) unit * 1.6f else unit
                val w = (size.width - pad * 2) * maxOf(0.06f, lines.toFloat() / most)
                drawRect(on, Offset(pad, y), Size(w, h))
                y += h + unit * 0.7f
            }
        }
        if (parts.size > shown.size) {
            Text(
                "+${parts.size - shown.size}",
                style = MaterialTheme.typography.labelMedium,
                color = on,
                modifier = Modifier.align(Alignment.BottomEnd).padding(end = 6.dp, bottom = 4.dp),
            )
        }
    }
}

/** The ear drama head board's mark: the cast fingerprint at the strip's place, in the board's own onBoard color. */
@Composable
fun PlayHeadBoard(script: PlayListing, kicker: String, modifier: Modifier = Modifier, title: String = script.title) {
    val facts = listOf(
        script.year?.toString(),
        script.cast.size.let { "$it ${if (it == 1) "part" else "parts"}" },
        (script as? PlayScript)?.let { linesFact(it.lines.size) },
    )
    HeadBoard(
        name = title,
        genre = PLAY_BOARD,
        art = null,
        kicker = kicker,
        facts = facts,
        first = null,
        last = null,
        modifier = modifier,
        credits = script.authorWithYears.ifEmpty { null },
        window = { m -> CastWindow(script, m) },
        mark = { h ->
            val on = onBoardColor(PLAY_BOARD, OnAir.colors.dark)
            Box(Modifier.height(h), contentAlignment = Alignment.BottomStart) { CastFingerprint(script, onBoard = on, height = 10.dp) }
        },
    )
}

/**
 * The play page's head (WEB-DESIGN §6.4g): its title page, else its author's portrait, at their own shape; else its opening drawn
 * as a page at tier L, the voice bands at its foot. The production's board keeps [PlayHeadBoard].
 */
@Composable
fun PlayPageHead(
    script: PlayListing,
    kicker: String,
    modifier: Modifier = Modifier,
    titlePage: Artwork? = null,
    authorArt: Artwork? = null,
    production: Artwork? = null,
    /** The library's index row for this play (B31 §3.5): the head is then on the form's board with a picture of the play, else its title page or portrait, else its label. */
    row: PlayRow? = null,
) {
    if (row != null) {
        val voices = script.voices
        ItemHeadBoard(
            name = script.title,
            genre = row.hue,
            label = row.labelItem,
            modifier = modifier,
            art = row.pageLead,
            kicker = { ink -> TextKicker(com.example.appname.plays.FindCore.kicker(row.kind, row.form, row.oneAct), ink) },
            facts = listOf(script.year?.toString(), "$voices ${if (voices == 1) "voice" else "voices"}", "About ${script.minutes} min"),
            credits = script.authorWithYears.ifEmpty { row.authorLine }.ifEmpty { null }?.let { if (row.attributed) "Attributed to $it" else it },
            mark = { h ->
                val on = onBoardColor(row.hue, OnAir.colors.dark)
                Box(Modifier.height(h), contentAlignment = Alignment.BottomStart) { CastFingerprint(script, onBoard = on, height = 10.dp) }
            },
        )
        return
    }
    val lead = ItemLead.playLead(titlePage, authorArt, production)
    val facts = listOf(
        script.year?.toString(),
        script.cast.size.let { "$it ${if (it == 1) "part" else "parts"}" },
        (script as? PlayScript)?.let { linesFact(it.lines.size) },
    )
    val label = LabelItem(LabelKind.Play, voices = script.voices, opening = true)
    ItemHeadBoard(
        name = script.title,
        genre = PLAY_BOARD,
        label = label,
        modifier = modifier,
        art = lead,
        kicker = { ink -> TextKicker(kicker, ink) },
        facts = facts,
        credits = script.authorWithYears.ifEmpty { null },
        mark = { h ->
            val on = onBoardColor(PLAY_BOARD, OnAir.colors.dark)
            Box(Modifier.height(h), contentAlignment = Alignment.BottomStart) { CastFingerprint(script, onBoard = on, height = 10.dp) }
        },
        customWindow = if (ItemLead.shown(lead) == null) { m -> PlayOpeningWindow(script, label, m) } else null,
    )
}

/** A play's opening drawn as a page: the first speeches in body type on the script's ground, the voice bands at its foot. */
@Composable
fun PlayOpeningWindow(script: PlayListing, label: LabelItem, modifier: Modifier = Modifier, count: Int = 4) {
    val speeches = remember(script, count) { PlayScript.openingOf(script, count) }
    val ink = remember { LabelPalette(false) }.let { if (OnAir.colors.dark) LabelPalette(true).color("brand.text") else it.color("brand.text") }
    Box(modifier.clip(RoundedCornerShape(4.dp))) {
        LabelArt(label, Modifier.fillMaxSize())
        Column(
            Modifier.fillMaxSize().padding(start = Spacing.S3.dp, end = Spacing.S3.dp, top = Spacing.S3.dp, bottom = Spacing.S6.dp),
            verticalArrangement = Arrangement.spacedBy(Spacing.S2.dp),
        ) {
            speeches.forEach { speech ->
                Column {
                    Text(speech.name, style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.SemiBold), color = ink, maxLines = 1)
                    Text(speech.text, style = MaterialTheme.typography.bodySmall, color = ink, maxLines = 2, overflow = TextOverflow.Ellipsis)
                }
            }
        }
    }
}

private fun linesFact(n: Int) = String.format(java.util.Locale.US, "%,d", n) + if (n == 1) " line" else " lines"

fun lineCountText(n: Int) = if (n == 1) "1 line" else "$n lines"

/**
 * A part card: the face, the part's name in the display face, its lines, the presence strip, the
 * who line (or [whoSlot], a part's voice chip, in its place), and the verbs the page gives it. [highlight] outlines the part being recorded (a full
 * outline, never a one-sided stripe).
 */
@Composable
fun PartCard(
    script: PlayScript,
    part: CastPart,
    holder: Holder,
    recorded: Boolean,
    modifier: Modifier = Modifier,
    who: String? = null,
    highlight: Boolean = false,
    whoSlot: (@Composable () -> Unit)? = null,
    actions: (@Composable () -> Unit)? = null,
) {
    val shape = RoundedCornerShape(12.dp)
    Surface(
        modifier
            .semantics(mergeDescendants = true) {
                contentDescription = listOfNotNull(part.title, lineCountText(part.lineCount), who).joinToString(", ")
            },
        shape = shape,
        color = MaterialTheme.colorScheme.surfaceContainer,
        border = if (highlight) BorderStroke(2.dp, OnAir.colors.play) else null,
    ) {
        Column(Modifier.fillMaxHeight().padding(Spacing.S3.dp), verticalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
                PartFace(script, part.id, holder, recorded)
                Text(
                    part.title.uppercase(),
                    style = MaterialTheme.typography.headlineSmall,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            Text(lineCountText(part.lineCount), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            PresenceStrip(script, part.id)
            if (whoSlot != null) whoSlot() else if (who != null) Text(who, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
            if (actions != null) {
                Spacer(Modifier.weight(1f))
                Column(verticalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) { actions() }
            }
        }
    }
}

/**
 * The parts as a grid of cards, two across on a phone and three from 840 dp, each row as tall as its tallest card.
 * [card] draws one part's card into the slot it is given.
 */
@Composable
fun PartGrid(parts: List<CastPart>, modifier: Modifier = Modifier, card: @Composable (CastPart, Modifier) -> Unit) {
    BoxWithConstraints(modifier.fillMaxWidth()) {
        val columns = if (maxWidth >= 840.dp) 3 else 2
        Column(Modifier.padding(horizontal = Spacing.S4.dp), verticalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
            parts.chunked(columns).forEach { row ->
                Row(Modifier.fillMaxWidth().height(IntrinsicSize.Max), horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
                    row.forEach { part -> card(part, Modifier.weight(1f).fillMaxHeight()) }
                    repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
                }
            }
        }
    }
}
