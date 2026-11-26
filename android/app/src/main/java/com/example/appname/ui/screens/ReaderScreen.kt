package com.example.appname.ui.screens

import android.provider.Settings
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.animateScrollBy
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.SideEffect
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.focusable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.RecordVoiceOver
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.FormatSize
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.automirrored.filled.Toc
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material.icons.filled.VerticalAlignBottom
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.adaptive.ExperimentalMaterial3AdaptiveApi
import androidx.compose.material3.adaptive.currentWindowAdaptiveInfo
import androidx.compose.material3.adaptive.layout.AnimatedPane
import androidx.compose.material3.adaptive.layout.SupportingPaneScaffold
import androidx.compose.material3.adaptive.layout.calculatePaneScaffoldDirective
import androidx.compose.material3.adaptive.navigation.rememberSupportingPaneScaffoldNavigator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconToggleButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEvent
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.isShiftPressed
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.drag
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.material.icons.automirrored.filled.StickyNote2
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.GraphicEq
import com.example.appname.ui.describeVoice
import androidx.compose.runtime.Stable
import androidx.compose.ui.input.pointer.AwaitPointerEventScope
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.customActions
import kotlinx.coroutines.withTimeoutOrNull
import com.example.appname.ui.theme.markColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.ParagraphStyle
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.platform.LocalFontFamilyResolver
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.BaselineShift
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextIndent
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.vector.rememberVectorPainter
import com.example.appname.plays.LinePart
import com.example.appname.plays.Mark
import com.example.appname.plays.MarkExtra
import com.example.appname.plays.MarkPatch
import com.example.appname.plays.MarksCore
import com.example.appname.plays.MarksDatabase
import com.example.appname.plays.MarksPrefsStore
import com.example.appname.plays.MarksRepository
import com.example.appname.plays.Piece
import com.example.appname.plays.PageRow
import com.example.appname.plays.PartID
import com.example.appname.plays.PlayPage
import com.example.appname.plays.PlayScript
import com.example.appname.plays.ReaderMath
import com.example.appname.plays.ReaderPagination
import com.example.appname.plays.ReaderPrefs
import com.example.appname.plays.ReaderStore
import com.example.appname.plays.RecordingSession
import com.example.appname.plays.Relay
import com.example.appname.plays.StudioCore
import com.example.appname.plays.chipVoiceName
import com.example.appname.plays.soleAccent
import com.example.appname.plays.StudioOpen
import com.example.appname.plays.ScriptLine
import com.example.appname.plays.ScriptReading
import com.example.appname.plays.AlongModel
import com.example.appname.plays.FinishedList
import com.example.appname.data.EpisodeRow
import com.example.appname.ui.PLAY_BOARD
import com.example.appname.plays.ReadAlong
import com.example.appname.plays.ReadCore
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SkipPrevious
import com.example.appname.ui.VoicePickerSheet
import com.example.appname.ui.VoicesSheet
import com.example.appname.ui.rememberCast
import com.example.appname.ui.rememberDeviceVoices
import com.example.appname.ui.EmptyAction
import com.example.appname.ui.EmptyMessage
import com.example.appname.ui.Haptic
import com.example.appname.ui.LocalAppContainer
import com.example.appname.ui.LocalIsTelevision
import com.example.appname.ui.theme.AppSemantics
import com.example.appname.ui.rememberHaptics
import com.example.appname.ui.theme.DisplayFontFamily
import com.example.appname.ui.theme.OnAir
import com.example.appname.ui.theme.Spacing
import com.example.appname.ui.theme.genreColor
import java.util.Locale
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.Job
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// The script reader (ANDROID-DESIGN §4.17, PLAYS-DESIGN §2.7, Decision 076 S1; port spec
// docs/research/design/R2-reader-port-brief.md). Pages by default: the script is cut into pages from TextMeasurer
// heights (ReaderPagination, pure) and each page is drawn from the same measured layout, so what is drawn is what was
// measured. A page is never stored: the position is a line id, and a page is wherever that line falls in this layout.

private const val BODY_SP = 16f
private const val LINE_GAP_EM = 0.6f
private val PageMargin = 24.dp
private val PageGap = 48.dp
private val PageVertical = 16.dp
private val PageHead = 28.dp
private val RuleInset = 10.dp

/** Room below the text in the studio, so the current line's outline is never clipped at a page foot (PLAYS-DESIGN §2.9). */
private val StudioFoot = 8.dp
private val StudioPaneWidth = 360.dp
private const val MARK_GLYPH_EM = 0.95f
/** The room a take mark needs beside a name in the gutter: the glyph, a two-digit count and a gap. */
private const val MARK_RESERVE_EM = 2.3f

private sealed interface Loaded {
    data object Loading : Loaded
    data object Missing : Loaded
    data class Failed(val line: String) : Loaded
    data class Ready(val script: PlayScript, val drama: DramaAlong? = null) : Loaded
}

/** A finished drama's read-along: its production id and the line each of its files speaks. */
internal class DramaAlong(val pid: String, val plan: List<ReadAlong.DramaLine>)

