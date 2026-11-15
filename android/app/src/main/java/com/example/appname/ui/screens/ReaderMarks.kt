package com.example.appname.ui.screens

import android.view.ActionMode
import android.view.Menu
import android.view.MenuItem
import android.view.View
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.FormatUnderlined
import androidx.compose.material.icons.automirrored.filled.StickyNote2
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import com.example.appname.plays.Mark
import com.example.appname.plays.MarkExtra
import com.example.appname.plays.MarkPatch
import com.example.appname.plays.MarkPrefs
import com.example.appname.plays.MarksCore
import com.example.appname.plays.MarksPrefsStore
import com.example.appname.plays.MarksRepository
import com.example.appname.plays.Piece
import com.example.appname.plays.PlayScript
import com.example.appname.plays.ScriptReading
import com.example.appname.ui.theme.Spacing
import com.example.appname.ui.theme.markColor
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

// The reader's marks (PLAYS-DESIGN §2.10, ANDROID-DESIGN §4.17): the model that holds them, the floating text toolbar's
// six actions, the menu a tap on a mark opens, the sheet for a beat or a note, and the notebook. What a selection makes,
// how marks merge and where a revision puts them is MarksCore's; drawing them is ReaderScreen's.

/** Where a point mark (or a note's end) stands in a line, for the page to leave room for its glyph. */
internal data class PointKey(val id: String, val line: String, val at: Int, val kind: String, val label: String)

internal val MARK_LABEL = mapOf(
    "highlight" to "Highlight", "underline" to "Underline", "breath" to "Breath", "pause" to "Pause", "beat" to "Beat", "note" to "Note",
)
internal val MARK_KEY = mapOf("highlight" to 'h', "underline" to 'u', "breath" to '/', "pause" to 'p', "beat" to 'b', "note" to 'n')

@Stable
internal class MarksModel(
    val script: PlayScript,
    private val repo: MarksRepository,
    private val prefsStore: MarksPrefsStore,
    private val scope: CoroutineScope,
) {
    private val initial = prefsStore.prefs()

    /** Every mark of this play as stored: the placed and the not placed. */
    var all by mutableStateOf<List<Mark>>(emptyList())
        private set
    private var lostIds by mutableStateOf<Set<String>>(emptySet())
    var show by mutableStateOf(initial.show)
        private set
    var hue by mutableStateOf(initial.hue)
        private set
    var failed by mutableStateOf(false)
        private set
    var ready by mutableStateOf(false)
        private set
    private val writes = Mutex()

    val placed: List<Mark> by derivedStateOf { all.filter { it.id !in lostIds } }
    val lost: List<Mark> by derivedStateOf { all.filter { it.id in lostIds } }
    val byLine: Map<String, List<Mark>> by derivedStateOf { placed.groupBy { it.line } }

    /** Where the page makes room, while marks show: a breath, pause or beat, and the end of a note. */
    val points: List<PointKey> by derivedStateOf {
        if (!show) {
            emptyList()
        } else {
            placed.mapNotNull { m ->
                when (m.kind) {
                    "note" -> PointKey(m.id, m.line, m.end, m.kind, "")
                    "breath", "pause", "beat" -> PointKey(m.id, m.line, m.start, m.kind, m.label.orEmpty())
                    else -> null
                }
            }.sortedWith(compareBy({ it.line }, { it.at }, { if (it.kind == "note") 0 else 1 }))
        }
    }

    suspend fun load() {
        val stored = repo.load(script.id)
        val r = MarksCore.place(script, stored)
        all = r.placed + r.lost
        lostIds = r.lost.map { it.id }.toSet()
        ready = true
        if (r.changed) persist()
    }

    private fun persist() {
        val snapshot = all
        scope.launch(Dispatchers.IO) { writes.withLock { failed = !repo.save(script.id, script.title, snapshot) } }
    }

    private fun commit(placedNow: List<Mark>) {
        all = placedNow + all.filter { it.id in lostIds }
        persist()
    }

    private fun savePrefs() = prefsStore.save(MarkPrefs(show, hue))

    fun showMarks(on: Boolean) {
        show = on
        savePrefs()
    }

    /** Makes the marks a selection asks for; marks show again. Returns what was made (the merged result may differ). */
    fun make(kind: String, pieces: List<Piece>, extra: MarkExtra = MarkExtra()): List<Mark> {
        val made = MarksCore.fromSelection(script, pieces, kind, if (kind == "highlight") extra.copy(hue = extra.hue ?: hue) else extra)
        if (made.isEmpty()) return made
        var next = placed
        for (m in made) next = MarksCore.add(script, next, m)
        if (!show) showMarks(true)
        commit(next)
        return made
    }

    fun update(id: String, patch: MarkPatch) {
        if (patch.hue != null) {
            hue = patch.hue
            savePrefs()
        }
        val next = MarksCore.update(all, id, patch)
        all = next
        persist()
    }

    /** Removes a mark and its group; the result is what to give [restore] for Undo. */
    fun remove(id: String): List<Mark> {
        val r = MarksCore.remove(all, id)
        all = r.marks
        lostIds = lostIds - r.removed.map { it.id }.toSet()
        persist()
        return r.removed
    }

    fun restore(removed: List<Mark>, wasLost: Set<String>) {
        all = all + removed
        lostIds = lostIds + wasLost
        persist()
    }

    fun isLost(id: String) = id in lostIds
}

