package com.example.appname.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.example.appname.BuildConfig
import com.example.appname.navigation.LaunchDoors
import com.example.appname.plays.PlayScript
import com.example.appname.plays.ReadClass
import com.example.appname.plays.ReadClassDetail
import com.example.appname.plays.ReadCore
import com.example.appname.plays.ReadFailure
import com.example.appname.plays.ReadProductionInfo
import com.example.appname.plays.ReadProgress
import com.example.appname.plays.ReadSeatKeys
import com.example.appname.plays.ReadSeatList
import com.example.appname.plays.ReadSession
import com.example.appname.plays.ReadSnapshot
import com.example.appname.plays.ReadState
import com.example.appname.plays.ScriptLine
import com.example.appname.plays.ScriptReading
import com.example.appname.ui.LocalAppContainer
import com.example.appname.ui.SectionHeader
import com.example.appname.ui.theme.Spacing
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject

// Reading together on Android (PLAYS-DESIGN §12, ANDROID-DESIGN §4.19): join a room by code, follow the lit line, lead
// with Back/Next/Again, the shared screen (a TV pairs as this and records nothing, rule 12), and the teacher's class
// page with its casting board. Rules are ReadCore's and the transport ReadSession's; these only draw the snapshot.

/** Where the Library's classes and a play's Read together lead (provided once by AppRoot). */
class ReadNav(val openClass: (String) -> Unit = {}, val openRoom: (String) -> Unit = {})

val LocalReadNav = androidx.compose.runtime.staticCompositionLocalOf { ReadNav() }

/** A play page's door: opens an adult room on this play and lands in it (WEB-DESIGN §4.17's twin). */
@Composable
fun ReadTogetherButton(script: PlayScript) {
    val container = LocalAppContainer.current
    val nav = LocalReadNav.current
    val scope = rememberCoroutineScope()
    var failure by remember { mutableStateOf<String?>(null) }
    OutlinedButton(onClick = {
        failure = null
        scope.launch {
            try {
                val session = ReadSession(container.readWire, scope)
                session.open(ReadClass.openingBody(script), teacher = false)
                session.state.value.code?.let { ReadHandover.hold(session); nav.openRoom(it) }
            } catch (e: CancellationException) { throw e } catch (e: Exception) { failure = say(e) }
        }
    }) { Text("Read together") }
    failure?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.labelMedium) }
}

/** The room a leader just opened is already joined as its leader: the screen it lands on takes this session. */
object ReadHandover {
    private var held: ReadSession? = null
    @Synchronized fun hold(s: ReadSession) { held = s }
    @Synchronized fun take(): ReadSession? = held.also { held = null }
}

internal object ReadText {
    /** The code in two groups of three, so it reads aloud ("ABC 123"). */
    fun grouped(code: String) = if (code.length == ReadCore.CODE_LENGTH) code.take(3) + " " + code.drop(3) else code

    /** The status line: a refusal, a warning, or a fact the room cannot show by itself. */
    fun status(s: ReadState): String {
        s.ended?.let { return ReadCore.refusal(it) }
        val snap = s.snapshot ?: return if (s.offline) ReadCore.refusal("offline") else ""
        if (snap.waitingForLeader) {
            ReadCore.waitingFor(snap)?.let { return "Waiting for $it" }
            return if (snap.kind == "class") "Waiting for the teacher" else "Waiting for the leader"
        }
        if (s.offline) return ReadCore.refusal("offline")
        return if (s.slow) "Slow connection" else ""
    }
}

private fun n(count: Int, noun: String) = if (count == 1) "1 $noun" else "$count ${noun}s"

private fun say(e: Exception): String = if (e is ReadFailure) ReadCore.refusal(e.code) else ReadCore.refusal("error")

private fun msg(vararg pairs: Pair<String, Any>): JsonObject = buildJsonObject {
    pairs.forEach { (k, v) ->
        when (v) {
            is Boolean -> put(k, JsonPrimitive(v))
            is Number -> put(k, JsonPrimitive(v))
            else -> put(k, JsonPrimitive(v.toString()))
        }
    }
}

// ---- The room ----