/** The reader over one play, full screen: it opens at [startLine], else where this device last left off. */
@Composable
fun ReaderScreen(
    scriptId: String,
    startLine: String?,
    productionId: String? = null,
    part: String? = null,
    along: Boolean = false,
    drama: String? = null,
    onBack: () -> Unit,
    onOpenStudio: (String, String, String?) -> Unit = { _, _, _ -> },
    room: RoomSeam? = null,
    /** The play a room already holds whole (an own script's, fetched by the member's key): read as it stands, not asked for again. */
    held: PlayScript? = null,
) {
    val container = LocalAppContainer.current
    val plays = container.plays
    var attempt by remember { mutableStateOf(0) }
    val loaded by produceState<Loaded>(Loaded.Loading, scriptId, productionId, drama, attempt) {
        value = Loaded.Loading
        if (held != null) { value = Loaded.Ready(held); return@produceState }
        value = try {
            if (drama != null) {
                val play = (container.finished.state.value as? FinishedList.State.Ready)?.plays?.firstOrNull { it.id == drama } ?: container.openPlays.finished(drama)
                val script = plays.script(scriptId)
                val plan = script?.let { container.finished.alongFor(play, it) }
                value = if (script != null && plan != null) Loaded.Ready(script, DramaAlong(drama, plan)) else Loaded.Missing
                return@produceState
            }
            // With the studio the script is the production's own copy, so its line ids match the takes.
            (productionId?.let { plays.castScript(it) } ?: plays.script(scriptId))?.let { Loaded.Ready(it) } ?: Loaded.Missing
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: Exception) {
            Loaded.Failed("This play could not be loaded. Check the connection.")
        }
    }
    when (val l = loaded) {
        Loaded.Loading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            CircularProgressIndicator(Modifier.semantics { contentDescription = "Loading" })
        }
        Loaded.Missing -> ReaderFrame(onBack) { EmptyMessage(if (drama != null) "This recording has no line timeline." else "This play is not on this device.") }
        is Loaded.Failed -> ReaderFrame(onBack) { EmptyMessage(l.line, action = EmptyAction("Try again") { attempt++ }) }
        is Loaded.Ready -> ReaderBody(
            l.script, startLine, if (productionId != null && part != null) StudioTarget(productionId, PartID(part)) else null,
            onBack, onOpenStudio, alongProduction = productionId.takeIf { along && part == null },
            alongDrama = l.drama.takeIf { along }, room = room,
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ReaderFrame(onBack: () -> Unit, content: @Composable () -> Unit) {
    Scaffold(topBar = {
        TopAppBar(title = {}, navigationIcon = {
            IconButton(onClick = onBack) { Icon(Icons.Filled.Close, contentDescription = "Close") }
        })
    }) { padding -> Box(Modifier.padding(padding)) { content() } }
}

// MARK: Blocks: a front page, headings, and per speech a name, its words, and its cues (the Ear Drama page)

private enum class Kind { Front, Heading, Name, Text, Cue, Direction }

private const val GUTTER_EM = 8.5f
private const val COL_EM = 9.5f
private const val INDENT_EM = 1.5f
private const val CAPTION_EM = 0.8125f
private const val GLYPH_EM = CAPTION_EM * 1.7f
private const val GAP_EM = 0.7f
private const val CUE_GAP_EM = 0.2f

private class Blk(
    val owner: Int,
    val text: AnnotatedString,
    val said: List<IntRange>,
    val style: TextStyle,
    val gapEm: Float,
    val kind: Kind,
    val keepWithNext: Boolean = false,
    var breakBefore: Boolean = false,
    /** The speaker's role on a speech's blocks; null for a heading, a direction or the front. */
    val role: String? = null,
    val hue: Color? = null,
    /** Where the text starts, in em from the column's inner edge (a gutter, an indent, a cue's glyph). */
    val xOffEm: Float = 0f,
    val speech: Int = -1,
    val speechStart: Boolean = false,
    /** The speaker's name, set in the gutter beside the words, when the page is wide. */
    val name: AnnotatedString? = null,
    /** Where each printed row of a verse speech begins in [text]. */
    val rowOffsets: List<Int> = emptyList(),
    val heading: Boolean = false,
    /** Where each drawn run of the line's words stands in [text] (marks anchor to the line's words, never to this block). */
    val map: List<MapSeg> = emptyList(),
    /** The room [text] holds for a mark's glyph (a breath, a pause, a beat, the end of a note). */
    val inserts: List<MarkInsert> = emptyList(),
    /** A heading set before its line: it draws none of the line's words (B29). */
    val lead: Boolean = false,
) {
    /** The line's words that block range [bs, be) covers, or null when it covers none (a name, a printed bracket, a glyph). */
    fun lineRange(bs: Int, be: Int): IntRange? {
        var s = -1
        var e = -1
        for (g in map) {
            if (g.blk + g.len <= bs || g.blk >= be) continue
            if (s < 0) s = g.line + maxOf(0, bs - g.blk)
            e = g.line + minOf(g.len, be - g.blk)
        }
        return if (s < 0 || e <= s) null else s until e
    }

    /** Where the line's words [ls, le) are drawn in this block: from the first to the last, whatever is drawn between. */
    fun blkRange(ls: Int, le: Int): IntRange? {
        var s = -1
        var e = -1
        for (g in map) {
            if (g.line + g.len <= ls || g.line >= le) continue
            if (s < 0) s = g.blk + maxOf(0, ls - g.line)
            e = g.blk + minOf(g.len, le - g.line)
        }
        return if (s < 0 || e <= s) null else s until e
    }

    /** The offset into the line's words of the character at block offset [off], or null for one the line does not hold. */
    fun lineAt(off: Int): Int? {
        for (g in map) if (off >= g.blk && off < g.blk + g.len) return g.line + off - g.blk
        return null
    }

    /** The words a part comes in on, underlined when that part is the one being played. */
    var cueRole: String? = null
    var cueHue: Color? = null
    var cueRange: IntRange? = null
    var speechEnd = false

    val description: String get() = (name?.text?.let { "$it " }.orEmpty()) + text.text

    /** The same words with the said runs drawn transparent (Hide my lines): the layout does not change. */
    val hiddenText: AnnotatedString by lazy {
        buildAnnotatedString {
            append(text)
            for (r in said) addStyle(SpanStyle(color = Color.Transparent), r.first, r.last + 1)
        }
    }
}

/** A run of the block's text that is the line's words: block offset, line offset, length. */
private class MapSeg(val blk: Int, val line: Int, val len: Int)

/** A mark's glyph drawn in room the block leaves for it ([label] is a beat's words, inside [range]). */
private class MarkInsert(val id: String, val kind: String, val range: IntRange, val label: IntRange?)

/**
 * Builds a block's text while keeping what marks need: each run's place in the line's words ([segs]) and, where a point
 * mark stands, room for its glyph ([inserts]). The glyph is drawn text of the page's own; the script's words, their
 * offsets, search and the read-along never see it.
 */
private class Mapper(val points: List<PointKey>, val glyph: SpanStyle, val labelStyle: SpanStyle) {
    val segs = ArrayList<MapSeg>()
    val inserts = ArrayList<MarkInsert>()

    fun run(b: AnnotatedString.Builder, text: String, at: Int, emit: AnnotatedString.Builder.(String) -> Unit) {
        var from = 0
        val here = points.filter { it.at > at && it.at <= at + text.length }
        for (k in here.map { it.at }.distinct()) {
            val cut = k - at
            piece(b, text, at, from, cut, emit)
            for (p in here) if (p.at == k) insert(b, p)
            from = cut
        }
        piece(b, text, at, from, text.length, emit)
    }

    private fun piece(b: AnnotatedString.Builder, text: String, at: Int, from: Int, to: Int, emit: AnnotatedString.Builder.(String) -> Unit) {
        if (to <= from) return
        segs += MapSeg(b.length, at + from, to - from)
        b.emit(text.substring(from, to))
    }

    private fun insert(b: AnnotatedString.Builder, p: PointKey) {
        val st = b.length
        var label: IntRange? = null
        when (p.kind) {
            "note" -> b.withStyle(glyph) { append("\u2007") }
            "breath" -> b.withStyle(glyph) { append("\u00A0/") }
            "pause" -> b.withStyle(glyph) { append("\u00A0//") }
            else -> {
                b.withStyle(glyph) { append("\u00A0//") }
                if (p.label.isNotBlank()) {
                    b.withStyle(glyph) { append("\u00A0") }
                    val ls = b.length
                    b.withStyle(labelStyle) { append(p.label.uppercase(Locale.US)) }
                    label = ls until b.length
                }
            }
        }
        inserts += MarkInsert(p.id, p.kind, st until b.length, label)
    }
}

/** The words a speech's cue begins at, as a range of the block's text, found through the runs just appended. */
private fun cueRangeOf(segs: List<MapSeg>, at: Int, text: String): IntRange? {
    if (segs.isEmpty()) return null
    fun toBlk(i: Int): Int {
        val line = at + i
        for (g in segs) if (line >= g.line && line < g.line + g.len) return g.blk + line - g.line
        return segs.last().let { it.blk + it.len }
    }
    return toBlk(PlayPage.cueTail(text)) until toBlk(text.length)
}

private class Palette(val text: Color, val muted: Color, val accent: Color, val block: Color, val hues: Map<String, Color>)

private val ASIDE_OPEN = Regex("^\\s*[(\\[]")
private val ASIDE_CLOSE = Regex("[)\\]][.,;:!?]*\\s*$")

private fun buildBlocks(
    script: PlayScript,
    pal: Palette,
    scale: Float,
    leading: Float,
    gutter: Boolean,
    measurer: TextMeasurer,
    density: Density,
    studioRole: String? = null,
    points: Map<String, List<PointKey>> = emptyMap(),
): List<Blk> {
    val bodySp = BODY_SP * scale
    val bodyPx = with(density) { bodySp.sp.toPx() }
    fun style(em: Float = 1f, display: Boolean = false) = TextStyle(
        fontSize = (bodySp * em).sp,
        lineHeight = (bodySp * em * leading).sp,
        color = pal.text,
        fontFamily = if (display) DisplayFontFamily else FontFamily.Default,
        fontWeight = if (display) FontWeight.Bold else FontWeight.Normal,
    )
    fun nameSpan(hue: Color?) = SpanStyle(fontWeight = FontWeight.SemiBold, color = hue ?: pal.muted, letterSpacing = 0.02.em)
    fun nameText(name: String, hue: Color?) = buildAnnotatedString { withStyle(nameSpan(hue)) { append(name) } }
    val glyphStyle = SpanStyle(fontWeight = FontWeight.SemiBold, color = pal.text, baselineShift = BaselineShift(0.15f))
    val labelStyle = SpanStyle(fontSize = (bodySp * CAPTION_EM).sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.06.em, color = pal.text)
    fun mapperFor(line: ScriptLine) = Mapper(points[line.id].orEmpty(), glyphStyle, labelStyle)

    val roles = script.roles.map { it.name }
    val capNames = roles.filter { it.length >= 3 && it == it.uppercase(Locale.US) && it.any { c -> c in 'A'..'Z' } }
        .sortedByDescending { it.length }
        .takeIf { it.isNotEmpty() }
        ?.let { caps -> Regex("(?<![\\p{L}])(?:${caps.joinToString("|") { Regex.escape(it) }})(?![\\p{L}])") }

    val before = HashMap<Int, MutableList<ScriptReading.Section>>()
    val heads = HashMap<Int, ScriptReading.Section>()
    for (s in ScriptReading.sectionsOf(script)) {
        if (s.isLine) heads[s.index] = s else before.getOrPut(s.index) { ArrayList() } += s
    }
    val out = ArrayList<Blk>(script.lines.size * 2 + 16)
    var pendingBreak = true
    fun add(b: Blk) {
        if (pendingBreak) {
            b.breakBefore = true
            pendingBreak = false
        }
        out += b
    }
    fun heading(owner: Int, level: ScriptReading.Level, body: String, lead: Boolean = false) {
        val opens = level != ScriptReading.Level.Scene
        add(
            Blk(
                owner, AnnotatedString(body), emptyList(), style(if (opens) 1.75f else 1.25f, display = true),
                if (opens) 0f else 1.2f, Kind.Heading, keepWithNext = true, breakBefore = opens, heading = true, lead = lead,
            ),
        )
    }

    // The front of the play: its title, its authors, and its speaking parts in their hues (the key to the colors).
    if (script.lines.isNotEmpty()) {
        add(Blk(0, AnnotatedString(script.title), emptyList(), style(1.75f, display = true), 0f, Kind.Front, keepWithNext = true))
        val by = script.authorLine
        if (by.isNotEmpty()) {
            add(Blk(0, buildAnnotatedString { withStyle(SpanStyle(color = pal.muted)) { append(by) } }, emptyList(), style(), 0.3f, Kind.Front, keepWithNext = true))
        }
        val speaking = script.castParts.filter { it.id.isSpeaking }
        if (speaking.isNotEmpty()) {
            add(Blk(0, buildAnnotatedString { withStyle(SpanStyle(color = pal.muted)) { append("Parts") } }, emptyList(), style(CAPTION_EM), 1.2f, Kind.Front, keepWithNext = true))
            add(
                Blk(
                    0,
                    buildAnnotatedString {
                        speaking.forEachIndexed { i, p ->
                            if (i > 0) append("   ")
                            withStyle(nameSpan(pal.hues[p.id.roleName.orEmpty()])) { append(p.title) }
                        }
                    },
                    emptyList(), style(), 0.3f, Kind.Front,
                ),
            )
        }
        pendingBreak = true
    }

    /** A direction's words, each part it names in capitals in that part's hue, upright and strong. */
    fun AnnotatedString.Builder.direction(raw: String, italic: Boolean) {
        val text = PlayPage.drawn(raw)
        val base = SpanStyle(fontStyle = if (italic) FontStyle.Italic else FontStyle.Normal, color = pal.muted)
        var last = 0
        fun plain(from: Int, to: Int) {
            if (to > from) withStyle(base) { append(text.substring(from, to)) }
        }
        for (m in capNames?.findAll(text).orEmpty()) {
            plain(last, m.range.first)
            val hue = pal.hues[m.value]
            if (hue != null) withStyle(SpanStyle(fontWeight = FontWeight.SemiBold, color = hue)) { append(m.value) } else withStyle(base) { append(m.value) }
            last = m.range.last + 1
        }
        plain(last, text.length)
    }

    /** A cue's words on the sound lane, in capitals as the web draws them. */
    fun AnnotatedString.Builder.cue(row: PageRow, mapper: Mapper) {
        row.runs.forEachIndexed { n, r ->
            if (n > 0 && row.runs[n - 1].piece != r.piece) append(' ')
            mapper.run(this, r.text, r.at) { piece ->
                val up = piece.uppercase(Locale.US)
                withStyle(SpanStyle(fontWeight = FontWeight.SemiBold, letterSpacing = 0.06.em)) { append(if (up.length == piece.length) up else piece) }
            }
        }
    }

    var speechCount = 0
    var previous: Triple<String, Int, IntRange?>? = null

    script.lines.forEachIndexed { i, line ->
        for (s in before[i].orEmpty()) heading(i, s.level, s.title, lead = true)
        val head = heads[i]
        if (head != null) {
            heading(i, head.level, ScriptReading.runsOf(line).joinToString("") { it.text })
            return@forEachIndexed
        }
        val layout = PlayPage.layoutOf(line, roles, emphasis = !script.isOwn)
        if (line.kind == ScriptLine.Kind.Speech && line.parts != null) {
            for (sp in layout.speeches) {
                speechCount++
                val hue = pal.hues[sp.role]
                previous?.let { (role, at, range) ->
                    if (range != null && role != sp.role) out[at].apply { cueRole = sp.role; cueHue = hue; cueRange = range }
                }
                val name = sp.name?.text ?: sp.role
                val firstIsCue = sp.rows.firstOrNull()?.cue == true
                val nameStyled = nameText(name, hue)
                val beside = gutter && name.isNotEmpty() && sp.rows.isNotEmpty() && !firstIsCue &&
                    measurer.measure(nameStyled, style()).size.width + (if (sp.role == studioRole) MARK_RESERVE_EM * bodyPx else 0f) <= GUTTER_EM * bodyPx
                val base = if (beside) COL_EM else 0f
                var first = true
                var lastTail: Pair<Int, IntRange?>? = null
                if (!beside && name.isNotEmpty()) {
                    add(Blk(i, nameStyled, emptyList(), style(), GAP_EM, Kind.Name, keepWithNext = sp.rows.isNotEmpty(), role = sp.role, hue = hue, speech = speechCount, speechStart = true))
                    first = false
                }
                var afterName = !first
                var k = 0
                while (k < sp.rows.size) {
                    val row = sp.rows[k]
                    val gap = when {
                        first -> GAP_EM
                        afterName && !row.cue -> 0f
                        else -> CUE_GAP_EM
                    }
                    if (row.cue) {
                        val mapper = mapperFor(line)
                        add(
                            Blk(
                                i, buildAnnotatedString { cue(row, mapper) }, emptyList(), style(CAPTION_EM), gap, Kind.Cue,
                                role = sp.role, hue = hue, xOffEm = base + GLYPH_EM, speech = speechCount, speechStart = first,
                                map = mapper.segs, inserts = mapper.inserts,
                            ),
                        )
                        k++
                    } else {
                        var end = k
                        while (end < sp.rows.size && !sp.rows[end].cue) end++
                        val said = ArrayList<IntRange>()
                        val offsets = ArrayList<Int>()
                        val mapper = mapperFor(line)
                        var tail: IntRange? = null
                        var hasTail = false
                        val text = buildAnnotatedString {
                            for (r in k until end) {
                                val rw = sp.rows[r]
                                offsets += length
                                val half = rw.indent
                                val indent = if (layout.verse) TextIndent((bodySp * if (half) 2.5f else 0f).sp, (bodySp * if (half) 4f else INDENT_EM).sp) else TextIndent.None
                                withStyle(ParagraphStyle(textIndent = indent)) {
                                    rw.runs.forEachIndexed { n, run ->
                                        if (n > 0 && rw.runs[n - 1].piece != run.piece && ScriptReading.spaceBetween(rw.runs[n - 1].text, run.text)) append(' ')
                                        if (run.said) {
                                            val st = length
                                            val segStart = mapper.segs.size
                                            mapper.run(this, run.text, run.at) { piece ->
                                                withStyle(if (run.kind == ScriptReading.RunKind.Em) SpanStyle(fontStyle = FontStyle.Italic) else SpanStyle()) { append(piece) }
                                            }
                                            said += st until length
                                            tail = cueRangeOf(mapper.segs.subList(segStart, mapper.segs.size), run.at, run.text)
                                            hasTail = true
                                            return@forEachIndexed
                                        }
                                        val whole = rw.runs.filter { it.piece == run.piece && !it.said }.joinToString("") { it.text }
                                        val opens = (n == 0 || rw.runs[n - 1].piece != run.piece) && !ASIDE_OPEN.containsMatchIn(whole)
                                        val closes = (n == rw.runs.size - 1 || rw.runs[n + 1].piece != run.piece) && !ASIDE_CLOSE.containsMatchIn(whole)
                                        if (opens) append('(')
                                        mapper.run(this, run.text, run.at) { piece -> direction(piece, italic = run.kind != ScriptReading.RunKind.Plain) }
                                        if (closes) append(')')
                                    }
                                }
                            }
                        }
                        add(
                            Blk(
                                i, text, said, style(), gap, Kind.Text, role = sp.role, hue = hue, xOffEm = base, speech = speechCount,
                                speechStart = first, name = if (first && beside) nameStyled else null, rowOffsets = if (layout.verse) offsets else emptyList(),
                                map = mapper.segs, inserts = mapper.inserts,
                            ),
                        )
                        if (hasTail) lastTail = out.size - 1 to tail
                        k = end
                    }
                    first = false
                    afterName = false
                }
                out.lastOrNull()?.takeIf { it.speech == speechCount }?.speechEnd = true
                lastTail?.let { (at, range) -> previous = Triple(sp.role, at, range) }
            }
            return@forEachIndexed
        }
        val row = layout.rows.firstOrNull() ?: PageRow(false, false)
        val indent = if (gutter) COL_EM else INDENT_EM
        val mapper = mapperFor(line)
        if (row.cue) {
            add(
                Blk(
                    i, buildAnnotatedString { cue(row, mapper) }, emptyList(), style(CAPTION_EM), GAP_EM, Kind.Cue, xOffEm = indent + GLYPH_EM,
                    map = mapper.segs, inserts = mapper.inserts,
                ),
            )
        } else {
            add(
                Blk(
                    i,
                    buildAnnotatedString {
                        for (r in row.runs) mapper.run(this, r.text, r.at) { piece -> direction(piece, italic = r.kind == ScriptReading.RunKind.Plain) }
                    },
                    emptyList(), style(), GAP_EM, Kind.Direction, xOffEm = indent, map = mapper.segs, inserts = mapper.inserts,
                ),
            )
        }
    }
    return out
}

// MARK: The flow: blocks, and when reading in pages, where each page begins

private class ReaderFlow(
    val blocks: List<Blk>,
    val paged: ReaderPagination.Paged?,
    val per: Int,
    val contentPx: Int,
    val colPx: Int,
    val firstBlock: IntArray,
    val bodyPx: Float,
    val gutter: Boolean,
    /** Each script line's id, by index: what a block's owner names, for marks. */
    val ids: List<String>,
)

private data class FlowSpec(
    val scriptId: String,
    val colPx: Int,
    val pageHeightPx: Int,
    val density: Float,
    val fontScale: Float,
    val prefs: ReaderPrefs,
    val dark: Boolean,
    val per: Int,
    val insetPx: Int,
    /** The studio's part (its role name): its speeches stay whole on a page and carry take marks. */
    val studioRole: String? = null,
    /** Where the page leaves room for a mark's glyph: a different set is a different layout. */
    val points: List<PointKey> = emptyList(),
)

private fun textWidth(flow: ReaderFlow, b: Blk): Int = (flow.contentPx - (b.xOffEm * flow.bodyPx).toInt()).coerceAtLeast(1)

private suspend fun computeFlow(
    script: PlayScript,
    spec: FlowSpec,
    pal: Palette,
    resolver: androidx.compose.ui.text.font.FontFamily.Resolver,
    density: Density,
): ReaderFlow = withContext(Dispatchers.Default) {
    val bodyPx = with(density) { (BODY_SP * spec.prefs.scale).sp.toPx() }
    val gutter = spec.colPx / bodyPx >= PlayPage.GUTTER_MIN_EM
    val measurer = TextMeasurer(resolver, density, LayoutDirection.Ltr)
    val blocks = buildBlocks(script, pal, spec.prefs.scale, spec.prefs.leading, gutter, measurer, density, spec.studioRole, spec.points.groupBy { it.line })
    val ids = script.lines.map { it.id }
    val contentPx = (spec.colPx - spec.insetPx).coerceAtLeast(1)
    val firstBlock = IntArray(script.lines.size) { -1 }
    blocks.forEachIndexed { b, blk -> if (firstBlock[blk.owner] < 0) firstBlock[blk.owner] = b }
    var last = 0
    for (i in firstBlock.indices) if (firstBlock[i] < 0) firstBlock[i] = last else last = firstBlock[i]
    val flow0 = ReaderFlow(blocks, null, spec.per, contentPx, spec.colPx, firstBlock, bodyPx, gutter, ids)
    if (!spec.prefs.pages) return@withContext flow0
    val measured = blocks.map { b ->
        ensureActive()
        val l = measurer.measure(b.text, b.style, constraints = Constraints(maxWidth = textWidth(flow0, b)), skipCache = true)
        val rows = if (b.rowOffsets.size > 1) b.rowOffsets.map { l.getLineForOffset(it) }.distinct().toIntArray() else null
        ReaderPagination.Block(
            b.owner, FloatArray(l.lineCount) { l.getLineBottom(it) - l.getLineTop(it) }, b.gapEm * bodyPx, b.keepWithNext,
            b.breakBefore, b.speech, b.speechStart, rows, keepSpeech = spec.studioRole != null && b.role == spec.studioRole,
            lead = b.lead || b.kind == Kind.Front || b.kind == Kind.Name,
        )
    }
    val paged = ReaderPagination.paginate(measured, script.lines.size, spec.pageHeightPx.toFloat())
    ReaderFlow(blocks, paged, spec.per, contentPx, spec.colPx, firstBlock, bodyPx, gutter, ids)
}

// MARK: Drawing one block, whole or a page's slice of it

private class Measured(val text: TextLayoutResult, val name: TextLayoutResult?)

private fun measureBlk(measurer: TextMeasurer, flow: ReaderFlow, b: Blk, hidden: Boolean): Measured {
    val text = measurer.measure(if (hidden) b.hiddenText else b.text, b.style, constraints = Constraints(maxWidth = textWidth(flow, b)))
    val gw = (GUTTER_EM * flow.bodyPx).toInt()
    val name = b.name?.let { measurer.measure(it, b.style.copy(textAlign = TextAlign.End), constraints = Constraints(minWidth = gw, maxWidth = gw)) }
    return Measured(text, name)
}

private class Ink(
    val accent: Color,
    val block: Color,
    val muted: Color,
    val ruleWidth: Float,
    val pad: Float,
    val insetPx: Float,
    val bodyPx: Float,
    val glyph: androidx.compose.ui.graphics.painter.Painter,
    val warn: androidx.compose.ui.graphics.painter.Painter,
    val measurer: TextMeasurer,
    val targetPx: Float,
    val text: Color,
    val dark: Boolean,
    val note: androidx.compose.ui.graphics.painter.Painter,
    val wave: androidx.compose.ui.graphics.painter.Painter,
)

/** How the studio outlines the current line (§2.9 rule 2): ink, dashed record red while its cue plays, solid while the microphone is open. */
private enum class StudioOutline { Ink, Armed, Recording }

/** What the page draws for the studio: its part, the current line (a script line index), and each of my lines' take state. */
private class StudioPaint(
    val role: String,
    val current: Int?,
    val outline: StudioOutline,
    val states: Map<Int, StudioCore.LineState>,
    val record: Color,
    val warning: Color,
    val ink: Color,
    /** Each other speaking part's device voice, by role; its lines show the ring unless a usable take stands (§2.9 rule 3a). */
    val rings: Map<String, DeviceVoice> = emptyMap(),
    /** Script line indexes whose chosen take is usable. */
    val taken: Set<Int> = emptySet(),
)

/** What a device-voice ring says: the short name it shows and the name the part's voice is read as. */
private class DeviceVoice(val part: PartID, val text: String, val label: String)

private fun StudioPaint.ringFor(blk: Blk): DeviceVoice? =
    if (blk.speechStart && blk.role != null && blk.role != role && blk.owner !in taken) rings[blk.role] else null

private fun measureRing(ink: Ink, d: Density, text: String): TextLayoutResult =
    ink.measurer.measure(androidx.compose.ui.text.AnnotatedString(text), TextStyle(fontSize = with(d) { (CAPTION_EM * ink.bodyPx).toSp() }, color = ink.muted))

private class MarkSpot(val glyph: Rect, val textX: Float, val cy: Float, val hit: Rect)

/**
 * Where a line's take-state mark sits (§2.9 rule 3), in the slice's coordinates: after the speaker's name when it stands above
 * its words; in the gutter the name is right-aligned beside the words, so the mark stands before it. The hit area is the name
 * and the mark together, at least a finger tall.
 */
private fun markSpot(m: Measured, blk: Blk, ink: Ink, top: Float, state: StudioCore.LineState, widthOf: Float? = null): MarkSpot? {
    val lay = (if (blk.kind == Kind.Name) m.text else m.name) ?: return null
    val g = ink.bodyPx * MARK_GLYPH_EM
    val gap = ink.bodyPx * 0.3f
    val countW = if (state.state == StudioCore.LineState.Kind.Chosen) ink.bodyPx * (0.25f + 0.55f * state.takes.toString().length) else 0f
    val width = widthOf ?: (g + countW)
    val lineH = lay.getLineBottom(0) - lay.getLineTop(0)
    val cy = top + lineH / 2
    val nameL: Float
    val nameR: Float
    val left: Float
    if (blk.kind == Kind.Name) {
        val x0 = ink.insetPx + blk.xOffEm * ink.bodyPx
        nameL = x0 + lay.getLineLeft(0)
        nameR = x0 + lay.getLineRight(0)
        left = nameR + gap
    } else {
        nameL = ink.insetPx + lay.getLineLeft(0)
        nameR = ink.insetPx + lay.getLineRight(0)
        left = nameL - gap - width
    }
    val half = maxOf(lineH, ink.targetPx) / 2
    val hit = Rect(minOf(nameL, left) - 6f, cy - half, maxOf(nameR, left + width) + 6f, cy + half)
    return MarkSpot(Rect(left, cy - g / 2, left + g, cy + g / 2), left + g + ink.bodyPx * 0.25f, cy, hit)
}

/** The ring and the voice's name, after the speaker's name (or before it in the gutter); the hit area is at least a finger tall. */
private fun ringSpot(m: Measured, blk: Blk, ink: Ink, top: Float, d: Density, voice: DeviceVoice): MarkSpot? =
    markSpot(m, blk, ink, top, StudioCore.LineState(StudioCore.LineState.Kind.None, 0, 0), ink.bodyPx * (MARK_GLYPH_EM + 0.25f) + measureRing(ink, d, voice.text).size.width)

private fun DrawScope.drawRing(spot: MarkSpot, voice: DeviceVoice, blk: Blk, ink: Ink) {
    val hue = blk.hue ?: ink.accent
    val c = spot.glyph.center
    val r = spot.glyph.width / 2
    val w = ink.ruleWidth * 0.5f
    drawCircle(hue, r * 0.9f, c, style = Stroke(w, pathEffect = PathEffect.dashPathEffect(floatArrayOf(w * 2.2f, w * 1.6f))))
    val g = spot.glyph.width * 0.62f
    translate(c.x - g / 2, c.y - g / 2) { with(ink.wave) { draw(Size(g, g), colorFilter = ColorFilter.tint(hue)) } }
    val text = measureRing(ink, this, voice.text)
    drawText(text, topLeft = Offset(spot.textX, spot.cy - text.size.height / 2f))
}

private fun DrawScope.drawMark(spot: MarkSpot, state: StudioCore.LineState, blk: Blk, ink: Ink, studio: StudioPaint) {
    val hue = blk.hue ?: ink.accent
    val c = spot.glyph.center
    val r = spot.glyph.width / 2
    when (state.state) {
        StudioCore.LineState.Kind.None -> drawCircle(ink.muted, r * 0.8f, c, style = Stroke(ink.ruleWidth * 0.5f))
        StudioCore.LineState.Kind.Chosen -> {
            drawCircle(hue, r * 0.85f, c)
            val text = ink.measurer.measure(
                androidx.compose.ui.text.AnnotatedString(state.takes.toString()),
                TextStyle(fontSize = (CAPTION_EM * ink.bodyPx).toSp(), fontWeight = FontWeight.SemiBold, color = hue),
            )
            drawText(text, topLeft = Offset(spot.textX, spot.cy - text.size.height / 2f))
        }
        StudioCore.LineState.Kind.Flagged -> translate(spot.glyph.left, spot.glyph.top) {
            with(ink.warn) { draw(Size(spot.glyph.width, spot.glyph.height), colorFilter = ColorFilter.tint(studio.warning)) }
        }
    }
}


// MARK: Marks on the page: what a block draws for them, a selection, and where a touch lands

/** What a block draws for marks: its line's marks (none while hidden or switched off) and the selected range of it. */
private class MarkLayer(val marks: List<Mark>, val sel: IntRange?, val selTint: Color)

private class LineBox(val line: Int, val left: Float, val right: Float)

/** The visual lines a range of a block's text covers, from [from] on, each as its left and right edge. */
private fun boxesOf(layout: TextLayoutResult, r: IntRange, from: Int): List<LineBox> {
    if (r.isEmpty() || r.last >= layout.layoutInput.text.length) return emptyList()
    val first = layout.getLineForOffset(r.first)
    val last = layout.getLineForOffset(r.last)
    val out = ArrayList<LineBox>()
    for (l in first..last) {
        if (l < from) continue
        val left = if (l == first) layout.getBoundingBox(r.first).left else layout.getLineLeft(l)
        val right = if (l == last) layout.getBoundingBox(r.last).right else layout.getLineRight(l)
        out += LineBox(l, left, right)
    }
    return out
}

private data class Pos(val blk: Int, val off: Int) : Comparable<Pos> {
    override fun compareTo(other: Pos) = if (blk != other.blk) blk.compareTo(other.blk) else off.compareTo(other.off)
}

/** A selection on one page (in Scroll, one block): its two ends as the finger set them, and the line pieces they cover. */
private class Sel(val a: Pos, val b: Pos, val where: Int, val pieces: List<Piece>) {
    val lo: Pos get() = if (a <= b) a else b
    val hi: Pos get() = if (a <= b) b else a
}

/** What the reader holds for marks: the model, the selection and its toolbar rectangle, and what a tap on a mark asks. */
@Stable
private class MarkUi(
    val model: MarksModel,
    val dark: Boolean,
    val onEdit: (Mark) -> Unit,
    val onDelete: (Mark) -> Unit,
    val haptic: () -> Unit,
) {
    var sel by mutableStateOf<Sel?>(null)
    var rect by mutableStateOf<Rect?>(null)
    var dragging by mutableStateOf(false)
}

/** One drawn slice of a block, in the coordinates of the canvas that holds it. */
private class SegGeo(
    val index: Int,
    val blk: Blk,
    val m: Measured,
    val top: Float,
    val bottom: Float,
    val from: Int,
    val to: Int,
    val x0: Float,
    val hidden: Boolean,
) {
    fun layoutY(y: Float): Float = y.coerceIn(top, bottom - 1f) - top + m.text.getLineTop(from)
    fun canvasY(layoutY: Float): Float = layoutY - m.text.getLineTop(from) + top
    val length: Int get() = m.text.layoutInput.text.length
    fun shows(off: Int): Boolean = m.text.getLineForOffset(off.coerceIn(0, length)).let { it >= from && it < to }
}

/** The text offset nearest a point of the canvas, in the slice under it (or the nearest). */
private fun hitPos(geos: List<SegGeo>, p: Offset): Pos? {
    val g = geos.firstOrNull { p.y < it.bottom } ?: geos.lastOrNull() ?: return null
    return Pos(g.index, g.m.text.getOffsetForPosition(Offset(p.x - g.x0, g.layoutY(p.y))))
}

/** The line pieces a selection from [lo] to [hi] covers: per line, the first drawn word's start to the last one's end. */
private fun piecesOf(flow: ReaderFlow, lo: Pos, hi: Pos): List<Piece> {
    val out = ArrayList<Piece>()
    for (bi in lo.blk..hi.blk) {
        val blk = flow.blocks.getOrNull(bi) ?: continue
        if (blk.map.isEmpty()) continue
        val bs = if (bi == lo.blk) lo.off else 0
        val be = if (bi == hi.blk) hi.off else blk.text.length
        val r = blk.lineRange(bs, be) ?: continue
        val id = flow.ids[blk.owner]
        val last = out.lastOrNull()
        if (last != null && last.line == id) out[out.lastIndex] = Piece(id, minOf(last.start, r.first), maxOf(last.end, r.last + 1))
        else out += Piece(id, r.first, r.last + 1)
    }
    return out
}

private fun selRange(sel: Sel?, index: Int, length: Int): IntRange? {
    if (sel == null || index < sel.lo.blk || index > sel.hi.blk) return null
    val s = if (index == sel.lo.blk) sel.lo.off else 0
    val e = if (index == sel.hi.blk) sel.hi.off else length
    return if (e > s) s until e else null
}

/** The rectangle a selection covers on its canvas, for the floating toolbar to stand beside. */
private fun selBounds(geos: List<SegGeo>, sel: Sel): Rect? {
    var out: Rect? = null
    for (g in geos) {
        val r = selRange(sel, g.index, g.length) ?: continue
        for (bx in boxesOf(g.m.text, r, g.from)) {
            if (bx.line >= g.to) continue
            val box = Rect(g.x0 + bx.left, g.canvasY(g.m.text.getLineTop(bx.line)), g.x0 + bx.right, g.canvasY(g.m.text.getLineBottom(bx.line)))
            out = out?.let { Rect(minOf(it.left, box.left), minOf(it.top, box.top), maxOf(it.right, box.right), maxOf(it.bottom, box.bottom)) } ?: box
        }
    }
    return out
}

/** Where a selection's handle stands: under its line, at the end of the selection. */
private fun handleAt(geos: List<SegGeo>, pos: Pos): Offset? {
    val g = geos.firstOrNull { it.index == pos.blk && it.shows(pos.off) } ?: return null
    val c = g.m.text.getCursorRect(pos.off.coerceIn(0, g.length))
    return Offset(g.x0 + c.left, g.canvasY(c.bottom))
}

/** A mark under a tap, with the rectangle of the words tapped (for its menu to hang from). */
private fun markAt(geos: List<SegGeo>, ui: MarkUi, flow: ReaderFlow, p: Offset): Pair<Mark, Rect>? {
    if (!ui.model.show) return null
    val g = geos.firstOrNull { p.y >= it.top && p.y < it.bottom } ?: return null
    if (g.hidden) return null
    val lay = g.m.text
    val lx = p.x - g.x0
    val off = lay.getOffsetForPosition(Offset(lx, g.layoutY(p.y)))
    var hit = -1
    for (o in intArrayOf(off - 1, off)) {
        if (o < 0 || o >= g.length) continue
        val box = lay.getBoundingBox(o)
        if (lx >= box.left - 4f && lx <= box.right + 4f && g.layoutY(p.y) >= box.top && g.layoutY(p.y) <= box.bottom) {
            hit = o
            break
        }
    }
    if (hit < 0) return null
    val marks = ui.model.byLine[flow.ids[g.blk.owner]].orEmpty()
    val box = lay.getBoundingBox(hit)
    val where = Rect(g.x0 + box.left, g.canvasY(box.top), g.x0 + box.right, g.canvasY(box.bottom))
    g.blk.inserts.firstOrNull { hit in it.range }?.let { ins -> marks.firstOrNull { it.id == ins.id }?.let { return it to where } }
    val at = g.blk.lineAt(hit) ?: return null
    return MarksCore.at(marks, flow.ids[g.blk.owner], at).firstOrNull()?.let { it to where }
}

/**
 * One touch on a page or a block. A tap on a mark opens it; a tap with a selection let go of it; a long press selects the word
 * and a drag goes on from it; a handle drags its end. Anything else is left unconsumed, for the reader's own taps and the pager.
 */
private suspend fun AwaitPointerEventScope.markTouch(
    geos: List<SegGeo>,
    flow: ReaderFlow,
    ui: MarkUi,
    where: Int,
    handleR: Float,
    onOpen: (Mark, Rect) -> Unit,
) {
    val down = awaitFirstDown(requireUnconsumed = false)
    fun set(a: Pos, b: Pos) {
        val lo = if (a <= b) a else b
        val hi = if (a <= b) b else a
        ui.sel = Sel(a, b, where, piecesOf(flow, lo, hi))
    }
    val current = ui.sel?.takeIf { it.where == where }
    if (current != null) {
        val pad = handleR * 2.2f
        val loAt = handleAt(geos, current.lo)?.let { it + Offset(0f, handleR) }
        val hiAt = handleAt(geos, current.hi)?.let { it + Offset(0f, handleR) }
        val dLo = loAt?.let { (it - down.position).getDistance() } ?: Float.MAX_VALUE
        val dHi = hiAt?.let { (it - down.position).getDistance() } ?: Float.MAX_VALUE
        if (minOf(dLo, dHi) <= pad) {
            val movingLo = dLo <= dHi
            val fixed = if (movingLo) current.hi else current.lo
            ui.dragging = true
            down.consume()
            drag(down.id) { ch ->
                ch.consume()
                hitPos(geos, ch.position - Offset(0f, handleR * 2.5f))?.let { set(fixed, it) }
            }
            ui.dragging = false
            return
        }
    }
    var finished = false
    val up = withTimeoutOrNull(viewConfiguration.longPressTimeoutMillis) { waitForUpOrCancellation().also { finished = true } }
    if (finished) {
        if (up == null) return
        if (ui.sel != null) {
            ui.sel = null
            up.consume()
            return
        }
        markAt(geos, ui, flow, up.position)?.let { (m, r) ->
            up.consume()
            onOpen(m, r)
        }
        return
    }
    // A long press that selects nothing is still not a tap: the reader's own tap would turn the page.
    suspend fun AwaitPointerEventScope.swallow() {
        waitForUpOrCancellation()?.consume()
    }
    val g = geos.firstOrNull { down.position.y >= it.top && down.position.y < it.bottom }
    if (g != null && g.hidden) return
    if (g == null || g.blk.map.isEmpty() || g.length == 0) return swallow()
    val start = hitPos(geos, down.position) ?: return swallow()
    val word = g.m.text.getWordBoundary(start.off.coerceIn(0, g.length - 1))
    val wa = Pos(g.index, word.start)
    val wb = Pos(g.index, word.end)
    if (flow.blocks[g.index].lineRange(word.start, word.end) == null) return swallow()
    ui.haptic()
    set(wa, wb)
    ui.dragging = true
    down.consume()
    drag(down.id) { ch ->
        ch.consume()
        val p = hitPos(geos, ch.position) ?: return@drag
        if (p < wa) set(wb, p) else set(wa, if (p > wb) p else wb)
    }
    ui.dragging = false
}

private fun DrawScope.drawHandles(geos: List<SegGeo>, sel: Sel, color: Color, r: Float, stem: Float) {
    for (pos in listOf(sel.lo, sel.hi)) {
        val at = handleAt(geos, pos) ?: continue
        drawLine(color, at - Offset(0f, 2f), at + Offset(0f, r), strokeWidth = stem)
        drawCircle(color, r, at + Offset(0f, r))
    }
}

private fun DrawScope.drawSlice(
    m: Measured,
    blk: Blk,
    from: Int,
    top: Float,
    bottom: Float,
    ink: Ink,
    tint: Boolean,
    hidden: Boolean,
    flash: Boolean,
    underline: Boolean,
    lit: Boolean = false,
    studio: StudioPaint? = null,
    marks: MarkLayer? = null,
    heard: Heard? = null,
) {
    val layout = m.text
    val tone = blk.hue ?: ink.accent
    val x0 = ink.insetPx + blk.xOffEm * ink.bodyPx
    val shift = top - layout.getLineTop(from)
    if (lit) {
        val up = if (from == 0 && blk.gapEm < GAP_EM) blk.gapEm * ink.bodyPx else ink.pad
        val down = if (blk.speechEnd) ink.pad else 0f
        drawRect(tone.copy(alpha = 0.2f), Offset(0f, top - up), Size(size.width, bottom - top + up + down))
    }
    if (heard != null) {
        val up = if (from == 0 && blk.gapEm < GAP_EM) blk.gapEm * ink.bodyPx else ink.pad
        val down = if (blk.speechEnd) ink.pad else 0f
        drawRect(ink.text.copy(alpha = 0.08f), Offset(0f, top - up), Size(size.width, bottom - top + up + down))
    }
    if (tint) {
        val up = if (from == 0 && blk.gapEm < GAP_EM) blk.gapEm * ink.bodyPx else ink.pad
        val down = if (blk.speechEnd) ink.pad else 0f
        drawRect(tone.copy(alpha = 0.09f), Offset(0f, top - up), Size(size.width, bottom - top + up + down))
        drawRect(tone, Offset(0f, top - up), Size(ink.ruleWidth, bottom - top + up + down))
    }
    clipRect(0f, top, size.width, bottom) {
        if (blk.kind == Kind.Cue) {
            val glyphW = GLYPH_EM * ink.bodyPx
            for (l in from until layout.lineCount) {
                val lt = shift + layout.getLineTop(l)
                if (lt >= bottom - 1f) break
                val left = x0 + layout.getLineLeft(l) - (if (l == 0) glyphW else 0f) - 6f
                drawRoundRect(
                    ink.block, Offset(left, lt + 1f), Size(x0 + layout.getLineRight(l) + 6f - left, layout.getLineBottom(l) - layout.getLineTop(l) - 2f),
                    CornerRadius(8f, 8f),
                )
            }
            if (from == 0) {
                val h = CAPTION_EM * ink.bodyPx
                translate(x0 - glyphW + 2f, shift + layout.getLineTop(0) + (layout.getLineBottom(0) - layout.getLineTop(0) - h) / 2) {
                    with(ink.glyph) { draw(Size(h, h), colorFilter = ColorFilter.tint(ink.muted)) }
                }
            }
        }
        if (marks != null && !hidden) {
            for (mk in marks.marks) {
                if (mk.kind != "highlight") continue
                val r = blk.blkRange(mk.start, mk.end) ?: continue
                for (bx in boxesOf(layout, r, from)) {
                    drawRoundRect(
                        markColor(mk.hue, ink.dark), Offset(x0 + bx.left - 1f, shift + layout.getLineTop(bx.line)),
                        Size(bx.right - bx.left + 2f, layout.getLineBottom(bx.line) - layout.getLineTop(bx.line)), CornerRadius(4f, 4f),
                    )
                }
            }
        }
        val wordRange = heard?.word?.let { blk.blkRange(it.start, it.end) }
        val wordTone = blk.hue ?: ink.text
        if (wordRange != null) {
            for (bx in boxesOf(layout, wordRange, from)) {
                drawRoundRect(
                    wordTone.copy(alpha = 0.26f), Offset(x0 + bx.left - 1f, shift + layout.getLineTop(bx.line)),
                    Size(bx.right - bx.left + 2f, layout.getLineBottom(bx.line) - layout.getLineTop(bx.line)), CornerRadius(4f, 4f),
                )
            }
        }
        marks?.sel?.let { r ->
            for (bx in boxesOf(layout, r, from)) {
                drawRect(
                    marks.selTint, Offset(x0 + bx.left, shift + layout.getLineTop(bx.line)),
                    Size(bx.right - bx.left, layout.getLineBottom(bx.line) - layout.getLineTop(bx.line)),
                )
            }
        }
        drawText(layout, topLeft = Offset(x0, shift))
        if (wordRange != null) {
            for (bx in boxesOf(layout, wordRange, from)) {
                drawRect(
                    wordTone, Offset(x0 + bx.left, shift + layout.getLineBaseline(bx.line) + ink.bodyPx * 0.14f),
                    Size(bx.right - bx.left, 2.dp.toPx()),
                )
            }
        }
        m.name?.let { if (from == 0) drawText(it, topLeft = Offset(ink.insetPx, shift)) }
        if (marks != null && !hidden) {
            for (mk in marks.marks) {
                if (mk.kind != "underline" && mk.kind != "note") continue
                val r = blk.blkRange(mk.start, mk.end) ?: continue
                val note = mk.kind == "note"
                for (bx in boxesOf(layout, r, from)) {
                    val y = shift + layout.getLineBaseline(bx.line) + ink.bodyPx * (if (note) 0.24f else 0.14f)
                    if (note) {
                        drawLine(
                            ink.text, Offset(x0 + bx.left, y), Offset(x0 + bx.right, y), strokeWidth = ink.ruleWidth * 2 / 3,
                            pathEffect = PathEffect.dashPathEffect(floatArrayOf(ink.ruleWidth, ink.ruleWidth * 1.3f)),
                        )
                    } else {
                        drawRect(ink.text, Offset(x0 + bx.left, y), Size(bx.right - bx.left, ink.ruleWidth * 2 / 3))
                    }
                }
            }
            for (ins in blk.inserts) {
                if (ins.kind == "note") {
                    if (ins.range.first >= layout.layoutInput.text.length) continue
                    val box = layout.getBoundingBox(ins.range.first)
                    val g = ink.bodyPx * 0.62f
                    translate(x0 + box.center.x - g / 2, shift + (box.top + box.bottom) / 2 - g / 2) {
                        with(ink.note) { draw(Size(g, g), colorFilter = ColorFilter.tint(ink.text)) }
                    }
                } else if (ins.label != null) {
                    for (bx in boxesOf(layout, ins.label, from)) {
                        val top = shift + layout.getLineTop(bx.line) + ink.bodyPx * 0.08f
                        val bottom = shift + layout.getLineBottom(bx.line) - ink.bodyPx * 0.08f
                        drawRoundRect(
                            ink.muted, Offset(x0 + bx.left - 3f, top), Size(bx.right - bx.left + 6f, bottom - top), CornerRadius(5f, 5f),
                            style = Stroke(ink.ruleWidth * 0.4f),
                        )
                    }
                }
            }
        }
        if (studio != null && from == 0 && blk.speechStart && blk.role == studio.role) {
            studio.states[blk.owner]?.let { state -> markSpot(m, blk, ink, top, state)?.let { drawMark(it, state, blk, ink, studio) } }
        }
        if (studio != null && from == 0) {
            studio.ringFor(blk)?.let { v -> ringSpot(m, blk, ink, top, this, v)?.let { drawRing(it, v, blk, ink) } }
        }
        val cue = blk.cueRange
        if (underline && cue != null) {
            val first = layout.getLineForOffset(cue.first)
            val lastLine = layout.getLineForOffset(cue.last)
            for (l in first..lastLine) {
                if (l < from) continue
                val left = if (l == first) layout.getBoundingBox(cue.first).left else layout.getLineLeft(l)
                val right = if (l == lastLine) layout.getBoundingBox(cue.last).right else layout.getLineRight(l)
                drawRect(
                    blk.cueHue ?: tone,
                    Offset(x0 + left, shift + layout.getLineBaseline(l) + ink.bodyPx * 0.14f),
                    Size((right - left).coerceAtLeast(2f), ink.ruleWidth * 2 / 3),
                )
            }
        }
        if (hidden) {
            for (r in blk.said) {
                val first = layout.getLineForOffset(r.first)
                val lastLine = layout.getLineForOffset(r.last)
                for (l in first..lastLine) {
                    val left = if (l == first) layout.getBoundingBox(r.first).left else layout.getLineLeft(l)
                    val right = if (l == lastLine) layout.getBoundingBox(r.last).right else layout.getLineRight(l)
                    drawRoundRect(
                        tone.copy(alpha = 0.3f),
                        Offset(x0 + left, shift + layout.getLineTop(l) + 1f),
                        Size((right - left).coerceAtLeast(2f), layout.getLineBottom(l) - layout.getLineTop(l) - 2f),
                        CornerRadius(6f, 6f),
                    )
                }
            }
        }
    }
    if (flash) {
        drawRect(tone, Offset(1f, top - ink.pad), Size(size.width - 2f, bottom - top + 2 * ink.pad), style = Stroke(width = 2f * 2f))
    }
}

/** The line heard and, inside it, the word heard (PLAYS-DESIGN 2.11 rules 2 and 3): painted over the page, never part of its layout. */
private class Heard(val line: Int, val word: ReadAlong.Word?)

/** Whose lines are mine: a role (I'm playing), or in a room the exact lines this reader or seat holds (claims, assignment ranges). */
private class Mine(val role: String?, val lines: Set<Int>?, val lit: Int? = null) {
    fun has(b: Blk) = if (lines != null) b.role != null && b.owner in lines else role != null && b.role == role
}

private fun hideable(b: Blk, mine: Mine, hiding: Boolean, peeked: Int?) =
    hiding && mine.has(b) && b.kind == Kind.Text && b.owner != peeked

/** One page: its slices of the blocks it holds, measured now from the same text and width the pagination used. */
@Composable
private fun PageView(
    index: Int,
    page: ReaderPagination.Page?,
    flow: ReaderFlow,
    pal: Palette,
    mine: Mine,
    hiding: Boolean,
    peeked: Int?,
    flash: Int?,
    heard: Heard?,
    headPx: Float,
    onPeek: (Int) -> Unit,
    modifier: Modifier,
    ui: MarkUi,
    studio: StudioPaint? = null,
    onTakes: (Int) -> Unit = {},
    onRing: (PartID) -> Unit = {},
) {
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    val segs = page?.segs.orEmpty()
    val layouts = remember(page, flow, hiding, mine, peeked) {
        segs.map { seg ->
            val b = flow.blocks[seg.block]
            measureBlk(measurer, flow, b, hideable(b, mine, hiding, peeked))
        }
    }
    val ink = rememberInk(pal, flow)
    val contd = flow.paged?.contd?.getOrNull(index)?.takeIf { it >= 0 }?.let { flow.blocks[it] }
    val head = remember(contd, pal) {
        contd?.role?.takeIf { it.isNotEmpty() }?.let { role ->
            buildAnnotatedString {
                withStyle(SpanStyle(fontWeight = FontWeight.SemiBold, color = contd.hue ?: pal.muted)) { append(role) }
                withStyle(SpanStyle(color = pal.muted)) { append(" (cont’d)") }
            }
        }
    }
    val headLayout = remember(head, flow) {
        head?.let { measurer.measure(it, TextStyle(fontSize = with(density) { (CAPTION_EM * flow.bodyPx).toSp() })) }
    }
    val description = remember(page, flow) { segs.joinToString(" ") { flow.blocks[it.block].description } }
    val geos = remember(segs, layouts, flow, hiding, mine, peeked, ink, headPx) {
        segs.mapIndexed { s, seg ->
            val b = flow.blocks[seg.block]
            SegGeo(seg.block, b, layouts[s], seg.top + headPx, seg.bottom + headPx, seg.from, seg.to, ink.insetPx + b.xOffEm * ink.bodyPx, hideable(b, mine, hiding, peeked))
        }
    }
    var origin by remember { mutableStateOf(Offset.Zero) }
    var open by remember { mutableStateOf<Pair<Mark, Rect>?>(null) }
    val sel = ui.sel?.takeIf { it.where == index }
    val selTint = MaterialTheme.colorScheme.primary.copy(alpha = 0.3f)
    val handleColor = MaterialTheme.colorScheme.primary
    val handleR = with(density) { 9.dp.toPx() }
    LaunchedEffect(sel, geos, origin) { if (sel != null) ui.rect = selBounds(geos, sel)?.translate(origin) }
    val shownMarks = if (ui.model.show) ui.model.byLine else emptyMap()
    val markActions = remember(segs, flow, shownMarks) {
        MarksCore.order(ui.model.script, segs.map { flow.ids[flow.blocks[it.block].owner] }.distinct().flatMap { shownMarks[it].orEmpty() })
    }
    val markWhere = Rect(0f, headPx, 1f, headPx + 1f)
    Box(
        modifier
            .semantics {
                contentDescription = description
                customActions = markActions.map { m ->
                    CustomAccessibilityAction("${MARK_LABEL.getValue(m.kind)}: ${m.text.replace("_", "").ifEmpty { m.label.orEmpty() }}") { open = m to markWhere; true }
                }
            }
            .onGloballyPositioned { origin = it.positionInRoot() }
            .pointerInput(geos, flow) {
                awaitEachGesture { markTouch(geos, flow, ui, index, handleR, onOpen = { m, r -> open = m to r }) }
            },
    ) {
        Canvas(Modifier.fillMaxSize()) {
            headLayout?.let {
                val x = ink.insetPx + (if (flow.gutter) COL_EM * flow.bodyPx else 0f)
                drawText(it, topLeft = Offset(x, (headPx - it.size.height) / 2))
            }
            translate(top = headPx) {
                segs.forEachIndexed { s, seg ->
                    val b = flow.blocks[seg.block]
                    drawSlice(
                        layouts[s], b, seg.from, seg.top, seg.bottom, ink,
                        tint = mine.has(b) && b.kind != Kind.Heading,
                        hidden = hideable(b, mine, hiding, peeked), flash = b.owner == flash,
                        underline = mine.role != null && b.cueRole == mine.role,
                        lit = mine.lit == b.owner && b.kind != Kind.Heading,
                        heard = heard?.takeIf { it.line == b.owner },
                        studio = studio,
                        marks = MarkLayer(if (ui.model.show) ui.model.byLine[flow.ids[b.owner]].orEmpty() else emptyList(), selRange(sel, seg.block, b.text.length), selTint),
                    )
                }
                if (studio?.current != null) {
                    val current = segs.filter { flow.blocks[it.block].let { b -> b.owner == studio.current && b.role == studio.role } }
                    if (current.isNotEmpty()) {
                        val margin = 6.dp.toPx()
                        val top = current.first().top - ink.pad - margin
                        val bottom = current.last().bottom + ink.pad + margin
                        val stroke = when (studio.outline) {
                            StudioOutline.Ink -> Stroke(1.5.dp.toPx())
                            StudioOutline.Armed -> Stroke(2.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(6.dp.toPx(), 4.dp.toPx())))
                            StudioOutline.Recording -> Stroke(2.5.dp.toPx())
                        }
                        drawRoundRect(
                            if (studio.outline == StudioOutline.Ink) studio.ink else studio.record,
                            Offset(2.dp.toPx(), top), Size(size.width - 4.dp.toPx(), bottom - top), CornerRadius(8.dp.toPx()), style = stroke,
                        )
                    }
                }
            }
            if (sel != null) drawHandles(geos, sel, handleColor, handleR, 2.dp.toPx())
        }
        open?.let { (m, r) ->
            Box(Modifier.offset { IntOffset(r.left.toInt(), r.bottom.toInt()) }) {
                MarkMenu(
                    m, ui.dark,
                    onHue = { ui.model.update(m.id, MarkPatch(hue = it)); open = null },
                    onEdit = { open = null; ui.onEdit(m) },
                    onDelete = { open = null; ui.onDelete(m) },
                    onDismiss = { open = null },
                )
            }
        }
        if (studio != null) {
            segs.forEachIndexed { s, seg ->
                val b = flow.blocks[seg.block]
                if (seg.from != 0 || !b.speechStart || b.role != studio.role) return@forEachIndexed
                val state = studio.states[b.owner] ?: return@forEachIndexed
                val spot = markSpot(layouts[s], b, ink, seg.top, state) ?: return@forEachIndexed
                Box(
                    Modifier
                        .offset { IntOffset(spot.hit.left.toInt(), (spot.hit.top + headPx).toInt()) }
                        .size(with(density) { spot.hit.width.toDp() }, with(density) { spot.hit.height.toDp() })
                        .clickable(role = Role.Button, onClickLabel = "Open the take list") { onTakes(b.owner) }
                        .semantics(mergeDescendants = true) { contentDescription = StudioCore.spoken(state) },
                )
            }
        }
        if (studio != null) {
            segs.forEachIndexed { s, seg ->
                val b = flow.blocks[seg.block]
                if (seg.from != 0) return@forEachIndexed
                val voice = studio.ringFor(b) ?: return@forEachIndexed
                val spot = ringSpot(layouts[s], b, ink, seg.top, density, voice) ?: return@forEachIndexed
                Box(
                    Modifier
                        .offset { IntOffset(spot.hit.left.toInt(), (spot.hit.top + headPx).toInt()) }
                        .size(with(density) { spot.hit.width.toDp() }, with(density) { spot.hit.height.toDp() })
                        .clickable(role = Role.Button, onClickLabel = "Choose the voice") { onRing(voice.part) }
                        .semantics(mergeDescendants = true) { contentDescription = "Device voice for ${voice.part.title}: ${voice.label}" },
                )
            }
        }
        segs.forEach { seg ->
            val b = flow.blocks[seg.block]
            if (hideable(b, mine, hiding, peeked)) {
                val top = seg.top + headPx
                Box(
                    Modifier
                        .offset { IntOffset(0, top.toInt()) }
                        .size(with(density) { flow.colPx.toDp() }, with(density) { (seg.bottom - seg.top).toDp() })
                        .semantics(mergeDescendants = true) {
                            role = Role.Button
                            contentDescription = "Show line"
                            onClick(label = "Show line") { onPeek(b.owner); true }
                        },
                )
            }
        }
    }
}

@Composable
private fun rememberInk(pal: Palette, flow: ReaderFlow): Ink {
    val density = LocalDensity.current
    val glyph = rememberVectorPainter(Icons.AutoMirrored.Filled.VolumeUp)
    val warn = rememberVectorPainter(Icons.Filled.Warning)
    val measurer = rememberTextMeasurer()
    val note = rememberVectorPainter(Icons.AutoMirrored.Filled.StickyNote2)
    val wave = rememberVectorPainter(Icons.Filled.GraphicEq)
    val dark = OnAir.colors.dark
    return remember(pal, flow, glyph, warn, measurer, note, wave, dark) {
        Ink(
            pal.accent, pal.block, pal.muted, with(density) { 3.dp.toPx() }, flow.bodyPx * LINE_GAP_EM / 3, with(density) { RuleInset.toPx() },
            flow.bodyPx, glyph, warn, measurer, with(density) { 44.dp.toPx() }, pal.text, dark, note, wave,
        )
    }
}

/** One block in Scroll: the whole of it, its width the column's. */
@Composable
private fun ScrollBlock(
    blk: Blk, index: Int, flow: ReaderFlow, pal: Palette, mine: Mine, hiding: Boolean, peeked: Int?, flash: Boolean, heard: Heard?, ui: MarkUi, onPeek: (Int) -> Unit,
) {
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    val hidden = hideable(blk, mine, hiding, peeked)
    val m = remember(blk, flow, hidden) { measureBlk(measurer, flow, blk, hidden) }
    val ink = rememberInk(pal, flow)
    val height = with(density) { m.text.size.height.toDp() }
    val geos = remember(m, blk, index, hidden, ink) {
        listOf(SegGeo(index, blk, m, 0f, m.text.size.height.toFloat(), 0, m.text.lineCount, ink.insetPx + blk.xOffEm * ink.bodyPx, hidden))
    }
    var open by remember { mutableStateOf<Pair<Mark, Rect>?>(null) }
    var origin by remember { mutableStateOf(Offset.Zero) }
    val sel = ui.sel?.takeIf { it.where == index }
    val selTint = MaterialTheme.colorScheme.primary.copy(alpha = 0.3f)
    val handleColor = MaterialTheme.colorScheme.primary
    val handleR = with(density) { 9.dp.toPx() }
    LaunchedEffect(sel, geos, origin) { if (sel != null) ui.rect = selBounds(geos, sel)?.translate(origin) }
    Box(
        Modifier
            .onGloballyPositioned { origin = it.positionInRoot() }
            .pointerInput(geos, flow) { awaitEachGesture { markTouch(geos, flow, ui, index, handleR, onOpen = { mk, r -> open = mk to r }) } },
    ) {
    Canvas(
        Modifier
            .width(with(density) { flow.colPx.toDp() })
            .padding(top = with(density) { (flow.bodyPx * blk.gapEm).toDp() })
            .height(height)
            .then(
                if (hidden) {
                    Modifier
                        .clickable(onClickLabel = "Show line") { onPeek(blk.owner) }
                        .semantics { role = Role.Button; contentDescription = "Show line" }
                } else {
                    Modifier.semantics { contentDescription = blk.description; if (blk.heading) heading() }
                },
            ),
    ) {
        drawSlice(
            m, blk, 0, 0f, m.text.size.height.toFloat(), ink,
            tint = mine.has(blk) && blk.kind != Kind.Heading, hidden = hidden, flash = flash,
            underline = mine.role != null && blk.cueRole == mine.role,
            lit = mine.lit == blk.owner && blk.kind != Kind.Heading,
            heard = heard?.takeIf { it.line == blk.owner },
            marks = MarkLayer(if (ui.model.show) ui.model.byLine[flow.ids[blk.owner]].orEmpty() else emptyList(), selRange(sel, index, blk.text.length), selTint),
        )
        if (sel != null) drawHandles(geos, sel, handleColor, handleR, 2.dp.toPx())
    }
    open?.let { (mk, r) ->
        Box(Modifier.offset { IntOffset(r.left.toInt(), (r.bottom + with(density) { (flow.bodyPx * blk.gapEm).toDp().toPx() }).toInt()) }) {
            MarkMenu(
                mk, ui.dark,
                onHue = { ui.model.update(mk.id, MarkPatch(hue = it)); open = null },
                onEdit = { open = null; ui.onEdit(mk) },
                onDelete = { open = null; ui.onDelete(mk) },
                onDismiss = { open = null },
            )
        }
    }
    }
}


// MARK: The screen

/** What a hardware key or pedal asks of the visible stage, set by whichever stage is showing. */
private class Turner {
    var turn: (ReaderMath.Turn) -> Unit = {}
}

private fun readerKeyName(key: Key): String? = when (key) {
    Key.DirectionRight -> "ArrowRight"
    Key.DirectionDown -> "ArrowDown"
    Key.DirectionLeft -> "ArrowLeft"
    Key.DirectionUp -> "ArrowUp"
    Key.PageDown -> "PageDown"
    Key.PageUp -> "PageUp"
    Key.Spacebar -> " "
    Key.MoveHome -> "Home"
    Key.MoveEnd -> "End"
    else -> null
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalMaterial3AdaptiveApi::class)
@Composable
internal fun ReaderBody(
    script: PlayScript,
    startLine: String?,
    studioTarget: StudioTarget?,
    onBack: () -> Unit,
    onOpenStudio: (String, String, String?) -> Unit,
    alongProduction: String? = null,
    alongDrama: DramaAlong? = null,
    room: RoomSeam? = null,
    marksDao: com.example.appname.plays.MarkDao? = null,
) {
    val context = LocalContext.current
    val store = remember { ReaderStore(context.getSharedPreferences("ed.reader", android.content.Context.MODE_PRIVATE)) }
    val haptics = rememberHaptics()
    val density = LocalDensity.current
    val resolver = LocalFontFamilyResolver.current
    val dark = OnAir.colors.dark
    val container = LocalAppContainer.current
    val muted = com.example.appname.navigation.LocalPlayerMuted.current
    val television = LocalIsTelevision.current
    // A reader in a room makes no sound (PLAYS-DESIGN §12.3), so it has no cast to hear.
    val deviceVoices = if (room == null) rememberDeviceVoices() else null
    val castHandle = deviceVoices?.let { rememberCast(it, script, studioTarget?.production) }
    val studio = rememberStudio(studioTarget, script, startLine, castHandle)
    var prefs by remember { mutableStateOf(store.prefs()) }
    var volumeKeys by remember { mutableStateOf(store.volumeKeys) }
    val saved = remember(script.id) { store.position(script.id) }
    var posId by rememberSaveable(script.id) {
        val open = studio?.studio?.current?.value ?: startLine ?: saved["line"]
        mutableStateOf(script.lines.firstOrNull { it.id == open }?.id ?: script.lines.firstOrNull()?.id.orEmpty())
    }
    var part by rememberSaveable(script.id) {
        mutableStateOf(
            studio?.part?.raw ?: saved["part"]?.takeIf { p -> script.castParts.any { it.id.raw == p && it.id.isSpeaking } },
        )
    }
    var hiding by rememberSaveable(script.id) { mutableStateOf(false) }
    var peeked by remember { mutableStateOf<Int?>(null) }
    var flash by remember { mutableStateOf<Int?>(null) }
    var jump by remember { mutableIntStateOf(0) }
    // The last jump follows a line heard (the read-along, a room's cursor): it turns to the line's words, not its front.
    var jumpFollows by remember { mutableStateOf(false) }
    var sheet by rememberSaveable { mutableStateOf("") }
    val scope = rememberCoroutineScope()
    val snackbar = remember { SnackbarHostState() }
    val marksModel = remember(script.id) {
        MarksModel(
            script, MarksRepository(marksDao ?: MarksDatabase.get(context).marks()),
            MarksPrefsStore(context.getSharedPreferences("ed.marks", android.content.Context.MODE_PRIVATE)), scope,
        )
    }
    LaunchedEffect(marksModel) { marksModel.load() }
    var composing by remember { mutableStateOf<Composing?>(null) }
    val clipboard = androidx.compose.ui.platform.LocalClipboard.current
    var pickingVoice by remember { mutableStateOf<PartID?>(null) }
    var pageLabel by remember { mutableStateOf("") }
    val posIndex = remember(posId, script) { script.lines.indexOfFirst { it.id == posId }.coerceAtLeast(0) }
    val mineRole = part?.let { PartID(it).roleName }
    // The room seam (PLAYS-DESIGN §12, ANDROID-DESIGN §4.19): the reader follows the room's cursor and tints the lines this device holds.
    val roomState = room?.session?.state?.collectAsState()?.value
    val roomSnap = roomState?.snapshot
    val roomCast = remember(script) { script.lines.map { it.id to it.part.raw } }
    val roomMine: Set<Int>? = remember(roomSnap?.generation, roomSnap?.you, roomSnap?.claims, roomSnap?.assignments) {
        val s = roomSnap
        if (s == null || s.you?.role == "screen") null
        else script.lines.indices.filter { ReadCore.holds(s.room, roomCast, s.meMember, it) }.toSet()
    }
    val roomIdx = roomSnap?.cursor?.let { id -> script.lines.indexOfFirst { it.id == id }.takeIf { it >= 0 } }
    val mine = remember(mineRole, roomMine, roomIdx, room == null) { Mine(if (room == null) mineRole else null, roomMine, roomIdx) }
    var roomHide by rememberSaveable(script.id) { mutableStateOf(false) }
    val roomHiding = roomHide && roomSnap?.mode == "rehearse"
    val roomFollow = remember(script.id) { ReadAlong.Follow() }
    var roomAway by remember { mutableStateOf(false) }
    val focus = remember { FocusRequester() }
    val turner = remember { Turner() }
    val animationsOff = remember {
        Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    }

    val onSurface = MaterialTheme.colorScheme.onSurface
    val mutedInk = MaterialTheme.colorScheme.onSurfaceVariant
    val accent = MaterialTheme.colorScheme.primary
    val block = MaterialTheme.colorScheme.surfaceContainerHigh
    val pal = remember(script, dark, onSurface, mutedInk, accent, block) {
        val hues = HashMap<String, Color>()
        script.castParts.filter { it.id.isSpeaking }.forEach { p ->
            genreColor(script.partHue(p.id), dark)?.let { hues[p.id.roleName.orEmpty()] = it }
        }
        Palette(onSurface, mutedInk, accent, block, hues)
    }

    val ui = remember(marksModel, dark, haptics) {
        MarkUi(
            marksModel, dark,
            onEdit = { m -> composing = Composing(m.kind, emptyList(), m) },
            onDelete = { m ->
                val wasLost = marksModel.isLost(m.id)
                val removed = marksModel.remove(m.id)
                scope.launch {
                    val r = snackbar.showSnackbar("Mark deleted", actionLabel = "Undo", duration = SnackbarDuration.Short)
                    if (r == SnackbarResult.ActionPerformed) marksModel.restore(removed, if (wasLost) removed.map { it.id }.toSet() else emptySet())
                }
            },
            haptic = { haptics(Haptic.Selection) },
        )
    }
    LaunchedEffect(posId, sheet) { ui.sel = null }
    LaunchedEffect(composing) { if (composing != null) ui.sel = null }

    /** A mark the selection asks for: a beat or a note opens its sheet first; the rest are made now. */
    fun markSelection(kind: String) {
        val s = ui.sel ?: return
        if (s.pieces.isEmpty()) {
            ui.sel = null
            return
        }
        if (kind == "beat" || kind == "note") {
            composing = Composing(kind, s.pieces, null)
        } else {
            marksModel.make(kind, s.pieces)
            haptics(Haptic.Selection)
        }
        ui.sel = null
    }

    LaunchedEffect(posId, part) {
        delay(300)
        store.savePosition(script.id, posId.ifEmpty { null }, if (studio != null) saved["part"] else part)
    }
    LaunchedEffect(flash) {
        if (flash != null) {
            delay(1600)
            flash = null
        }
    }
    LaunchedEffect(sheet, studio?.sheet) { if (sheet.isEmpty() && studio?.sheet != true) runCatching { focus.requestFocus() } }

    val place = remember(posIndex, script) { ScriptReading.placeOf(script, posIndex) }
    val windowWidth = with(LocalDensity.current) { androidx.compose.ui.platform.LocalWindowInfo.current.containerSize.width.toDp() }
    val wide = windowWidth >= 600.dp
    val adaptive = currentWindowAdaptiveInfo()
    val tabletop = adaptive.windowPosture.isTabletop
    // The studio's panel stands beside the script once the reader has 860 dp, or below the hinge in tabletop (§2.9 rule 7).
    val paneMode = studio != null && (windowWidth >= 860.dp || tabletop)

    /** Goes to a line: the position is that line wherever it falls, and the stage turns to it. */
    fun goTo(index: Int, outline: Boolean, follows: Boolean = false) {
        if (index !in script.lines.indices) return
        posId = script.lines[index].id
        peeked = null
        if (outline) flash = index
        jumpFollows = follows
        jump++
    }
    fun follow(id: String) = goTo(script.lines.indexOfFirst { it.id == id }, outline = false, follows = true)
    SideEffect { studio?.studio?.onFollow = { id -> follow(id) } }
    LaunchedEffect(roomSnap?.cursor) {
        val cursor = roomSnap?.cursor ?: return@LaunchedEffect
        if (roomFollow.line(cursor).turn) follow(cursor)
    }

    // Read along (PLAYS-DESIGN 2.11): the production's listen-through, a finished drama, or Hear the cast; one transport,
    // the page following the line heard and, inside it, the word heard (device voices only).
    val alongMode = alongProduction != null || alongDrama != null
    val alongPrefs = remember { context.getSharedPreferences("ed.reader", android.content.Context.MODE_PRIVATE) }
    var alongSpeed by remember { mutableStateOf(AlongModel.savedSpeed(alongPrefs)) }
    var dramaOn by remember { mutableStateOf(false) }
    val alongFollow = remember(script.id) { ReadAlong.Follow() }
    var alongFollowing by remember { mutableStateOf(true) }
    var alongLine by remember { mutableStateOf<String?>(null) }
    var alongWord by remember { mutableStateOf<ReadAlong.Word?>(null) }
    var alongModel by remember { mutableStateOf<AlongModel?>(null) }
    val alongState = alongModel?.state?.collectAsState()?.value
    val playbackNow = container.playback.state.collectAsState().value
    val alongActive = alongModel != null || dramaOn
    val alongPlaying = if (dramaOn) playbackNow.isPlaying else alongState?.playing == true
    val backShown = alongActive && alongPlaying && !alongFollowing
    val hearing: ScriptLine? = if (alongState?.device == true) alongLine?.let { id -> script.lines.firstOrNull { it.id == id } } else null
    fun alongAway() {
        if (alongMode || alongActive) { alongFollow.away(); alongFollowing = false }
        if (room != null && roomFollow.following) { roomFollow.away(); roomAway = true }
    }
    fun alongBack() {
        alongFollowing = true
        alongFollow.back()?.let { follow(it) }
    }
    fun stopAlong() {
        if (dramaOn) { dramaOn = false; container.playback.stop() }
        alongModel?.stop()
        alongModel = null
        alongLine = null
        alongWord = null
        alongFollow.back()
        alongFollowing = true
    }
    DisposableEffect(script.id) { onDispose { alongModel?.stop(); if (dramaOn) container.playback.stop() } }
    // A finished drama: the file playing is the line heard, the page following it at file boundaries.
    LaunchedEffect(dramaOn) {
        val d = alongDrama ?: return@LaunchedEffect
        if (!dramaOn) return@LaunchedEffect
        container.playback.state.collect { st ->
            val seq = d.plan.firstOrNull { dramaRowId(d.pid, it.seq) == st.episode?.id }?.seq
            val last = d.plan.lastOrNull()?.takeIf { it.seq == seq }
            if (seq == null || (last != null && !st.isPlaying && st.durationMs > 0 && st.positionMs >= st.durationMs - 250)) {
                stopAlong()
                return@collect
            }
            val id = script.lines[seq - 1].id
            if (id == alongLine) return@collect
            val step = alongFollow.line(id)
            alongLine = id
            alongWord = null
            if (step.turn) follow(id)
        }
    }
    LaunchedEffect(alongModel) {
        val m = alongModel ?: return@LaunchedEffect
        m.state.collect { s ->
            alongWord = s.word
            if (s.line != alongLine) {
                val step = alongFollow.line(s.line)
                alongLine = s.line
                if (step.turn && s.line != null) follow(s.line)
            }
        }
    }
    fun startDramaAlong(d: DramaAlong) {
        if (container.playback.state.value.isPlaying) container.playback.togglePlay()
        alongFollow.back()
        alongFollowing = true
        val files = d.plan.filter { it.seq > posIndex }.ifEmpty { d.plan }
        dramaOn = true
        haptics(Haptic.Selection)
        container.playback.playFiles(
            files.map { f -> dramaRowId(d.pid, f.seq).let { EpisodeRow(it, it, script.title, null, null, null, script.title, null, PLAY_BOARD) } },
            files.map { it.url },
        )
        container.playback.setSpeed(alongSpeed.toFloat())
    }

    fun startModel(plan: List<Relay.ListenEntry>) {
        val h = castHandle ?: return
        if (container.playback.state.value.isPlaying) container.playback.togglePlay()
        alongFollow.back()
        alongFollowing = true
        alongModel?.stop()
        val production = alongProduction?.let { container.plays.store.takesFolder(it) }
        val model = AlongModel(scope, script, plan, production, h.speaker, muted, alongSpeed, onEnd = { stopAlong() })
        alongModel = model
        haptics(Haptic.Selection)
        model.play(0)
    }

    fun startAlong() {
        alongDrama?.let { return startDramaAlong(it) }
        val h = castHandle ?: return
        val id = alongProduction ?: return
        val production = container.plays.store.production(id) ?: return
        val ids = script.lines.drop(posIndex).map { it.id }.toSet()
        startModel(Relay.listenPlan(production, script) { !it.isSpeaking && h.cast.resolve(it).read }.filter { it.lineID in ids })
    }

    /** Hear the cast: the same read-along over the play's own cast, from the reader's place (rule 1). */
    fun startHearing() {
        val h = castHandle ?: return
        startModel(AlongModel.tablePlan(script, posIndex) { h.cast.resolve(it).read })
    }

    // Read along starts reading at once, from the reader's place (rule 1).
    var autoStarted by rememberSaveable(script.id) { mutableStateOf(false) }
    LaunchedEffect(alongMode, castHandle != null) {
        if (alongMode && !autoStarted && (alongDrama != null || castHandle != null)) {
            autoStarted = true
            startAlong()
        }
    }

    fun alongPlayPause() {
        if (dramaOn) {
            if (container.playback.state.value.isPlaying) container.playback.pause() else container.playback.restartItem()
        } else {
            val m = alongModel ?: return
            if (alongState?.playing == true) m.pause() else m.play()
        }
        haptics(Haptic.Selection)
    }
    fun alongStep(by: Int) {
        if (dramaOn) container.playback.seekItem(by) else alongModel?.step(by)
        haptics(Haptic.Selection)
    }
    fun alongSetSpeed(x: Double) {
        alongSpeed = ReadAlong.speed(x)
        AlongModel.saveSpeed(alongPrefs, alongSpeed)
        alongModel?.speed = alongSpeed
        if (dramaOn) container.playback.setSpeed(alongSpeed.toFloat())
        haptics(Haptic.Selection)
    }

    fun myLine(direction: Int) {
        if (studio != null) {
            if (studio.studio.move(direction)) {
                haptics(Haptic.Selection)
                studio.studio.current.value?.let { follow(it) }
            }
            return
        }
        val p = PartID(part ?: return)
        var i = ScriptReading.nextLineOf(script, p, posIndex, direction)
        if (i < 0 && direction > 0) i = ScriptReading.nextLineOf(script, p, -1, 1)
        if (i >= 0) {
            haptics(Haptic.Selection)
            goTo(i, outline = true)
        }
    }

    /** Record in the reader's bottom bar: continues the part, takes it where it is open, else makes a production (§2.9 rule 1). */
    fun record() {
        val raw = part ?: return
        scope.launch {
            StudioOpen.resolve(container.plays, script, PartID(raw))?.let { onOpenStudio(it, raw, posId) }
        }
    }

    fun finishPart() {
        val t = studio ?: return
        val latest = container.plays.store.production(t.target.production) ?: return
        try {
            container.plays.store.save(Relay.finish(t.part, latest, t.script))
            t.close()
            onBack()
        } catch (e: Relay.Refusal) {
            t.refusal = e.text
        }
    }

    SelectionToolbar(
        active = ui.sel != null && !ui.dragging && sheet.isEmpty() && composing == null,
        rect = ui.rect,
        onAction = { a ->
            if (a == "copy") {
                ui.sel?.let { sel ->
                    val text = sel.pieces.joinToString(" ") { pc ->
                        script.lines.firstOrNull { it.id == pc.line }?.let { ScriptReading.lineText(it) }?.substring(pc.start, pc.end).orEmpty()
                    }
                    scope.launch { clipboard.setClipEntry(androidx.compose.ui.platform.ClipEntry(android.content.ClipData.newPlainText(null, text.replace("_", "")))) }
                }
                ui.sel = null
            } else {
                markSelection(a)
            }
        },
        onGone = { ui.sel = null },
    )

    val keys = Modifier.onPreviewKeyEvent { e: KeyEvent ->
        val studioKey = studio != null && when (e.key) {
            Key.Spacebar, Key.HeadsetHook, Key.MediaPlayPause, Key.Enter, Key.NumPadEnter, Key.R -> true
            else -> false
        }
        val volume = volumeKeys && (e.key == Key.VolumeDown || e.key == Key.VolumeUp)
        val name = readerKeyName(e.key)
        val letter = part != null && (e.key == Key.J || e.key == Key.K)
        val markKey = ui.sel != null && when (e.key) {
            Key.H, Key.U, Key.Slash, Key.P, Key.B, Key.N, Key.Escape -> true
            else -> false
        }
        if (!studioKey && !volume && name == null && !letter && !markKey) return@onPreviewKeyEvent false
        if (e.type == KeyEventType.KeyDown) {
            when {
                markKey -> when (e.key) {
                    Key.H -> markSelection("highlight")
                    Key.U -> markSelection("underline")
                    Key.Slash -> markSelection("breath")
                    Key.P -> markSelection("pause")
                    Key.B -> markSelection("beat")
                    Key.N -> markSelection("note")
                    else -> ui.sel = null
                }
                studioKey -> when (e.key) {
                    Key.Enter, Key.NumPadEnter -> studio.studio.keep()
                    Key.R -> scope.launch { studio.again() }
                    else -> scope.launch { studio.primary() }
                }
                volume -> { alongAway(); turner.turn(ReaderMath.Turn.By(if (e.key == Key.VolumeDown) 1 else -1)) }
                letter -> myLine(if (e.key == Key.J) 1 else -1)
                else -> ReaderMath.keyTurn(name!!, e.isShiftPressed)?.let { alongAway(); turner.turn(it) }
            }
        }
        true
    }

    val studioPhase = studio?.session?.phase?.collectAsState()?.value
    val studioProduction = studio?.session?.production?.collectAsState()?.value
    val studioCurrent = studio?.studio?.current?.collectAsState()?.value
    val inReview = studioPhase is RecordingSession.Phase.Review || studioPhase is RecordingSession.Phase.RunReview
    val recordRed = OnAir.colors.record
    val warningInk = AppSemantics.colors.warning
    val paint = if (studio != null && studioProduction != null && mineRole != null) {
        StudioPaint(
            role = mineRole,
            current = studioCurrent?.let { id -> script.lines.indexOfFirst { it.id == id }.takeIf { it >= 0 } },
            outline = when (studioPhase) {
                is RecordingSession.Phase.Listening -> StudioOutline.Recording
                is RecordingSession.Phase.Cue -> StudioOutline.Armed
                else -> StudioOutline.Ink
            },
            states = studio.studio.mine.associate { id ->
                script.lines.indexOfFirst { it.id == id } to StudioCore.lineState(studioProduction, id)
            },
            record = recordRed,
            warning = warningInk,
            ink = onSurface,
            rings = if (castHandle == null) emptyMap() else script.castParts.map { it.id }
                .filter { it.isSpeaking && it != studio.part }
                .associate { p ->
                    val d = describeVoice(castHandle, p)
                    p.roleName!! to DeviceVoice(p, if (d.resolved.read && !d.resolved.none) chipVoiceName(StudioCore.shortVoiceName(d.text), castHandle.cast.soleAccent()) else d.text, d.text)
                },
            taken = script.lines.indices.filter { studioProduction.usableTake(script.lines[it].id) != null }.toSet(),
        )
    } else {
        null
    }

    /** The reader's own bar: the part, Hide my lines and the page count; Record once a part is chosen; the Studio button on a phone. */
    val bar: @Composable () -> Unit = {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = Spacing.S2.dp, vertical = Spacing.S1.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (studio != null) {
                Text(
                    studio.part.title, Modifier.weight(1f).padding(horizontal = Spacing.S2.dp),
                    style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis,
                    color = genreColor(script.partHue(studio.part), dark) ?: onSurface,
                )
            } else if (room != null) {
                Box(Modifier.weight(1f))
            } else {
                var menu by remember { mutableStateOf(false) }
                Box(Modifier.weight(1f)) {
                    TextButton(onClick = { menu = true }) {
                        val who = part?.let { PartID(it).title }
                        Text(
                            if (who == null) "I’m playing…" else "I’m playing $who",
                            maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.widthIn(max = 168.dp),
                        )
                    }
                    DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                        DropdownMenuItem(
                            text = { Text("Nobody") },
                            leadingIcon = if (part == null) ({ Icon(Icons.Filled.Check, contentDescription = null) }) else null,
                            onClick = { menu = false; part = null; hiding = false; peeked = null; haptics(Haptic.Selection) },
                        )
                        script.castParts.filter { it.id.isSpeaking }.forEach { p ->
                            DropdownMenuItem(
                                text = { Text("${p.title} · ${p.lineCount}") },
                                leadingIcon = if (part == p.id.raw) ({ Icon(Icons.Filled.Check, contentDescription = null) }) else null,
                                onClick = { menu = false; part = p.id.raw; peeked = null; haptics(Haptic.Selection) },
                            )
                        }
                    }
                }
                if (castHandle != null || alongDrama != null) {
                    val label = if (alongMode) "Read along" else "Hear the cast"
                    TextButton(onClick = { if (alongMode) startAlong() else startHearing() }) {
                        Icon(Icons.Filled.PlayArrow, contentDescription = label)
                        if (wide) Text(label, Modifier.padding(start = Spacing.S1.dp))
                    }
                }
                if (part != null) {
                    IconButton(onClick = { myLine(1) }) { Icon(Icons.Filled.VerticalAlignBottom, contentDescription = "Next line") }
                }
            }
            if (part != null && room == null) {
                IconToggleButton(checked = hiding, onCheckedChange = { hiding = it; peeked = null; haptics(Haptic.Selection) }) {
                    Icon(if (hiding) Icons.Filled.VisibilityOff else Icons.Filled.Visibility, contentDescription = "Hide my lines")
                }
            }
            if (studio == null && part != null && !television && !alongMode && room == null) {
                IconButton(onClick = { record() }) { Icon(Icons.Filled.Mic, contentDescription = "Record") }
            }
            // A review hides the page count and the Studio button so its three buttons fit at 320 dp.
            if (studio != null && !paneMode && !inReview) {
                IconButton(onClick = { studio.sheet = true }) { Icon(Icons.Filled.Tune, contentDescription = "Studio") }
            }
            if (!inReview) {
                Text(
                    pageLabel,
                    style = MaterialTheme.typography.bodySmall,
                    color = mutedInk,
                    modifier = Modifier.padding(horizontal = Spacing.S2.dp),
                )
            }
        }
    }

    /** The read-along's transport (rule 6): the speaker, previous line, play or pause, next line, speed, stop. */
    val transport: @Composable () -> Unit = {
        val speakerPart = alongLine?.let { id -> script.lines.firstOrNull { it.id == id }?.part }
        val hue = speakerPart?.let { genreColor(script.partHue(it), dark) } ?: onSurface
        var speedMenu by remember { mutableStateOf(false) }
        Row(
            Modifier.fillMaxWidth().padding(horizontal = Spacing.S2.dp, vertical = Spacing.S1.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                speakerPart?.title.orEmpty(), Modifier.weight(1f).padding(horizontal = Spacing.S2.dp),
                style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis, color = hue,
            )
            IconButton(onClick = { alongStep(-1) }) { Icon(Icons.Filled.SkipPrevious, contentDescription = "Previous line") }
            IconButton(onClick = { alongPlayPause() }) {
                Icon(if (alongPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow, contentDescription = if (alongPlaying) "Pause" else "Play")
            }
            IconButton(onClick = { alongStep(1) }) { Icon(Icons.Filled.SkipNext, contentDescription = "Next line") }
            Box {
                TextButton(onClick = { speedMenu = true }, Modifier.semantics { contentDescription = "Speed ${ReadAlong.speedLabel(alongSpeed)}" }) {
                    Text(ReadAlong.speedLabel(alongSpeed))
                }
                DropdownMenu(expanded = speedMenu, onDismissRequest = { speedMenu = false }) {
                    ReadAlong.SPEEDS.forEach { x ->
                        DropdownMenuItem(
                            text = { Text(ReadAlong.speedLabel(x)) },
                            leadingIcon = if (x == alongSpeed) ({ Icon(Icons.Filled.Check, contentDescription = null) }) else null,
                            onClick = { speedMenu = false; alongSetSpeed(x) },
                        )
                    }
                }
            }
            IconButton(onClick = { stopAlong() }) { Icon(Icons.Filled.Stop, contentDescription = "Stop") }
            if (wide) Text(pageLabel, style = MaterialTheme.typography.bodySmall, color = mutedInk, modifier = Modifier.padding(horizontal = Spacing.S2.dp))
        }
    }

    val pickVoice: (PartID) -> Unit = { pickingVoice = it }
    val heardIdx = alongLine?.let { id -> script.lines.indexOfFirst { it.id == id }.takeIf { it >= 0 } }
    val heard = heardIdx?.let { Heard(it, alongWord) }

    /** The page: pages (the studio always reads in pages, so a line is whole), or Scroll when no studio is attached. */
    val stage: @Composable () -> Unit = {
        BoxWithConstraints(
            Modifier.fillMaxSize().clipToBounds().focusRequester(focus).focusable().then(keys)
                .pointerInput(alongMode, room == null) {
                    if (alongMode || room != null) awaitEachGesture { awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial); alongAway() }
                },
        ) {
            val shownPrefs = if (studio != null && !prefs.pages) prefs.copy(layout = "pages") else prefs
            val bodyPx = with(density) { (BODY_SP * shownPrefs.scale).sp.toPx() }
            val per = ReaderMath.perSpread(maxWidth.value)
            val marginPx = with(density) { PageMargin.toPx() }
            val gapPx = with(density) { PageGap.toPx() }
            val vertical = with(density) { PageVertical.toPx() }
            val headPx = with(density) { PageHead.toPx() }
            val footPx = if (studio != null) with(density) { StudioFoot.toPx() } else 0f
            val colPx = (((constraints.maxWidth - 2 * marginPx - (per - 1) * gapPx) / per).coerceAtMost(36 * bodyPx)).toInt().coerceAtLeast(1)
            val spec = FlowSpec(
                script.id, colPx, (constraints.maxHeight - headPx - vertical - footPx).toInt().coerceAtLeast(1), density.density, density.fontScale,
                shownPrefs, dark, per, with(density) { RuleInset.toPx() }.toInt(), studio?.part?.roleName, marksModel.points,
            )
            val ready = marksModel.ready
            val flow by produceState<ReaderFlow?>(null, spec, pal, ready) { if (ready) value = computeFlow(script, spec, pal, resolver, density) }
            val f = flow
            when {
                f == null -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(Modifier.semantics { contentDescription = "Loading" })
                }
                f.paged != null -> key(f) {
                    PagesStage(
                        f, f.paged, posIndex = posIndex, jump = jump, jumpFollows = jumpFollows, mine = mine, hiding = if (room != null) roomHiding else hiding, peeked = if (roomHiding) peeked ?: roomIdx else peeked, flash = flash,
                        heard = heard, following = alongFollowing, pal = pal, headPx = headPx, animationsOff = animationsOff, turner = turner, haptics = { haptics(Haptic.Selection) },
                        vertical = vertical, gap = gapPx, ui = ui,
                        onPos = { posId = script.lines[it].id },
                        onPeek = { peeked = it }, onClearPeek = { peeked = null }, onLabel = { pageLabel = it },
                        studio = paint, onRing = pickVoice,
                        onSelect = { idx -> if (studio?.studio?.select(script.lines[idx].id) == true) haptics(Haptic.Selection) },
                        onTakes = { idx ->
                            studio?.let {
                                it.studio.select(script.lines[idx].id)
                                if (!paneMode) it.sheet = true
                            }
                        },
                    )
                }
                else -> key(f) {
                    ScrollStage(
                        f, posIndex = posIndex, jump = jump, mine = mine, hiding = if (room != null) roomHiding else hiding, peeked = if (roomHiding) peeked ?: roomIdx else peeked, flash = flash, heard = heard, following = alongFollowing, animationsOff = animationsOff, pal = pal,
                        turner = turner, margin = marginPx, vertical = vertical, ui = ui,
                        onPos = { posId = script.lines[it].id }, onPeek = { peeked = it }, onLabel = { pageLabel = it },
                    )
                }
            }
        }
    }

    val panel: @Composable (Boolean) -> Unit = { full ->
        if (studio != null) {
            StudioPanel(
                studio, castHandle, muted, full = full, onPickVoice = pickVoice, onFollow = { follow(it) }, onDone = { finishPart() },
                onTakes = { id -> studio.studio.select(id) },
            )
        }
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbar) },
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text(script.title, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        if (place.label.isNotEmpty()) {
                            Text(place.label, style = MaterialTheme.typography.labelMedium, color = mutedInk, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                    }
                },
                navigationIcon = { IconButton(onClick = { stopAlong(); onBack() }) { Icon(Icons.Filled.Close, contentDescription = "Close") } },
                actions = {
                    if (castHandle != null && room == null) IconButton(onClick = { sheet = "voices" }) { Icon(Icons.Filled.RecordVoiceOver, contentDescription = "Voices") }
                    IconButton(onClick = { sheet = "marks" }) { Icon(Icons.Filled.Bookmark, contentDescription = "Marks") }
                    IconButton(onClick = { sheet = "contents" }) { Icon(Icons.AutoMirrored.Filled.Toc, contentDescription = "Contents") }
                    IconButton(onClick = { sheet = "search" }) { Icon(Icons.Filled.Search, contentDescription = "Search") }
                    IconButton(onClick = { sheet = "text" }) { Icon(Icons.Filled.FormatSize, contentDescription = "Text") }
                },
            )
        },
        bottomBar = {
            if (!paneMode) {
                Surface(color = MaterialTheme.colorScheme.surfaceContainer) {
                    Column(Modifier.navigationBarsPadding()) {
                        // The row stays while a listen-through runs, empty for a take: a row that came and went changed the page
                        // height and re-cut the pages at each change of reader (B29).
                        if (hearing != null || (alongModel != null && alongLine != null)) {
                            val line = hearing
                            Text(
                                if (line != null) "Device voice · ${line.part.title}" else "",
                                Modifier.fillMaxWidth().padding(horizontal = Spacing.S4.dp, vertical = Spacing.S1.dp)
                                    .semantics { liveRegion = androidx.compose.ui.semantics.LiveRegionMode.Polite },
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.primary,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                        }
                        if (room != null && roomSnap != null) {
                            RoomBar(
                                room, roomState, roomSnap, script, roomCast, roomHide, onHide = { roomHide = it },
                                away = roomAway, onBackToLine = { roomAway = false; roomFollow.back()?.let { follow(it) } },
                                hasMine = !roomMine.isNullOrEmpty(),
                            )
                        }
                        if (backShown) {
                            TextButton(
                                onClick = { alongBack() },
                                Modifier.align(Alignment.CenterHorizontally),
                            ) {
                                Icon(Icons.AutoMirrored.Filled.Undo, contentDescription = null)
                                Text("Back to the line", Modifier.padding(start = Spacing.S1.dp))
                            }
                        }
                        if (studio != null) {
                            StudioDock(studio, onTakes = { id -> studio.studio.select(id); studio.sheet = true }, onListen = rememberListenAction(studio, castHandle, muted) { follow(it) })
                        }
                        if (alongActive) transport() else bar()
                    }
                }
            }
        },
    ) { padding ->
        Box(Modifier.padding(padding).fillMaxSize()) {
            if (paneMode) {
                val directive = calculatePaneScaffoldDirective(adaptive)
                val navigator = rememberSupportingPaneScaffoldNavigator<Nothing>(scaffoldDirective = directive)
                SupportingPaneScaffold(
                    directive = navigator.scaffoldDirective,
                    value = navigator.scaffoldValue,
                    mainPane = {
                        AnimatedPane {
                            Column(Modifier.fillMaxSize()) {
                                Box(Modifier.weight(1f)) { stage() }
                                Surface(color = MaterialTheme.colorScheme.surfaceContainer) { Column(Modifier.navigationBarsPadding()) { if (alongActive) transport() else bar() } }
                            }
                        }
                    },
                    supportingPane = {
                        AnimatedPane(Modifier.preferredWidth(StudioPaneWidth)) {
                            Surface(color = MaterialTheme.colorScheme.surfaceContainerLow, modifier = Modifier.fillMaxSize()) { panel(true) }
                        }
                    },
                )
            } else {
                stage()
            }
        }
    }

    if (studio != null && studio.sheet && !paneMode) {
        StudioSheet(
            studio, castHandle, muted, onPickVoice = pickVoice, onFollow = { follow(it) }, onDone = { finishPart() },
        )
    }
    when (sheet) {
        "voices" -> castHandle?.let { h -> VoicesSheet(h, script, onPick = { pickingVoice = it }, onDismiss = { sheet = "" }) }
        "marks" -> NotebookSheet(
            marksModel, dark,
            onGo = { m ->
                sheet = ""
                goTo(script.lines.indexOfFirst { it.id == m.line }, outline = true)
            },
            onDelete = { m -> ui.onDelete(m) },
            onDismiss = { sheet = "" },
        )
        "contents" -> ContentsSheet(script, posIndex, onGo = { sheet = ""; goTo(it, outline = false) }, onDismiss = { sheet = "" })
        "search" -> SearchSheet(script, onGo = { sheet = ""; goTo(it, outline = true) }, onDismiss = { sheet = "" })
        "text" -> TextSheet(
            prefs, onPrefs = { prefs = it; store.savePrefs(it) },
            volumeKeys = volumeKeys, onVolumeKeys = { volumeKeys = it; store.volumeKeys = it },
            onDismiss = { sheet = "" },
        )
    }
    if (castHandle != null) pickingVoice?.let { VoicePickerSheet(castHandle, script, it) { pickingVoice = null } }
    composing?.let { c ->
        val editing = c.editing
        val draft = remember(c) { if (editing == null) MarksCore.fromSelection(script, c.pieces, c.kind).firstOrNull() else editing }
        val words = remember(c) { draft?.let { notebookWords(script, it, onSurface) } ?: AnnotatedString("") }
        MarkEditSheet(
            c.kind, words, if (c.kind == "note") editing?.note.orEmpty() else editing?.label.orEmpty(),
            onSave = { text ->
                if (editing != null) {
                    marksModel.update(editing.id, if (c.kind == "note") MarkPatch(note = text) else MarkPatch(label = text))
                } else {
                    marksModel.make(c.kind, c.pieces, if (c.kind == "note") MarkExtra(note = text) else MarkExtra(label = text))
                }
                haptics(Haptic.Selection)
                composing = null
            },
            onDismiss = { composing = null },
        )
    }
}

