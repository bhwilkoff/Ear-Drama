package com.example.appname.ui.screens

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.core.content.edit
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import com.example.appname.BuildConfig
import com.example.appname.navigation.StudioDoor
import com.example.appname.plays.Consent
import com.example.appname.plays.DeviceLiveAudio
import com.example.appname.plays.MixPlayback
import com.example.appname.plays.PartID
import com.example.appname.plays.PlayScript
import com.example.appname.plays.ReadClassDetail
import com.example.appname.plays.ReadClassWire
import com.example.appname.plays.ReadCore
import com.example.appname.plays.ReadFailure
import com.example.appname.plays.ReadRecord
import com.example.appname.plays.ReadSession
import com.example.appname.plays.ReadSnapshot
import com.example.appname.plays.ReadState
import com.example.appname.plays.Relay
import com.example.appname.plays.RoomPublish
import com.example.appname.ui.LocalAppContainer
import com.example.appname.ui.rememberCast
import com.example.appname.ui.rememberDeviceVoices
import com.example.appname.ui.theme.OnAir
import com.example.appname.ui.theme.Spacing
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject

// The room inside the reader (PLAYS-DESIGN §12 and §12.10, ANDROID-DESIGN §4.19): the reader follows the room's cursor, tints
// the lines this device holds, and carries the room bar, the Record row and the Takes sheet in its own chrome. Rules are
// ReadCore's, the transport ReadSession's, the take machinery ReadRecord's; these only draw them. No sound from a reader.

/** What the reader needs to be a room's reader: the session, the take machinery, the class calls, and the doors out. */
class RoomSeam(
    val session: ReadSession,
    val record: ReadRecord,
    val classes: ReadClassWire,
    val scope: CoroutineScope,
    val onOpenScreen: (String) -> Unit,
    val onLeave: () -> Unit,
) {
    private val _publish = MutableStateFlow("")

    /** The publish line under Takes: "Queued for archive.org", "On archive.org", or a refusal. */
    val publish: StateFlow<String> = _publish

    fun setPublish(text: String) { _publish.value = text }
}

private fun msg(vararg pairs: Pair<String, Any>): JsonObject = buildJsonObject {
    pairs.forEach { (k, v) -> put(k, if (v is Number) JsonPrimitive(v) else if (v is Boolean) JsonPrimitive(v) else JsonPrimitive(v.toString())) }
}

private fun count(n: Int, noun: String) = if (n == 1) "1 $noun" else "$n ${noun}s"

