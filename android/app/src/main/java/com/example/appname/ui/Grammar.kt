package com.example.appname.ui

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.Typography
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.ColorMatrix
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.FirstBaseline
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.LineBreak
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil3.compose.AsyncImage
import com.example.appname.data.Artwork
import com.example.appname.data.Grade
import com.example.appname.data.SeriesRow
import com.example.appname.data.WindowFill
import com.example.appname.data.blockSize
import com.example.appname.data.dateBlockParts
import com.example.appname.data.eventParts
import com.example.appname.data.gradeOf
import com.example.appname.data.monogram
import com.example.appname.data.nameStep
import com.example.appname.data.runBars
import com.example.appname.data.runSpan
import com.example.appname.data.windowFill
import com.example.appname.ui.theme.DisplayFontFamily
import com.example.appname.ui.theme.OnAir
import com.example.appname.ui.theme.PrintEdgeDark
import com.example.appname.ui.theme.PrintEdgeLight
import com.example.appname.ui.theme.PrintGroundDark
import com.example.appname.ui.theme.PrintGroundLight
import com.example.appname.ui.theme.Spacing
import com.example.appname.ui.theme.boardColor
import com.example.appname.ui.theme.onBoardColor
import kotlin.math.roundToInt

// One grammar for every level of content (WEB-DESIGN §6.4b, ANDROID-DESIGN R11b): each object has
// one skeleton of fixed slots; richer data fills more slots and never adds, moves or resizes one.

private val WindowShape = RoundedCornerShape(4.dp)

@Composable
private fun board(genre: String?): Color = boardColor(genre, OnAir.colors.dark)

@Composable
private fun onBoard(genre: String?): Color = onBoardColor(genre, OnAir.colors.dark)

/** A 1 dp hairline drawn over the content, inside the shape. */
private fun Modifier.hairline(color: Color): Modifier = drawWithContent {
    drawContent()
    val inset = 0.5.dp.toPx()
    drawRoundRect(
        color,
        topLeft = Offset(inset, inset),
        size = Size(size.width - 2 * inset, size.height - 2 * inset),
        cornerRadius = CornerRadius(4.dp.toPx() - inset),
        style = Stroke(1.dp.toPx()),
    )
}

/**
 * The grade a picture takes (`uniform-imagery-design` §2): saturation 0 (Rec. 709 luminance), then
 * `k * v + o`, in sRGB; written as the one matrix those two steps make.
 */
fun gradeMatrix(g: Grade): ColorMatrix {
    val k = g.k.toFloat()
    val o = (g.o * 255).toFloat()
    val r = 0.2126f * k
    val gr = 0.7152f * k
    val b = 0.0722f * k
    return ColorMatrix(
        floatArrayOf(
            r, gr, b, 0f, o,
            r, gr, b, 0f, o,
            r, gr, b, 0f, o,
            0f, 0f, 0f, 1f, 0f,
        ),
    )
}

/** The title block: the monogram as an outline in the board's onBoard color, on the board. */
@Composable
fun TitleBlock(name: String, genre: String?, modifier: Modifier = Modifier) {
    val on = onBoard(genre)
    val m = remember(name) { monogram(name) }
    BoxWithConstraints(
        modifier
            .clip(WindowShape)
            .background(board(genre))
            .hairline(on.copy(alpha = 0.32f))
            .clearAndSetSemantics {},
    ) {
        val side = maxWidth
        val density = LocalDensity.current
        val style = TextStyle(
            fontFamily = DisplayFontFamily,
            fontWeight = FontWeight.Bold,
            fontSize = with(density) { (side * blockSize(m) / 100f).toSp() },
            color = on,
            drawStyle = Stroke(width = with(density) { 1.4.dp.toPx() }),
        )
        Text(
            m,
            style = style,
            softWrap = false,
            maxLines = 1,
            modifier = Modifier.layout { measurable, c ->
                val p = measurable.measure(Constraints())
                val base = p[FirstBaseline]
                layout(c.maxWidth, c.maxHeight) {
                    p.place((0.09f * c.maxWidth).roundToInt(), (0.93f * c.maxHeight).roundToInt() - base)
                }
            },
        )
    }
}