/** A beat or a note being written: the selection it is for, or the mark being edited. */
private class Composing(val kind: String, val pieces: List<Piece>, val editing: Mark?)

/** The spread holding the word heard, when its line runs over more than one page; null when the line sits on one page or the word is not drawn. */
private fun spreadOfWord(flow: ReaderFlow, paged: ReaderPagination.Paged, h: Heard, measurer: androidx.compose.ui.text.TextMeasurer): Int? {
    val w = h.word ?: return null
    if (paged.starts[h.line] == paged.ends[h.line]) return null
    for ((bi, b) in flow.blocks.withIndex()) {
        if (b.owner != h.line) continue
        val r = b.blkRange(w.start, w.end) ?: continue
        val ln = measureBlk(measurer, flow, b, false).text.getLineForOffset(r.first)
        val page = paged.pages.indexOfFirst { p -> p.segs.any { it.block == bi && ln >= it.from && ln < it.to } }
        return if (page < 0) null else page / flow.per
    }
    return null
}

@Composable
private fun PagesStage(
    flow: ReaderFlow,
    paged: ReaderPagination.Paged,
    posIndex: Int,
    jump: Int,
    jumpFollows: Boolean,
    mine: Mine,
    hiding: Boolean,
    peeked: Int?,
    flash: Int?,
    heard: Heard?,
    following: Boolean,
    pal: Palette,
    headPx: Float,
    animationsOff: Boolean,
    turner: Turner,
    haptics: () -> Unit,
    vertical: Float,
    gap: Float,
    ui: MarkUi,
    onPos: (Int) -> Unit,
    onPeek: (Int) -> Unit,
    onClearPeek: () -> Unit,
    onLabel: (String) -> Unit,
    studio: StudioPaint? = null,
    onSelect: (Int) -> Unit = {},
    onTakes: (Int) -> Unit = {},
    onRing: (PartID) -> Unit = {},
) {
    val per = flow.per
    val spreads = ((paged.count + per - 1) / per).coerceAtLeast(1)
    val measurer = rememberTextMeasurer()
    // A new layout (the page height changed) opens on the word heard, or the line heard's own words, while the read-along
    // follows; on the line kept otherwise. Opening on the kept line's first page sent the page back at each re-layout (B29).
    val opening = remember(paged) {
        val h = heard
        if (following && h != null) spreadOfWord(flow, paged, h, measurer) ?: paged.followSpreadOf(h.line, per) else paged.spreadOf(posIndex, per)
    }
    val pager = rememberPagerState(initialPage = opening.coerceIn(0, spreads - 1)) { spreads }
    val scope = rememberCoroutineScope()
    val density = LocalDensity.current
    val latestPos by rememberUpdatedState(posIndex)
    val latestFollows by rememberUpdatedState(jumpFollows)

    // Rule 4: within a long speech the word heard turns the page itself when it reaches one not in view (either page of a spread is in view).
    LaunchedEffect(heard?.line, heard?.word, following) {
        val h = heard ?: return@LaunchedEffect
        if (!following) return@LaunchedEffect
        val target = spreadOfWord(flow, paged, h, measurer)?.coerceIn(0, spreads - 1) ?: return@LaunchedEffect
        if (target != pager.currentPage) {
            if (animationsOff) pager.scrollToPage(target) else pager.animateScrollToPage(target)
        }
    }

    LaunchedEffect(Unit) {
        var first = true
        snapshotFlow { pager.settledPage }.collect { sp ->
            if (first) {
                first = false
                return@collect
            }
            val a = sp * per
            val b = a + per - 1
            val cur = latestPos
            if (!(paged.ends[cur] >= a && paged.starts[cur] <= b)) onPos(ReaderMath.lineAtPage(paged.starts, paged.ends, a))
            onClearPeek()
            ui.sel = null
            haptics()
        }
    }
    LaunchedEffect(Unit) {
        snapshotFlow { pager.currentPage }.collect { onLabel(ReaderMath.pageLabel(it * per, per, paged.count)) }
    }
    LaunchedEffect(jump) {
        if (jump == 0) return@LaunchedEffect
        val target = (if (latestFollows) paged.followSpreadOf(latestPos, per) else paged.spreadOf(latestPos, per)).coerceIn(0, spreads - 1)
        if (animationsOff || Math.abs(target - pager.currentPage) > 3) pager.scrollToPage(target) else pager.animateScrollToPage(target)
    }
    val turn: (ReaderMath.Turn) -> Unit = { t ->
        val target = when (t) {
            is ReaderMath.Turn.By -> (pager.currentPage + t.delta).coerceIn(0, spreads - 1)
            ReaderMath.Turn.First -> 0
            ReaderMath.Turn.Last -> spreads - 1
        }
        if (target != pager.currentPage) {
            scope.launch { if (animationsOff) pager.scrollToPage(target) else pager.animateScrollToPage(target) }
        }
    }
    SideEffect { turner.turn = turn }

    Box(
        Modifier.fillMaxSize().pointerInput(flow, mine, hiding, peeked, studio?.role) {
            detectTapGestures { off ->
                val spreadW = per * flow.colPx + (per - 1) * gap
                val left = (size.width - spreadW) / 2
                val col = Math.floor(((off.x - left) / (flow.colPx + gap)).toDouble()).toInt()
                val page = if (col in 0 until per) paged.pages.getOrNull(pager.currentPage * per + col) else null
                val hit = page?.segAt(off.y - headPx)?.let { flow.blocks[it.block] }
                // A tap on one of my lines in the studio makes it current and does not turn the page.
                if (hit != null && studio != null && hit.role == studio.role && hit.kind != Kind.Heading && studio.states.containsKey(hit.owner)) {
                    onSelect(hit.owner)
                    return@detectTapGestures
                }
                if (hit != null && hideable(hit, mine, hiding, peeked)) {
                    onPeek(hit.owner)
                    return@detectTapGestures
                }
                onClearPeek()
                when (ReaderMath.tapZone(off.x, size.width.toFloat())) {
                    ReaderMath.Zone.Prev -> turn(ReaderMath.Turn.By(-1))
                    ReaderMath.Zone.Next -> turn(ReaderMath.Turn.By(1))
                    ReaderMath.Zone.Middle -> Unit
                }
            }
        },
    ) {
        HorizontalPager(pager, Modifier.fillMaxSize(), beyondViewportPageCount = 1, key = { it }) { spread ->
            Row(
                Modifier.fillMaxSize().padding(bottom = with(density) { vertical.toDp() }),
                horizontalArrangement = Arrangement.spacedBy(with(density) { gap.toDp() }, Alignment.CenterHorizontally),
            ) {
                for (k in 0 until per) {
                    PageView(
                        spread * per + k, paged.pages.getOrNull(spread * per + k), flow, pal, mine, hiding, peeked, flash, heard, headPx, onPeek,
                        Modifier.width(with(density) { flow.colPx.toDp() }).fillMaxSize(),
                        ui = ui, studio = studio, onTakes = onTakes, onRing = onRing,
                    )
                }
            }
        }
    }
}

