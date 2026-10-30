package com.example.appname.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.appname.data.DayYears
import com.example.appname.data.DecadeField
import com.example.appname.data.DisplayVocabulary
import com.example.appname.data.GENRE_ORDER
import com.example.appname.data.SeriesRow
import com.example.appname.data.fieldSide
import com.example.appname.ui.theme.OnAir
import com.example.appname.ui.theme.Spacing
import com.example.appname.ui.theme.boardColor
import com.example.appname.ui.theme.onBoardColor
import java.text.NumberFormat
import java.util.Locale

// Home's day board and Browse's decade field (ANDROID-DESIGN R11c; WEB-DESIGN §6.4c), drawn in the
// genre mark colors from the generated tokens.

private val Thousands: NumberFormat = NumberFormat.getIntegerInstance(Locale.US)

fun formatCount(n: Int): String = Thousands.format(n)

/** A show tile and what it opens: [facts] replace the years and episode count (a night's tile reads its episode). */
data class TileSpec(val key: String, val series: SeriesRow, val facts: List<String>? = null, val openLabel: String = "Open series", val onOpen: () -> Unit)

/** The columns and the tile width a content width holds: tiles of about 152 dp, two at least, six at most. */
fun tileLayout(available: Dp): Pair<Int, Dp> {
    val inner = available - Spacing.S4.dp * 2
    val gap = Spacing.S2.dp
    val cols = ((inner + gap) / (TILE_WIDTH_DP.dp + gap)).toInt().coerceIn(2, 6)
    return cols to (inner - gap * (cols - 1)) / cols
}

/** A page of show tiles in a plain grid, for a screen section that is not itself a lazy grid; a row shares its tallest name. */
@Composable
fun TileGrid(tiles: List<TileSpec>, modifier: Modifier = Modifier) {
    BoxWithConstraints(modifier.fillMaxWidth()) {
        val (cols, tileWidth) = tileLayout(maxWidth)
        val heights = rememberNameHeights(tiles.map { it.series.name }, innerWidth(tileWidth))
        Column(Modifier.padding(horizontal = Spacing.S4.dp), verticalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
            tiles.chunked(cols).forEachIndexed { r, chunk ->
                val nameHeight = (0 until chunk.size).maxOf { heights[r * cols + it] }
                Row(horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
                    chunk.forEach { t ->
                        ShowTile(
                            t.series,
                            onOpen = t.onOpen,
                            width = tileWidth,
                            nameHeight = nameHeight,
                            facts = t.facts,
                            openLabel = t.openLabel,
                        )
                    }
                }
            }
        }
    }
}

/** A section's heading with a plain fact or link at its right edge. */
@Composable
fun SectionHeading(title: String, modifier: Modifier = Modifier, trailing: (@Composable () -> Unit)? = null) {
    Row(
        modifier.fillMaxWidth().padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            title,
            style = MaterialTheme.typography.headlineSmall,
            modifier = Modifier.weight(1f, fill = false).semantics { heading() },
        )
        if (trailing != null) {
            Spacer(Modifier.width(Spacing.S3.dp))
            trailing()
        }
    }
}

/** A link in running text: the blue of wayfinding, one line. */
@Composable
fun TextLink(text: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    Text(
        text,
        style = MaterialTheme.typography.bodyMedium,
        color = OnAir.colors.link,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
        modifier = modifier.clickable(role = Role.Button, onClick = onClick).padding(vertical = Spacing.S2.dp).tvFocusMark(),
    )
}

@Composable
private fun genreColors(): Map<String, Color> = GENRE_ORDER.associateWith { OnAir.genre(it) ?: Color.Gray }

@Composable
private fun Swatch(color: Color, size: Dp = 10.dp) {
    Box(Modifier.size(size).clip(RoundedCornerShape(2.dp)).background(color))
}