// MARK: The floating toolbar: the system's own, with six more actions after Copy

private const val ACTION_COPY = 100

/** The system's floating text toolbar over a selection, after Copy the six mark actions (and H U / P B N when a keyboard has them). */
@Composable
internal fun SelectionToolbar(active: Boolean, rect: Rect?, onAction: (String) -> Unit, onGone: () -> Unit) {
    val view = LocalView.current
    val latestRect by rememberUpdatedState(rect)
    val act by rememberUpdatedState(onAction)
    val gone by rememberUpdatedState(onGone)
    val holder = remember { arrayOfNulls<ActionMode>(1) }
    DisposableEffect(active, view) {
        if (!active) return@DisposableEffect onDispose { }
        var finishing = false
        val callback = object : ActionMode.Callback2() {
            override fun onCreateActionMode(mode: ActionMode, menu: Menu): Boolean {
                menu.add(Menu.NONE, ACTION_COPY, 0, "Copy").setShowAsAction(MenuItem.SHOW_AS_ACTION_IF_ROOM)
                MarksCore.KINDS.forEachIndexed { i, kind ->
                    menu.add(Menu.NONE, 101 + i, 1 + i, MARK_LABEL.getValue(kind))
                        .setAlphabeticShortcut(MARK_KEY.getValue(kind))
                        .setShowAsAction(MenuItem.SHOW_AS_ACTION_IF_ROOM)
                }
                return true
            }

            override fun onPrepareActionMode(mode: ActionMode, menu: Menu) = false

            override fun onActionItemClicked(mode: ActionMode, item: MenuItem): Boolean {
                act(if (item.itemId == ACTION_COPY) "copy" else MarksCore.KINDS[item.itemId - 101])
                return true
            }

            override fun onDestroyActionMode(mode: ActionMode) {
                if (!finishing) gone()
            }

            override fun onGetContentRect(mode: ActionMode, v: View, outRect: android.graphics.Rect) {
                val r = latestRect
                if (r != null) outRect.set(r.left.toInt(), r.top.toInt(), r.right.toInt(), r.bottom.toInt()) else super.onGetContentRect(mode, v, outRect)
            }
        }
        val mode = view.startActionMode(callback, ActionMode.TYPE_FLOATING)
        holder[0] = mode
        onDispose {
            finishing = true
            holder[0] = null
            mode?.finish()
        }
    }
    LaunchedEffect(rect) { holder[0]?.invalidateContentRect() }
}

// MARK: A tap on a mark

