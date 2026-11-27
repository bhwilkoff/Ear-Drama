package com.example.appname.ui.screens

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.outlined.FolderOpen
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.appname.plays.OwnSounds
import com.example.appname.plays.SoundCore
import com.example.appname.plays.SoundCue
import com.example.appname.ui.recordButtonColors
import com.example.appname.ui.theme.AppSemantics
import com.example.appname.ui.theme.OnAir
import com.example.appname.ui.theme.Spacing
import com.example.appname.ui.wayColors

// The board (B32 §3.2; ANDROID-DESIGN §4.17): the slot, what is in it, then a library to put sounds from. Stateless: the
// screen builds a BoardModel and answers the BoardActions, so the same composables draw the frames.

/** The chip that holds the person's own sounds, after the pack's categories. */
const val MINE = "mine"

/** One sound already in the cue. */
data class InCueRow(val id: String, val title: String, val meta: String, val missing: Boolean = false, val selected: Boolean = false)

sealed interface PackUi {
    data object Absent : PackUi
    data object Loading : PackUi
    data object Unreachable : PackUi
    data class Ready(
        val cues: List<SoundCore.PackCue>,
        val categories: List<SoundCore.Category>,
        val here: Set<String>,
        val downloading: String? = null,
        val failed: String? = null,
        val offline: Boolean = false,
    ) : PackUi
}

data class BoardModel(
    val headline: String,
    val words: String,
    val silent: Boolean,
    val inCue: List<InCueRow>,
    val selected: SoundCue?,
    val untilLabel: String?,
    val laneDuckDb: Double,
    val query: String,
    val category: String?,
    val pack: PackUi,
    val inCueIds: Set<String>,
    val mine: List<OwnSounds.Sound>,
    val recordingOwn: Boolean = false,
    val ownSeconds: Int = 0,
    val ownError: String? = null,
    val auditioning: String? = null,
    val picking: Boolean = false,
)

class BoardActions(
    val onDone: () -> Unit = {},
    val onSilent: (Boolean) -> Unit = {},
    val onSelect: (String) -> Unit = {},
    val onRemove: (String) -> Unit = {},
    val onPatch: (SoundCore.Patch) -> Unit = {},
    val onPickUntil: () -> Unit = {},
    val onQuery: (String) -> Unit = {},
    val onCategory: (String?) -> Unit = {},
    val onAddPack: (SoundCore.PackCue) -> Unit = {},
    val onAddOwn: (OwnSounds.Sound) -> Unit = {},
    val onAudition: (String) -> Unit = {},
    val onDownload: (String) -> Unit = {},
    val onRetry: () -> Unit = {},
    val onRecordOwn: () -> Unit = {},
    val onBring: () -> Unit = {},
    val onRemoveOwn: (String) -> Unit = {},
    val onRecordIt: () -> Unit = {},
)

private fun dbWords(db: Double) = (if (db < 0) "−" else if (db > 0) "+" else "") + "${kotlin.math.abs(db).toInt()} dB"

private fun secondsWords(ms: Double) = if (ms == 0.0) "0 s" else String.format(java.util.Locale.US, "%.1f s", ms / 1000).replace(".0 s", " s")