@Composable
fun ReadRoomScreen(code: String, onBack: () -> Unit, onOpenScreen: (String) -> Unit, seatDoor: String? = null) {
    val container = LocalAppContainer.current
    val scope = rememberCoroutineScope()
    val session = remember { ReadHandover.take() ?: ReadSession(container.readWire, scope, diag = BuildConfig.DEBUG && LaunchDoors.diag) }
    val state by session.state.collectAsState()
    var failure by remember { mutableStateOf<String?>(null) }
    var needsSeat by remember { mutableStateOf(false) }
    var attempt by remember { mutableIntStateOf(0) }
    var script by remember { mutableStateOf<PlayScript?>(null) }
    val wire = container.readClass

    suspend fun join(seatKey: String? = null, seatId: String? = null, move: Boolean = false) {
        if (session.state.value.snapshot != null) return
        val normal = ReadCore.normalizeCode(code) ?: run { failure = ReadCore.refusal("bad_code"); return }
        val want = buildJsonObject {
            if (seatId != null && seatKey != null) { put("seat", JsonPrimitive(seatId)); put("seat_key", JsonPrimitive(seatKey)) }
            if (move) put("move", JsonPrimitive(true))
        }
        try {
            session.join(normal, want)
            needsSeat = false
        } catch (e: CancellationException) {
            throw e
        } catch (e: ReadFailure) {
            if (e.code == "seat_required" || e.code == "seat_key_required") needsSeat = true else failure = ReadCore.refusal(e.code)
        } catch (e: Exception) {
            failure = say(e)
        }
    }

    LaunchedEffect(attempt) { if (!needsSeat) join() }
    LaunchedEffect(state.snapshot?.scriptId) {
        val id = state.snapshot?.scriptId ?: return@LaunchedEffect
        script = container.plays.script(id)
    }
    DisposableEffect(Unit) { onDispose { session.pause() } }

    Scaffold(topBar = { BackBar(onBack, script?.title ?: "Reading") }) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            val snap = state.snapshot
            when {
                state.ended != null -> Text(ReadCore.refusal(state.ended!!), Modifier.padding(Spacing.S4.dp), style = MaterialTheme.typography.bodyMedium)
                snap != null -> ReadRoomContent(snap, state, script, session, onOpenScreen)
                needsSeat -> SeatPicker(wire, seatDoor, onClaimed = { seatKey, seatId, move -> scope.launch { join(seatKey, seatId, move) } })
                failure != null -> Column(Modifier.padding(Spacing.S4.dp), verticalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
                    Text(failure!!, color = MaterialTheme.colorScheme.error)
                    OutlinedButton(onClick = { failure = null; attempt += 1 }) { Text("Try again") }
                }
            }
        }
    }
}

@Composable
private fun SeatPicker(wire: com.example.appname.plays.ReadClassWire, seatDoor: String?, onClaimed: (String, String, Boolean) -> Unit) {
    val scope = rememberCoroutineScope()
    var classCode by remember { mutableStateOf("") }
    var list by remember { mutableStateOf<ReadSeatList?>(null) }
    var failure by remember { mutableStateOf<String?>(null) }

    suspend fun load() {
        failure = null
        try { list = wire.seatList(classCode) } catch (e: CancellationException) { throw e } catch (e: Exception) { failure = say(e) }
    }

    suspend fun claim(s: ReadSeatList.Seat, move: Boolean) {
        failure = null
        try {
            val r = wire.seatClaim(classCode, s.id, move)
            ReadSeatKeys.set(r.seat, r.seatKey)
            onClaimed(r.seatKey, r.seat, move)
        } catch (e: CancellationException) { throw e } catch (e: Exception) { failure = say(e) }
    }

    LaunchedEffect(seatDoor) {
        // DEBUG door appname_start_seat=<class code>:<seat id or label> picks that name without a person at the form.
        if (!BuildConfig.DEBUG || seatDoor == null || ':' !in seatDoor) return@LaunchedEffect
        classCode = seatDoor.substringBefore(':')
        load()
        val want = seatDoor.substringAfter(':')
        list?.seats?.firstOrNull { it.id == want || it.label == want }?.let { claim(it, true) }
    }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(Spacing.S4.dp), verticalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
        OutlinedTextField(classCode, { classCode = it.uppercase() }, label = { Text("Class code") }, singleLine = true)
        Button(onClick = { scope.launch { load() } }, enabled = classCode.isNotBlank()) { Text("Show names") }
        failure?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        list?.let { l ->
            SectionHeader(l.`class`.name)
            l.seats.forEach { s ->
                ListItem(
                    headlineContent = { Text(s.label, style = MaterialTheme.typography.bodyMedium) },
                    trailingContent = { if (s.taken) TextButton(onClick = { scope.launch { claim(s, true) } }) { Text("Move here") } },
                    modifier = Modifier.fillMaxWidth().clickable { scope.launch { claim(s, false) } },
                )
            }
        }
    }
}

