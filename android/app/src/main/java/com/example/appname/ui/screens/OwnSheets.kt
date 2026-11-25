package com.example.appname.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.focusable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.FlowRowScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.InputChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SuggestionChip
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.paneTitle
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.setProgress
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import com.example.appname.plays.LinePart
import com.example.appname.plays.OwnPiece
import com.example.appname.plays.OwnScript
import com.example.appname.plays.PlayPage
import com.example.appname.plays.PlayScript
import com.example.appname.plays.ScriptLine
import com.example.appname.plays.ScriptReading
import com.example.appname.ui.Haptic
import com.example.appname.ui.playButtonColors
import com.example.appname.ui.rememberHaptics
import com.example.appname.ui.theme.AppSemantics
import com.example.appname.ui.theme.OnAir
import com.example.appname.ui.theme.Spacing
import com.example.appname.ui.theme.genreColor
import kotlin.math.abs
import kotlin.math.roundToInt

// What the parts page and the casting page share (ANDROID-DESIGN §4.23): a part's chip, a name's form, the words with a place
// to cut, the sheet that is a bottom sheet on a phone and a side sheet on a wide window, and a line as the reader draws it.

/** From this width the sheet stands beside the lines and casting's parts are a rail. */
internal val OwnWide = 840.dp
private val SideWidth = 380.dp

/** The hue of the [i]th part, as the recorder's and the reader's. */
internal fun hueKeyAt(i: Int): String? = PlayScript.PART_HUES.getOrNull(i)

@Composable
internal fun hueColor(key: String?): Color = genreColor(key, OnAir.colors.dark) ?: MaterialTheme.colorScheme.onSurfaceVariant

@Composable
internal fun HueDot(key: String?) {
    Box(Modifier.size(12.dp).clip(CircleShape).background(hueColor(key)))
}

/** A part as a chip: its dot, its name and, where it helps, its count. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun OwnPartChip(
    name: String, hue: String?, onClick: () -> Unit, modifier: Modifier = Modifier, selected: Boolean = false, count: Int? = null, label: String? = null,
) {
    InputChip(
        selected = selected,
        onClick = onClick,
        label = {
            Row(Modifier.padding(vertical = Spacing.S1.dp), horizontalArrangement = Arrangement.spacedBy(Spacing.S1.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(name, style = MaterialTheme.typography.titleMedium)
                if (count != null) Text(count.toString(), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        },
        leadingIcon = { Box(Modifier.padding(start = Spacing.S1.dp)) { HueDot(hue) } },
        modifier = modifier.heightIn(min = 40.dp).semantics { if (label != null) contentDescription = label },
    )
}

@Composable
internal fun PlainChip(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, icon: (@Composable () -> Unit)? = null) {
    SuggestionChip(
        onClick = onClick,
        label = { Text(text, Modifier.padding(vertical = Spacing.S1.dp), style = MaterialTheme.typography.bodyMedium) },
        icon = icon,
        modifier = modifier.heightIn(min = 40.dp),
    )
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun ChipFlow(modifier: Modifier = Modifier, content: @Composable FlowRowScope.() -> Unit) {
    FlowRow(modifier, horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp), verticalArrangement = Arrangement.spacedBy(2.dp), content = content)
}

/** The steps under a line, two across; one when the text is large. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun StepGrid(steps: List<Pair<String, (() -> Unit)?>>, modifier: Modifier = Modifier, strong: Set<String> = emptySet()) {
    val across = if (LocalDensity.current.fontScale > 1.4f) 1 else 2
    FlowRow(modifier.fillMaxWidth(), maxItemsInEachRow = across, horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp), verticalArrangement = Arrangement.spacedBy(Spacing.S1.dp)) {
        steps.forEach { (text, go) ->
            val m = Modifier.weight(1f)
            if (text in strong) Button(onClick = { go?.invoke() }, modifier = m, enabled = go != null, colors = playButtonColors()) { Text(text) }
            else OutlinedButton(onClick = { go?.invoke() }, modifier = m, enabled = go != null) { Text(text) }
        }
        // An odd last step keeps half the row, so every step is the same size.
        if (across == 2 && steps.size % 2 == 1) Box(Modifier.weight(1f))
    }
}

/** One name and one button: rename, a new part, the title. [act] answers a refusal's words or null. */
@Composable
internal fun NameForm(label: String, button: String, max: Int, act: (String) -> String?, value: String = "", claim: Boolean = false) {
    var name by remember { mutableStateOf(value) }
    var error by remember { mutableStateOf<String?>(null) }
    val focus = remember { FocusRequester() }
    val haptics = rememberHaptics()
    fun submit() {
        error = act(name)
        if (error != null) haptics(Haptic.Error)
    }
    if (claim) LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.S1.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
            OutlinedTextField(
                name, { name = it.take(max); error = null }, Modifier.weight(1f).focusRequester(focus), label = { Text(label) }, singleLine = true, isError = error != null,
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words, autoCorrectEnabled = false, imeAction = ImeAction.Done),
                keyboardActions = KeyboardActions(onDone = { submit() }),
            )
            OutlinedButton(onClick = { submit() }) { Text(button) }
        }
        error?.let { Refusal(it) }
    }
}

