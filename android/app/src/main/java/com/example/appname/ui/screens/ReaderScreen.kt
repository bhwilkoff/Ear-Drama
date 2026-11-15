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
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.focusable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.RecordVoiceOver
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.FormatSize
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Toc
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material.icons.filled.VerticalAlignBottom
import androidx.compose.material3.CircularProgressIndicator
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
import androidx.compose.ui.input.pointer.pointerInput
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
import com.example.appname.plays.PageRow
import com.example.appname.plays.PartID
import com.example.appname.plays.PlayPage
import com.example.appname.plays.PlayScript
import com.example.appname.plays.ReaderMath
import com.example.appname.plays.ReaderPagination
import com.example.appname.plays.ReaderPrefs
import com.example.appname.plays.ReaderStore
import com.example.appname.plays.ScriptLine
import com.example.appname.plays.ScriptReading
import com.example.appname.plays.TableRead
import com.example.appname.ui.VoicePickerSheet
import com.example.appname.ui.VoicesSheet
import com.example.appname.ui.rememberCast
import com.example.appname.ui.rememberDeviceVoices
import com.example.appname.ui.EmptyAction
import com.example.appname.ui.EmptyMessage
import com.example.appname.ui.Haptic
import com.example.appname.ui.LocalAppContainer
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

private sealed interface Loaded {
    data object Loading : Loaded
    data object Missing : Loaded
    data class Failed(val line: String) : Loaded
    data class Ready(val script: PlayScript) : Loaded
}

