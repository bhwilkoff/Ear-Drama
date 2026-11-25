package com.example.appname.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.isCtrlPressed
import androidx.compose.ui.input.key.isShiftPressed
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import com.example.appname.data.Transcript
import com.example.appname.plays.OwnDoc
import com.example.appname.plays.OwnEnv
import com.example.appname.plays.OwnLine
import com.example.appname.plays.OwnMeta
import com.example.appname.plays.OwnOp
import com.example.appname.plays.OwnRecord
import com.example.appname.plays.OwnScript
import com.example.appname.plays.OwnScripts
import com.example.appname.plays.OwnTarget
import com.example.appname.plays.OwnWords
import com.example.appname.ui.EmptyAction
import com.example.appname.ui.EmptyMessage
import com.example.appname.ui.Haptic
import com.example.appname.ui.LocalAppContainer
import com.example.appname.ui.playButtonColors
import com.example.appname.ui.rememberHaptics
import com.example.appname.ui.theme.AppSemantics
import com.example.appname.ui.theme.Spacing
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Keeps a script a moment after its last change, and whatever is owed when the page goes. One writer a page. */
internal class OwnKeeper(private val own: OwnScripts, private val scope: CoroutineScope, private val now: () -> OwnRecord?) {
    /** Why the last write failed, or null. */
    var problem by mutableStateOf<String?>(null)
        private set
    private var job: Job? = null
    private var owed = false
    private var dropped = false

    /** The script is being deleted: nothing more is kept for it. */
    fun drop() {
        dropped = true
        job?.cancel()
    }

    fun soon() {
        owed = true
        job?.cancel()
        job = scope.launch {
            delay(350)
            write()
        }
    }

    /** What is owed, now, on a scope that outlives the page. */
    fun flush() {
        if (owed && !dropped) scope.launch { write() }
    }

    suspend fun write(): Boolean = withContext(NonCancellable) {
        if (dropped) return@withContext true
        val rec = now() ?: return@withContext true
        owed = false
        try {
            // Shared from another screen since this one opened it: what people were sent stands (§13 item 12).
            if (own.keep(rec) == "shared") {
                problem = OwnWords.say("shared")
                return@withContext false
            }
            problem = null
            true
        } catch (e: Exception) {
            if (e is CancellationException) throw e
            owed = true
            problem = OwnWords.notKept(e)
            false
        }
    }
}

/** The page's state: the script as it stands, the lines that may not move, what the last step said. */
@Stable
internal class OwnPartsModel(rec: OwnRecord, val takes: Set<String>) {
    var rec by mutableStateOf(rec)
    var current by mutableIntStateOf(0)
    var edited by mutableStateOf(false)
    var said by mutableStateOf("" to 0)
        private set
    val doc: OwnDoc get() = rec.doc

    fun say(words: String) { said = words to said.second + 1 }
    fun line(k: Int): OwnLine? = doc.lines.firstOrNull { it.k == k }
    fun index(k: Int): Int = doc.lines.indexOfFirst { it.k == k }
    fun locked(l: OwnLine?): Boolean = l?.id != null && l.id in takes

    /** The parts, most lines first, then those named and not yet given one. */
    fun parts(): List<Pair<String, Int>> {
        val ps = OwnScript.partsOf(doc.lines)
        val at = ps.withIndex().associate { it.value.first to it.index }
        return ps.sortedWith(compareByDescending<Pair<String, Int>> { it.second }.thenBy { at.getValue(it.first) }) +
            rec.extras.filter { it !in at }.map { it to 0 }
    }

    /** One change: a refusal's code, or null when it is done (or was nothing). */
    fun apply(op: OwnOp, spoken: String?): String? {
        val r = OwnScript.apply(doc, op, OwnEnv(takes))
        r.refusal?.let { return it }
        if (r.doc !== doc) {
            rec = rec.copy(doc = r.doc)
            edited = true
            spoken?.let(::say)
        }
        return null
    }

