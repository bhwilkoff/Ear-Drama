package com.example.appname.ui

import androidx.compose.material3.ButtonDefaults
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
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
import com.example.appname.plays.PlayScript
import com.example.appname.plays.Production
import com.example.appname.ui.theme.OnAir
import com.example.appname.ui.theme.Spacing
import com.example.appname.ui.theme.genreColor
import com.example.appname.ui.theme.onBoardColor
import com.example.appname.ui.theme.onGenreColor

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
fun CastFingerprint(script: PlayScript, modifier: Modifier = Modifier, onBoard: Color? = null, height: Dp = 10.dp) {
    val speaking = remember(script) { script.castParts.filter { it.id.isSpeaking } }
    val total = remember(script) { speaking.sumOf { it.lineCount }.coerceAtLeast(1) }
    val marks = speaking.map { partMark(script, it.id) ?: MaterialTheme.colorScheme.onSurfaceVariant }
    Canvas(
        modifier
            .fillMaxWidth()
            .height(height)
            .semantics { contentDescription = "${speaking.size} parts by size" },
    ) {
        val gap = 1.dp.toPx()
        val room = size.width - gap * (speaking.size - 1).coerceAtLeast(0)
        var x = 0f
        speaking.forEachIndexed { i, part ->
            val w = maxOf(1f, room * part.lineCount / total)
            drawRect(onBoard ?: marks[i], Offset(x, 0f), Size(w, size.height))
            x += w + gap
        }
    }
}

/** The ear drama head board's mark: the cast fingerprint at the strip's place, in the board's own onBoard color. */
@Composable
fun PlayHeadBoard(script: PlayScript, kicker: String, modifier: Modifier = Modifier, title: String = script.title) {
    val facts = listOf(script.year?.toString(), script.castParts.count { it.id.isSpeaking }.let { "$it ${if (it == 1) "part" else "parts"}" }, linesFact(script.lines.size))
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
        mark = { h ->
            val on = onBoardColor(PLAY_BOARD, OnAir.colors.dark)
            Box(Modifier.height(h), contentAlignment = Alignment.BottomStart) { CastFingerprint(script, onBoard = on, height = 10.dp) }
        },
    )
}

private fun linesFact(n: Int) = String.format(java.util.Locale.US, "%,d", n) + if (n == 1) " line" else " lines"

fun lineCountText(n: Int) = if (n == 1) "1 line" else "$n lines"

/**
 * A part card: the face, the part's name in the display face, its lines, the presence strip, the
 * who line, and the verbs the page gives it. [highlight] outlines the part being recorded (a full
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
            if (who != null) Text(who, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
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