/**
 * The window: one square slot on the print ground with a hairline. [windowFill] decides what it
 * holds: the picture cropped around its face, a wide picture whole inside a 6 % inset, or the
 * [TitleBlock] (no picture, one under the size floor, or one that failed to load). The caller
 * sizes it; it is hidden from accessibility, as the row or tile around it speaks.
 */
@Composable
fun PictureWindow(art: Artwork?, name: String, genre: String?, modifier: Modifier = Modifier) {
    BoxWithConstraints(modifier) {
        val side = maxWidth
        val fill = remember(art, side) { windowFill(art, side.value) }
        var failed by remember(art) { mutableStateOf(false) }
        if (art == null || fill is WindowFill.Block || failed) {
            TitleBlock(name, genre, Modifier.fillMaxSize())
            return@BoxWithConstraints
        }
        val dark = OnAir.colors.dark
        val filter = remember(art) { ColorFilter.colorMatrix(gradeMatrix(gradeOf(art))) }
        Box(
            Modifier
                .fillMaxSize()
                .clip(WindowShape)
                .background(if (dark) PrintGroundDark else PrintGroundLight)
                .hairline(if (dark) PrintEdgeDark else PrintEdgeLight)
                .clearAndSetSemantics {},
        ) {
            when (fill) {
                is WindowFill.Crop -> ArtImage(
                    art, side, Modifier.fillMaxSize(),
                    colorFilter = filter, onError = { failed = true },
                )
                else -> {
                    val pixels = with(LocalDensity.current) { (side * 0.88f).roundToPx() }
                    AsyncImage(
                        model = art.url(pixels),
                        contentDescription = null,
                        contentScale = ContentScale.Fit,
                        colorFilter = filter,
                        onError = { failed = true },
                        modifier = Modifier.fillMaxSize().padding(side * 0.06f),
                    )
                }
            }
        }
    }
}

/**
 * The run strip: the years from the first to the last broadcast as a solid bar on one fixed
 * 1930 to 1962 axis, over a baseline at 30 %; an undated show is the baseline alone.
 */
@Composable
fun RunStrip(
    first: String?,
    last: String?,
    color: Color,
    modifier: Modifier = Modifier,
    height: Dp = 18.dp,
    years: List<Int>? = null,
) {
    val bars = remember(years) { runBars(years) }
    val span = remember(first, last, bars) { if (bars == null) runSpan(first, last) else null }
    Box(
        modifier
            .fillMaxWidth()
            .height(height)
            .clearAndSetSemantics {}
            .drawWithContent {
                val line = 1.dp.toPx()
                drawRect(color.copy(alpha = 0.3f), Offset(0f, size.height - line), Size(size.width, line))
                if (bars != null) {
                    val room = size.height - line - 2.dp.toPx()
                    bars.forEach { b ->
                        val h = maxOf(2.dp.toPx(), room * b.height.toFloat())
                        drawRect(
                            color,
                            Offset((b.from * size.width).toFloat(), size.height - line - h),
                            Size(maxOf(1f, ((b.to - b.from) * size.width).toFloat() - 0.5.dp.toPx()), h),
                        )
                    }
                } else if (span != null) {
                    val top = size.height * 3f / 18f
                    drawRect(
                        color,
                        Offset((span.from * size.width).toFloat(), top),
                        Size(((span.to - span.from) * size.width).toFloat(), size.height - top),
                    )
                }
            },
    )
}