@Composable
fun ReadRoomContent(snap: ReadSnapshot, state: ReadState, script: PlayScript?, session: ReadSession?, onOpenScreen: (String) -> Unit) {
    val scope = rememberCoroutineScope()
    val lines = script?.lines.orEmpty()
    val cast = lines.map { it.id to it.part.raw }
    val roomState = snap.room
    val me = snap.meMember
    val mine = remember(snap.generation, lines.size, snap.you) { cast.indices.filter { ReadCore.holds(roomState, cast, me, it) }.toSet() }
    val next = snap.nextMine?.let { ReadCore.Next(it.line, it.inLines) }
    val leads = snap.you?.leads == true
    val isScreen = snap.you?.role == "screen"
    var following by remember { mutableStateOf(true) }
    var hideMine by remember { mutableStateOf(false) }
    var menu by remember { mutableStateOf(false) }
    var parts by remember { mutableStateOf(false) }
    var ending by remember { mutableStateOf(false) }
    val listState = rememberLazyListState()
    val cursorIndex = lines.indexOfFirst { it.id == snap.cursor }

    fun send(m: JsonObject) { scope.launch { try { session?.send(m) } catch (e: CancellationException) { throw e } catch (_: Exception) { } } }
    fun move(delta: Int) { ReadCore.step(cast, snap.cursor, delta)?.let { send(msg("type" to "cursor", "line" to it, "base" to snap.cursorGen)) } }
    fun again() {
        val starts = script?.let { s -> ScriptReading.sectionsOf(s).filter { it.level != ScriptReading.Level.Part }.map { it.index } } ?: return
        ReadCore.sceneStart(cast, snap.cursor, starts)?.takeIf { it != snap.cursor }?.let { send(msg("type" to "cursor", "line" to it, "base" to snap.cursorGen)) }
    }

    LaunchedEffect(snap.cursor, following, lines.size) {
        if (following && cursorIndex >= 0) listState.animateScrollToItem(maxOf(0, cursorIndex - 1))
    }
    LaunchedEffect(listState) {
        // Only a finger leaves the line; the scroll that follows the cursor is the app's own.
        listState.interactionSource.interactions.collect { if (it is androidx.compose.foundation.interaction.DragInteraction.Start) following = false }
    }

    Column(Modifier.fillMaxSize()) {
        Box(Modifier.weight(1f)) {
            LazyColumn(Modifier.fillMaxSize(), state = listState, contentPadding = androidx.compose.foundation.layout.PaddingValues(Spacing.S4.dp), verticalArrangement = Arrangement.spacedBy(Spacing.S3.dp)) {
                itemsIndexed(lines, key = { _, l -> l.id }) { i, line ->
                    LineRow(line, current = line.id == snap.cursor, mine = i in mine, hidden = i in mine && hideMine && snap.mode == "rehearse" && line.id != snap.cursor)
                }
            }
            if (!following) {
                Button(onClick = { following = true }, modifier = Modifier.align(Alignment.BottomEnd).padding(Spacing.S4.dp)) { Text("Back to the line") }
            }
        }
        HorizontalDivider()
        Column(Modifier.fillMaxWidth().padding(Spacing.S4.dp), verticalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
            val status = ReadText.status(state)
            val fact = ReadCore.nextLine(next).orEmpty()
            if (status.isNotEmpty() || fact.isNotEmpty()) Text(status.ifEmpty { fact }, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            state.refusal?.let { Text(ReadCore.refusal(it), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.error) }
            Row(horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp), verticalAlignment = Alignment.CenterVertically) {
                if (snap.mode == "rehearse" && !leads) {
                    TextButton(onClick = { hideMine = !hideMine }) { Text(if (hideMine) "Show my lines" else "Hide my lines") }
                }
                Box(Modifier.weight(1f))
                if (leads) {
                    OutlinedButton(onClick = { move(-1) }) { Text("Back") }
                    if (snap.mode == "rehearse") OutlinedButton(onClick = { again() }) { Text("Again") }
                    Button(onClick = { move(1) }) { Text("Next") }
                    Box {
                        TextButton(onClick = { menu = true }) { Text("Reading") }
                        DropdownMenu(menu, { menu = false }) {
                            DropdownMenuItem(text = { Text(if (snap.mode == "rehearse") "Table read" else "Rehearse") }, onClick = { menu = false; send(msg("type" to "mode", "mode" to if (snap.mode == "rehearse") "read" else "rehearse")) })
                            DropdownMenuItem(text = { Text(if (snap.locked) "Unlock joining" else "Lock joining") }, onClick = { menu = false; send(msg("type" to "lock", "locked" to !snap.locked)) })
                            DropdownMenuItem(text = { Text(if (snap.readOpen) "Stop reading open parts" else "Read open parts") }, onClick = { menu = false; send(msg("type" to "read-open", "open" to !snap.readOpen)) })
                            DropdownMenuItem(text = { Text("Open the screen") }, onClick = { menu = false; onOpenScreen(snap.code) })
                            DropdownMenuItem(text = { Text("End the reading") }, onClick = { menu = false; ending = true })
                        }
                    }
                } else if (snap.kind == "adult" && !isScreen) {
                    TextButton(onClick = { parts = true }) { Text("Parts") }
                }
            }
        }
    }
    if (ending) {
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { ending = false },
            title = { Text("End the reading for everyone?") },
            confirmButton = { TextButton(onClick = { ending = false; send(msg("type" to "end")) }) { Text("End the reading") } },
            dismissButton = { TextButton(onClick = { ending = false }) { Text("Cancel") } },
        )
    }
    if (parts) {
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { parts = false },
            title = { Text("Parts") },
            text = {
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    script?.roles.orEmpty().forEach { role ->
                        val id = com.example.appname.plays.PartID.role(role.name).raw
                        val holder = snap.claims[id]
                        ListItem(
                            headlineContent = { Text(role.name) },
                            trailingContent = {
                                when {
                                    holder != null && holder == snap.you?.id -> TextButton(onClick = { send(msg("type" to "release", "part" to id)) }) { Text("Release") }
                                    holder == null -> TextButton(onClick = { send(msg("type" to "claim", "part" to id)) }) { Text("Take") }
                                    else -> Text("Taken", style = MaterialTheme.typography.labelMedium)
                                }
                            },
                        )
                    }
                }
            },
            confirmButton = { TextButton(onClick = { parts = false }) { Text("Done") } },
        )
    }
}