@Composable
private fun ScrollStage(
    flow: ReaderFlow,
    posIndex: Int,
    jump: Int,
    mine: Mine,
    hiding: Boolean,
    peeked: Int?,
    flash: Int?,
    heard: Heard?,
    following: Boolean,
    animationsOff: Boolean,
    pal: Palette,
    turner: Turner,
    margin: Float,
    vertical: Float,
    onPos: (Int) -> Unit,
    ui: MarkUi,
    onPeek: (Int) -> Unit,
    onLabel: (String) -> Unit,
) {
    val density = LocalDensity.current
    val scope = rememberCoroutineScope()
    val list = rememberLazyListState(initialFirstVisibleItemIndex = flow.firstBlock.getOrElse(posIndex) { 0 })
    val latestPos by rememberUpdatedState(posIndex)
    LaunchedEffect(heard?.line, heard?.word, following) {
        val h = heard ?: return@LaunchedEffect
        val w = h.word ?: return@LaunchedEffect
        if (!following) return@LaunchedEffect
        val at = flow.blocks.indexOfFirst { it.owner == h.line && it.blkRange(w.start, w.end) != null }
        if (at < 0 || list.layoutInfo.visibleItemsInfo.any { it.index == at }) return@LaunchedEffect
        if (animationsOff) list.scrollToItem(at) else list.animateScrollToItem(at)
    }
    LaunchedEffect(jump) {
        if (jump > 0) list.scrollToItem(flow.firstBlock.getOrElse(latestPos) { 0 })
    }
    LaunchedEffect(Unit) {
        var first = true
        snapshotFlow { list.firstVisibleItemIndex }.collect { b ->
            onLabel("${Math.round(100f * b / flow.blocks.size.coerceAtLeast(1))}%")
            if (first) {
                first = false
                return@collect
            }
            flow.blocks.getOrNull(b)?.let { onPos(it.owner) }
        }
    }
    SideEffect {
        turner.turn = { t ->
            scope.launch {
                when (t) {
                    is ReaderMath.Turn.By -> list.animateScrollBy(t.delta * list.layoutInfo.viewportSize.height * 0.9f)
                    ReaderMath.Turn.First -> list.scrollToItem(0)
                    ReaderMath.Turn.Last -> list.scrollToItem(flow.blocks.size - 1)
                }
            }
        }
    }
    LazyColumn(
        Modifier.fillMaxSize(),
        state = list,
        contentPadding = PaddingValues(horizontal = with(density) { margin.toDp() }, vertical = with(density) { vertical.toDp() }),
    ) {
        items(flow.blocks.size, key = { it }) { b ->
            val blk = flow.blocks[b]
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.TopCenter) {
                ScrollBlock(blk, b, flow, pal, mine, hiding, peeked, blk.owner == flash, heard, ui, onPeek)
            }
        }
    }
}

