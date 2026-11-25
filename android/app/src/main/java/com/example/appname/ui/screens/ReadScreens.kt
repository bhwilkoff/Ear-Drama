package com.example.appname.ui.screens

import androidx.compose.foundation.background
import androidx.core.content.edit
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
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
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.unit.sp
import com.example.appname.ui.ClaimTvFocus
import com.example.appname.ui.LocalIsTelevision
import com.example.appname.ui.rememberCast
import com.example.appname.ui.rememberDeviceVoices
import com.example.appname.ui.tvFocusMark
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
import com.example.appname.plays.ScriptLoad
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
class ReadNav(
    val openClass: (String) -> Unit = {},
    val openRoom: (String) -> Unit = {},
    val showReading: () -> Unit = {},
    val openParts: () -> Unit = {},
    val openVoiceSettings: () -> Unit = {},
    val exit: RoomExit = RoomExit(),
)

/**
 * What a person's way out of a room does (PLAYS-DESIGN §12.13 rule 3): the room screen on top says it, and AppRoot's one `back`
 * (Close, system back, a TV's Leave) runs it. A disposal never does.
 */
class RoomExit {
    private var onLeave: (() -> Unit)? = null

    fun set(leave: () -> Unit) { onLeave = leave }

    fun clear(leave: () -> Unit) { if (onLeave === leave) onLeave = null }

    fun leave() {
        val run = onLeave
        onLeave = null
        run?.invoke()
    }
}

@Composable
private fun LeaveOnExit(session: ReadSession) {
    val exit = LocalReadNav.current.exit
    DisposableEffect(exit, session) {
        val leave: () -> Unit = { session.leave() }
        exit.set(leave)
        onDispose { exit.clear(leave) }
    }
}

val LocalReadNav = androidx.compose.runtime.staticCompositionLocalOf { ReadNav() }

/** A play page's door: opens an adult room on this play and lands in it (WEB-DESIGN §4.17's twin). */
@Composable
fun ReadTogetherButton(script: PlayScript) {
    val container = LocalAppContainer.current
    val nav = LocalReadNav.current
    val scope = rememberCoroutineScope()
    var failure by remember { mutableStateOf<String?>(null) }
    var confirming by remember { mutableStateOf(false) }
    val age = com.example.appname.ui.screens.rememberAgeAsk()
    com.example.appname.ui.screens.AgeAskDialogs(age)
    /** An own script's room carries the production it was shared as (PLAYS-DESIGN §13 item 13): its opener is signed in. */
    fun open(productionId: String?) {
        scope.launch {
            try {
                // Not this screen's scope: the room outlives the page it was opened from.
                val session = ReadSession(container.readWire, container.appScope)
                session.open(ReadClass.openingBody(script, productionId = productionId), teacher = productionId != null)
                session.state.value.code?.let { ReadHandover.hold(session); nav.openRoom(it) }
            } catch (e: CancellationException) { throw e } catch (e: Exception) { failure = ownSay(e) }
        }
    }
    OutlinedButton(onClick = {
        failure = null
        if (!script.isOwn) { open(null); return@OutlinedButton }
        if (container.accounts.account.value == null) { container.plays.accountAsk.value = "Sharing needs an account."; return@OutlinedButton }
        age.ask {
            scope.launch {
                try {
                    val pid = com.example.appname.ui.screens.alreadySharedProduction(container, script)
                    if (pid != null) open(pid) else confirming = true
                } catch (e: CancellationException) { throw e } catch (e: Exception) { failure = ownSay(e) }
            }
        }
    }) { Text("Read together") }
    failure?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.labelMedium) }
    if (confirming) {
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { confirming = false },
            title = { Text("Share ${script.title}?") },
            text = { Text("People who join the reading can read it.") },
            confirmButton = {
                TextButton(onClick = {
                    confirming = false
                    scope.launch {
                        try { open(com.example.appname.ui.screens.shareForReading(container, script)) }
                        catch (e: CancellationException) { throw e } catch (e: Exception) { failure = ownSay(e) }
                    }
                }) { Text("Share") }
            },
            dismissButton = { TextButton(onClick = { confirming = false }) { Text("Cancel") } },
        )
    }
}