/** What a tap on a mark offers: a highlight's four hues and Delete; Edit and Delete for a beat or a note; Delete for the rest. */
@Composable
internal fun MarkMenu(mark: Mark, dark: Boolean, onHue: (String) -> Unit, onEdit: () -> Unit, onDelete: () -> Unit, onDismiss: () -> Unit) {
    DropdownMenu(expanded = true, onDismissRequest = onDismiss) {
        if (mark.kind == "highlight") {
            Row(Modifier.padding(horizontal = 12.dp), horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                for (h in MarksCore.HUES) {
                    val on = mark.hue == h
                    Box(
                        Modifier.size(48.dp)
                            .clickable(role = Role.RadioButton, onClickLabel = "Make it $h") { onHue(h) }
                            .semantics { contentDescription = h.replaceFirstChar { it.uppercase() }; selected = on },
                        contentAlignment = Alignment.Center,
                    ) {
                        Box(
                            Modifier.size(32.dp).clip(CircleShape).background(markColor(h, dark))
                                .border(BorderStroke(if (on) 2.dp else 1.dp, if (on) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.outline), CircleShape),
                        )
                    }
                }
            }
        }
        if (mark.kind == "beat" || mark.kind == "note") DropdownMenuItem(text = { Text("Edit") }, onClick = onEdit)
        DropdownMenuItem(
            text = { Text("Delete") }, onClick = onDelete,
            leadingIcon = { Icon(Icons.Filled.Delete, contentDescription = null) },
        )
    }
}

/** The words a mark is on, shown as printed: no `_italic_` marks, a gap squeezed. */
private fun shown(s: String): String = s.replace("_", "").replace(Regex("\\s+"), " ")