/** The line a room shows above its buttons: the one fact (who is reading, when mine is next, who is awaited). */
internal fun roomFact(snap: ReadSnapshot, ended: String?): String {
    ended?.let { return ReadCore.refusal(it) }
    val leads = snap.you?.leads == true
    if (snap.waitingForLeader && !leads) {
        ReadCore.waitingFor(snap)?.let { return "Waiting for $it" }
        return if (snap.kind == "class") "Waiting for the teacher" else "Waiting for the leader"
    }
    val reads = snap.readsNow
    val next = ReadCore.nextLine(snap.nextMine?.let { ReadCore.Next(it.line, it.inLines) })
    val mineNow = snap.nextMine?.inLines == 0
    val cast = ReadCore.Reads(reads?.part.orEmpty(), reads?.seat, reads?.holder, reads?.members.orEmpty())
    val named = if (snap.mode == "record" && !mineNow && reads != null) ReadCore.readerName(snap, cast) else null
    if (named != null) return listOfNotNull("$named is reading", next).joinToString(" · ")
    if (next != null) return next
    if (reads == null) return ""
    val seat = if (snap.kind == "class") reads.seat?.let { id -> snap.seats.firstOrNull { it.id == id }?.label } else null
    val open = if (snap.kind == "class") reads.seat == null else reads.holder == null
    return listOfNotNull(PartID(reads.part).title, seat, if (open) "Open" else null).joinToString(" · ")
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun RoomBar(
    seam: RoomSeam,
    state: ReadState?,
    snap: ReadSnapshot,
    script: PlayScript,
    cast: List<Pair<String, String>>,
    hide: Boolean,
    onHide: (Boolean) -> Unit,
    away: Boolean,
    onBackToLine: () -> Unit,
    hasMine: Boolean,
) {
    val scope = rememberCoroutineScope()
    val rec by seam.record.state.collectAsState()
    val context = LocalContext.current
    val container = LocalAppContainer.current
    val leads = snap.you?.leads == true
    val receives = snap.you?.receives == true
    val isReader = snap.you?.role == "reader"
    val ended = state?.ended
    var menu by remember { mutableStateOf(false) }
    var parts by remember { mutableStateOf(false) }
    var ending by remember { mutableStateOf(false) }
    var adding by remember { mutableStateOf(false) }
    var takes by remember { mutableStateOf(false) }
    var people by remember { mutableStateOf(false) }
    var refused by remember { mutableStateOf<String?>(null) }

    fun send(m: JsonObject) {
        scope.launch {
            try { seam.session.send(m); refused = null } catch (e: CancellationException) { throw e } catch (e: ReadFailure) { if (e.code != "stale") refused = ReadCore.refusal(e.code) } catch (_: Exception) { }
        }
    }
    fun move(delta: Int) { ReadCore.step(cast, snap.cursor, delta)?.let { send(msg("type" to "cursor", "line" to it, "base" to snap.cursorGen)) } }
    fun again() {
        val starts = com.example.appname.plays.ScriptReading.sectionsOf(script)
            .filter { it.level != com.example.appname.plays.ScriptReading.Level.Part }.map { it.index }
        ReadCore.sceneStart(cast, snap.cursor, starts)?.takeIf { it != snap.cursor }?.let { send(msg("type" to "cursor", "line" to it, "base" to snap.cursorGen)) }
    }

    val arm = {
        if (container.playback.state.value.isPlaying) container.playback.togglePlay()
        scope.launch { seam.record.arm() }
        Unit
    }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted -> if (granted) arm() }
    val stubbed = BuildConfig.DEBUG && StudioDoor.stub
    fun startRecording() {
        if (stubbed || ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) arm()
        else permission.launch(Manifest.permission.RECORD_AUDIO)
    }

    if (BuildConfig.DEBUG) {
        // DEBUG doors (T7b): claim a part once, then arm Record, without a person's taps; consumed so a recomposition never repeats them.
        LaunchedEffect(Unit) {
            val part = com.example.appname.navigation.ReadRoomDoor.part
            if (part != null) {
                com.example.appname.navigation.ReadRoomDoor.part = null
                send(msg("type" to "claim", "part" to if (part.startsWith("role:")) part else com.example.appname.plays.PartID.role(part).raw))
                delay(1000)
            }
            if (com.example.appname.navigation.ReadRoomDoor.record) {
                com.example.appname.navigation.ReadRoomDoor.record = false
                startRecording()
            }
        }
    }
    Column(Modifier.fillMaxWidth().padding(horizontal = Spacing.S4.dp, vertical = Spacing.S1.dp), verticalArrangement = Arrangement.spacedBy(Spacing.S1.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                roomFact(snap, ended), Modifier.weight(1f).semantics { liveRegion = LiveRegionMode.Polite },
                style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2, overflow = TextOverflow.Ellipsis,
            )
            val removable = remember(snap) { ReadCore.removable(snap) }
            if (removable.isEmpty() || ended != null) {
                Text("${snap.present} here", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            } else {
                TextButton(onClick = { people = true }) { Text("${snap.present} here") }
            }
        }
        if (ended != null) {
            TextButton(onClick = seam.onLeave) { Text("Close") }
            return@Column
        }
        val warn = when {
            refused != null -> refused
            state?.offline == true -> ReadCore.refusal("offline")
            state?.slow == true -> "Slow connection"
            state?.refusal != null && state.refusal != "stale" -> ReadCore.refusal(state.refusal)
            else -> null
        }
        warn?.let { Text(it, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.error) }
        if (away) {
            TextButton(onClick = onBackToLine, Modifier.align(Alignment.CenterHorizontally)) { Text("Back to the line") }
        }
        if (snap.mode == "record" && isReader) {
            val holdsAny = cast.indices.any { ReadCore.holds(snap.room, cast, snap.meMember, it) }
            val records = (holdsAny && !receives) || (receives && rec.oneMic)
            Row(horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp), verticalAlignment = Alignment.CenterVertically) {
                when {
                    rec.recording != null -> {
                        Box(Modifier.size(10.dp).background(OnAir.colors.record, CircleShape))
                        Text("Recording", style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })
                        OutlinedButton(onClick = { seam.record.stop() }) { Text("Stop") }
                    }
                    records && !rec.armed -> {
                        Button(onClick = { startRecording() }) { Text("Start recording") }
                        rec.failed?.let { Text("Recording did not start.", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.error) }
                    }
                    else -> {
                        val reads = snap.readsNow
                        val held = reads != null && (if (snap.kind == "class") reads.seat != null else reads.holder != null)
                        val mineNow = snap.nextMine?.inLines == 0
                        if (held && !mineNow && snap.cursor !in snap.done) Text("Quiet while others record", style = MaterialTheme.typography.labelMedium)
                    }
                }
                if (rec.outbox.isNotEmpty()) Text("${count(rec.outbox.size, "take")} on this device", style = MaterialTheme.typography.labelMedium)
                if (receives) TextButton(onClick = { takes = true }) { Text("Takes") }
            }
        }
        FlowRow(horizontalArrangement = Arrangement.spacedBy(Spacing.S1.dp), verticalArrangement = Arrangement.spacedBy(Spacing.S1.dp)) {
            if (snap.mode == "rehearse" && hasMine) {
                TextButton(onClick = { onHide(!hide) }) {
                    Icon(if (hide) Icons.Filled.VisibilityOff else Icons.Filled.Visibility, contentDescription = null)
                    Text(if (hide) "Show my lines" else "Hide my lines", Modifier.padding(start = Spacing.S1.dp))
                }
            }
            if (snap.kind == "adult" && isReader) TextButton(onClick = { parts = true }) { Text("Parts") }
            if (leads) {
                OutlinedButton(onClick = { move(-1) }, enabled = ReadCore.step(cast, snap.cursor, -1) != null) { Text("Back") }
                if (snap.mode == "rehearse") OutlinedButton(onClick = { again() }) { Text("Again") }
                Button(onClick = { move(1) }, enabled = ReadCore.step(cast, snap.cursor, 1) != null) { Text("Next") }
                Box {
                    TextButton(onClick = { menu = true }) { Text("Reading") }
                    DropdownMenu(menu, { menu = false }) {
                        listOf("read" to "Table read", "rehearse" to "Rehearse", "record" to "Record").forEach { (mode, label) ->
                            DropdownMenuItem(
                                text = { Text(label) },
                                leadingIcon = if (snap.mode == mode) ({ Icon(Icons.Filled.Check, contentDescription = null) }) else null,
                                onClick = { menu = false; if (snap.mode != mode) send(msg("type" to "mode", "mode" to mode)) },
                            )
                        }
                        if (snap.mode == "record") {
                            DropdownMenuItem(
                                text = { Text("Record every line here") },
                                leadingIcon = if (rec.oneMic) ({ Icon(Icons.Filled.Check, contentDescription = null) }) else null,
                                onClick = { menu = false; seam.record.setOneMic(!rec.oneMic) },
                            )
                        }
                        DropdownMenuItem(
                            text = { Text(if (snap.locked) "Unlock joining" else "Lock joining") },
                            onClick = { menu = false; send(msg("type" to "lock", "locked" to !snap.locked)) },
                        )
                        DropdownMenuItem(
                            text = { Text(if (snap.readOpen) "Stop reading open parts" else "Read open parts") },
                            onClick = { menu = false; send(msg("type" to "read-open", "open" to !snap.readOpen)) },
                        )
                        DropdownMenuItem(text = { Text("Open the screen") }, onClick = { menu = false; seam.onOpenScreen(snap.code) })
                        DropdownMenuItem(text = { Text("Add a screen") }, onClick = { menu = false; adding = true })
                        DropdownMenuItem(text = { Text("End the reading") }, onClick = { menu = false; ending = true })
                    }
                }
            }
        }
    }
    if (ending) {
        AlertDialog(
            onDismissRequest = { ending = false },
            title = { Text("End the reading for everyone?") },
            confirmButton = { TextButton(onClick = { ending = false; send(msg("type" to "end")) }) { Text("End the reading") } },
            dismissButton = { TextButton(onClick = { ending = false }) { Text("Cancel") } },
        )
    }
    if (adding) AddScreenDialog(seam, onDismiss = { adding = false })
    if (people && ended == null) {
        PeopleDialog(ReadCore.removable(snap), refused, onRemove = { send(msg("type" to "remove", "member" to it)) }, onDismiss = { people = false })
    }
    if (parts) PartsDialog(snap, script, onSend = ::send, onDismiss = { parts = false })
    if (takes) TakesSheet(seam, snap, script, cast, onDismiss = { takes = false }, onSend = ::send)
}