/** A refusal in words: the Worker's own for sharing (a script's refusals are the share's), the room's otherwise. */
/** A class production of [s]: an own script's carries its title and goes with its text; one that can never be sent undoes it. */
private suspend fun makeClassProduction(
    container: com.example.appname.app.AppContainer, wire: com.example.appname.plays.ReadClassWire, classId: String, s: PlayScript, owed: (String, Throwable) -> Unit,
): ReadProductionInfo {
    if (!s.isOwn) return wire.classProduction(classId, s.id, s.revision, s.lines.map { it.id to it.part.raw })
    val prod = wire.classProductionBody(classId, com.example.appname.plays.OwnShare.makeBody(s))
    val unsent = com.example.appname.plays.OwnShare.sendOrUndo(container.scriptWire, container.scriptWire, prod.id, s, com.example.appname.plays.ScriptFreezer { container.plays.own.freeze(it) })
    if (unsent != null) {
        if (!com.example.appname.plays.OwnShare.passes(unsent)) {
            // sendOrUndo deleted the production through the share's own delete, which a class production answers for its teacher.
            throw unsent
        }
        owed(prod.id, unsent)
    }
    return prod
}

/** Try again for a class script that is owed, from this device's copy; one that is not here says so. */
internal suspend fun sendClassScript(
    container: com.example.appname.app.AppContainer, rec: com.example.appname.plays.SharedRecord, notSent: Map<String, Throwable>, set: (Map<String, Throwable>) -> Unit,
) {
    val own = container.plays.own.script(rec.scriptID)?.takeIf { it.revision == rec.scriptRevision }
        ?: throw com.example.appname.plays.PlaysException("not_on_device")
    val e = com.example.appname.plays.OwnShare.sendOrUndo(container.scriptWire, container.scriptWire, rec.id, own, com.example.appname.plays.ScriptFreezer { container.plays.own.freeze(it) })
    if (e == null) { set(notSent - rec.id); return }
    if (com.example.appname.plays.OwnShare.passes(e)) set(notSent + (rec.id to e))
    throw e
}

/** A class production's own script when it is not there: owed (Try again, from this device's copy) or removed. */
@Composable
private fun OwnClassRow(rec: com.example.appname.plays.SharedRecord, why: Throwable?, busy: Boolean, onAgain: () -> Unit) {
    val own = com.example.appname.plays.OwnShare.ownState(rec) ?: return
    if (own.state == "kept") return
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.S1.dp)) {
        if (own.state == "removed") {
            Text(com.example.appname.plays.PlaysShare.line(com.example.appname.plays.PlaysException("script_removed")), color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.labelMedium)
        } else {
            Text(com.example.appname.plays.OwnShare.NOT_SENT, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.labelMedium)
            why?.let { Text(com.example.appname.plays.PlaysShare.line(it), color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.labelMedium) }
            OutlinedButton(onClick = onAgain, enabled = !busy) { Text("Try again") }
        }
    }
}

private fun ownSay(e: Exception): String = if (e is com.example.appname.plays.PlaysException) com.example.appname.plays.PlaysShare.line(e) else say(e)

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

private fun say(e: Exception): String = when (e) {
    is com.example.appname.plays.PlaysException -> com.example.appname.plays.PlaysShare.line(e)
    // A script's own refusals (docs/WORKER.md "Own scripts") have their words; the room's are ReadCore's.
    is ReadFailure -> com.example.appname.plays.OwnShare.scriptLine(com.example.appname.plays.PlaysException(e.code)).ifEmpty { ReadCore.refusal(e.code) }
    else -> ReadCore.refusal("error")
}

// ---- The room ----