/** The board's content, in a sheet on a phone and the screen's end pane from 840 dp. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun SoundBoard(model: BoardModel, act: BoardActions, modifier: Modifier = Modifier) {
    val pack = model.pack
    val mineOn = model.category == MINE
    val hasQuery = model.query.isNotBlank()
    val results = remember(pack, model.query, model.category) {
        if (pack is PackUi.Ready && !mineOn) SoundCore.search(pack.cues, model.query, model.category) else emptyList()
    }
    val mine = remember(model.mine, model.query, mineOn) {
        if (mineOn || hasQuery) SoundCore.searchMine(model.mine, model.query) { it.name } else emptyList()
    }
    LazyColumn(modifier.fillMaxWidth().heightIn(max = 720.dp), contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = Spacing.S6.dp)) {
        item(key = "slot") {
            Column(Modifier.padding(horizontal = Spacing.S4.dp), verticalArrangement = Arrangement.spacedBy(Spacing.S1.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(model.headline.uppercase(), Modifier.weight(1f).semantics { heading() }, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    TextButton(onClick = act.onDone) { Text("Done") }
                }
                if (model.words.isNotBlank()) {
                    Text(model.words, style = MaterialTheme.typography.bodyMedium.copy(fontStyle = androidx.compose.ui.text.font.FontStyle.Italic), maxLines = 3, overflow = TextOverflow.Ellipsis)
                }
                if (model.inCue.isEmpty()) {
                    OutlinedButton(onClick = { act.onSilent(!model.silent) }, colors = wayColors()) { Text(if (model.silent) "Silent. Undo" else "Leave silent") }
                }
            }
        }
        if (model.inCue.isNotEmpty()) {
            item(key = "in-h") { BoardHeader("In this cue") }
            items(model.inCue, key = { "in-${it.id}" }) { row -> InCue(row, row.id == model.auditioning, act) }
            model.selected?.let { x -> item(key = "controls") { Controls(x, model, act) } }
        }
        item(key = "find-h") { BoardHeader("Sounds") }
        item(key = "search") {
            OutlinedTextField(
                value = model.query, onValueChange = act.onQuery, singleLine = true,
                label = { Text("Search sounds") },
                keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(imeAction = ImeAction.Search),
                modifier = Modifier.fillMaxWidth().padding(horizontal = Spacing.S4.dp),
            )
        }
        item(key = "chips") {
            FlowRow(Modifier.fillMaxWidth().padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp), horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
                val cats = (pack as? PackUi.Ready)?.categories.orEmpty()
                cats.forEach { c ->
                    FilterChip(selected = model.category == c.id, onClick = { act.onCategory(if (model.category == c.id) null else c.id) }, label = { Text(c.title) })
                }
                FilterChip(selected = mineOn, onClick = { act.onCategory(if (mineOn) null else MINE) }, label = { Text("Mine") })
            }
        }
        when (pack) {
            PackUi.Loading -> items(3, key = { "skel-$it" }) { Skeleton() }
            PackUi.Unreachable -> item(key = "unreachable") {
                Row(Modifier.fillMaxWidth().padding(horizontal = Spacing.S4.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text("The sounds are not downloaded yet.", Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
                    TextButton(onClick = act.onRetry) { Text("Try again") }
                }
            }
            is PackUi.Ready -> {
                val cat = pack.categories.firstOrNull { it.id == model.category }
                if (cat != null && cat.id !in pack.here) item(key = "download") { CategoryHead(cat, pack, act) }
                items(results, key = { "r-${it.id}" }) { cue ->
                    val here = cue.category in pack.here
                    PackResult(cue, here, cue.id in model.inCueIds, cue.id == model.auditioning, act)
                }
            }
            PackUi.Absent -> Unit
        }
        if (mineOn) {
            items(mine, key = { "m-${it.id}" }) { s -> MineRow(s, s.id in model.inCueIds, s.id == model.auditioning, act) }
            item(key = "mine-empty") {
                if (mine.isEmpty() && !hasQuery) Text("No sounds of your own yet.", Modifier.padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp), style = MaterialTheme.typography.bodyMedium)
            }
            item(key = "mine-verbs") {
                Column(Modifier.padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp), verticalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
                    if (model.recordingOwn) {
                        Button(onClick = act.onRecordOwn, colors = recordButtonColors()) {
                            Icon(Icons.Filled.Stop, contentDescription = null)
                            Text("Stop · ${SoundCore.clock(model.ownSeconds * 1000.0)}", Modifier.padding(start = Spacing.S2.dp))
                        }
                    } else {
                        OutlinedButton(onClick = act.onRecordOwn, colors = wayColors()) {
                            Icon(Icons.Filled.Mic, contentDescription = null)
                            Text("Record a sound", Modifier.padding(start = Spacing.S2.dp))
                        }
                    }
                    OutlinedButton(onClick = act.onBring, colors = wayColors(), enabled = !model.recordingOwn) {
                        Icon(Icons.Outlined.FolderOpen, contentDescription = null)
                        Text("Bring a file", Modifier.padding(start = Spacing.S2.dp))
                    }
                    model.ownError?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = AppSemantics.colors.error) }
                }
            }
        } else if (hasQuery && results.isEmpty() && mine.isEmpty() && pack !is PackUi.Loading) {
            item(key = "none") {
                Column(Modifier.padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp), verticalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
                    Text("No sound called “${model.query.trim()}”.", style = MaterialTheme.typography.bodyMedium)
                    OutlinedButton(onClick = act.onRecordIt, colors = wayColors()) { Text("Record it") }
                }
            }
        } else if (hasQuery) {
            items(mine, key = { "q-${it.id}" }) { s -> MineRow(s, s.id in model.inCueIds, s.id == model.auditioning, act) }
        }
    }
}

@Composable
private fun BoardHeader(text: String) {
    Text(
        text, Modifier.fillMaxWidth().padding(horizontal = Spacing.S4.dp).padding(top = Spacing.S4.dp, bottom = Spacing.S1.dp).semantics { heading() },
        style = MaterialTheme.typography.titleMedium,
    )
}

@Composable
private fun PlayDot(playing: Boolean, label: String, enabled: Boolean, onClick: () -> Unit) {
    IconButton(onClick = onClick, enabled = enabled, modifier = Modifier.semantics { contentDescription = if (playing) "Stop" else "Play $label" }) {
        Icon(if (playing) Icons.Filled.Stop else Icons.Filled.PlayArrow, contentDescription = null, tint = if (enabled) OnAir.colors.play else MaterialTheme.colorScheme.outline)
    }
}

@Composable
private fun InCue(row: InCueRow, playing: Boolean, act: BoardActions) {
    Row(Modifier.fillMaxWidth().padding(horizontal = Spacing.S2.dp), verticalAlignment = Alignment.CenterVertically) {
        PlayDot(playing, row.title, !row.missing) { act.onAudition("s:${row.id}") }
        Column(
            Modifier.weight(1f).clickable(role = Role.Button) { act.onSelect(row.id) }.padding(vertical = Spacing.S2.dp),
        ) {
            Text(row.title, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis, color = if (row.selected) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant)
            Text(row.meta, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2)
        }
        TextButton(onClick = { act.onRemove(row.id) }) { Text("Remove") }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Controls(x: SoundCue, model: BoardModel, act: BoardActions) {
    var more by remember(x.id) { mutableStateOf(false) }
    Column(Modifier.fillMaxWidth().padding(horizontal = Spacing.S4.dp), verticalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
            SoundCore.PLACEMENTS.forEachIndexed { i, at ->
                SegmentedButton(
                    selected = x.at == at, onClick = { act.onPatch(SoundCore.Patch(at = at)) },
                    shape = SegmentedButtonDefaults.itemShape(i, SoundCore.PLACEMENTS.size),
                ) { Text(SoundCore.PLACEMENT_LABEL.getValue(at), maxLines = 1) }
            }
        }
        if (x.at == "bed") {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Until", Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
                OutlinedButton(onClick = act.onPickUntil, colors = wayColors()) { Text(if (model.picking) "Tap a line" else model.untilLabel ?: "Pick a line") }
            }
        } else {
            Stepper("Start", secondsWords(x.startMs).let { if (x.startMs > 0) "+$it" else if (x.startMs < 0) "−${it.removePrefix("-")}" else it },
                canLess = x.startMs > -2000.0, onLess = { act.onPatch(SoundCore.Patch(startMs = x.startMs - SoundCore.START_STEP_MS)) },
                onMore = { act.onPatch(SoundCore.Patch(startMs = x.startMs + SoundCore.START_STEP_MS)) })
        }
        TextButton(onClick = { more = !more }) {
            Text("Level and fades")
            Icon(if (more) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore, contentDescription = null)
        }
        if (more) {
            Stepper("Level", dbWords(x.gainDb), canLess = x.gainDb > -12, onLess = { act.onPatch(SoundCore.Patch(gainDb = x.gainDb - 1)) }, onMore = { act.onPatch(SoundCore.Patch(gainDb = x.gainDb + 1)) })
            Fade("Fade in", x.fadeInMs) { act.onPatch(SoundCore.Patch(fadeInMs = it.toDouble())) }
            Fade("Fade out", x.fadeOutMs) { act.onPatch(SoundCore.Patch(fadeOutMs = it.toDouble())) }
            if (x.at == "under") {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
                    FilterChip(selected = !x.loop, onClick = { act.onPatch(SoundCore.Patch(loop = false)) }, label = { Text("Whole") })
                    FilterChip(selected = x.loop, onClick = { act.onPatch(SoundCore.Patch(loop = true)) }, label = { Text("Loop to the end of the line") })
                }
            }
            Text("Under voices", style = MaterialTheme.typography.bodyMedium)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
                FilterChip(selected = x.duckDb == null, onClick = { act.onPatch(SoundCore.Patch(duck = SoundCore.Duck.Lane)) }, label = { Text("Lane ${dbWords(model.laneDuckDb)}") })
                FilterChip(selected = x.duckDb == 0.0, onClick = { act.onPatch(SoundCore.Patch(duck = SoundCore.Duck.Depth(0.0))) }, label = { Text("Off") })
                listOf(-6.0, -12.0, -18.0).forEach { d ->
                    FilterChip(selected = x.duckDb == d, onClick = { act.onPatch(SoundCore.Patch(duck = SoundCore.Duck.Depth(d))) }, label = { Text(dbWords(d)) })
                }
            }
        }
    }
}

@Composable
private fun Stepper(label: String, value: String, canLess: Boolean = true, onLess: () -> Unit, onMore: () -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(label, Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
        IconButton(onClick = onLess, enabled = canLess, modifier = Modifier.semantics { contentDescription = "$label less" }) { Icon(Icons.Filled.Remove, contentDescription = null) }
        Text(value, Modifier.size(width = 64.dp, height = 24.dp), textAlign = TextAlign.Center, style = MaterialTheme.typography.bodyMedium)
        IconButton(onClick = onMore, modifier = Modifier.semantics { contentDescription = "$label more" }) { Icon(Icons.Filled.Add, contentDescription = null) }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Fade(label: String, ms: Double, pick: (Int) -> Unit) {
    Column {
        Text(label, style = MaterialTheme.typography.bodyMedium)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
            val options = (SoundCore.FADES_MS + SoundCore.BED_FADE_IN_MS).distinct().sorted().filter { it <= 2000 }
            options.forEach { f ->
                FilterChip(selected = ms == f.toDouble(), onClick = { pick(f) }, label = { Text(secondsWords(f.toDouble())) })
            }
        }
    }
}

@Composable
private fun CategoryHead(cat: SoundCore.Category, pack: PackUi.Ready, act: BoardActions) {
    Row(Modifier.fillMaxWidth().padding(horizontal = Spacing.S4.dp), verticalAlignment = Alignment.CenterVertically) {
        val size = SoundCore.megabytes(cat.bytes)
        Text(
            if (pack.offline) "${cat.title} · $size · Offline" else "${cat.title} · $size",
            Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium,
        )
        when {
            pack.downloading == cat.id -> CircularProgressIndicator(Modifier.size(24.dp).semantics { contentDescription = "Downloading" }, strokeWidth = 2.dp)
            pack.failed == cat.id -> TextButton(onClick = { act.onDownload(cat.id) }) { Text("Try again") }
            else -> TextButton(onClick = { act.onDownload(cat.id) }, enabled = !pack.offline) { Text("Download") }
        }
    }
    if (pack.failed == cat.id) Text("This did not download.", Modifier.padding(horizontal = Spacing.S4.dp), style = MaterialTheme.typography.bodySmall, color = AppSemantics.colors.error)
}

@Composable
private fun PackResult(cue: SoundCore.PackCue, here: Boolean, inCue: Boolean, playing: Boolean, act: BoardActions) {
    Row(Modifier.fillMaxWidth().heightIn(min = 72.dp).padding(horizontal = Spacing.S2.dp), verticalAlignment = Alignment.CenterVertically) {
        PlayDot(playing, cue.title, here) { act.onAudition("p:${cue.id}") }
        Column(Modifier.weight(1f)) {
            Text(cue.title, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis, color = if (here) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant)
            Text(SoundCore.cueLine(cue), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        AddButton(inCue, here) { act.onAddPack(cue) }
    }
}

@Composable
private fun MineRow(s: OwnSounds.Sound, inCue: Boolean, playing: Boolean, act: BoardActions) {
    Row(Modifier.fillMaxWidth().heightIn(min = 72.dp).padding(horizontal = Spacing.S2.dp), verticalAlignment = Alignment.CenterVertically) {
        PlayDot(playing, s.name, true) { act.onAudition("o:${s.id}") }
        Column(Modifier.weight(1f)) {
            Text(s.name, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text("${SoundCore.clock(s.seconds * 1000)} · ${if (s.from == "file") "Your file" else "Recorded here"}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        TextButton(onClick = { act.onRemoveOwn(s.id) }) { Text("Delete") }
        AddButton(inCue, true) { act.onAddOwn(s) }
    }
}

@Composable
private fun AddButton(inCue: Boolean, enabled: Boolean, onClick: () -> Unit) {
    if (inCue) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(horizontal = Spacing.S2.dp)) {
            Icon(Icons.Filled.Check, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(18.dp))
            Text("In cue", Modifier.padding(start = Spacing.S1.dp), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    } else {
        OutlinedButton(onClick = onClick, enabled = enabled, colors = wayColors(), border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline)) { Text("Add") }
    }
}

@Composable
private fun Skeleton() {
    Row(Modifier.fillMaxWidth().heightIn(min = 72.dp).padding(horizontal = Spacing.S4.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.S3.dp)) {
        Surface(Modifier.size(40.dp), shape = androidx.compose.foundation.shape.CircleShape, color = MaterialTheme.colorScheme.surfaceContainerHigh) {}
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.S1.dp)) {
            Surface(Modifier.size(width = 160.dp, height = 14.dp), color = MaterialTheme.colorScheme.surfaceContainerHigh, shape = androidx.compose.foundation.shape.RoundedCornerShape(4.dp)) {}
            Surface(Modifier.size(width = 110.dp, height = 10.dp), color = MaterialTheme.colorScheme.surfaceContainerHigh, shape = androidx.compose.foundation.shape.RoundedCornerShape(4.dp)) {}
        }
    }
}