/** Who is here, for whoever may remove a member (ANDROID-DESIGN §4.19a): each with Remove, whose confirmation says that joining locks. */
@Composable
internal fun PeopleDialog(members: List<ReadCore.Removable>, refused: String?, onRemove: (String) -> Unit, onDismiss: () -> Unit) {
    var removing by remember { mutableStateOf<ReadCore.Removable?>(null) }
    LaunchedEffect(members.isEmpty()) { if (members.isEmpty()) onDismiss() }
    val target = removing
    if (target != null) {
        AlertDialog(
            onDismissRequest = { removing = null },
            title = { Text("Remove ${target.label} and lock joining?") },
            confirmButton = {
                TextButton(onClick = { removing = null; onRemove(target.id) }) { Text("Remove", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { removing = null }) { Text("Cancel") } },
        )
        return
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Here") },
        text = {
            Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState())) {
                members.forEach { m ->
                    ListItem(
                        headlineContent = { Text(m.label) },
                        supportingContent = if (m.live) null else ({ Text("Away") }),
                        trailingContent = {
                            TextButton(onClick = { removing = m }, modifier = Modifier.semantics { contentDescription = "Remove ${m.label}" }) { Text("Remove") }
                        },
                    )
                }
                refused?.let { Text(it, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.error) }
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("Done") } },
    )
}