/** A beat's or a note's sheet: the marked words (a point mark's words around it, the mark between them) above a field. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun MarkEditSheet(kind: String, words: AnnotatedString, initial: String, onSave: (String) -> Unit, onDismiss: () -> Unit) {
    var text by rememberSaveable { mutableStateOf(initial) }
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
    val note = kind == "note"
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(Modifier.padding(horizontal = Spacing.S4.dp).navigationBarsPadding(), verticalArrangement = Arrangement.spacedBy(Spacing.S3.dp)) {
            Text(MARK_LABEL.getValue(kind), style = MaterialTheme.typography.headlineSmall, modifier = Modifier.semantics { heading() })
            if (words.isNotEmpty()) Text(words, style = MaterialTheme.typography.bodyMedium, maxLines = 4, overflow = TextOverflow.Ellipsis)
            OutlinedTextField(
                text, { text = if (note) it else it.take(MarksCore.LABEL_MAX) },
                label = { Text(if (note) "Your note" else "The turn, in a word or three") },
                singleLine = !note, minLines = if (note) 3 else 1,
                supportingText = if (note) null else ({ Text("${text.length}/${MarksCore.LABEL_MAX}") }),
                keyboardOptions = KeyboardOptions(imeAction = if (note) ImeAction.Default else ImeAction.Done),
                modifier = Modifier.fillMaxWidth().focusRequester(focus),
            )
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                TextButton(onClick = onDismiss) { Text("Cancel") }
                Button(onClick = { onSave(text) }, enabled = !note || text.isNotBlank()) { Text("Save") }
            }
            Spacer(Modifier.height(Spacing.S4.dp))
        }
    }
}

// MARK: The notebook

/** The words of a mark for the notebook: a point mark's words around it with the mark between them. */
internal fun notebookWords(script: PlayScript, m: Mark, ink: androidx.compose.ui.graphics.Color): AnnotatedString {
    if (m.kind in MarksCore.SPAN) return AnnotatedString(shown(m.text))
    val lt = script.lines.firstOrNull { it.id == m.line }?.let(ScriptReading::lineText).orEmpty()
    val before = shown(lt.substring(maxOf(0, m.start - 32), m.start.coerceAtMost(lt.length))).replace(Regex("^\\S*\\s"), "… ")
    val after = shown(lt.substring(m.start.coerceAtMost(lt.length), minOf(lt.length, m.start + 32))).replace(Regex("\\s\\S*$"), " …")
    return buildAnnotatedString {
        append(before)
        withStyle(SpanStyle(fontWeight = FontWeight.Bold, color = ink)) { append(if (m.kind == "breath") " / " else " // ") }
        append(after)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun NotebookSheet(
    model: MarksModel,
    dark: Boolean,
    onGo: (Mark) -> Unit,
    onDelete: (Mark) -> Unit,
    onDismiss: () -> Unit,
) {
    val script = model.script
    val roles = remember(script) { script.lines.associate { it.id to it.role } }
    val ink = MaterialTheme.colorScheme.onSurface
    val placed = remember(model.placed, script) { MarksCore.order(script, model.placed) }
    val lost = model.lost
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(Modifier.navigationBarsPadding()) {
            Text(
                "Marks", style = MaterialTheme.typography.headlineSmall,
                modifier = Modifier.padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp).semantics { heading() },
            )
            Row(Modifier.fillMaxWidth().padding(horizontal = Spacing.S4.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Show marks", style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
                Switch(checked = model.show, onCheckedChange = { model.showMarks(it) })
            }
            if (model.failed) {
                Row(Modifier.padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.Warning, contentDescription = null, tint = MaterialTheme.colorScheme.error, modifier = Modifier.size(18.dp))
                    Text(
                        "Marks are not being saved on this device.", style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(start = 8.dp),
                    )
                }
            }
            if (placed.isEmpty() && lost.isEmpty()) {
                Text(
                    "Select words on the page to mark them.", style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.padding(Spacing.S4.dp),
                )
                Spacer(Modifier.height(Spacing.S4.dp))
                return@Column
            }
            LazyColumn(Modifier.heightIn(max = 520.dp)) {
                items(placed, key = { it.id }) { m ->
                    NotebookRow(model, m, roles[m.line], dark, ink, trailing = null) { onGo(m) }
                }
                if (lost.isNotEmpty()) {
                    item(key = "not-placed") {
                        Text(
                            "Not placed", style = MaterialTheme.typography.titleMedium,
                            modifier = Modifier.padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp).semantics { heading() },
                        )
                    }
                    items(lost, key = { "lost-" + it.id }) { m ->
                        NotebookRow(
                            model, m, roles[m.line], dark, ink,
                            trailing = {
                                IconButton(onClick = { onDelete(m) }) { Icon(Icons.Filled.Delete, contentDescription = "Delete this mark") }
                            },
                            onClick = null,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun NotebookRow(
    model: MarksModel,
    m: Mark,
    role: String?,
    dark: Boolean,
    ink: androidx.compose.ui.graphics.Color,
    trailing: (@Composable () -> Unit)?,
    onClick: (() -> Unit)?,
) {
    val words = remember(m) { notebookWords(model.script, m, ink) }
    val said = words.text.ifEmpty { m.kind }
    Row(
        Modifier.fillMaxWidth()
            .then(if (onClick != null) Modifier.clickable(onClickLabel = "Go to this mark") { onClick() } else Modifier)
            .heightIn(min = 56.dp)
            .padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp)
            .semantics(mergeDescendants = true) {
                contentDescription = "${MARK_LABEL.getValue(m.kind)}: $said" + (m.label?.takeIf { it.isNotEmpty() }?.let { ", $it" } ?: "") + (m.note?.let { ", $it" } ?: "")
            },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(32.dp), contentAlignment = Alignment.Center) { MarkGlyph(m, dark, ink) }
        Column(Modifier.weight(1f).padding(start = Spacing.S3.dp)) {
            role?.takeIf { it.isNotEmpty() }?.let {
                Text(it, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
            }
            if (words.isNotEmpty()) Text(words, style = MaterialTheme.typography.bodyMedium, maxLines = 3, overflow = TextOverflow.Ellipsis)
            m.label?.takeIf { it.isNotEmpty() }?.let {
                Text(it.uppercase(java.util.Locale.US), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            m.note?.takeIf { it.isNotEmpty() }?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        }
        trailing?.invoke()
    }
}

/** A mark's glyph in the notebook: the hue for a highlight, an icon or the slashes for the rest. */
@Composable
private fun MarkGlyph(m: Mark, dark: Boolean, ink: androidx.compose.ui.graphics.Color) {
    when (m.kind) {
        "highlight" -> Box(Modifier.size(22.dp).clip(CircleShape).background(markColor(m.hue, dark)).border(1.dp, MaterialTheme.colorScheme.outline, CircleShape))
        "underline" -> Icon(Icons.Filled.FormatUnderlined, contentDescription = null, tint = ink)
        "note" -> Icon(Icons.AutoMirrored.Filled.StickyNote2, contentDescription = null, tint = ink)
        "breath" -> Text("/", style = MaterialTheme.typography.titleMedium, color = ink)
        else -> Text("//", style = MaterialTheme.typography.titleMedium, color = ink)
    }
}