/** Facts joined by " ·", each separator kept with the fact before it, so a line never opens on a dot. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun EventLine(
    facts: List<Any?>,
    modifier: Modifier = Modifier,
    color: Color = MaterialTheme.colorScheme.onSurfaceVariant,
    style: TextStyle = MaterialTheme.typography.labelMedium,
    maxLines: Int = 2,
) {
    val parts = remember(facts) { eventParts(facts) }
    if (parts.isEmpty()) return
    FlowRow(modifier, horizontalArrangement = Arrangement.spacedBy(4.dp), maxLines = maxLines) {
        parts.forEach { Text(it, style = style, color = color, maxLines = 1, overflow = TextOverflow.Ellipsis) }
    }
}

/** A name's style on a tile or head board: L2 in Big Shoulders, one level down (L3's size) or two (L5's) for a long word. */
fun nameStyle(step: Int, t: Typography, headL1: Boolean = false): TextStyle {
    val base = if (headL1) t.displaySmall else t.headlineSmall
    val size = when (step) {
        0 -> base.fontSize
        1 -> if (headL1) t.headlineSmall.fontSize else t.titleMedium.fontSize
        else -> if (headL1) t.titleMedium.fontSize else t.labelMedium.fontSize
    }
    return base.copy(fontSize = size, lineBreak = LineBreak.Heading)
}

private fun nameText(name: String) = name.uppercase()

/** The tile's name height for the tallest name in a shelf, so every strip below sits on one line. */
@Composable
fun rememberNameHeight(names: List<String>, width: Dp): Dp {
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    val typography = MaterialTheme.typography
    return remember(names, width, typography, density) {
        val px = with(density) { width.roundToPx() }
        val tallest = names.maxOfOrNull { n ->
            measurer.measure(
                nameText(n),
                nameStyle(nameStep(n), typography),
                constraints = Constraints(maxWidth = px),
            ).size.height
        } ?: 0
        with(density) { tallest.toDp() }
    }
}

/** Each name's height at [width], one per name, so a grid row can share its tallest. */
@Composable
fun rememberNameHeights(names: List<String>, width: Dp): List<Dp> {
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    val typography = MaterialTheme.typography
    return remember(names, width, typography, density) {
        val px = with(density) { width.roundToPx() }
        names.map { n ->
            with(density) {
                measurer.measure(nameText(n), nameStyle(nameStep(n), typography), constraints = Constraints(maxWidth = px)).size.height.toDp()
            }
        }
    }
}

const val TILE_WIDTH_DP = 152
private val TileWidth = TILE_WIDTH_DP.dp
private val TileWidthTv = 200.dp
private val TilePad = 6.dp

/** The width a tile's window and name have inside its padding. */
fun innerWidth(width: Dp) = width - TilePad * 2

/**
 * The show tile: on the genre's board (the neutral surface for no genre), the window, the name,
 * the run strip and the facts, each in its own slot. [nameHeight] is the tallest name in the
 * shelf ([ShowShelf] measures it), so the strips of a row of tiles sit on one line.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun ShowTile(
    row: SeriesRow,
    onOpen: () -> Unit,
    modifier: Modifier = Modifier,
    width: Dp = TileWidth,
    nameHeight: Dp? = null,
    facts: List<String>? = null,
    openLabel: String = "Open series",
    onLongClick: (() -> Unit)? = null,
) {
    val on = onBoard(row.genre)
    val style = nameStyle(nameStep(row.name), MaterialTheme.typography)
    Column(
        modifier
            .width(width)
            .tvFocusMark()
            .clip(RoundedCornerShape(12.dp))
            .background(board(row.genre))
            .combinedClickable(
                onClickLabel = openLabel,
                onClick = onOpen,
                onLongClickLabel = if (onLongClick != null) "Unfollow" else null,
                onLongClick = onLongClick,
            )
            .padding(start = TilePad, top = TilePad, end = TilePad, bottom = 10.dp),
    ) {
        PictureWindow(row.windowArt, row.name, row.genre, Modifier.fillMaxWidth().height(innerWidth(width)))
        Text(
            nameText(row.name),
            style = style,
            color = on,
            modifier = Modifier
                .padding(top = Spacing.S2.dp)
                .then(if (nameHeight != null) Modifier.height(nameHeight) else Modifier),
        )
        RunStrip(row.firstDate, row.lastDate, on, Modifier.padding(top = Spacing.S1.dp), years = row.yearCounts)
        (facts ?: listOf(seriesYears(row) ?: "Undated", episodeCount(row.episodes))).forEach {
            Text(it, style = MaterialTheme.typography.labelMedium, color = on)
        }
    }
}

/** A shelf of show tiles in one row; the names share the tallest name's height. */
@Composable
fun ShowShelf(
    rows: List<SeriesRow>,
    onOpen: (SeriesRow) -> Unit,
    modifier: Modifier = Modifier,
    contentPadding: PaddingValues = PaddingValues(horizontal = Spacing.S4.dp),
    tileModifier: (SeriesRow) -> Modifier = { Modifier },
    onLongClick: ((SeriesRow) -> Unit)? = null,
) {
    val width = if (LocalIsTelevision.current) TileWidthTv else TileWidth
    val nameHeight = rememberNameHeight(rows.map { it.name }, innerWidth(width))
    LazyRow(modifier, contentPadding = contentPadding, horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
        items(rows, key = { "s:" + it.key }) { row ->
            ShowTile(
                row, onOpen = { onOpen(row) }, modifier = tileModifier(row), width = width, nameHeight = nameHeight,
                onLongClick = onLongClick?.let { { it(row) } },
            )
        }
    }
}