// MARK: The sheets

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ContentsSheet(script: PlayScript, posIndex: Int, onGo: (Int) -> Unit, onDismiss: () -> Unit) {
    val toc = remember(script) { ScriptReading.contentsOf(script) }
    val place = remember(script, posIndex) { ScriptReading.placeOf(script, posIndex) }
    val here = place.scene?.index ?: place.act?.index
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Text(
            "Contents", style = MaterialTheme.typography.headlineSmall,
            modifier = Modifier.padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp).semantics { heading() },
        )
        if (toc.isEmpty()) {
            Text(
                "This script prints no acts or scenes.", style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.padding(Spacing.S4.dp),
            )
            return@ModalBottomSheet
        }
        val rows = remember(toc) { toc.flatMap { t -> listOf(t.section to false) + t.scenes.map { it to true } } }
        val start = rows.indexOfFirst { it.first.index == here }.coerceAtLeast(0)
        LazyColumn(state = rememberLazyListState(initialFirstVisibleItemIndex = (start - 2).coerceAtLeast(0))) {
            items(rows.size, key = { rows[it].first.index.toString() + ":" + it }) { r ->
                val (section, scene) = rows[r]
                val current = section.index == here
                Row(
                    Modifier.fillMaxWidth().height(52.dp)
                        .clickable(onClickLabel = "Go to ${section.title}") { onGo(section.index) }
                        .padding(start = (Spacing.S4 + if (scene) 20 else 0).dp, end = Spacing.S4.dp)
                        .semantics { if (current) contentDescription = "${section.title}, current" },
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        section.title,
                        style = if (scene) MaterialTheme.typography.bodyMedium else MaterialTheme.typography.titleMedium,
                        maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f),
                    )
                    if (current) Icon(Icons.Filled.Check, contentDescription = null)
                }
            }
        }
    }
}