@Composable
private fun PartsDialog(snap: ReadSnapshot, script: PlayScript, onSend: (JsonObject) -> Unit, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Parts") },
        text = {
            Column(Modifier.fillMaxWidth()) {
                script.roles.forEach { role ->
                    val id = PartID.role(role.name).raw
                    val holder = snap.claims[id]
                    ListItem(
                        headlineContent = { Text(role.name) },
                        trailingContent = {
                            when {
                                holder != null && holder == snap.you?.id -> TextButton(onClick = { onSend(msg("type" to "release", "part" to id)) }) { Text("Release") }
                                holder == null -> TextButton(onClick = { onSend(msg("type" to "claim", "part" to id)) }) { Text("Take") }
                                else -> Text(snap.members.firstOrNull { it.id == holder }?.name ?: "Taken", style = MaterialTheme.typography.labelMedium)
                            }
                        },
                    )
                }
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("Done") } },
    )
}

/** The leader's Add a screen (PLAYS-DESIGN §12.10 item 9): the code a TV shows, typed here. */
@Composable
private fun AddScreenDialog(seam: RoomSeam, onDismiss: () -> Unit) {
    val scope = rememberCoroutineScope()
    var code by remember { mutableStateOf("") }
    var line by remember { mutableStateOf<String?>(null) }
    var added by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Add a screen") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
                OutlinedTextField(
                    code, { code = it.uppercase().take(9); added = false }, label = { Text("Code on the TV") }, singleLine = true,
                    keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
                        capitalization = androidx.compose.ui.text.input.KeyboardCapitalization.Characters,
                        keyboardType = androidx.compose.ui.text.input.KeyboardType.Ascii,
                    ),
                )
                if (added) Text("Screen added.", style = MaterialTheme.typography.labelMedium)
                line?.let { Text(it, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.error) }
            }
        },
        confirmButton = {
            TextButton(
                enabled = code.isNotBlank() && !busy,
                onClick = {
                    busy = true
                    line = null
                    scope.launch {
                        try { seam.session.attach(code); code = ""; added = true } catch (e: CancellationException) { throw e } catch (e: ReadFailure) {
                            line = ReadCore.refusal(e.code)
                        } catch (_: Exception) { line = ReadCore.refusal("error") }
                        busy = false
                    }
                },
            ) { Text("Add a screen") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Done") } },
    )
}