    /** A part named before any line is given to it. */
    fun addPart(raw: String): Pair<String, String?> {
        val name = OwnScript.partName(OwnScript.normalize(raw))
        OwnScript.partNameRefusal(name)?.let { return name to OwnWords.name(it) }
        if (parts().none { it.first == name }) rec = rec.copy(extras = rec.extras + name)
        return name to null
    }

    fun nextOpen(): Int? {
        val lines = doc.lines
        if (lines.isEmpty()) return null
        val from = if (edited || current != lines.first().k) index(current) else -1
        return lines.indices.map { (from + 1 + it) % lines.size }.firstOrNull { lines[it].kind == "open" }?.let { lines[it].k }
    }
}

private sealed interface PartsLoad {
    data object Loading : PartsLoad
    data object Missing : PartsLoad
    data object Failed : PartsLoad

    /** Shared once, a script is what people were sent: its page has Edit a copy (§13 item 12). */
    data object Shared : PartsLoad
    data class Ready(val model: OwnPartsModel) : PartsLoad
}

/** The sheet over the page, or beside it on a wide window. */
private sealed interface OwnSheet {
    data class Line(val k: Int) : OwnSheet
    data class Part(val name: String) : OwnSheet
}

/** The parts page of a script on this device (ANDROID-DESIGN §4.23 item 2). */
@Composable
fun OwnPartsScreen(id: String, onBack: () -> Unit, onDone: (String) -> Unit) {
    val own = LocalAppContainer.current.plays.own
    var attempt by remember { mutableIntStateOf(0) }
    val load by produceState<PartsLoad>(PartsLoad.Loading, id, attempt) {
        value = PartsLoad.Loading
        value = withContext(Dispatchers.IO) {
            try {
                own.get(id)?.let { rec ->
                    if (rec.shared != null) return@let PartsLoad.Shared
                    val taken = own.takes(id)
                    // A transcript cast in part: its marks become the lines' own parts, and left-out lines are gone (§13 item 10).
                    PartsLoad.Ready(OwnPartsModel(if (rec.ear != null) rec.copy(doc = OwnScript.settle(rec.doc)) else rec, taken))
                } ?: PartsLoad.Missing
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                PartsLoad.Failed
            }
        }
    }
    if (load == PartsLoad.Shared) LaunchedEffect(id) { onDone(id) }
    when (val l = load) {
        is PartsLoad.Ready -> OwnPartsPage(l.model, onBack, onDone)
        else -> Scaffold(topBar = { BackBar(onBack) }) { padding ->
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                when (l) {
                    PartsLoad.Missing -> EmptyMessage("This script is not on this device.")
                    PartsLoad.Failed -> EmptyMessage("This did not load.", action = EmptyAction("Try again") { attempt++ })
                    else -> CircularProgressIndicator(Modifier.semantics { contentDescription = "Loading" })
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun OwnPartsPage(model: OwnPartsModel, onBack: () -> Unit, onDone: (String) -> Unit) {
    val container = LocalAppContainer.current
    val haptics = rememberHaptics()
    val scope = rememberCoroutineScope()
    val keeper = remember(model) { OwnKeeper(container.plays.own, container.appScope) { model.rec } }
    val list = rememberLazyListState()
    var sheet by remember { mutableStateOf<OwnSheet?>(null) }
    var renaming by remember { mutableStateOf(false) }
    var naming by remember { mutableStateOf(false) }
    var more by remember { mutableStateOf(false) }
    var refusal by remember { mutableStateOf<String?>(null) }
    var finishing by remember { mutableStateOf(false) }
    if (model.current == 0) model.doc.lines.firstOrNull()?.let { model.current = it.k }

    LifecycleEventEffect(Lifecycle.Event.ON_STOP) { keeper.flush() }
    DisposableEffect(keeper) { onDispose { keeper.flush() } }

    /** One change: drawn, kept and said; the refusal's words when it is not allowed. */
    fun change(op: OwnOp, spoken: String?): String? {
        val before = model.rec
        val why = model.apply(op, spoken)
        if (why != null) {
            haptics(Haptic.Error)
            return OwnWords.say(why)
        }
        if (model.rec !== before) {
            haptics(Haptic.Selection)
            keeper.soon()
        }
        refusal = null
        return null
    }
    fun undo() { if (model.doc.undo.isNotEmpty()) change(OwnOp("undo"), "Undone") }
    fun finish() {
        val rec = model.rec
        val doc = OwnScript.done(rec.doc)
        val why = OwnScript.refusalOf(OwnScript.toScript(doc, OwnMeta(rec.id, rec.title, rec.episode?.id, rec.episode?.url)))
        if (why != null) {
            refusal = OwnWords.script(why)
            return
        }
        finishing = true
        scope.launch {
            model.rec = rec.copy(doc = doc, done = true)
            if (keeper.write()) onDone(rec.id) else {
                model.rec = rec
                finishing = false
            }
        }
    }

    val lines = model.doc.lines
    val parts = remember(lines, model.rec.extras) { model.parts() }
    val hues = remember(parts) { partHues(parts) }
    val near = remember(lines) { OwnScripts.nearestAll(lines) }
    val open = remember(lines) { lines.count { it.kind == "open" } }
    val large = largeText()
    val size = OwnWords.partsAndLines(parts.count { it.second > 0 }, lines.size)

    Scaffold(
        modifier = Modifier.onPreviewKeyEvent { e ->
            if (e.type == KeyEventType.KeyDown && e.key == Key.Z && e.isCtrlPressed && !e.isShiftPressed && sheet == null) {
                undo()
                true
            } else {
                false
            }
        },
        topBar = {
            TopAppBar(
                title = {
                    Column(Modifier.clickable(onClickLabel = "Change the title") { renaming = true }.padding(vertical = Spacing.S1.dp)) {
                        Text(model.rec.title, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        if (!large) {
                            Text(size, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                    }
                },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back") } },
                actions = {
                    IconButton(onClick = ::undo, enabled = model.doc.undo.isNotEmpty()) { Icon(Icons.AutoMirrored.Filled.Undo, contentDescription = "Undo") }
                    Button(onClick = ::finish, enabled = !finishing, colors = playButtonColors(), modifier = Modifier.padding(end = Spacing.S3.dp)) { Text("Done") }
                },
            )
        },
    ) { padding ->
        BoxWithConstraints(Modifier.fillMaxSize().padding(padding)) {
            val wide = maxWidth >= OwnWide
            Row(Modifier.fillMaxSize()) {
                Column(Modifier.weight(1f)) {
                    Announcer(model.said.first, model.said.second)
                    if (large) UnderBar(size)
                    (keeper.problem ?: refusal)?.let { words ->
                        ProblemBar(words, if (keeper.problem != null) ({ scope.launch { keeper.write() } }) else null)
                    }
                    if (open > 0) {
                        Surface(color = MaterialTheme.colorScheme.surfaceContainer) {
                            Row(Modifier.fillMaxWidth().padding(start = Spacing.S4.dp, end = Spacing.S2.dp), verticalAlignment = Alignment.CenterVertically) {
                                Text(OwnWords.noPart(open), Modifier.weight(1f), style = MaterialTheme.typography.titleMedium, color = AppSemantics.colors.warning)
                                TextButton(onClick = {
                                    model.nextOpen()?.let { k ->
                                        model.current = k
                                        model.edited = true
                                        haptics(Haptic.Selection)
                                        scope.launch { list.scrollToItem(model.index(k) + HEADERS, -list.layoutInfo.viewportSize.height / 3) }
                                        model.line(k)?.let { model.say("No part. ${it.text}") }
                                    }
                                }) { Text("Next") }
                            }
                        }
                    }
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
                        LazyColumn(
                            Modifier.widthIn(max = 720.dp).fillMaxSize(), state = list,
                            contentPadding = PaddingValues(start = Spacing.S4.dp, end = Spacing.S4.dp, top = Spacing.S2.dp, bottom = Spacing.S8.dp),
                            verticalArrangement = Arrangement.spacedBy(Spacing.S1.dp),
                        ) {
                            item(key = "chips", contentType = "chips") {
                                Column {
                                    if (model.rec.ear != null) Text(Transcript.LABEL, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    PartChips(parts, hues, more, if (wide) 8 else 4, onMore = { more = true }, onPart = { sheet = OwnSheet.Part(it) }, onNew = { naming = true })
                                }
                            }
                            if (lines.isEmpty()) item(key = "none") { EmptyMessage(OwnWords.say("no_lines"), Modifier.fillMaxWidth()) }
                            items(lines, key = { it.k }, contentType = { if (it.kind == "open") "open" else it.kind }) { l ->
                                val openIt = remember(l.k) { { model.current = l.k; sheet = OwnSheet.Line(l.k) } }
                                if (l.kind == "open") {
                                    OpenLine(l, near[l.k].orEmpty(), hues, onGive = { to, spoken -> model.current = l.k; change(OwnOp("assign", line = l.k, to = to), spoken)?.let { refusal = it } }, onMore = openIt)
                                } else {
                                    OwnLineView(
                                        l.kind, l.role, l.text, hues[l.role],
                                        Modifier.fillMaxWidth().heightIn(min = 48.dp).clickable(onClickLabel = "Change this line", onClick = openIt).padding(vertical = Spacing.S1.dp),
                                    )
                                }
                            }
                        }
                    }
                }
                val now = sheet
                // Beside the lines it is no dialog, so back is its own: it closes the sheet before the page.
                androidx.activity.compose.BackHandler(enabled = wide && now != null) { sheet = null }
                if (wide && now != null) SidePane(if (now is OwnSheet.Part) now.name else "Line", onDismiss = { sheet = null }) {
                    SheetBody(now, model, hues, near, ::change, onPartGone = { keeper.soon() }, onClose = { sheet = null })
                }
            }
            if (!wide) sheet?.let { now ->
                OwnBottomSheet(if (now is OwnSheet.Part) now.name else "Line", onDismiss = { sheet = null }) {
                    SheetBody(now, model, hues, near, ::change, onPartGone = { keeper.soon() }, onClose = { sheet = null })
                }
            }
        }
    }
    if (renaming) NameDialog("Title", "Title", "Save", OwnScript.MAX_TITLE, model.rec.title, act = { v ->
        val t = OwnScript.trim(OwnScript.normalize(v))
        if (t.isEmpty()) OwnWords.say("no_title") else {
            model.rec = model.rec.copy(title = t)
            keeper.soon()
            renaming = false
            null
        }
    }, onDismiss = { renaming = false }, below = if (model.rec.done) null else ({
        DeleteNotDone(model.rec.title, delete = { keeper.drop(); container.plays.deleteOwn(model.rec.id) }, onGone = { renaming = false; onBack() })
    }))
    if (naming) NameDialog("New part", "Name", "Add", OwnScript.MAX_PART_NAME, act = { v ->
        val (_, why) = model.addPart(v)
        if (why == null) {
            more = true
            keeper.soon()
            naming = false
        }
        why
    }, onDismiss = { naming = false })
}

private const val HEADERS = 1

@Composable
private fun PartChips(parts: List<Pair<String, Int>>, hues: Map<String, String?>, all: Boolean, few: Int, onMore: () -> Unit, onPart: (String) -> Unit, onNew: () -> Unit) {
    val shown = if (all) parts.size else minOf(parts.size, few)
    ChipFlow(Modifier.fillMaxWidth()) {
        parts.take(shown).forEach { (name, n) -> OwnPartChip(name, hues[name], onClick = { onPart(name) }, count = n, label = "$name, ${OwnWords.lines(n)}") }
        if (parts.size > shown) PlainChip("${parts.size - shown} more", onMore)
        PlainChip("Part", onNew, Modifier.semantics { contentDescription = "New part" }, icon = { Icon(Icons.Outlined.Add, contentDescription = null) })
    }
}

/** A paragraph given to nobody: its nearest speakers are one tap away. */
@Composable
private fun OpenLine(l: OwnLine, near: List<String>, hues: Map<String, String?>, onGive: (OwnTarget, String) -> Unit, onMore: () -> Unit) {
    val warn = AppSemantics.colors.warning
    Column(
        Modifier.fillMaxWidth()
            .drawBehind {
                val w = 1.5.dp.toPx()
                drawRoundRect(
                    warn, topLeft = androidx.compose.ui.geometry.Offset(w / 2, w / 2), size = Size(size.width - w, size.height - w), cornerRadius = CornerRadius(8.dp.toPx()),
                    style = Stroke(w, pathEffect = PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(), 3.dp.toPx()))),
                )
            }
            .padding(horizontal = Spacing.S3.dp, vertical = Spacing.S2.dp),
    ) {
        Column(Modifier.fillMaxWidth().heightIn(min = 48.dp).clickable(onClickLabel = "Change this line", onClick = onMore)) {
            Text("No part", style = MaterialTheme.typography.labelMedium, color = warn)
            Text(flowed(l.text), style = MaterialTheme.typography.bodyMedium)
        }
        ChipFlow {
            near.forEach { name -> OwnPartChip(name, hues[name], onClick = { onGive(OwnTarget.Role(name), name) }, label = "Give to $name") }
            PlainChip("Direction", { onGive(OwnTarget.KindOf("direction"), "Direction") })
            PlainChip("More", onMore)
        }
    }
}

private val KIND_WORD = linkedMapOf("direction" to "Direction", "sound" to "Sound", "music" to "Music")

@Composable
private fun SheetBody(
    sheet: OwnSheet, model: OwnPartsModel, hues: Map<String, String?>, near: Map<Int, List<String>>, change: (OwnOp, String?) -> String?, onPartGone: () -> Unit, onClose: () -> Unit,
) {
    when (sheet) {
        is OwnSheet.Line -> {
            val line = model.line(sheet.k)
            if (line == null) LaunchedEffect(sheet) { onClose() } else androidx.compose.runtime.key(sheet.k) { LineBody(line, model, hues, near, change, onClose) }
        }
        is OwnSheet.Part -> androidx.compose.runtime.key(sheet.name) { PartBody(sheet.name, model, hues, change, onPartGone, onClose) }
    }
}

@Composable
private fun LineBody(l: OwnLine, model: OwnPartsModel, hues: Map<String, String?>, near: Map<Int, List<String>>, change: (OwnOp, String?) -> String?, onClose: () -> Unit) {
    var refusal by remember { mutableStateOf<String?>(null) }
    var editing by remember { mutableStateOf(false) }
    var cut by remember(l.text) { mutableIntStateOf(-1) }
    var all by remember { mutableStateOf(false) }
    var wider by remember { mutableStateOf(false) }
    /** Does it and closes; a refusal stays in the sheet. */
    fun act(op: OwnOp, spoken: String) {
        val why = change(op, spoken)
        if (why != null) refusal = why else onClose()
    }
    if (editing) {
        WordsEditor(l.text, refusal, onSave = { act(OwnOp("words", line = l.k, text = it), "Words changed") }, onCancel = onClose)
        return
    }
    if (model.locked(l)) {
        Text(flowed(l.text), style = MaterialTheme.typography.bodyMedium)
        Refusal(OwnWords.say("line_has_take"))
        StepGrid(listOf("Edit words" to { editing = true }))
        return
    }
    Cutter(l.text, cut, { cut = it })
    val parts = remember(model.rec) { model.parts().map { it.first } }
    val nearest = remember(model.rec) { (listOfNotNull(l.role) + (near[l.k] ?: OwnScript.nearestParts(model.doc.lines, model.index(l.k)))).distinct() }
    val rest = parts.filter { it !in nearest }
    val few = parts.size <= 6
    ChipFlow {
        (nearest + if (few || all) rest else emptyList()).forEach { name ->
            OwnPartChip(name, hues[name], onClick = { act(OwnOp("assign", line = l.k, to = OwnTarget.Role(name)), name) }, selected = l.kind == "speech" && l.role == name)
        }
        if (!all) PlainChip(if (few) "New part" else "All parts", { all = true })
        KIND_WORD.filter { it.key != "music" || l.kind == "music" }.forEach { (kind, word) ->
            if (l.kind == kind) OwnPartChip(word, null, onClick = onClose, selected = true) else PlainChip(word, { act(OwnOp("assign", line = l.k, to = OwnTarget.KindOf(kind)), word) })
        }
    }
    if (all) NameForm("New part", "Give", OwnScript.MAX_PART_NAME, act = { v ->
        val (name, why) = model.addPart(v)
        if (why == null) act(OwnOp("assign", line = l.k, to = OwnTarget.Role(name)), name)
        why
    }, claim = few)
    val i = model.index(l.k)
    val last = i == model.doc.lines.lastIndex
    val steps = buildList<Pair<String, (() -> Unit)?>> {
        if (l.text.trim().any { it.isWhitespace() }) add("Split here" to (if (cut >= 0) ({ act(OwnOp("split", line = l.k, at = cut), "Split") }) else null))
        if (i > 0) add("Join to line above" to { act(OwnOp("join", line = l.k), "Joined") })
        add("Edit words" to { editing = true })
        add("Leave out" to { act(OwnOp("leaveOut", line = l.k), "Left out") })
    }
    StepGrid(steps)
    if (i != 0 || !last) {
        if (!wider) OutlinedButton(onClick = { wider = true }, Modifier.fillMaxWidth()) { Text("More") } else {
            if (i > 0) OutlinedButton(onClick = { act(OwnOp("leaveOutAbove", line = l.k), "Left out") }, Modifier.fillMaxWidth()) { Text("Leave out everything above") }
            if (!last) OutlinedButton(onClick = { act(OwnOp("leaveOutBelow", line = l.k), "Left out") }, Modifier.fillMaxWidth()) { Text("Leave out everything below") }
        }
    }
    refusal?.let { Refusal(it) }
}

@Composable
private fun PartBody(name: String, model: OwnPartsModel, hues: Map<String, String?>, change: (OwnOp, String?) -> String?, onPartGone: () -> Unit, onClose: () -> Unit) {
    var refusal by remember { mutableStateOf<String?>(null) }
    val mine = remember(model.rec) { model.doc.lines.filter { it.kind == "speech" && it.role == name } }
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
        HueDot(hues[name])
        Text(name, style = MaterialTheme.typography.titleMedium, color = hueColor(hues[name]))
        Text(OwnWords.lines(mine.size), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
    if (mine.any { model.locked(it) }) {
        Refusal(OwnWords.say("part_has_take"))
        return
    }
    if (mine.isEmpty()) {
        OutlinedButton(onClick = {
            model.rec = model.rec.copy(extras = model.rec.extras - name)
            onPartGone()
            onClose()
        }) { Text("Leave out") }
        return
    }
    fun act(op: OwnOp, spoken: String): String? = change(op, spoken).also { if (it == null) onClose() }
    NameForm("Name", "Rename", OwnScript.MAX_PART_NAME, act = { v ->
        val to = OwnScript.partName(OwnScript.normalize(v))
        OwnScript.partNameRefusal(to)?.let(OwnWords::name) ?: act(OwnOp("rename", part = name, rename = v), to)
    }, value = name)
    val others = model.parts().filter { it.first != name }
    if (others.isNotEmpty()) {
        Text("Join to", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        ChipFlow {
            others.forEach { (other, n) ->
                OwnPartChip(other, hues[other], onClick = { refusal = act(OwnOp("rename", part = name, rename = other), other) }, count = n, label = "Join to $other")
            }
        }
    }
    OutlinedButton(onClick = { refusal = act(OwnOp("notPart", part = name), "No part") }) { Text("Not a part") }
    refusal?.let { Refusal(it) }
}