/** The reader over one play, full screen: it opens at [startLine], else where this device last left off. */
@Composable
fun ReaderScreen(scriptId: String, startLine: String?, onBack: () -> Unit) {
    val plays = LocalAppContainer.current.plays
    var attempt by remember { mutableStateOf(0) }
    val loaded by produceState<Loaded>(Loaded.Loading, scriptId, attempt) {
        value = Loaded.Loading
        value = try {
            plays.script(scriptId)?.let { Loaded.Ready(it) } ?: Loaded.Missing
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
        Loaded.Missing -> ReaderFrame(onBack) { EmptyMessage("This play is not on this device.") }
        is Loaded.Failed -> ReaderFrame(onBack) { EmptyMessage(l.line, action = EmptyAction("Try again") { attempt++ }) }
        is Loaded.Ready -> ReaderBody(l.script, startLine, onBack)
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
) {
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
    fun heading(owner: Int, level: ScriptReading.Level, body: String) {
        val opens = level != ScriptReading.Level.Scene
        add(
            Blk(
                owner, AnnotatedString(body), emptyList(), style(if (opens) 1.75f else 1.25f, display = true),
                if (opens) 0f else 1.2f, Kind.Heading, keepWithNext = true, breakBefore = opens, heading = true,
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
    fun AnnotatedString.Builder.direction(text: String, italic: Boolean) {
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
    fun AnnotatedString.Builder.cue(row: PageRow) {
        row.runs.forEachIndexed { n, r ->
            if (n > 0 && row.runs[n - 1].piece != r.piece) append(' ')
            val up = r.text.uppercase(Locale.US)
            withStyle(SpanStyle(fontWeight = FontWeight.SemiBold, letterSpacing = 0.06.em)) { append(if (up.length == r.text.length) up else r.text) }
        }
    }

    var speechCount = 0
    var previous: Triple<String, Int, IntRange?>? = null

    script.lines.forEachIndexed { i, line ->
        for (s in before[i].orEmpty()) heading(i, s.level, s.title)
        val head = heads[i]
        if (head != null) {
            heading(i, head.level, ScriptReading.runsOf(line).joinToString("") { it.text })
            return@forEachIndexed
        }
        val layout = PlayPage.layoutOf(line, roles)
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
                    measurer.measure(nameStyled, style()).size.width <= GUTTER_EM * bodyPx
                val base = if (beside) COL_EM else 0f
                var first = true
                var lastTail: Triple<Int, Int, String>? = null
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
                        add(
                            Blk(
                                i, buildAnnotatedString { cue(row) }, emptyList(), style(CAPTION_EM), gap, Kind.Cue,
                                role = sp.role, hue = hue, xOffEm = base + GLYPH_EM, speech = speechCount, speechStart = first,
                            ),
                        )
                        k++
                    } else {
                        var end = k
                        while (end < sp.rows.size && !sp.rows[end].cue) end++
                        val said = ArrayList<IntRange>()
                        val offsets = ArrayList<Int>()
                        var tail: Pair<Int, String>? = null
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
                                            withStyle(if (run.kind == ScriptReading.RunKind.Em) SpanStyle(fontStyle = FontStyle.Italic) else SpanStyle()) { append(run.text) }
                                            said += st until length
                                            tail = st to run.text
                                            return@forEachIndexed
                                        }
                                        val whole = rw.runs.filter { it.piece == run.piece && !it.said }.joinToString("") { it.text }
                                        val opens = (n == 0 || rw.runs[n - 1].piece != run.piece) && !ASIDE_OPEN.containsMatchIn(whole)
                                        val closes = (n == rw.runs.size - 1 || rw.runs[n + 1].piece != run.piece) && !ASIDE_CLOSE.containsMatchIn(whole)
                                        if (opens) append('(')
                                        direction(run.text, italic = run.kind != ScriptReading.RunKind.Plain)
                                        if (closes) append(')')
                                    }
                                }
                            }
                        }
                        add(
                            Blk(
                                i, text, said, style(), gap, Kind.Text, role = sp.role, hue = hue, xOffEm = base, speech = speechCount,
                                speechStart = first, name = if (first && beside) nameStyled else null, rowOffsets = if (layout.verse) offsets else emptyList(),
                            ),
                        )
                        tail?.let { (st, t) -> lastTail = Triple(out.size - 1, st, t) }
                        k = end
                    }
                    first = false
                    afterName = false
                }
                out.lastOrNull()?.takeIf { it.speech == speechCount }?.speechEnd = true
                lastTail?.let { (at, st, t) ->
                    val c = PlayPage.cueTail(t)
                    previous = Triple(sp.role, at, (st + c) until (st + t.length))
                }
            }
            return@forEachIndexed
        }
        val row = layout.rows.firstOrNull() ?: PageRow(false, false)
        val indent = if (gutter) COL_EM else INDENT_EM
        if (row.cue) {
            add(Blk(i, buildAnnotatedString { cue(row) }, emptyList(), style(CAPTION_EM), GAP_EM, Kind.Cue, xOffEm = indent + GLYPH_EM))
        } else {
            add(
                Blk(
                    i,
                    buildAnnotatedString { for (r in row.runs) direction(r.text, italic = r.kind == ScriptReading.RunKind.Plain) },
                    emptyList(), style(), GAP_EM, Kind.Direction, xOffEm = indent,
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
    val blocks = buildBlocks(script, pal, spec.prefs.scale, spec.prefs.leading, gutter, measurer, density)
    val contentPx = (spec.colPx - spec.insetPx).coerceAtLeast(1)
    val firstBlock = IntArray(script.lines.size) { -1 }
    blocks.forEachIndexed { b, blk -> if (firstBlock[blk.owner] < 0) firstBlock[blk.owner] = b }
    var last = 0
    for (i in firstBlock.indices) if (firstBlock[i] < 0) firstBlock[i] = last else last = firstBlock[i]
    val flow0 = ReaderFlow(blocks, null, spec.per, contentPx, spec.colPx, firstBlock, bodyPx, gutter)
    if (!spec.prefs.pages) return@withContext flow0
    val measured = blocks.map { b ->
        ensureActive()
        val l = measurer.measure(b.text, b.style, constraints = Constraints(maxWidth = textWidth(flow0, b)), skipCache = true)
        val rows = if (b.rowOffsets.size > 1) b.rowOffsets.map { l.getLineForOffset(it) }.distinct().toIntArray() else null
        ReaderPagination.Block(
            b.owner, FloatArray(l.lineCount) { l.getLineBottom(it) - l.getLineTop(it) }, b.gapEm * bodyPx, b.keepWithNext,
            b.breakBefore, b.speech, b.speechStart, rows,
        )
    }
    val paged = ReaderPagination.paginate(measured, script.lines.size, spec.pageHeightPx.toFloat())
    ReaderFlow(blocks, paged, spec.per, contentPx, spec.colPx, firstBlock, bodyPx, gutter)
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
)

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
) {
    val layout = m.text
    val tone = blk.hue ?: ink.accent
    val x0 = ink.insetPx + blk.xOffEm * ink.bodyPx
    val shift = top - layout.getLineTop(from)
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
        drawText(layout, topLeft = Offset(x0, shift))
        m.name?.let { if (from == 0) drawText(it, topLeft = Offset(ink.insetPx, shift)) }
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

private fun hideable(b: Blk, mineRole: String?, hiding: Boolean, peeked: Int?) =
    hiding && mineRole != null && b.kind == Kind.Text && b.role == mineRole && b.owner != peeked

/** One page: its slices of the blocks it holds, measured now from the same text and width the pagination used. */
@Composable
private fun PageView(
    index: Int,
    page: ReaderPagination.Page?,
    flow: ReaderFlow,
    pal: Palette,
    mineRole: String?,
    hiding: Boolean,
    peeked: Int?,
    flash: Int?,
    headPx: Float,
    onPeek: (Int) -> Unit,
    modifier: Modifier,
) {
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    val segs = page?.segs.orEmpty()
    val layouts = remember(page, flow, hiding, mineRole, peeked) {
        segs.map { seg ->
            val b = flow.blocks[seg.block]
            measureBlk(measurer, flow, b, hideable(b, mineRole, hiding, peeked))
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
    Box(modifier.semantics { contentDescription = description }) {
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
                        tint = mineRole != null && b.role == mineRole && b.kind != Kind.Heading,
                        hidden = hideable(b, mineRole, hiding, peeked), flash = b.owner == flash,
                        underline = mineRole != null && b.cueRole == mineRole,
                    )
                }
            }
        }
        segs.forEach { seg ->
            val b = flow.blocks[seg.block]
            if (hideable(b, mineRole, hiding, peeked)) {
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
    return remember(pal, flow, glyph) {
        Ink(pal.accent, pal.block, pal.muted, with(density) { 3.dp.toPx() }, flow.bodyPx * LINE_GAP_EM / 3, with(density) { RuleInset.toPx() }, flow.bodyPx, glyph)
    }
}

/** One block in Scroll: the whole of it, its width the column's. */
@Composable
private fun ScrollBlock(blk: Blk, flow: ReaderFlow, pal: Palette, mineRole: String?, hiding: Boolean, peeked: Int?, flash: Boolean, onPeek: (Int) -> Unit) {
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    val hidden = hideable(blk, mineRole, hiding, peeked)
    val m = remember(blk, flow, hidden) { measureBlk(measurer, flow, blk, hidden) }
    val ink = rememberInk(pal, flow)
    val height = with(density) { m.text.size.height.toDp() }
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
            tint = mineRole != null && blk.role == mineRole && blk.kind != Kind.Heading, hidden = hidden, flash = flash,
            underline = mineRole != null && blk.cueRole == mineRole,
        )
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

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ReaderBody(script: PlayScript, startLine: String?, onBack: () -> Unit) {
    val context = LocalContext.current
    val store = remember { ReaderStore(context.getSharedPreferences("ed.reader", android.content.Context.MODE_PRIVATE)) }
    val haptics = rememberHaptics()
    val density = LocalDensity.current
    val resolver = LocalFontFamilyResolver.current
    val dark = OnAir.colors.dark
    var prefs by remember { mutableStateOf(store.prefs()) }
    var volumeKeys by remember { mutableStateOf(store.volumeKeys) }
    val saved = remember(script.id) { store.position(script.id) }
    var posId by rememberSaveable(script.id) {
        mutableStateOf(script.lines.firstOrNull { it.id == (startLine ?: saved["line"]) }?.id ?: script.lines.firstOrNull()?.id.orEmpty())
    }
    var part by rememberSaveable(script.id) {
        mutableStateOf(saved["part"]?.takeIf { p -> script.castParts.any { it.id.raw == p && it.id.isSpeaking } })
    }
    var hiding by rememberSaveable(script.id) { mutableStateOf(false) }
    var peeked by remember { mutableStateOf<Int?>(null) }
    var flash by remember { mutableStateOf<Int?>(null) }
    var jump by remember { mutableIntStateOf(0) }
    var sheet by rememberSaveable { mutableStateOf("") }
    val container = LocalAppContainer.current
    val deviceVoices = rememberDeviceVoices()
    val castHandle = rememberCast(deviceVoices, script, null)
    val scope = rememberCoroutineScope()
    var pickingVoice by remember { mutableStateOf<PartID?>(null) }
    var hearing by remember { mutableStateOf<ScriptLine?>(null) }
    var hearingOn by remember { mutableStateOf(false) }
    var hearJob by remember { mutableStateOf<Job?>(null) }
    var pageLabel by remember { mutableStateOf("") }
    val posIndex = remember(posId, script) { script.lines.indexOfFirst { it.id == posId }.coerceAtLeast(0) }
    val mineRole = part?.let { PartID(it).roleName }
    val focus = remember { FocusRequester() }
    val turner = remember { Turner() }
    val animationsOff = remember {
        Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    }

    val onSurface = MaterialTheme.colorScheme.onSurface
    val muted = MaterialTheme.colorScheme.onSurfaceVariant
    val accent = MaterialTheme.colorScheme.primary
    val block = MaterialTheme.colorScheme.surfaceContainerHigh
    val pal = remember(script, dark, onSurface, muted, accent, block) {
        val hues = HashMap<String, Color>()
        script.castParts.filter { it.id.isSpeaking }.forEach { p ->
            genreColor(script.partHue(p.id), dark)?.let { hues[p.id.roleName.orEmpty()] = it }
        }
        Palette(onSurface, muted, accent, block, hues)
    }

    LaunchedEffect(posId, part) {
        delay(300)
        store.savePosition(script.id, posId.ifEmpty { null }, part)
    }
    LaunchedEffect(flash) {
        if (flash != null) {
            delay(1600)
            flash = null
        }
    }
    LaunchedEffect(sheet) { if (sheet.isEmpty()) runCatching { focus.requestFocus() } }

    val place = remember(posIndex, script) { ScriptReading.placeOf(script, posIndex) }
    val wide = with(LocalDensity.current) { androidx.compose.ui.platform.LocalWindowInfo.current.containerSize.width.toDp() } >= 600.dp

    fun stopHearing() {
        hearJob?.cancel()
        hearJob = null
        hearingOn = false
        hearing = null
        castHandle?.speaker?.cancel()
    }
    DisposableEffect(script.id) { onDispose { hearJob?.cancel() } }

    /** Goes to a line: the position is that line wherever it falls, and the stage turns to it. */
    fun goTo(index: Int, outline: Boolean) {
        if (index !in script.lines.indices) return
        posId = script.lines[index].id
        peeked = null
        if (outline) flash = index
        jump++
    }

    /** Hear the cast: from the first line on the page to the end, each part in its voice, the page following. */
    fun startHearing() {
        val h = castHandle ?: return
        if (container.playback.state.value.isPlaying) container.playback.togglePlay()
        hearingOn = true
        haptics(Haptic.Selection)
        hearJob = scope.launch {
            try {
                TableRead(script, h.speaker) { line ->
                    hearing = line
                    if (line != null) goTo(script.lines.indexOfFirst { it.id == line.id }, outline = false)
                }.play(posIndex)
            } finally {
                hearingOn = false
                hearing = null
                hearJob = null
            }
        }
    }

    fun myLine(direction: Int) {
        val p = PartID(part ?: return)
        var i = ScriptReading.nextLineOf(script, p, posIndex, direction)
        if (i < 0 && direction > 0) i = ScriptReading.nextLineOf(script, p, -1, 1)
        if (i >= 0) {
            haptics(Haptic.Selection)
            goTo(i, outline = true)
        }
    }

    val keys = Modifier.onPreviewKeyEvent { e: KeyEvent ->
        val volume = volumeKeys && (e.key == Key.VolumeDown || e.key == Key.VolumeUp)
        val name = readerKeyName(e.key)
        val letter = part != null && (e.key == Key.J || e.key == Key.K)
        if (!volume && name == null && !letter) return@onPreviewKeyEvent false
        if (e.type == KeyEventType.KeyDown) {
            when {
                volume -> turner.turn(ReaderMath.Turn.By(if (e.key == Key.VolumeDown) 1 else -1))
                letter -> myLine(if (e.key == Key.J) 1 else -1)
                else -> ReaderMath.keyTurn(name!!, e.isShiftPressed)?.let { turner.turn(it) }
            }
        }
        true
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text(script.title, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        if (place.label.isNotEmpty()) {
                            Text(place.label, style = MaterialTheme.typography.labelMedium, color = muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                    }
                },
                navigationIcon = { IconButton(onClick = { stopHearing(); onBack() }) { Icon(Icons.Filled.Close, contentDescription = "Close") } },
                actions = {
                    if (castHandle != null) IconButton(onClick = { sheet = "voices" }) { Icon(Icons.Filled.RecordVoiceOver, contentDescription = "Voices") }
                    IconButton(onClick = { sheet = "contents" }) { Icon(Icons.Filled.Toc, contentDescription = "Contents") }
                    IconButton(onClick = { sheet = "search" }) { Icon(Icons.Filled.Search, contentDescription = "Search") }
                    IconButton(onClick = { sheet = "text" }) { Icon(Icons.Filled.FormatSize, contentDescription = "Text") }
                },
            )
        },
        bottomBar = {
            Surface(color = MaterialTheme.colorScheme.surfaceContainer) {
              Column(Modifier.navigationBarsPadding()) {
                hearing?.let { line ->
                    Text(
                        "Device voice \u00b7 ${line.part.title}",
                        Modifier.fillMaxWidth().padding(horizontal = Spacing.S4.dp, vertical = Spacing.S1.dp)
                            .semantics { liveRegion = androidx.compose.ui.semantics.LiveRegionMode.Polite },
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.primary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                Row(
                    Modifier.fillMaxWidth().padding(horizontal = Spacing.S2.dp, vertical = Spacing.S1.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    var menu by remember { mutableStateOf(false) }
                    Box {
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
                    Spacer(Modifier.weight(1f))
                    if (castHandle != null) {
                        TextButton(onClick = { if (hearingOn) stopHearing() else startHearing() }) {
                            Icon(
                                if (hearingOn) Icons.Filled.Stop else Icons.Filled.PlayArrow,
                                contentDescription = if (hearingOn) "Stop" else "Hear the cast",
                            )
                            if (wide) Text(if (hearingOn) "Stop" else "Hear the cast", Modifier.padding(start = Spacing.S1.dp))
                        }
                    }
                    if (part != null) {
                        IconButton(onClick = { myLine(1) }) { Icon(Icons.Filled.VerticalAlignBottom, contentDescription = "Next line") }
                        IconToggleButton(checked = hiding, onCheckedChange = { hiding = it; peeked = null; haptics(Haptic.Selection) }) {
                            Icon(if (hiding) Icons.Filled.VisibilityOff else Icons.Filled.Visibility, contentDescription = "Hide my lines")
                        }
                    }
                    Text(
                        pageLabel,
                        style = MaterialTheme.typography.bodySmall,
                        color = muted,
                        modifier = Modifier.padding(horizontal = Spacing.S2.dp),
                    )
                }
              }
            }
        },
    ) { padding ->
        BoxWithConstraints(
            Modifier.padding(padding).fillMaxSize().clipToBounds().focusRequester(focus).focusable().then(keys),
        ) {
            val bodyPx = with(density) { (BODY_SP * prefs.scale).sp.toPx() }
            val per = ReaderMath.perSpread(maxWidth.value)
            val marginPx = with(density) { PageMargin.toPx() }
            val gapPx = with(density) { PageGap.toPx() }
            val vertical = with(density) { PageVertical.toPx() }
            val headPx = with(density) { PageHead.toPx() }
            val colPx = (((constraints.maxWidth - 2 * marginPx - (per - 1) * gapPx) / per).coerceAtMost(36 * bodyPx)).toInt().coerceAtLeast(1)
            val spec = FlowSpec(
                script.id, colPx, (constraints.maxHeight - headPx - vertical).toInt().coerceAtLeast(1), density.density, density.fontScale,
                prefs, dark, per, with(density) { RuleInset.toPx() }.toInt(),
            )
            val flow by produceState<ReaderFlow?>(null, spec, pal) { value = computeFlow(script, spec, pal, resolver, density) }
            val f = flow
            when {
                f == null -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(Modifier.semantics { contentDescription = "Loading" })
                }
                f.paged != null -> key(f) {
                    PagesStage(
                        f, f.paged, posIndex = posIndex, jump = jump, mineRole = mineRole, hiding = hiding, peeked = peeked, flash = flash,
                        pal = pal, headPx = headPx, animationsOff = animationsOff, turner = turner, haptics = { haptics(Haptic.Selection) },
                        vertical = vertical, gap = gapPx,
                        onPos = { posId = script.lines[it].id },
                        onPeek = { peeked = it }, onClearPeek = { peeked = null }, onLabel = { pageLabel = it },
                    )
                }
                else -> key(f) {
                    ScrollStage(
                        f, posIndex = posIndex, jump = jump, mineRole = mineRole, hiding = hiding, peeked = peeked, flash = flash, pal = pal,
                        turner = turner, margin = marginPx, vertical = vertical,
                        onPos = { posId = script.lines[it].id }, onPeek = { peeked = it }, onLabel = { pageLabel = it },
                    )
                }
            }
        }
    }

    when (sheet) {
        "voices" -> castHandle?.let { h -> VoicesSheet(h, script, onPick = { pickingVoice = it }, onDismiss = { sheet = "" }) }
        "contents" -> ContentsSheet(script, posIndex, onGo = { sheet = ""; goTo(it, outline = false) }, onDismiss = { sheet = "" })
        "search" -> SearchSheet(script, onGo = { sheet = ""; goTo(it, outline = true) }, onDismiss = { sheet = "" })
        "text" -> TextSheet(
            prefs, onPrefs = { prefs = it; store.savePrefs(it) },
            volumeKeys = volumeKeys, onVolumeKeys = { volumeKeys = it; store.volumeKeys = it },
            onDismiss = { sheet = "" },
        )
    }
    if (castHandle != null) pickingVoice?.let { VoicePickerSheet(castHandle, script, it) { pickingVoice = null } }
}

@Composable
private fun PagesStage(
    flow: ReaderFlow,
    paged: ReaderPagination.Paged,
    posIndex: Int,
    jump: Int,
    mineRole: String?,
    hiding: Boolean,
    peeked: Int?,
    flash: Int?,
    pal: Palette,
    headPx: Float,
    animationsOff: Boolean,
    turner: Turner,
    haptics: () -> Unit,
    vertical: Float,
    gap: Float,
    onPos: (Int) -> Unit,
    onPeek: (Int) -> Unit,
    onClearPeek: () -> Unit,
    onLabel: (String) -> Unit,
) {
    val per = flow.per
    val spreads = ((paged.count + per - 1) / per).coerceAtLeast(1)
    val pager = rememberPagerState(initialPage = paged.spreadOf(posIndex, per).coerceIn(0, spreads - 1)) { spreads }
    val scope = rememberCoroutineScope()
    val density = LocalDensity.current
    val latestPos by rememberUpdatedState(posIndex)

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
            haptics()
        }
    }
    LaunchedEffect(Unit) {
        snapshotFlow { pager.currentPage }.collect { onLabel(ReaderMath.pageLabel(it * per, per, paged.count)) }
    }
    LaunchedEffect(jump) {
        if (jump == 0) return@LaunchedEffect
        val target = paged.spreadOf(latestPos, per).coerceIn(0, spreads - 1)
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
        Modifier.fillMaxSize().pointerInput(flow, mineRole, hiding, peeked) {
            detectTapGestures { off ->
                val spreadW = per * flow.colPx + (per - 1) * gap
                val left = (size.width - spreadW) / 2
                val col = Math.floor(((off.x - left) / (flow.colPx + gap)).toDouble()).toInt()
                val page = if (col in 0 until per) paged.pages.getOrNull(pager.currentPage * per + col) else null
                val hit = page?.segAt(off.y - headPx)?.let { flow.blocks[it.block] }
                if (hit != null && hideable(hit, mineRole, hiding, peeked)) {
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
                        spread * per + k, paged.pages.getOrNull(spread * per + k), flow, pal, mineRole, hiding, peeked, flash, headPx, onPeek,
                        Modifier.width(with(density) { flow.colPx.toDp() }).fillMaxSize(),
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
    mineRole: String?,
    hiding: Boolean,
    peeked: Int?,
    flash: Int?,
    pal: Palette,
    turner: Turner,
    margin: Float,
    vertical: Float,
    onPos: (Int) -> Unit,
    onPeek: (Int) -> Unit,
    onLabel: (String) -> Unit,
) {
    val density = LocalDensity.current
    val scope = rememberCoroutineScope()
    val list = rememberLazyListState(initialFirstVisibleItemIndex = flow.firstBlock.getOrElse(posIndex) { 0 })
    val latestPos by rememberUpdatedState(posIndex)
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
                ScrollBlock(blk, flow, pal, mineRole, hiding, peeked, blk.owner == flash, onPeek)
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