@Composable
private fun LineRow(line: ScriptLine, current: Boolean, mine: Boolean, hidden: Boolean) {
    val tint = if (mine) MaterialTheme.colorScheme.secondary.copy(alpha = 0.14f) else androidx.compose.ui.graphics.Color.Transparent
    Column(Modifier.fillMaxWidth().background(tint).padding(Spacing.S2.dp)) {
        if (line.kind == ScriptLine.Kind.Speech) Text(line.part.title, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        val words = if (hidden) "…" else line.spokenText.ifEmpty { line.source.orEmpty() }
        Text(words, style = if (current) MaterialTheme.typography.titleMedium else MaterialTheme.typography.bodyMedium)
    }
}

// ---- The shared screen ----

/** The room's current line large, the code, who is here. A TV pairs as this and holds no part (rule 12). */
@Composable
fun ReadScreenContent(state: ReadState, script: PlayScript?) {
    val snap = state.snapshot
    val lines = script?.lines.orEmpty()
    val i = maxOf(0, lines.indexOfFirst { it.id == snap?.cursor })
    Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background).padding(Spacing.S6.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Column(Modifier.weight(1f).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Spacing.S8.dp, Alignment.CenterVertically), horizontalAlignment = Alignment.CenterHorizontally) {
            if (lines.isNotEmpty()) {
                ScreenLine(lines.getOrNull(i - 1), large = false)
                ScreenLine(lines[i], large = true)
                ScreenLine(lines.getOrNull(i + 1), large = false)
            } else snap?.readsNow?.let { Text(com.example.appname.plays.PartID(it.part).title, style = MaterialTheme.typography.displaySmall) }
        }
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom) {
            Text(ReadText.status(state), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Box(Modifier.weight(1f))
            if (snap != null) {
                Text(ReadText.grouped(snap.code), style = MaterialTheme.typography.headlineSmall, modifier = Modifier.semantics { contentDescription = snap.code.toList().joinToString(" ") })
                Text("  ${snap.present} here", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun ScreenLine(line: ScriptLine?, large: Boolean) {
    if (line == null) return
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        if (line.kind == ScriptLine.Kind.Speech) Text(line.part.title, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(
            line.spokenText.ifEmpty { line.source.orEmpty() },
            style = if (large) MaterialTheme.typography.displaySmall else MaterialTheme.typography.bodyMedium,
            color = if (large) MaterialTheme.colorScheme.onBackground else MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
    }
}

/** Joins as role "screen" and shows the room. On a TV this is the whole pairing; it records nothing. */
@Composable
fun ReadScreenScreen(code: String, onBack: () -> Unit) {
    val container = LocalAppContainer.current
    val scope = rememberCoroutineScope()
    val session = remember { ReadSession(container.readWire, scope, diag = BuildConfig.DEBUG && LaunchDoors.diag) }
    val state by session.state.collectAsState()
    var failure by remember { mutableStateOf<String?>(null) }
    var attempt by remember { mutableIntStateOf(0) }
    var script by remember { mutableStateOf<PlayScript?>(null) }
    LaunchedEffect(attempt) {
        val normal = ReadCore.normalizeCode(code) ?: run { failure = ReadCore.refusal("bad_code"); return@LaunchedEffect }
        try { session.join(normal, buildJsonObject { put("role", JsonPrimitive("screen")) }) } catch (e: CancellationException) { throw e } catch (e: Exception) { failure = say(e) }
    }
    LaunchedEffect(state.snapshot?.scriptId) { state.snapshot?.scriptId?.let { script = container.plays.script(it) } }
    DisposableEffect(Unit) { onDispose { session.leave() } }
    Box(Modifier.fillMaxSize()) {
        ReadScreenContent(state, script)
        failure?.let { f ->
            Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Spacing.S4.dp)) {
                Text(f, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.titleMedium)
                OutlinedButton(onClick = { failure = null; attempt += 1 }) { Text("Try again") }
                TextButton(onClick = onBack) { Text("Back") }
            }
        }
    }
}

// ---- The class page ----

@Composable
fun ClassPageScreen(id: String, onBack: () -> Unit, onCasting: (String, String) -> Unit, onOpenRoom: (String) -> Unit) {
    val container = LocalAppContainer.current
    val wire = container.readClass
    val scope = rememberCoroutineScope()
    var detail by remember { mutableStateOf<ReadClassDetail?>(null) }
    var progress by remember { mutableStateOf<ReadProgress?>(null) }
    var failure by remember { mutableStateOf<String?>(null) }
    var paste by remember { mutableStateOf("") }
    var showCode by remember { mutableStateOf(false) }
    var choosing by remember { mutableStateOf(false) }
    var attempt by remember { mutableIntStateOf(0) }

    LaunchedEffect(id, attempt) {
        try {
            detail = wire.detail(id)
            progress = wire.progress(id)
            failure = null
        } catch (e: CancellationException) { throw e } catch (e: Exception) { failure = say(e) }
    }
    fun act(work: suspend () -> Unit) { scope.launch { try { work(); attempt += 1 } catch (e: CancellationException) { throw e } catch (e: Exception) { failure = say(e) } } }

    Scaffold(topBar = { BackBar(onBack, detail?.name ?: "Class") }) { padding ->
        Column(Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(Spacing.S4.dp), verticalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
            failure?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            detail?.code?.let { code ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(if (showCode) com.example.appname.plays.PlaysShare.classCodeDisplay(code) else "•••• ••••", style = MaterialTheme.typography.headlineSmall)
                    Box(Modifier.weight(1f))
                    TextButton(onClick = { showCode = !showCode }) { Text(if (showCode) "Hide code" else "Show code") }
                }
            }
            SectionHeader("Seats")
            detail?.seats.orEmpty().forEach { s ->
                ListItem(
                    headlineContent = { Text(s.label, style = MaterialTheme.typography.bodyMedium) },
                    supportingContent = if (s.claimed) ({ Text("In") }) else null,
                    trailingContent = {
                        Row {
                            if (s.claimed) TextButton(onClick = { act { wire.releaseSeat(id, s.id) } }) { Text("Release") }
                            TextButton(onClick = { act { wire.removeSeat(id, s.id) } }) { Text("Remove") }
                        }
                    },
                )
            }
            OutlinedTextField(paste, { paste = it }, label = { Text("Paste names, one a line") }, minLines = 2, modifier = Modifier.fillMaxWidth())
            Button(onClick = { val t = paste; paste = ""; act { wire.addSeats(id, t) } }, enabled = paste.isNotBlank()) { Text("Add names") }
            Button(onClick = { choosing = true }) { Text("Start a reading") }
            progress?.productions.orEmpty().forEach { p ->
                SectionHeader(p.title)
                p.seats.forEach { row ->
                    val lines = row.parts.sumOf { it.lines }
                    val done = row.parts.sumOf { it.approved }
                    ListItem(headlineContent = { Text(row.label) }, trailingContent = { Text("$done of $lines") })
                }
                TextButton(onClick = { onCasting(id, p.id) }) { Text("Casting") }
            }
        }
    }
    if (choosing) {
        val scripts by produceScripts()
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { choosing = false },
            title = { Text("Start a reading") },
            text = {
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    scripts.forEach { s ->
                        TextButton(onClick = {
                            choosing = false
                            scope.launch {
                                try {
                                    val prod: ReadProductionInfo = wire.classProduction(id, s.id, s.revision, s.lines.map { it.id to it.part.raw })
                                    val session = ReadSession(container.readWire, scope)
                                    session.open(ReadClass.openingBody(s, classId = id, productionId = prod.id), teacher = true)
                                    session.state.value.code?.let { ReadHandover.hold(session); onOpenRoom(it) }
                                } catch (e: CancellationException) { throw e } catch (e: Exception) { failure = say(e) }
                            }
                        }) { Text(s.title) }
                    }
                }
            },
            confirmButton = { TextButton(onClick = { choosing = false }) { Text("Cancel") } },
        )
    }
}