private val BEFORE_PUNCTUATION = Regex(" ([.,;:!?])")

private fun shown(s: String): String = s.replace("_", "").replace(BEFORE_PUNCTUATION, "$1")

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SearchSheet(script: PlayScript, onGo: (Int) -> Unit, onDismiss: () -> Unit) {
    var query by rememberSaveable { mutableStateOf("") }
    var found by remember { mutableStateOf(ScriptReading.Found(0, emptyList())) }
    LaunchedEffect(query) {
        delay(150)
        found = withContext(Dispatchers.Default) { ScriptReading.search(script, query) }
    }
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Text(
            "Search", style = MaterialTheme.typography.headlineSmall,
            modifier = Modifier.padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp).semantics { heading() },
        )
        OutlinedTextField(
            query, { query = it }, singleLine = true,
            label = { Text("Search in the script") },
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
            modifier = Modifier.fillMaxWidth().padding(horizontal = Spacing.S4.dp).focusRequester(focus),
        )
        val q = query.trim()
        val count = when {
            q.length < 2 -> ""
            found.total == 0 -> "No line has these words."
            found.total > found.hits.size -> "${found.total} lines · ${found.total - found.hits.size} more"
            found.total == 1 -> "1 line"
            else -> "${found.total} lines"
        }
        if (count.isNotEmpty()) {
            Text(
                count, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp),
            )
        }
        LazyColumn(Modifier.height(360.dp)) {
            items(found.hits.size, key = { found.hits[it].line }) { i ->
                val h = found.hits[i]
                Column(
                    Modifier.fillMaxWidth().clickable(onClickLabel = "Go to this line") { onGo(h.index) }
                        .padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp),
                ) {
                    h.role?.let { Text(it, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                    Text(
                        buildAnnotatedString {
                            append(shown(h.before))
                            withStyle(SpanStyle(fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary)) { append(shown(h.match)) }
                            append(shown(h.after))
                        },
                        style = MaterialTheme.typography.bodyMedium,
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TextSheet(
    prefs: ReaderPrefs,
    onPrefs: (ReaderPrefs) -> Unit,
    volumeKeys: Boolean,
    onVolumeKeys: (Boolean) -> Unit,
    onDismiss: () -> Unit,
) {
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.padding(horizontal = Spacing.S4.dp).navigationBarsPadding(), verticalArrangement = Arrangement.spacedBy(Spacing.S3.dp)) {
            Text("Text", style = MaterialTheme.typography.headlineSmall, modifier = Modifier.semantics { heading() })
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Size", style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
                TextButton(enabled = prefs.size > 0, onClick = { onPrefs(prefs.copy(size = prefs.size - 1)) }) { Text("A−") }
                Text("${Math.round(prefs.scale * 100)}%", style = MaterialTheme.typography.bodySmall, modifier = Modifier.widthIn(min = 48.dp), textAlign = TextAlign.Center)
                TextButton(enabled = prefs.size < ReaderMath.SIZES.size - 1, onClick = { onPrefs(prefs.copy(size = prefs.size + 1)) }) { Text("A+") }
            }
            Text("Line spacing", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            val spacings = listOf("tight" to "Tight", "normal" to "Normal", "loose" to "Loose")
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                spacings.forEachIndexed { i, (key, label) ->
                    SegmentedButton(
                        selected = prefs.spacing == key, onClick = { onPrefs(prefs.copy(spacing = key)) },
                        shape = SegmentedButtonDefaults.itemShape(i, spacings.size),
                    ) { Text(label) }
                }
            }
            Text("Layout", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            val layouts = listOf("pages" to "Pages", "scroll" to "Scroll")
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                layouts.forEachIndexed { i, (key, label) ->
                    SegmentedButton(
                        selected = prefs.layout == key, onClick = { onPrefs(prefs.copy(layout = key)) },
                        shape = SegmentedButtonDefaults.itemShape(i, layouts.size),
                    ) { Text(label) }
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Volume keys turn pages", style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
                Switch(checked = volumeKeys, onCheckedChange = onVolumeKeys)
            }
            Spacer(Modifier.height(Spacing.S4.dp))
        }
    }
}