/**
 * The receiver's Takes (PLAYS-DESIGN §12.10 items 4-5): counts per reader, each speaking line's state with Play and Again (and
 * Approve and Again, which offers an optional note, in a class production), then Listen through, Export, and in a class of 13 and over Publish under
 * my name. Counts, never a ranking.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
internal fun TakesSheet(seam: RoomSeam, snap: ReadSnapshot, script: PlayScript, cast: List<Pair<String, String>>, onDismiss: () -> Unit, onSend: (JsonObject) -> Unit) {
    val store = LocalAppContainer.current.plays.store
    val productions by store.productions.collectAsState()
    val rec by seam.record.state.collectAsState()
    val local = productions.firstOrNull { it.id == rec.localId }
    val castHandle = local?.let { rememberCast(rememberDeviceVoices(), script, it.id) }
    ModalBottomSheet(onDismissRequest = onDismiss) { TakesContent(seam, snap, script, cast, local, castHandle, store, onSend) }
}

/** The Takes sheet's body, apart from its window so a render can draw it. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun TakesContent(
    seam: RoomSeam, snap: ReadSnapshot, script: PlayScript, cast: List<Pair<String, String>>, local: com.example.appname.plays.Production?,
    castHandle: com.example.appname.ui.CastHandle?, store: com.example.appname.plays.ProductionStore, onSend: (JsonObject) -> Unit,
) {
    val muted = com.example.appname.navigation.LocalPlayerMuted.current
    val scope = rememberCoroutineScope()
    val player = remember { MixPlayback() }
    var line by remember { mutableStateOf<String?>(null) }
    var klass by remember { mutableStateOf<ReadClassDetail?>(null) }
    val byId = remember(script) { script.lines.associateBy { it.id } }
    val (rows, counts) = ReadCore.takeRows(snap, cast, local?.chosen?.keys.orEmpty(), speaking = { PartID(it).isSpeaking })
    fun label(c: ReadCore.TakeCount): String =
        (c.seat?.let { id -> snap.seats.firstOrNull { it.id == id }?.label } ?: snap.members.firstOrNull { it.id == c.holder }?.name) ?: "A reader"
    fun who(r: ReadCore.TakeRow): String? =
        r.seat?.let { id -> snap.seats.firstOrNull { it.id == id }?.label } ?: snap.members.firstOrNull { it.id == r.holder }?.name

    LaunchedEffect(snap.classId) {
        val id = snap.classId
        if (snap.kind == "class" && id != null) klass = try { seam.classes.detail(id) } catch (e: CancellationException) { throw e } catch (_: Exception) { null }
    }
    androidx.compose.runtime.DisposableEffect(Unit) { onDispose { player.stop() } }

    Column(Modifier.fillMaxWidth()) {
        Text("Takes", Modifier.padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp).semantics { heading() }, style = MaterialTheme.typography.headlineSmall)
        if (counts.isNotEmpty()) {
            Text(
                counts.joinToString(" · ") { "${label(it)} ${it.recorded} of ${it.lines}" },
                Modifier.padding(horizontal = Spacing.S4.dp), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        line?.let { Text(it, Modifier.padding(horizontal = Spacing.S4.dp), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.error) }
        LazyColumn(Modifier.weight(1f, fill = false)) {
            items(rows, key = { it.line }) { r ->
                val words = byId[r.line]?.spokenText.orEmpty().take(80)
                val take = local?.chosenTake(r.line)
                val state = when (r.state) {
                    ReadCore.TakeState.Away -> "On ${who(r) ?: "a reader"}'s device"
                    ReadCore.TakeState.Recorded -> "Recorded"
                    ReadCore.TakeState.Waiting -> "Waiting"
                    ReadCore.TakeState.Open -> "Open"
                }
                var noting by remember(r.line) { mutableStateOf(false) }
                var note by remember(r.line) { mutableStateOf("") }
                Column(Modifier.fillMaxWidth().padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(PartID(r.part).title, style = MaterialTheme.typography.titleMedium)
                            Text(words, style = MaterialTheme.typography.bodyMedium, maxLines = 2, overflow = TextOverflow.Ellipsis)
                        }
                        Text(state, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(Spacing.S1.dp)) {
                        if (take != null) {
                            TextButton(onClick = {
                                player.stop()
                                player.muted = muted
                                scope.launch { runCatching { player.load(store.takeFile(local, take)); player.toggle() } }
                            }) { Text("Play") }
                        }
                        val pid = snap.productionId
                        if (take != null && pid != null && snap.kind == "class") {
                            TextButton(onClick = {
                                scope.launch {
                                    try { seam.classes.review(pid, take.id, "approved", null); line = null } catch (e: CancellationException) { throw e } catch (e: ReadFailure) { line = ReadCore.refusal(e.code) } catch (_: Exception) { line = ReadCore.refusal("error") }
                                }
                            }) { Text("Approve") }
                            TextButton(onClick = { noting = !noting }) { Text("Again") }
                        } else if (r.state != ReadCore.TakeState.Open) {
                            TextButton(onClick = { onSend(msg("type" to "again", "line" to r.line, "base" to snap.cursorGen)) }) { Text("Again") }
                        }
                    }
                    if (noting) {
                        val pid = snap.productionId
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
                            OutlinedTextField(note, { note = it.take(500) }, label = { Text("Note (optional)") }, modifier = Modifier.weight(1f), singleLine = true)
                            Button(enabled = take != null && pid != null, onClick = {
                                scope.launch {
                                    try {
                                        if (note.isNotBlank()) seam.classes.review(pid!!, take!!.id, "again", note.trim())
                                        onSend(msg("type" to "again", "line" to r.line, "base" to snap.cursorGen))
                                        noting = false
                                        line = null
                                    } catch (e: CancellationException) { throw e } catch (e: ReadFailure) { line = ReadCore.refusal(e.code) } catch (_: Exception) { line = ReadCore.refusal("error") }
                                }
                            }) { Text("Send") }
                        }
                    }
                    HorizontalDivider(Modifier.padding(top = Spacing.S2.dp))
                }
            }
            item(key = "foot") {
                if (local != null) {
                    Column(Modifier.padding(vertical = Spacing.S2.dp), verticalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
                        ListenThrough(local, script, null, castHandle, null)
                        if (snap.kind == "class" && snap.productionId != null) {
                            val k = klass
                            val complete = Relay.isComplete(local, script)
                            when {
                                k != null && k.under13 -> Text("An under-13 class never publishes.", Modifier.padding(horizontal = Spacing.S4.dp), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.error)
                                k != null && complete -> PublishForm(seam, snap.productionId, local, script)
                            }
                        }
                    }
                }
            }
        }
    }
}

/** The two confirmations a class publish adds before the teacher's own consent (§12.12 item 6). */
@Composable
internal fun PublishConfirmations(performers: Boolean, onPerformers: (Boolean) -> Unit, released: Boolean, onReleased: (Boolean) -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Checkbox(performers, onPerformers)
        Text("Every performer agreed to publish.")
    }
    Row(verticalAlignment = Alignment.CenterVertically) {
        Checkbox(released, onReleased)
        Text("The school has a media release for each performer under 18.")
    }
}