@Composable
private fun produceScripts(): androidx.compose.runtime.State<List<PlayScript>> {
    val container = LocalAppContainer.current
    return androidx.compose.runtime.produceState(emptyList()) {
        container.plays.load()
        value = (container.plays.state.value as? com.example.appname.plays.PlaysLibrary.State.Ready)?.scripts.orEmpty()
    }
}

// ---- The casting board ----

@Composable
fun CastingBoardScreen(classId: String, productionId: String, onBack: () -> Unit) {
    val container = LocalAppContainer.current
    val wire = container.readClass
    val scope = rememberCoroutineScope()
    var detail by remember { mutableStateOf<ReadClassDetail?>(null) }
    var facts by remember { mutableStateOf<ReadClass.Facts?>(null) }
    var assignments by remember { mutableStateOf<List<ReadCore.Assignment>>(emptyList()) }
    var dirty by remember { mutableStateOf(false) }
    var failure by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(classId, productionId) {
        try {
            detail = wire.detail(classId)
            val info = wire.production(productionId)
            assignments = info.assignments.map { ReadCore.Assignment(it.part, it.seat, it.from, it.to) }
            val s = container.plays.script(info.scriptID)
            if (s != null && s.revision == info.scriptRevision) facts = ReadClass.Facts(s) else failure = ReadCore.refusal("revision_mismatch")
        } catch (e: CancellationException) { throw e } catch (e: Exception) { failure = say(e) }
    }
    val seats = detail?.seats.orEmpty().map { ReadCore.Seat(it.id, it.label) }
    fun set(next: List<ReadCore.Assignment>) { assignments = next; dirty = true }
    CastingBoardContent(
        facts = facts, seats = seats, assignments = assignments, failure = failure, dirty = dirty, onBack = onBack,
        onWhole = { part, seat -> set(assignments.filter { it.part != part } + if (seat.isEmpty()) emptyList() else listOf(ReadCore.Assignment(part, seat))) },
        onRange = { part, r, seat ->
            set(assignments.filter { !(it.part == part && it.from == null) && !(it.part == part && it.from == r.from) } + ReadCore.Assignment(part, seat, r.from, r.to))
        },
        onFill = { facts?.let { f -> set(ReadCore.fillEvenly(f.facts, seats, assignments, f.cast, f.words)) } },
        onClear = { set(emptyList()) },
        onSave = {
            scope.launch {
                try { assignments = wire.assign(productionId, assignments); dirty = false; failure = null } catch (e: CancellationException) { throw e } catch (e: Exception) { failure = say(e) }
            }
        },
    )
}