/** A reader's join screen, then the reader itself with the room attached (ANDROID-DESIGN §4.19): no separate line list. */
@Composable
fun ReadRoomScreen(code: String, onBack: () -> Unit, onOpenScreen: (String) -> Unit, seatDoor: String? = null) {
    val container = LocalAppContainer.current
    val nav = LocalReadNav.current
    val context = androidx.compose.ui.platform.LocalContext.current
    val scope = rememberCoroutineScope()
    val session = remember { ReadHandover.take() ?: ReadSession(container.readWire, scope, diag = BuildConfig.DEBUG && LaunchDoors.diag, after = container.appScope) }
    val state by session.state.collectAsState()
    val prefs = remember { context.getSharedPreferences("ed.read", android.content.Context.MODE_PRIVATE) }
    var failure by remember { mutableStateOf<String?>(null) }
    var gone by remember { mutableStateOf(false) }
    var needsSeat by remember { mutableStateOf(false) }
    var asking by remember { mutableStateOf(session.state.value.snapshot == null && !(BuildConfig.DEBUG && seatDoor != null)) }
    var name by remember { mutableStateOf(prefs.getString("name", "").orEmpty()) }
    var attempt by remember { mutableIntStateOf(0) }
    var scriptAttempt by remember { mutableIntStateOf(0) }
    val load = rememberRoomScript(state.snapshot, scriptAttempt, session.memberKey)
    val script = (load as? ScriptLoad.Ready)?.script
    val wire = container.readClass

    suspend fun join(seatKey: String? = null, seatId: String? = null, move: Boolean = false) {
        if (session.state.value.snapshot != null) return
        val normal = ReadCore.normalizeCode(code) ?: run { failure = ReadCore.refusal("bad_code"); return }
        val typed = name.trim()
        val want = buildJsonObject {
            if (seatId != null && seatKey != null) { put("seat", JsonPrimitive(seatId)); put("seat_key", JsonPrimitive(seatKey)) }
            else if (typed.isNotEmpty()) put("name", JsonPrimitive(typed))
            if (move) put("move", JsonPrimitive(true))
        }
        try {
            session.join(normal, want)
            needsSeat = false
            prefs.edit { putString("name", typed) }
        } catch (e: CancellationException) {
            throw e
        } catch (e: ReadFailure) {
            if (e.code == "seat_required" || e.code == "seat_key_required") needsSeat = true
            else { failure = ReadCore.refusal(e.code); gone = e.code in ReadSession.GONE }
        } catch (e: Exception) {
            failure = say(e)
        }
    }

    LaunchedEffect(code) {
        if (!asking) return@LaunchedEffect
        val normal = ReadCore.normalizeCode(code) ?: return@LaunchedEffect
        container.readWire.gone(normal)?.let { failure = ReadCore.refusal(it); gone = true }
    }
    LaunchedEffect(attempt, asking) { if (!asking && !needsSeat) join() }
    DisposableEffect(Unit) { onDispose { session.pause() } }
    LeaveOnExit(session)

    val snap = state.snapshot
    val s = script
    when {
        snap != null && s != null -> {
            val record = remember(s.id) { roomRecord(container, context, session, s, scope) }
            LaunchedEffect(record) { record.start(); record.resume() }
            DisposableEffect(record) { onDispose { record.detach() } }
            val seam = remember(record) { RoomSeam(session, record, wire, scope, onOpenScreen, onLeave = onBack) }
            com.example.appname.ui.screens.ReaderScreen(s.id, startLine = snap.cursor, onBack = onBack, room = seam)
        }
        snap != null -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            ScriptWait(load, onRetry = { scriptAttempt += 1 })
        }
        else -> Scaffold(topBar = { BackBar(onBack, "Reading") }) { padding ->
            Box(Modifier.fillMaxSize().padding(padding)) {
                when {
                    state.ended != null -> Text(ReadCore.refusal(state.ended!!), Modifier.padding(Spacing.S4.dp), style = MaterialTheme.typography.bodyMedium)
                    needsSeat -> SeatPicker(wire, seatDoor, onClaimed = { seatKey, seatId, move -> scope.launch { join(seatKey, seatId, move) } })
                    failure != null -> Column(Modifier.padding(Spacing.S4.dp), verticalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
                        Text(failure!!, color = MaterialTheme.colorScheme.error)
                        if (!gone) OutlinedButton(onClick = { failure = null; attempt += 1 }) { Text("Try again") }
                    }
                    asking -> Column(Modifier.padding(Spacing.S4.dp), verticalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
                        Text(ReadText.grouped(ReadCore.normalizeCode(code) ?: code), style = MaterialTheme.typography.headlineSmall)
                        OutlinedTextField(
                            name, { name = it.take(ReadCore.NAME_MAX) }, label = { Text("Your name, optional") }, singleLine = true,
                            keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(autoCorrectEnabled = false),
                        )
                        Button(onClick = { asking = false }) { Text("Join") }
                        androidx.compose.material3.TextButton(onClick = nav.openParts) { Text("Your parts") }
                    }
                }
            }
        }
    }
}