/**
 * The date block: the month and year small over the day (Big Shoulders), on the series' board; an
 * undated numbered episode says "No." over its number.
 */
@Composable
fun DateBlock(date: String?, num: Int?, genre: String?, modifier: Modifier = Modifier) {
    val on = onBoard(genre)
    val (small, big) = remember(date, num) { dateBlockParts(date, num) }
    Column(
        modifier
            .clip(WindowShape)
            .background(board(genre))
            .clearAndSetSemantics {},
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        val t = MaterialTheme.typography
        if (small.isNotEmpty()) {
            Text(
                small.uppercase(),
                style = t.labelMedium.copy(fontFamily = DisplayFontFamily, fontWeight = FontWeight.Bold),
                color = on,
                maxLines = 1,
                softWrap = false,
            )
        }
        Text(big, style = t.headlineSmall, color = on, maxLines = 1, softWrap = false)
    }
}

/**
 * The row: 64 dp at least whatever it carries, a 48 dp [visual], the title (L3), the sub line (L5,
 * muted, an event line), the length (L6) and Play (36 dp). A missing sub line centers the title in
 * the same height. [onPlay] null draws no Play (a series row opens only).
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun GrammarRow(
    title: String,
    visual: @Composable (Modifier) -> Unit,
    onOpen: () -> Unit,
    modifier: Modifier = Modifier,
    sub: List<Any?> = emptyList(),
    length: String? = null,
    onPlay: (() -> Unit)? = null,
    playDescription: String = "Play",
    description: String? = null,
    openLabel: String = "Open episode",
    onLongClick: (() -> Unit)? = null,
    quote: String? = null,
) {
    val muted = MaterialTheme.colorScheme.onSurfaceVariant
    Row(
        modifier.fillMaxWidth().heightIn(min = 64.dp).padding(start = Spacing.S4.dp, end = Spacing.S2.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(
            Modifier
                .weight(1f)
                .heightIn(min = 64.dp)
                .tvFocusMark()
                .combinedClickable(
                    onClickLabel = openLabel,
                    onClick = onOpen,
                    onLongClickLabel = if (onLongClick != null) "Queue options" else null,
                    onLongClick = onLongClick,
                )
                .padding(vertical = Spacing.S2.dp)
                .semantics(mergeDescendants = true) { if (description != null) contentDescription = description },
            verticalAlignment = Alignment.CenterVertically,
        ) {
            visual(Modifier.size(48.dp))
            Spacer(Modifier.width(Spacing.S3.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.Center) {
                Text(title, style = MaterialTheme.typography.titleMedium, maxLines = 2, overflow = TextOverflow.Ellipsis)
                EventLine(sub)
                if (quote != null) {
                    Text(
                        quote,
                        style = MaterialTheme.typography.labelMedium.copy(fontStyle = androidx.compose.ui.text.font.FontStyle.Italic),
                        color = MaterialTheme.colorScheme.onSurface,
                    )
                }
            }
            if (length != null) {
                Text(
                    length,
                    style = MaterialTheme.typography.bodySmall,
                    color = muted,
                    maxLines = 1,
                    softWrap = false,
                    modifier = Modifier.padding(start = Spacing.S2.dp),
                )
            }
        }
        if (onPlay != null) {
            IconButton(onClick = onPlay, modifier = Modifier.size(48.dp).tvFocusMark()) {
                Box(
                    Modifier.size(36.dp).clip(CircleShape).background(OnAir.colors.play),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(Icons.Filled.PlayArrow, contentDescription = playDescription, tint = OnAir.colors.onPlay)
                }
            }
        } else {
            Spacer(Modifier.width(Spacing.S2.dp))
        }
    }
}

/** The head board's window side: 96 dp, 128 from 600 dp wide, 176 from 1024. */
@Composable
fun headSlot(): Dp {
    val window = with(LocalDensity.current) { LocalWindowInfo.current.containerSize.width.toDp() }
    return if (window >= 1024.dp) 176.dp else if (window >= 600.dp) 128.dp else 96.dp
}