/** The board itself, stateless so a preview can draw it: parts largest first, a picker per part, totals per seat. */
@Composable
fun CastingBoardContent(
    facts: ReadClass.Facts?,
    seats: List<ReadCore.Seat>,
    assignments: List<ReadCore.Assignment>,
    failure: String?,
    dirty: Boolean,
    onBack: () -> Unit,
    onWhole: (String, String) -> Unit,
    onRange: (String, ReadCore.SceneRange, String) -> Unit,
    onFill: () -> Unit,
    onClear: () -> Unit,
    onSave: () -> Unit,
) {
    Scaffold(topBar = { BackBar(onBack, "Casting") }) { padding ->
        Column(Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(Spacing.S4.dp), verticalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
            failure?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            Row(horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
                OutlinedButton(onClick = onFill) { Text("Fill evenly") }
                OutlinedButton(onClick = onClear) { Text("Clear") }
                Button(onClick = onSave, enabled = dirty) { Text("Save") }
            }
            if (facts != null) {
                SectionHeader("Seats")
                val totals = ReadCore.seatTotals(facts.cast, facts.words, assignments, seats)
                seats.forEach { s ->
                    val t = totals.first { it.seat == s.id }
                    ListItem(headlineContent = { Text(s.label) }, supportingContent = { Text("${n(t.lines, "line")}, ${n(t.words, "word")}") })
                }
                SectionHeader("Parts")
                facts.facts.forEach { f -> PartRow(f, facts, seats, assignments, onWhole, onRange) }
            }
        }
    }
}