/** Publish under my name (§12.10 item 5): the credit name, the CC0 consent, then each line's file from this device. */
@Composable
private fun PublishForm(seam: RoomSeam, pid: String, local: com.example.appname.plays.Production, script: PlayScript) {
    val context = LocalContext.current
    val prefs = remember { context.getSharedPreferences("ed.read", android.content.Context.MODE_PRIVATE) }
    var credit by remember { mutableStateOf(prefs.getString("credit", "").orEmpty()) }
    var consent by remember { mutableStateOf<Consent?>(null) }
    var agreed by remember { mutableStateOf(false) }
    var performers by remember { mutableStateOf(false) }
    var released by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    val published by seam.publish.collectAsState()
    var refusal by remember { mutableStateOf<String?>(null) }
    val store = LocalAppContainer.current.plays.store
    LaunchedEffect(Unit) { consent = try { seam.classes.consent() } catch (e: CancellationException) { throw e } catch (_: Exception) { null } }
    Column(Modifier.padding(horizontal = Spacing.S4.dp), verticalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
        OutlinedTextField(credit, { credit = it.take(ReadCore.NAME_MAX) }, label = { Text("Credit name") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        val c = consent
        Text(
            if (c == null) "" else if (c.publishes) c.text else "Publishing opens when the Ear Drama archive account is connected.",
            style = MaterialTheme.typography.labelMedium,
        )
        PublishConfirmations(performers, { performers = it }, released, { released = it })
        Row(verticalAlignment = Alignment.CenterVertically) {
            Checkbox(agreed, { agreed = it })
            Text("I agree")
        }
        if (published.isNotEmpty()) Text(published, style = MaterialTheme.typography.labelMedium)
        refusal?.let { Text(it, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.error) }
        Button(
            enabled = c != null && c.publishes && agreed && credit.isNotBlank() && !busy,
            onClick = {
                if (!performers || !released) {
                    refusal = ReadCore.refusal("confirmations_required")
                    return@Button
                }
                busy = true
                refusal = null
                seam.scope.launch {
                    try {
                        seam.classes.agree(pid, c!!.version)
                        seam.classes.publish(pid, credit.trim())
                        prefs.edit { putString("credit", credit.trim()) }
                        seam.setPublish("Queued for archive.org")
                        val stopped = RoomPublish.sendFiles(seam.classes, store, store.production(local.id) ?: local, script, pid = pid)
                        seam.setPublish(if (stopped == null) "On archive.org" else ReadCore.refusal(stopped))
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: ReadFailure) {
                        refusal = ReadCore.refusal(e.code)
                    } catch (_: Exception) {
                        refusal = ReadCore.refusal("error")
                    }
                    busy = false
                }
            },
        ) { Text("Publish under my name") }
    }
}