@Composable
internal fun Refusal(text: String, modifier: Modifier = Modifier) {
    Text(
        text, modifier.semantics { liveRegion = LiveRegionMode.Assertive }, style = MaterialTheme.typography.labelMedium, color = AppSemantics.colors.error,
    )
}

/** A name asked for in a dialog of its own: a new part, the title. */
@Composable
internal fun NameDialog(title: String, label: String, button: String, max: Int, value: String = "", act: (String) -> String?, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = { NameForm(label, button, max, act, value, claim = true) },
        confirmButton = {},
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

/** A step or a fact spoken by TalkBack and drawn nowhere. [n] makes the same words twice two announcements. */
@Composable
internal fun Announcer(words: String, n: Int) {
    val mark = if (n % 2 == 0) "" else "​"
    Box(Modifier.size(1.dp).semantics { liveRegion = LiveRegionMode.Polite; contentDescription = words + mark })
}

/** A failure above the page with its way on; the work stays on the page. */
@Composable
internal fun ProblemBar(text: String, again: (() -> Unit)?) {
    val haptics = rememberHaptics()
    LaunchedEffect(text) { haptics(Haptic.Error) }
    Surface(color = AppSemantics.colors.errorSurface, modifier = Modifier.fillMaxWidth()) {
        Row(Modifier.padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(text, Modifier.weight(1f).semantics { liveRegion = LiveRegionMode.Assertive }, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurface)
            if (again != null) TextButton(onClick = again) { Text("Try again") }
        }
    }
}

/** A sheet on a phone; the same content from [OwnWide] is [SidePane], drawn by the page beside its lines. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun OwnBottomSheet(label: String, onDismiss: () -> Unit, content: @Composable () -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(
            Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = Spacing.S4.dp).padding(bottom = Spacing.S6.dp).semantics { paneTitle = label },
            verticalArrangement = Arrangement.spacedBy(Spacing.S2.dp),
        ) { content() }
    }
}

@Composable
internal fun SidePane(label: String, onDismiss: () -> Unit, content: @Composable () -> Unit) {
    Surface(Modifier.width(SideWidth).fillMaxHeight().semantics { paneTitle = label }, color = MaterialTheme.colorScheme.surfaceContainer) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = Spacing.S4.dp).padding(bottom = Spacing.S6.dp), verticalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(label, Modifier.weight(1f).semantics { heading() }, style = MaterialTheme.typography.titleMedium)
                IconButton(onClick = onDismiss) { Icon(Icons.Filled.Close, contentDescription = "Close") }
            }
            content()
        }
    }
}

/** A line's words as drawn: printed rows are kept for verse, as on the reader's page; a wrapped paragraph reflows. */
internal fun flowed(text: String): String = if (PlayPage.isVerse(listOf(text))) text else text.replace('\n', ' ')

/** Text this large does not fit a top bar's second line: the fact under the title stands under the bar instead. */
@Composable
internal fun largeText(): Boolean = LocalDensity.current.fontScale > 1.3f

@Composable
internal fun UnderBar(text: String, refused: Boolean = false) {
    Text(
        text, Modifier.fillMaxWidth().padding(horizontal = Spacing.S4.dp, vertical = Spacing.S1.dp)
            .semantics { if (refused) liveRegion = LiveRegionMode.Assertive },
        style = MaterialTheme.typography.bodySmall, color = if (refused) AppSemantics.colors.error else MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

private val WORD = Regex("\\S+")

/**
 * The words with a place to cut: a tap between two words places it; to TalkBack and a keyboard it is a slider over the gaps.
 * [cut] is a UTF-16 offset into [text], or -1.
 */
@Composable
internal fun Cutter(text: String, cut: Int, onCut: (Int) -> Unit, modifier: Modifier = Modifier) {
    val words = remember(text) { WORD.findAll(text).map { it.range.first to it.range.last + 1 }.toList() }
    var gap by remember(text) { mutableIntStateOf(0) }
    var layout by remember { mutableStateOf<TextLayoutResult?>(null) }
    val source = remember { MutableInteractionSource() }
    val focused by source.collectIsFocusedAsState()
    val link = OnAir.colors.link
    val drawn = remember(text) { flowed(text) }
    if (words.size < 2) {
        Text(drawn, modifier.fillMaxWidth(), style = MaterialTheme.typography.bodyMedium)
        return
    }
    fun place(to: Int) {
        gap = to.coerceIn(0, words.size - 1)
        onCut(if (gap > 0) OwnScript.cutAt(text, words[gap].first) else -1)
    }
    fun around(g: Int): String = if (g <= 0 || cut < 0) "None" else {
        fun some(range: IntRange) = range.filter { it in words.indices }.joinToString(" ") { text.substring(words[it].first, words[it].second) }
        some(g - 3 until g) + " | " + some(g until g + 3)
    }
    Text(
        drawn,
        modifier
            .fillMaxWidth()
            .border(2.dp, if (focused) link else Color.Transparent, RoundedCornerShape(4.dp))
            .onKeyEvent { e ->
                if (e.type != KeyEventType.KeyDown) return@onKeyEvent false
                val to = when (e.key) {
                    Key.DirectionRight -> gap + 1
                    Key.DirectionLeft -> gap - 1
                    Key.PageUp -> gap + 10
                    Key.PageDown -> gap - 10
                    Key.MoveHome -> 1
                    Key.MoveEnd -> words.size - 1
                    else -> return@onKeyEvent false
                }
                place(to)
                true
            }
            .focusable(interactionSource = source)
            .semantics {
                contentDescription = "Cut. $drawn"
                stateDescription = around(gap)
                progressBarRangeInfo = ProgressBarRangeInfo(gap.toFloat(), 0f..(words.size - 1).toFloat(), words.size - 2)
                setProgress { v -> val was = gap; place(v.roundToInt()); gap != was }
            }
            .pointerInput(text) {
                detectTapGestures { p ->
                    val l = layout ?: return@detectTapGestures
                    val off = l.getOffsetForPosition(Offset(p.x - Spacing.S1.dp.toPx(), p.y - Spacing.S1.dp.toPx()))
                    val i = words.indexOfLast { it.first <= off }.coerceAtLeast(0)
                    val (from, to) = words[i]
                    place(if (abs(off - from) <= abs(to - off) && off < to) i else i + 1)
                }
            }
            .drawWithContent {
                drawContent()
                val l = layout
                if (l != null && cut in 1 until l.layoutInput.text.length) {
                    val r = l.getCursorRect(cut)
                    val pad = Spacing.S1.dp.toPx()
                    drawLine(link, Offset(r.left + pad - 2.dp.toPx(), r.top + pad), Offset(r.left + pad - 2.dp.toPx(), r.bottom + pad), strokeWidth = 3.dp.toPx())
                }
            }
            .padding(Spacing.S1.dp),
        style = MaterialTheme.typography.bodyMedium,
        onTextLayout = { layout = it },
    )
}

/** A line's words edited in place of the sheet's own content. */
@Composable
internal fun WordsEditor(text: String, refusal: String?, onSave: (String) -> Unit, onCancel: () -> Unit) {
    var words by remember { mutableStateOf(text) }
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
    OutlinedTextField(words, { words = it }, Modifier.fillMaxWidth().heightIn(max = 280.dp).focusRequester(focus), label = { Text("Words") }, isError = refusal != null)
    refusal?.let { Refusal(it) }
    StepGrid(listOf("Save" to { onSave(words) }, "Cancel" to onCancel), strong = setOf("Save"))
}

/** A line as the reader's page sets it (PlayPage.layoutOf, no emphasis rule: the brackets are the person's): a speech's name in its hue over its words. */
@Composable
internal fun OwnLineView(kind: String, role: String?, text: String, hue: String?, modifier: Modifier = Modifier) {
    val muted = MaterialTheme.colorScheme.onSurfaceVariant
    Column(modifier) {
        if (kind == "speech") {
            Text(role.orEmpty(), style = MaterialTheme.typography.titleMedium, color = hueColor(hue))
            val rows = remember(text, role) { speechRows(text, role.orEmpty()) }
            rows.forEach { row ->
                if (row.cue) CueRow(row.words.joinToString(" ") { it.first })
                else Text(directed(row.words, muted), Modifier.padding(start = if (row.indent) Spacing.S6.dp else 0.dp), style = MaterialTheme.typography.bodyMedium)
            }
        } else if (kind == "sound" || kind == "music") {
            CueRow(blockText(text))
        } else {
            Text(
                blockText(text), style = MaterialTheme.typography.bodyMedium.copy(fontStyle = FontStyle.Italic), color = muted, modifier = Modifier.padding(start = Spacing.S4.dp),
            )
        }
    }
}

@Composable
private fun CueRow(text: String) {
    Row(
        Modifier.padding(vertical = 2.dp).clip(RoundedCornerShape(4.dp)).background(MaterialTheme.colorScheme.surfaceVariant).padding(horizontal = Spacing.S2.dp, vertical = 2.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.S1.dp),
    ) {
        Icon(Icons.AutoMirrored.Filled.VolumeUp, contentDescription = null, Modifier.size(14.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        val up = text.uppercase(java.util.Locale.US)
        Text(up, style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.SemiBold))
    }
}

private class DrawnRow(val cue: Boolean, val indent: Boolean, val words: List<Pair<String, Boolean>>)

/** A block's words as its one row draws them: its enclosing brackets left undrawn. */
private fun blockText(text: String): String =
    PlayPage.layoutOf(ScriptLine("L0", ScriptLine.Kind.Direction, source = text), emptyList(), emphasis = false).rows
        .firstOrNull()?.runs?.joinToString("") { it.text }?.let(PlayPage::drawn) ?: text

private fun speechRows(text: String, role: String): List<DrawnRow> {
    val parts = OwnScript.pieces(text).map { if (it is OwnPiece.Say) LinePart.Say(it.text) else LinePart.Direction(it.text) }
    val lay = PlayPage.layoutOf(ScriptLine("L0", ScriptLine.Kind.Speech, role = role, parts = parts), emptyList(), emphasis = false)
    return lay.speeches.flatMap { it.rows }.map { row ->
        val words = ArrayList<Pair<String, Boolean>>()
        row.runs.forEachIndexed { n, run ->
            val prev = row.runs.getOrNull(n - 1)
            if (prev != null && prev.piece != run.piece && ScriptReading.spaceBetween(prev.text, run.text)) words += " " to true
            val shown = PlayPage.drawn(run.text)
            if (run.said) words += shown to true else {
                val opens = (prev == null || prev.piece != run.piece) && !shown.trimStart().let { it.startsWith("(") || it.startsWith("[") }
                val next = row.runs.getOrNull(n + 1)
                val closes = (next == null || next.piece != run.piece) && !shown.trimEnd().let { it.endsWith(")") || it.endsWith("]") }
                words += ((if (opens) "(" else "") + shown + (if (closes) ")" else "")) to false
            }
        }
        DrawnRow(row.cue, row.indent, words)
    }
}

private fun directed(words: List<Pair<String, Boolean>>, muted: Color): AnnotatedString = buildAnnotatedString {
    words.forEach { (t, said) -> if (said) append(t) else withStyle(SpanStyle(fontStyle = FontStyle.Italic, color = muted)) { append(t) } }
}