@Composable
private fun PartRow(
    f: ReadCore.PartFacts, facts: ReadClass.Facts, seats: List<ReadCore.Seat>, assignments: List<ReadCore.Assignment>,
    onWhole: (String, String) -> Unit, onRange: (String, ReadCore.SceneRange, String) -> Unit,
) {
    val whole = assignments.firstOrNull { it.part == f.part && it.from == null && it.to == null }
    val ranges = ReadCore.sceneRanges(facts.cast, f.part, facts.starts)
    var open by remember { mutableStateOf(false) }
    var split by remember { mutableStateOf<ReadCore.SceneRange?>(null) }
    Column(Modifier.fillMaxWidth()) {
        ListItem(
            headlineContent = { Text(com.example.appname.plays.PartID(f.part).title, style = MaterialTheme.typography.titleMedium) },
            supportingContent = { Text("${n(f.lines, "line")}, ${n(f.words, "word")}, ${n(f.scenes, "scene")}, longest ${f.longest}") },
            trailingContent = {
                Box {
                    OutlinedButton(onClick = { open = true }) { Text(seats.firstOrNull { it.id == whole?.seat }?.label ?: "None") }
                    DropdownMenu(open, { open = false }) {
                        DropdownMenuItem(text = { Text("None") }, onClick = { open = false; onWhole(f.part, "") })
                        seats.forEach { s -> DropdownMenuItem(text = { Text(s.label) }, onClick = { open = false; onWhole(f.part, s.id) }) }
                    }
                }
            },
        )
        if (ranges.size > 1 && whole == null) {
            ranges.forEach { r ->
                val a = assignments.firstOrNull { it.part == f.part && it.from == r.from }
                Row(Modifier.padding(start = Spacing.S4.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text("Scene from ${r.from}: ${n(r.lines, "line")}", style = MaterialTheme.typography.labelMedium, modifier = Modifier.weight(1f))
                    Box {
                        TextButton(onClick = { split = r }) { Text(seats.firstOrNull { it.id == a?.seat }?.label ?: "Pick") }
                        DropdownMenu(split == r, { split = null }) {
                            seats.forEach { s -> DropdownMenuItem(text = { Text(s.label) }, onClick = { split = null; onRange(f.part, r, s.id) }) }
                        }
                    }
                }
            }
        }
    }
}