/**
 * The head board (series, episode, ear drama): the board with the window (96 dp, 128 from 600 dp
 * wide, 176 from 1024), the kicker, the name, the facts, and the run strip full width (56 dp)
 * under both. A series page names it as its heading; an episode page passes [onOpen] (the board
 * is the link to its show) and its own title is the heading.
 */
@Composable
fun HeadBoard(
    name: String,
    genre: String?,
    art: Artwork?,
    kicker: String?,
    facts: List<Any?>,
    first: String?,
    last: String?,
    modifier: Modifier = Modifier,
    onOpen: (() -> Unit)? = null,
    years: List<Int>? = null,
    /** The series page: the kicker's genre is a link that opens Browse filtered to it. */
    genreLink: GenreLink? = null,
    /** An ear drama's credits (its author), one line under the name. */
    credits: String? = null,
    /** What stands in the mark slot in place of the run strip (an ear drama's cast fingerprint), given the slot's height. */
    mark: (@Composable (Dp) -> Unit)? = null,
) {
    val on = onBoard(genre)
    val side = headSlot()
    val t = MaterialTheme.typography
    Column(
        modifier.fillMaxWidth().background(board(genre))
            .then(if (onOpen != null) Modifier.tvFocusMark().clickable(onClickLabel = "Open series", onClick = onOpen) else Modifier)
            .padding(Spacing.S4.dp),
        verticalArrangement = Arrangement.spacedBy(Spacing.S3.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(Spacing.S3.dp)) {
            PictureWindow(art, name, genre, Modifier.size(side))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Spacing.S1.dp)) {
                if (genreLink != null) {
                    Row {
                        Text(
                            genreLink.name.uppercase(),
                            style = t.labelMedium.copy(letterSpacing = 1.sp, textDecoration = TextDecoration.Underline),
                            color = on,
                            modifier = Modifier
                                .tvFocusMark()
                                .clickable(role = Role.Button, onClickLabel = "Browse ${genreLink.name}", onClick = genreLink.onOpen),
                        )
                        if (genreLink.rest.isNotEmpty()) {
                            Text(" \u00b7 " + genreLink.rest.uppercase(), style = t.labelMedium.copy(letterSpacing = 1.sp), color = on)
                        }
                    }
                } else if (kicker != null) {
                    Text(kicker.uppercase(), style = t.labelMedium.copy(letterSpacing = 1.sp), color = on)
                }
                Text(
                    nameText(name),
                    style = nameStyle(nameStep(name), t, headL1 = true),
                    color = on,
                    modifier = if (onOpen == null) Modifier.semantics { heading() } else Modifier,
                )
                if (credits != null) Text(credits, style = t.titleMedium, color = on)
                EventLine(facts, color = on)
            }
        }
        // The histogram needs height to read: 40 dp on a phone, 56 from 600 dp wide.
        val markHeight = if (side >= 128.dp) 56.dp else 40.dp
        if (mark != null) mark(markHeight) else RunStrip(first, last, on, height = markHeight, years = years)
    }
}

/** The kicker's genre as a link: its [name], the networks after it as [rest], and what opening it does. */
class GenreLink(val name: String, val rest: String, val onOpen: () -> Unit)