/**
 * The day board: the kicker, the big date, the facts, the years strip (one bar per year, stacked
 * by genre, on one fixed axis from 1930 to the last year; the [selected] year outlined, a tap
 * selects) and the legend of the genres seen.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun DayBoard(date: String, data: DayYears, selected: Int?, onSelect: (Int) -> Unit, modifier: Modifier = Modifier) {
    val dark = OnAir.colors.dark
    val ground = boardColor(null, dark)
    val on = onBoardColor(null, dark)
    val colors = genreColors()
    val t = MaterialTheme.typography
    val first = minOf(1930, data.years.firstOrNull()?.year ?: 1930)
    val last = data.years.lastOrNull()?.year ?: first
    val byYear = remember(data) { data.years.associateBy { it.year } }
    val most = data.years.maxOfOrNull { it.total } ?: 1
    val barHeight = 64.dp
    Column(
        modifier.fillMaxWidth().padding(horizontal = Spacing.S4.dp).clip(RoundedCornerShape(12.dp)).background(ground).padding(Spacing.S4.dp),
        verticalArrangement = Arrangement.spacedBy(Spacing.S2.dp),
    ) {
        Text("THIS DAY IN RADIO", style = t.labelMedium.copy(letterSpacing = 1.sp), color = on)
        Text(date, style = nameStyle(0, t, headL1 = true), color = on, modifier = Modifier.semantics { heading() })
        EventLine(listOf("${formatCount(data.count)} surviving broadcasts", "${data.years.size} years"), color = on)
        Row(Modifier.fillMaxWidth().height(barHeight).padding(top = Spacing.S2.dp)) {
            for (year in first..last) {
                val y = byYear[year]
                val isSel = year == selected
                Box(
                    Modifier
                        .weight(1f)
                        .height(barHeight)
                        .then(
                            if (y != null) {
                                Modifier
                                    .semantics { contentDescription = "$year, ${y.total} ${if (y.total == 1) "broadcast" else "broadcasts"}" + if (isSel) ", selected" else "" }
                                    .clickable(role = Role.Button, onClickLabel = "Show $year") { onSelect(year) }
                            } else Modifier,
                        )
                        .drawBehind {
                            val slot = size.width
                            val gap = slot * 0.2f
                            val w = slot - gap
                            val line = 1.dp.toPx()
                            if (y == null) {
                                drawRect(on.copy(alpha = 0.3f), Offset(gap / 2, size.height - line), Size(w, line))
                                return@drawBehind
                            }
                            val room = size.height - 4.dp.toPx()
                            var top = size.height
                            for (g in GENRE_ORDER + "") {
                                val n = y.genres[g] ?: continue
                                val h = n.toFloat() / most * room
                                top -= h
                                drawRect(if (g.isEmpty()) on.copy(alpha = 0.55f) else colors.getValue(g), Offset(gap / 2, top), Size(w, h))
                            }
                            if (isSel) {
                                val pad = 1.5.dp.toPx()
                                drawRect(
                                    on,
                                    Offset(gap / 2 - pad, top - pad),
                                    Size(w + pad * 2, size.height - top + pad),
                                    style = Stroke(1.5.dp.toPx()),
                                )
                            }
                        },
                )
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text("$first", style = t.labelMedium, color = on)
            if (selected != null) Text("$selected", style = t.labelMedium.copy(fontWeight = FontWeight.Bold), color = on)
            Text("$last", style = t.labelMedium, color = on)
        }
        FlowRow(horizontalArrangement = Arrangement.spacedBy(Spacing.S3.dp), verticalArrangement = Arrangement.spacedBy(Spacing.S1.dp)) {
            data.genres.forEach { g ->
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.S1.dp)) {
                    Swatch(colors.getValue(g))
                    Text(DisplayVocabulary.genreName(g) ?: g, style = t.labelMedium, color = on, maxLines = 1)
                }
            }
        }
    }
}

/**
 * Browse's decade by genre field: a square per cell in the genre's mark color, sized by
 * [fieldSide], the count under it. A non-empty cell applies its genre and decade; the cell that
 * matches [genre] and [decade] is outlined.
 */
@Composable
fun DecadeFieldView(
    field: DecadeField,
    genre: String?,
    decade: Int?,
    onCell: (String, Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = genreColors()
    val t = MaterialTheme.typography
    val rowHeight = 52.dp
    Column(modifier.fillMaxWidth()) {
        Row(Modifier.fillMaxWidth()) {
            Spacer(Modifier.width(LabelWidth))
            field.decades.forEach { d ->
                Text("${d}s", style = t.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, modifier = Modifier.weight(1f), textAlign = TextAlign.Center)
            }
        }
        field.genres.forEach { g ->
            val name = DisplayVocabulary.genreName(g) ?: g
            Row(Modifier.fillMaxWidth().height(rowHeight), verticalAlignment = Alignment.CenterVertically) {
                Row(Modifier.width(LabelWidth), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.S1.dp)) {
                    Swatch(colors.getValue(g))
                    Text(name, style = t.bodyMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                field.decades.forEach { d ->
                    val n = field.count(g, d)
                    val side = fieldSide(n, field.max)
                    val picked = g == genre && d == decade
                    Box(
                        Modifier
                            .weight(1f)
                            .height(rowHeight)
                            .then(
                                if (n > 0) {
                                    Modifier
                                        .semantics { contentDescription = "$name, ${d}s: $n ${if (n == 1) "show" else "shows"}" + if (picked) ", selected" else "" }
                                        .clickable(role = Role.Button, onClickLabel = "Filter to $name, ${d}s") { onCell(g, d) }
                                } else Modifier,
                            )
                            .then(if (picked) Modifier.border(BorderStroke(2.dp, MaterialTheme.colorScheme.onSurface), RoundedCornerShape(6.dp)) else Modifier)
                            .tvFocusMark(),
                        contentAlignment = Alignment.Center,
                    ) {
                        if (n > 0) {
                            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                Box(Modifier.size(side.dp).clip(RoundedCornerShape(2.dp)).background(colors.getValue(g)))
                                Text(formatCount(n), style = t.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
                            }
                        }
                    }
                }
            }
        }
    }
}

private val LabelWidth = 128.dp