/** The take machinery for a room on this device: the studio's session with no cue, the DEBUG stub microphone behind its door. */
private fun roomRecord(
    container: com.example.appname.app.AppContainer,
    context: android.content.Context,
    session: ReadSession,
    script: PlayScript,
    scope: kotlinx.coroutines.CoroutineScope,
): com.example.appname.plays.ReadRecord {
    val first = script.castParts.firstOrNull { it.id.isSpeaking }?.id ?: com.example.appname.plays.PartID.DIRECTIONS
    val api = com.example.appname.plays.PlaysApi(container.accounts.worker)
    return com.example.appname.plays.ReadRecord(
        wire = container.readWire, session = session, store = container.plays.store, script = script, scope = scope,
        engineFor = { production ->
            val stub = BuildConfig.DEBUG && com.example.appname.navigation.StudioDoor.stub
            val audio: com.example.appname.plays.LiveAudio = if (stub) StubLiveAudio(hold = false) else com.example.appname.plays.DeviceLiveAudio(context)
            com.example.appname.plays.SessionRoomEngine(
                com.example.appname.plays.RecordingSession(
                    production, script, first, container.plays.store, audio, SilentStandIn(),
                    wait = if (stub) ({ kotlinx.coroutines.delay(150) }) else ({ ms -> kotlinx.coroutines.delay(ms) }),
                ),
            )
        },
        upload = { pid, takeId, bytes, meta -> api.upload(pid, takeId, bytes, meta) },
    )
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

// ---- The shared screen ----

/** The room's current line large, the code, who is here. A TV pairs as this and holds no part (rule 12); on a TV one Leave button holds focus. */
@Composable
fun ReadScreenContent(state: ReadState, script: PlayScript?, onLeave: (() -> Unit)? = null, load: ScriptLoad? = null, onRetry: () -> Unit = {}) {
    val snap = state.snapshot
    val lines = script?.lines.orEmpty()
    val i = maxOf(0, lines.indexOfFirst { it.id == snap?.cursor })
    val leave = remember { FocusRequester() }
    if (onLeave != null) ClaimTvFocus(leave, Unit)
    Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background).padding(Spacing.S6.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Column(Modifier.weight(1f).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Spacing.S8.dp, Alignment.CenterVertically), horizontalAlignment = Alignment.CenterHorizontally) {
            if (lines.isNotEmpty()) {
                ScreenLine(lines.getOrNull(i - 1), large = false)
                ScreenLine(lines[i], large = true)
                ScreenLine(lines.getOrNull(i + 1), large = false)
            } else if (load is ScriptLoad.Loading || load is ScriptLoad.Failed) ScriptWait(load, onRetry)
            else snap?.readsNow?.let { Text(com.example.appname.plays.PartID(it.part).title, style = MaterialTheme.typography.displaySmall) }
        }
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom) {
            if (onLeave != null) OutlinedButton(onClick = onLeave, Modifier.focusRequester(leave).tvFocusMark()) { Text("Leave") }
            Text(ReadText.status(state), Modifier.padding(start = Spacing.S4.dp), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
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

/**
 * Read open parts on a screen (PLAYS-DESIGN §12.10 item 10): the live stand-in voice reads the cursor's line only while the
 * leader's switch is on and nobody holds the line, and stops the moment the cursor moves. Text only; nothing is stored.
 */
@Composable
private fun ScreenVoice(state: ReadState, script: PlayScript?) {
    val handle = rememberCast(rememberDeviceVoices(), script, null)
    val line = state.snapshot?.openVoiceLine()
    LaunchedEffect(line, handle) {
        val h = handle ?: return@LaunchedEffect
        val l = script?.lines?.firstOrNull { it.id == line } ?: return@LaunchedEffect
        if (l.kind != ScriptLine.Kind.Speech || l.spokenText.isBlank()) return@LaunchedEffect
        try { h.speaker.speak(l.spokenText, l.part) } finally { h.speaker.cancel() }
    }
}

/** The room's play, asked of the published library then the bundle (B15c) at the revision the room was cast from, or the words for why not. */
@Composable
private fun rememberRoomScript(snap: ReadSnapshot?, attempt: Int, key: String?): ScriptLoad {
    val container = LocalAppContainer.current
    val plays = container.plays
    val id = snap?.scriptId
    val revision = snap?.scriptRevision
    val own = id != null && com.example.appname.plays.OwnScript.isOwnId(id)
    val load by produceState<ScriptLoad>(ScriptLoad.Loading, id, revision, attempt, own && key == null) {
        if (id == null) { value = ScriptLoad.Loading; return@produceState }
        value = ScriptLoad.Loading
        if (!own) { value = plays.resolve(id, revision); return@produceState }
        // An own script is this device's copy, else the room's own route read by the member's key, drawn only once it is whole.
        if (revision == null || snap == null) { value = ScriptLoad.Failed(com.example.appname.plays.PlaysShare.line(com.example.appname.plays.PlaysException("script_damaged"))); return@produceState }
        if (key == null) return@produceState
        value = try {
            ScriptLoad.Ready(
                container.scripts.scriptOf(
                    id, revision, com.example.appname.plays.ScriptWho(room = snap.code, key = key, pid = snap.productionId),
                    com.example.appname.plays.OwnShare.Fits.room(snap.cursor, snap.claims.keys),
                ),
            )
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            ScriptLoad.Failed(if (e is com.example.appname.plays.PlaysException) com.example.appname.plays.PlaysShare.line(e) else ReadCore.refusal("error"))
        }
    }
    return load
}

/** The spinner while the play is asked for, or the words and a way to ask again. */
@Composable
private fun ScriptWait(load: ScriptLoad, onRetry: () -> Unit) {
    when (load) {
        is ScriptLoad.Failed -> Column(Modifier.padding(Spacing.S4.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
            Text(load.line, color = MaterialTheme.colorScheme.error, textAlign = TextAlign.Center)
            // A removed script has no Try again.
            if (load.line != com.example.appname.plays.PlaysShare.line(com.example.appname.plays.PlaysException("script_removed"))) OutlinedButton(onClick = onRetry) { Text("Try again") }
        }
        else -> androidx.compose.material3.CircularProgressIndicator(Modifier.semantics { contentDescription = "Loading" })
    }
}

/** A room as its shared screen: the line large and, while Read open parts is on, the voice. Records nothing, holds no part. */
@Composable
private fun ReadScreenBody(session: ReadSession, onBack: () -> Unit) {
    val container = LocalAppContainer.current
    val state by session.state.collectAsState()
    var attempt by remember { mutableIntStateOf(0) }
    val load = rememberRoomScript(state.snapshot, attempt, session.memberKey)
    val script = (load as? ScriptLoad.Ready)?.script
    ScreenVoice(state, script)
    ReadScreenContent(state, script, onLeave = if (LocalIsTelevision.current) onBack else null, load = load, onRetry = { attempt += 1 })
}

/** Joins as role "screen" and shows the room (a deep link, or a phone's Open the screen); it records nothing. */
@Composable
fun ReadScreenScreen(code: String, onBack: () -> Unit) {
    val container = LocalAppContainer.current
    val scope = rememberCoroutineScope()
    val session = remember { ReadSession(container.readWire, scope, diag = BuildConfig.DEBUG && LaunchDoors.diag, after = container.appScope) }
    var failure by remember { mutableStateOf<String?>(null) }
    var attempt by remember { mutableIntStateOf(0) }
    LaunchedEffect(attempt) {
        val normal = ReadCore.normalizeCode(code) ?: run { failure = ReadCore.refusal("bad_code"); return@LaunchedEffect }
        try { session.join(normal, buildJsonObject { put("role", JsonPrimitive("screen")) }) } catch (e: CancellationException) { throw e } catch (e: Exception) { failure = say(e) }
    }
    DisposableEffect(Unit) { onDispose { session.pause() } }
    LeaveOnExit(session)
    Box(Modifier.fillMaxSize()) {
        ReadScreenBody(session, onBack)
        failure?.let { f ->
            Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Spacing.S4.dp)) {
                Text(f, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.titleMedium)
                OutlinedButton(onClick = { failure = null; attempt += 1 }) { Text("Try again") }
                TextButton(onClick = onBack) { Text("Back") }
            }
        }
    }
}

/**
 * Show a reading (a Google TV, ANDROID-DESIGN §4.19): the pairing code large, split 3 + 3, with the one line that says what
 * to do; it asks again every 2 seconds, and once a leader adds it, becomes that room's screen. One Leave button holds focus.
 */
@Composable
fun ReadPairScreen(onBack: () -> Unit) {
    val container = LocalAppContainer.current
    val scope = rememberCoroutineScope()
    val pairing = remember { com.example.appname.plays.ReadPairing(container.readWire, scope) }
    val st by pairing.state.collectAsState()
    val session = remember { ReadSession(container.readWire, scope, diag = BuildConfig.DEBUG && LaunchDoors.diag, after = container.appScope) }
    DisposableEffect(pairing) {
        pairing.start()
        onDispose { pairing.stop(); session.pause() }
    }
    LeaveOnExit(session)
    LaunchedEffect(st.paired) { st.paired?.let { session.adopt(it) } }
    if (st.paired != null) ReadScreenBody(session, onBack) else PairContent(st.code, st.refusal, onBack)
}

@Composable
internal fun PairContent(code: String?, refusal: String?, onLeave: () -> Unit) {
    val leave = remember { FocusRequester() }
    ClaimTvFocus(leave, Unit)
    Column(
        Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background).padding(Spacing.S6.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Spacing.S6.dp, Alignment.CenterVertically),
    ) {
        Text("Show a reading", style = MaterialTheme.typography.headlineSmall, modifier = Modifier.semantics { heading() })
        Text(
            code?.let(com.example.appname.plays.ReadPairing::split).orEmpty(),
            style = MaterialTheme.typography.displaySmall.let { it.copy(fontSize = it.fontSize * 2, lineHeight = androidx.compose.ui.unit.TextUnit.Unspecified, letterSpacing = 8.sp) },
            modifier = Modifier.semantics { contentDescription = code.orEmpty().toList().joinToString(" ") },
        )
        Text("On the leader's device: Reading, then Add a screen.", style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        refusal?.let { Text(it, style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.error) }
        OutlinedButton(onClick = onLeave, Modifier.focusRequester(leave).tvFocusMark()) { Text("Leave") }
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
    var busy by remember { mutableStateOf(false) }
    var pickingDate by remember { mutableStateOf(false) }
    var deleting by remember { mutableStateOf(false) }
    var exported by remember { mutableStateOf<String?>(null) }
    val context = androidx.compose.ui.platform.LocalContext.current
    val saveExport = androidx.activity.compose.rememberLauncherForActivityResult(androidx.activity.result.contract.ActivityResultContracts.CreateDocument("application/json")) { uri ->
        val text = exported
        exported = null
        if (uri != null && text != null) {
            scope.launch {
                try {
                    kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) { context.contentResolver.openOutputStream(uri)?.use { it.write(text.toByteArray(Charsets.UTF_8)) } }
                } catch (e: CancellationException) { throw e } catch (_: Exception) { failure = ReadCore.refusal("error") }
            }
        }
    }
    fun guard(work: suspend () -> Unit) {
        if (busy) return
        busy = true
        scope.launch {
            try { work(); failure = null } catch (e: CancellationException) { throw e } catch (e: Exception) { failure = say(e) } finally { busy = false }
        }
    }
    /** Each class production's record, for what its own script says (owed, removed) and the lines that must match it. */
    var classRecords by remember { mutableStateOf<Map<String, com.example.appname.plays.SharedRecord>>(emptyMap()) }
    /** Why a class's script was not sent, for this visit: the Worker keeps only that it is owed. */
    var classNotSent by remember { mutableStateOf<Map<String, Throwable>>(emptyMap()) }
    var waiting by remember { mutableStateOf<List<com.example.appname.plays.ClassReviewItem>>(emptyList()) }
    var reviewScripts by remember { mutableStateOf<Map<String, PlayScript>>(emptyMap()) }
    var recordScripts by remember { mutableStateOf<Map<String, String>>(emptyMap()) }
    val heard = remember { com.example.appname.plays.MixPlayback() }
    DisposableEffect(heard) { onDispose { heard.stop() } }
    val transport = remember { com.example.appname.plays.PlaysApi(container.accounts.worker) }
    /** The seats' chosen takes with no review, read from each class production's record (the Worker merges them). */
    suspend fun loadReviews() {
        val records = progress?.productions.orEmpty().mapNotNull { p -> runCatching { transport.get(p.id) }.getOrNull() }
        classRecords = records.associateBy { it.id }
        val scripts = reviewScripts.toMutableMap()
        records.forEach { r ->
            if (r.scriptID in scripts) return@forEach
            // An own script is read from the production's record (its parts and lines must match the text); a removed or owed one has none to read.
            val own = com.example.appname.plays.OwnShare.ownState(r)
            if (own != null) {
                if (own.state == "kept") runCatching { container.scripts.scriptOf(r.scriptID, r.scriptRevision, com.example.appname.plays.ScriptWho(pid = r.id), com.example.appname.plays.OwnShare.Fits.record(r)) }.getOrNull()?.let { scripts[r.scriptID] = it }
            } else {
                container.plays.script(r.scriptID, r.scriptRevision)?.let { scripts[r.scriptID] = it }
            }
        }
        reviewScripts = scripts
        recordScripts = records.associate { it.id to it.scriptID }
        waiting = com.example.appname.plays.ClassReview.queue(records) { rec, line -> scripts[rec.scriptID]?.lines?.indexOfFirst { it.id == line } ?: -1 }
    }
    // Relay across time (PLAYS-DESIGN §12.11): while this page is open the teacher's app holds each production's pickup, so
    // takes recorded at home pass through; the progress list moves on every arrival.
    val inbox = remember(id) {
        com.example.appname.plays.ClassInbox(container.plays.store, com.example.appname.plays.PlaysApi(container.accounts.worker), scope,
            { sid, rev -> container.plays.script(sid, rev) }, onArrival = { scope.launch { try { progress = wire.progress(id); loadReviews() } catch (e: CancellationException) { throw e } catch (_: Exception) {} } })
    }
    DisposableEffect(inbox) { onDispose { inbox.release() } }
    val lifecycle = androidx.lifecycle.compose.LocalLifecycleOwner.current.lifecycle
    DisposableEffect(inbox, lifecycle) {
        val watch = androidx.lifecycle.LifecycleEventObserver { _, _ -> inbox.setActive(lifecycle.currentState.isAtLeast(androidx.lifecycle.Lifecycle.State.STARTED)) }
        inbox.setActive(lifecycle.currentState.isAtLeast(androidx.lifecycle.Lifecycle.State.STARTED))
        lifecycle.addObserver(watch)
        onDispose { lifecycle.removeObserver(watch) }
    }
    val receivingIdle by inbox.idle.collectAsState()

    LaunchedEffect(id, attempt) {
        try {
            detail = wire.detail(id)
            progress = wire.progress(id)
            failure = null
            progress?.productions.orEmpty().forEach { p -> runCatching { wire.production(p.id) }.getOrNull()?.let { inbox.hold(p.id, it.scriptID, it.scriptRevision) } }
            loadReviews()
        } catch (e: CancellationException) { throw e } catch (e: Exception) { failure = say(e) }
    }
    fun act(work: suspend () -> Unit) { scope.launch { try { work(); attempt += 1 } catch (e: CancellationException) { throw e } catch (e: Exception) { failure = say(e) } } }

    Scaffold(topBar = { BackBar(onBack, detail?.name ?: "Class") }) { padding ->
        Column(Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(Spacing.S4.dp), verticalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
            failure?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            if (receivingIdle) Button(onClick = { inbox.keepReceiving() }) { Text("Keep receiving takes") }
            detail?.takeIf { it.under13 && !it.schoolConsent }?.let {
                SchoolApproval(busy, null, onRecord = { reference -> guard { wire.schoolConsent(id, reference); attempt += 1 } })
            }
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
            if (waiting.isNotEmpty()) {
                SectionHeader("Review")
                waiting.forEach { item ->
                    val line = reviewScripts[recordScripts[item.pid]]?.lines?.firstOrNull { it.id == item.take.lineID }
                    val local = container.plays.store.findShared(item.pid)
                    val take = local?.take(item.take.id)
                    com.example.appname.ui.screens.ClassReviewRow(
                        item = item, seatLabel = detail?.seats.orEmpty().firstOrNull { it.id == item.take.seat }?.label ?: "A seat",
                        partTitle = com.example.appname.plays.PartID(item.take.part).title, words = line?.spokenText.orEmpty(), canPlay = take != null,
                        onPlay = { if (local != null && take != null) scope.launch { runCatching { heard.stop(); heard.load(container.plays.store.takeFile(local, take)); heard.toggle() } } },
                        onDecide = { state, note ->
                            scope.launch {
                                try {
                                    wire.review(item.pid, item.take.id, state, note)
                                    waiting = waiting.filterNot { it.id == item.id }
                                    failure = null
                                    progress = wire.progress(id)
                                } catch (e: CancellationException) { throw e } catch (e: ReadFailure) { failure = ReadCore.refusal(e.code) } catch (_: Exception) { failure = ReadCore.refusal("error") }
                            }
                        },
                    )
                }
            }
            progress?.productions.orEmpty().forEach { p ->
                SectionHeader(p.title)
                classRecords[p.id]?.let { rec -> OwnClassRow(rec, classNotSent[p.id], busy) { guard { sendClassScript(container, rec, classNotSent) { classNotSent = it }; attempt += 1 } } }
                p.seats.forEach { row ->
                    val lines = row.parts.sumOf { it.lines }
                    val done = row.parts.sumOf { it.recorded }
                    ListItem(headlineContent = { Text(row.label) }, trailingContent = { Text("$done of $lines") })
                }
                TextButton(onClick = { onCasting(id, p.id) }) { Text("Casting") }
            }
            detail?.let { d ->
                ClassSection(
                    endsOn = d.endsOn, busy = busy,
                    onChangeDate = { pickingDate = true },
                    onExport = {
                        guard {
                            val (text, without) = com.example.appname.plays.ClassExport.withLines(wire.exportClass(id)) { pid, sid, rev ->
                                container.scripts.scriptOf(sid, rev, com.example.appname.plays.ScriptWho(pid = pid))
                            }
                            exported = text
                            saveExport.launch(exportFileName(d.name))
                            if (without.isNotEmpty()) throw IllegalStateException("The lines of ${without.joinToString(", ")} did not load.")
                        }
                    },
                    onDelete = { deleting = true },
                )
            }
        }
    }
    if (pickingDate) {
        ClassDateDialog(
            endsOn = detail?.endsOn,
            onPick = { day -> pickingDate = false; guard { wire.setEnd(id, day); attempt += 1 } },
            onDismiss = { pickingDate = false },
        )
    }
    if (deleting) {
        DestructiveConfirm(
            message = "Delete ${detail?.name.orEmpty()}? Its names, casting and notes are deleted. Published plays stay.",
            action = "Delete class",
            onConfirm = { deleting = false; guard { wire.deleteClass(id); container.sharing.loadClasses(); onBack() } },
            onDismiss = { deleting = false },
        )
    }
    if (choosing) {
        val rows by produceRows()
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { choosing = false },
            title = { Text("Start a reading") },
            text = {
                val mine = rememberOwnRows().filter { it.done }
                val begin: (String) -> Unit = { scriptId ->
                    choosing = false
                    scope.launch {
                        try {
                            val s = container.plays.script(scriptId) ?: throw IllegalStateException("not_castable")
                            val prod: ReadProductionInfo = makeClassProduction(container, wire, id, s) { pid, e -> classNotSent = classNotSent + (pid to e) }
                            // Not this screen's scope: the room outlives the page it was opened from.
                            val session = ReadSession(container.readWire, container.appScope)
                            session.open(ReadClass.openingBody(s, classId = id, productionId = prod.id), teacher = true)
                            session.state.value.code?.let { ReadHandover.hold(session); onOpenRoom(it) }
                        } catch (e: CancellationException) { throw e } catch (e: Exception) { failure = say(e) }
                    }
                }
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    rows.forEach { row -> TextButton(onClick = { begin(row.id) }) { Text(row.title) } }
                    // The teacher's own scripts stand after the plays (PLAYS-DESIGN §13 item 14).
                    if (mine.isNotEmpty()) {
                        SectionHeader("Your scripts")
                        mine.forEach { row -> TextButton(onClick = { begin(row.id) }) { Text(row.title) } }
                        Text(com.example.appname.plays.OwnShare.CLASS_READERS, Modifier.padding(horizontal = Spacing.S4.dp), style = MaterialTheme.typography.labelMedium)
                    }
                }
            },
            confirmButton = { TextButton(onClick = { choosing = false }) { Text("Cancel") } },
        )
    }
}

/** The published library's plays (the bundle's when it cannot be reached): the choices for a class reading. */
@Composable
private fun produceRows(): androidx.compose.runtime.State<List<com.example.appname.plays.PlayRow>> {
    val container = LocalAppContainer.current
    return androidx.compose.runtime.produceState(emptyList()) {
        container.plays.loadRows()
        value = (container.plays.rows.value as? com.example.appname.plays.PlayLibraryFeed.Rows.Ready)?.rows.orEmpty()
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
            val s = if (com.example.appname.plays.OwnShare.isOwn(info.scriptID)) {
                container.scripts.scriptOf(
                    info.scriptID, info.scriptRevision, com.example.appname.plays.ScriptWho(pid = productionId),
                    com.example.appname.plays.OwnShare.Fits.seat(info.assignments.map { Triple(it.part, it.from, it.to) }),
                )
            } else {
                container.plays.script(info.scriptID, info.scriptRevision)
            }
            if (s != null) facts = ReadClass.Facts(s) else failure = ReadCore.refusal("revision_mismatch")
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
