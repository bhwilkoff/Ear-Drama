package com.example.appname.ui.screens

import android.Manifest
import android.content.pm.PackageManager
import android.media.MediaPlayer
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Headphones
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberModalBottomSheetState
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
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import com.example.appname.BuildConfig
import com.example.appname.navigation.StudioDoor
import com.example.appname.plays.AudioRoute
import com.example.appname.plays.DeviceLiveAudio
import com.example.appname.plays.LinePart
import com.example.appname.plays.LiveAudio
import com.example.appname.plays.LiveListen
import com.example.appname.plays.MixSound
import com.example.appname.plays.OwnSounds
import com.example.appname.plays.PartID
import com.example.appname.plays.PlayScript
import com.example.appname.plays.Production
import com.example.appname.plays.RecordingSession
import com.example.appname.plays.Relay
import com.example.appname.plays.ScriptLine
import com.example.appname.plays.SoundCore
import com.example.appname.plays.SoundCue
import com.example.appname.plays.SoundPack
import com.example.appname.plays.SoundSource
import com.example.appname.ui.Haptic
import com.example.appname.ui.LocalAppContainer
import com.example.appname.ui.recordButtonColors
import com.example.appname.ui.rememberCast
import com.example.appname.ui.rememberDeviceVoices
import com.example.appname.ui.rememberHaptics
import com.example.appname.ui.theme.AppSemantics
import com.example.appname.ui.theme.OnAir
import com.example.appname.ui.theme.Spacing
import com.example.appname.ui.wayColors
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// The Sound part's studio (B32 §3.1; ANDROID-DESIGN §4.17): the script's lines with each cue row drawn as a slot, a dock, and the
// board. Not the reader's page: that is a pager of speaking roles, and a slot is a cue row, not a role's line.

private const val WIDE_DP = 840

/** The Sound screen for one production. */
@Composable
fun SoundScreen(productionId: String, onBack: () -> Unit) {
    val plays = LocalAppContainer.current.plays
    val productions by plays.store.productions.collectAsState()
    val production = productions.firstOrNull { it.id == productionId }
    val script by produceState<PlayScript?>(plays.cachedCastScript(productionId), productionId) { value = plays.castScript(productionId) }
    DisposableEffect(productionId) {
        plays.store.hold(productionId)
        onDispose {
            plays.store.production(productionId)?.let { p -> SoundCore.prune(p).takeIf { it != p }?.let(plays.store::save) }
            plays.store.release(productionId)
            plays.leftStudio(productionId)
        }
    }
    val s = script
    if (production == null || s == null) {
        Scaffold(topBar = { SoundTopBar(onBack) }) { pad ->
            Box(Modifier.fillMaxSize().padding(pad), contentAlignment = Alignment.Center) {
                if (production == null && s != null) Text("This ear drama is gone.", style = MaterialTheme.typography.bodyMedium) else CircularProgressIndicator()
            }
        }
        return
    }
    SoundStudio(productionId, s, onBack)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SoundTopBar(onBack: () -> Unit, onDone: (() -> Unit)? = null) {
    TopAppBar(
        title = { Text("Sound") },
        navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back") } },
        actions = { if (onDone != null) TextButton(onClick = onDone) { Text("Done with this part") } },
    )
}

private fun lineWords(line: ScriptLine): String = when (line.kind) {
    ScriptLine.Kind.Speech -> line.parts.orEmpty().joinToString(" ") { it.text }
    else -> line.source.orEmpty()
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
private fun SoundStudio(productionId: String, script: PlayScript, onBack: () -> Unit) {
    val container = LocalAppContainer.current
    val plays = container.plays
    val store = plays.store
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val haptics = rememberHaptics()
    val muted = com.example.appname.navigation.LocalPlayerMuted.current
    val productions by store.productions.collectAsState()
    val production = productions.firstOrNull { it.id == productionId } ?: return
    val slots = remember(script, production) { SoundCore.slotsOf(script, production) }
    val lineAt = remember(script) { script.lines.withIndex().associate { (i, l) -> l.id to i } }
    var currentKey by rememberSaveable { mutableStateOf<String?>(null) }
    val current = slots.firstOrNull { it.key == currentKey } ?: slots.firstOrNull()
    val number = current?.let { c -> slots.indexOfFirst { it.key == c.key } + 1 } ?: 0
    var board by rememberSaveable { mutableStateOf(false) }
    var selId by remember { mutableStateOf<String?>(null) }
    var picking by remember { mutableStateOf(false) }
    var query by remember { mutableStateOf("") }
    var category by remember { mutableStateOf<String?>(null) }
    var auditioning by remember { mutableStateOf<String?>(null) }
    var menuFor by remember { mutableStateOf<String?>(null) }
    val listState = rememberLazyListState()

    fun latest(): Production? = store.production(productionId)

    fun edit(change: (Production) -> Production) {
        val p = latest() ?: return
        store.save(change(p))
    }

    /** A cue row's slot is written on first touch; the slot's key becomes its record id. */
    fun open(slot: SoundCore.Slot): String? {
        val p = latest() ?: return null
        val (made, id) = SoundCore.ensure(p, slot)
        val kept = SoundCore.prune(made, keep = id)
        if (kept != p) store.save(kept)
        currentKey = id
        return id
    }

    fun move(delta: Int) {
        if (slots.isEmpty()) return
        val i = (slots.indexOfFirst { it.key == current?.key }.coerceAtLeast(0) + delta).coerceIn(0, slots.size - 1)
        val to = slots[i]
        currentKey = to.key
        selId = null
        scope.launch { listState.animateScrollToItem(lineAt.getValue(to.line)) }
        haptics(Haptic.Selection)
    }

    // The pack: a source that may be absent (MANIFEST_URL null until the owner rules on its hosting).
    var packTick by remember { mutableIntStateOf(0) }
    val manifest by produceState<SoundPack.State?>(null, packTick) { value = withContext(Dispatchers.IO) { plays.soundPack.manifest() } }
    var hereTick by remember { mutableIntStateOf(0) }
    var downloading by remember { mutableStateOf<String?>(null) }
    var failed by remember { mutableStateOf<String?>(null) }
    val pack = (manifest as? SoundPack.State.Ready)?.pack
    val here = remember(pack, hereTick) { pack?.categories?.filter { c -> plays.soundPack.categoryHere(pack, c.id) }?.map { it.id }?.toSet().orEmpty() }
    var mine by remember { mutableStateOf(plays.ownSounds.list()) }
    val packUi: PackUi = when (val m = manifest) {
        null -> PackUi.Loading
        SoundPack.State.Absent -> PackUi.Absent
        SoundPack.State.Unreachable -> PackUi.Unreachable
        is SoundPack.State.Ready -> PackUi.Ready(m.pack.cues, m.pack.categories, here, downloading, failed)
    }

    // Opening the board seeds the search with a word from the cue itself, which is search and never authorship (§3.2 item 3).
    LaunchedEffect(board, current?.key, pack) {
        if (board) query = SoundCore.seedQuery(current?.text.orEmpty(), pack?.cues.orEmpty())
    }

    // Audition (the raw file) never overlaps a recording.
    val player = remember { Auditioner(muted) { auditioning = null } }
    DisposableEffect(Unit) { onDispose { player.release() } }

    fun fileFor(src: SoundSource, prod: Production): File? = when {
        src.take != null -> prod.take(src.take)?.let { store.takeFile(prod, it) }
        src.own != null -> plays.ownSounds.file(src.own).takeIf { it.isFile }
        src.pack != null && pack != null -> pack.cues.firstOrNull { it.id == src.cue }?.takeIf { plays.soundPack.has(pack, it) }?.let { plays.soundPack.file(pack, it) }
        else -> null
    }

    fun audition(key: String, file: File?) {
        if (auditioning == key || file == null) { player.stop(); auditioning = null; return }
        player.play(file)
        auditioning = key
    }

    // Hear it in place (B32 3.2 item 2): the line before the slot to the line after, mixed live as it will sound.
    val voices = rememberCast(rememberDeviceVoices(), script, productionId)
    var hearing by remember { mutableStateOf<LiveListen?>(null) }
    var hearJob by remember { mutableStateOf<Job?>(null) }
    fun stopHear() {
        hearJob?.cancel()
        hearing?.close()
        hearing = null
        hearJob = null
    }
    DisposableEffect(Unit) { onDispose { stopHear() } }

    fun hearInPlace(slot: SoundCore.Slot) {
        if (hearing != null) { stopHear(); return }
        val h = voices ?: return
        val prod = latest() ?: return
        player.stop()
        auditioning = null
        if (container.playback.state.value.isPlaying) container.playback.togglePlay()
        val plan = Relay.listenPlan(prod, script) { !it.isSpeaking && h.cast.resolve(it).read }
        val range = SoundCore.inPlace(script, plan, slot.line) ?: return
        val live = LiveListen(store.takesFolder(prod.id), h.speaker).also { it.muted = muted }
        hearing = live
        hearJob = scope.launch {
            try {
                live.run(plan, plays.listenCues(prod, script, plan, muted), range)
            } finally {
                if (hearing === live) { live.close(); hearing = null; hearJob = null }
            }
        }
    }

    // The performed cue: a take of the Sound part on the slot, never a line's chosen take.
    val stub = BuildConfig.DEBUG && StudioDoor.stub
    val audio: LiveAudio = remember(productionId) { if (stub) StubLiveAudio(hold = false) else DeviceLiveAudio(context) }
    LaunchedEffect(muted) { (audio as? DeviceLiveAudio)?.muted = muted }
    val session = remember(productionId) {
        RecordingSession(
            production, script, PartID.SOUND, store, audio, SilentStandIn(),
            wait = if (stub) ({ delay(150) }) else ({ ms -> delay(ms) }),
        )
    }
    DisposableEffect(session) { onDispose { session.end() } }
    val phase by session.phase.collectAsState()
    var gate by remember { mutableStateOf(StudioGate.Ready) }
    val roomTone = phase is RecordingSession.Phase.RoomTone
    val listening = phase is RecordingSession.Phase.Listening
    val started = session.started && !roomTone

    fun begin(echo: Boolean) {
        if (audio.outputRoute() == AudioRoute.Speaker && !echo) {
            gate = StudioGate.NeedsHeadphones
            return
        }
        gate = StudioGate.Ready
        if (container.playback.state.value.isPlaying) container.playback.togglePlay()
        scope.launch { session.begin(echo) }
    }
    val micPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) begin(false) else gate = StudioGate.MicrophoneDenied
    }

    fun startRecording() {
        if (stub || ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) begin(false)
        else micPermission.launch(Manifest.permission.RECORD_AUDIO)
    }

    fun recordCue() {
        val slot = current ?: return
        stopHear()
        player.stop()
        auditioning = null
        if (listening) { session.stopListening(); return }
        if (session.isBusy) return
        val id = open(slot) ?: return
        scope.launch {
            val take = session.recordCue(id, slot.line)
            if (take != null) {
                edit { p -> SoundCore.addPerformed(p, script, id, take) }
                haptics(Haptic.Success)
                selId = null
            }
        }
    }

    // Own sounds: Record a sound (up to 30 s, nothing plays, so no headphones gate) and Bring a file.
    var recordingOwn by remember { mutableStateOf(false) }
    var ownSeconds by remember { mutableIntStateOf(0) }
    var ownError by remember { mutableStateOf<String?>(null) }
    val ownAudio = remember { if (stub) StubLiveAudio(hold = false) else DeviceLiveAudio(context) }
    DisposableEffect(Unit) { onDispose { runCatching { ownAudio.stop() } } }

    fun stopOwn() {
        if (!recordingOwn) return
        recordingOwn = false
        val capture = ownAudio.endCapture()
        ownAudio.stop()
        if (capture.samples.isNotEmpty()) {
            scope.launch {
                withContext(Dispatchers.IO) { plays.ownSounds.add("", capture.samples, "recorded") }
                mine = plays.ownSounds.list()
            }
        }
    }
    LaunchedEffect(recordingOwn) {
        ownSeconds = 0
        while (recordingOwn) {
            delay(1000)
            ownSeconds += 1
            if (ownSeconds >= SoundCore.OWN_RECORD_MAX_S) stopOwn()
        }
    }
    fun beginOwn() {
        ownError = null
        player.stop()
        auditioning = null
        try {
            ownAudio.start(false)
            ownAudio.beginCapture { }
            recordingOwn = true
        } catch (e: Exception) {
            ownError = e.message ?: "The microphone could not be opened."
        }
    }
    val ownPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) beginOwn() else ownError = "Ear Drama needs the microphone to record a sound."
    }
    val bring = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri: Uri? ->
        if (uri != null) scope.launch {
            ownError = null
            try {
                withContext(Dispatchers.IO) {
                    val temp = File.createTempFile("bring", ".audio", context.cacheDir)
                    try {
                        context.contentResolver.openInputStream(uri)?.use { input ->
                            temp.outputStream().use { out ->
                                val buffer = ByteArray(64 * 1024)
                                var total = 0L
                                while (true) {
                                    val n = input.read(buffer)
                                    if (n < 0) break
                                    total += n
                                    if (total > SoundCore.OWN_FILE_MAX_BYTES) throw OwnSounds.TooBig("That file is larger than 50 MB.")
                                    out.write(buffer, 0, n)
                                }
                            }
                        } ?: throw java.io.IOException("That file could not be opened.")
                        val name = context.contentResolver.query(uri, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME), null, null, null)
                            ?.use { c -> if (c.moveToFirst()) c.getString(0) else null }.orEmpty().substringBeforeLast('.')
                        plays.ownSounds.bring(temp, name)
                    } finally {
                        temp.delete()
                    }
                }
                mine = plays.ownSounds.list()
            } catch (e: Exception) {
                ownError = e.message ?: "That file could not be read."
            }
        }
    }

    // What the board draws.
    fun titleOf(x: SoundCue, prod: Production): Pair<String, Double> = when {
        x.src.take != null -> "Performed" to (prod.take(x.src.take)?.seconds?.times(1000) ?: 0.0)
        x.src.own != null -> (plays.ownSounds.get(x.src.own)?.let { it.name to it.seconds * 1000 } ?: ("Your own sound" to 0.0))
        else -> pack?.cues?.firstOrNull { it.id == x.src.cue }?.let { it.title to it.ms } ?: ((x.src.cue ?: "Sound") to 0.0)
    }

    fun lineLabel(id: String) = "line ${(lineAt[id] ?: 0) + 1}"

    fun boardModel(slot: SoundCore.Slot): BoardModel {
        val sel = slot.sounds.firstOrNull { it.id == selId } ?: slot.sounds.firstOrNull()
        val speaker = script.lines.getOrNull(lineAt[slot.line] ?: -1)?.role.orEmpty()
        val rows = slot.sounds.map { x ->
            val (title, ms) = titleOf(x, production)
            val missing = fileFor(x.src, production) == null
            InCueRow(
                x.id, title,
                if (missing) (if (x.src.own != null) "On another device" else "Not downloaded") else "${SoundCore.clock(ms)} · ${SoundCore.placeLine(x, x.until?.let(::lineLabel))}",
                missing, x.id == sel?.id,
            )
        }
        val inIds = slot.sounds.mapNotNull { it.src.own ?: it.src.cue }.toSet()
        return BoardModel(
            headline = "Cue $number of ${slots.size}" + if (speaker.isNotEmpty()) " · $speaker" else "",
            words = slot.text, silent = slot.silent, inCue = rows, selected = sel, untilLabel = sel?.until?.let(::lineLabel),
            laneDuckDb = production.sound?.lanes?.get(if (sel?.at == "bed") "music" else "effects")?.duckDb
                ?: if (sel?.at == "bed") MixSound.Defaults.MUSIC_DUCK_DB else MixSound.Defaults.EFFECTS_DUCK_DB,
            query = query, category = category, pack = packUi, inCueIds = inIds, mine = mine,
            recordingOwn = recordingOwn, ownSeconds = ownSeconds, ownError = ownError, auditioning = auditioning, picking = picking,
            hearing = hearing != null, canHear = voices != null && !session.isBusy,
        )
    }

    fun addSource(slot: SoundCore.Slot, src: SoundSource, kind: String) {
        val id = open(slot) ?: return
        val anchor = production.chosenTake(slot.line)
        var added: String? = null
        edit { p -> SoundCore.addSound(p, script, id, src, kind, anchor).also { added = it.second }.first }
        selId = added
        haptics(Haptic.Selection)
    }

    fun act(slot: SoundCore.Slot) = BoardActions(
        onDone = { board = false; stopHear(); player.stop(); auditioning = null; latest()?.let { p -> SoundCore.prune(p).takeIf { it != p }?.let(store::save) } },
        onSilent = { on -> val id = open(slot); if (id != null) edit { SoundCore.setSilent(it, id, on) }; if (on) board = false },
        onSelect = { selId = it },
        onRemove = { sid -> slot.id?.let { id -> edit { SoundCore.removeSound(it, id, sid) }; if (selId == sid) selId = null } },
        onPatch = { patch -> val sid = (slot.sounds.firstOrNull { it.id == selId } ?: slot.sounds.firstOrNull())?.id; val id = slot.id; if (sid != null && id != null) edit { SoundCore.updateSound(it, id, sid, patch) } },
        onPickUntil = { picking = true; board = false },
        onQuery = { query = it },
        onCategory = { category = it },
        onAddPack = { cue -> addSource(slot, SoundSource(pack = pack?.pack, cue = cue.id), cue.kind) },
        onAddOwn = { s -> addSource(slot, SoundSource(own = s.id), "effect") },
        onAudition = { key ->
            val prod = latest() ?: production
            val file = when {
                key.startsWith("s:") -> slot.sounds.firstOrNull { it.id == key.removePrefix("s:") }?.let { fileFor(it.src, prod) }
                key.startsWith("p:") -> pack?.cues?.firstOrNull { it.id == key.removePrefix("p:") }?.takeIf { plays.soundPack.has(pack, it) }?.let { plays.soundPack.file(pack, it) }
                else -> plays.ownSounds.file(key.removePrefix("o:")).takeIf { it.isFile }
            }
            audition(key, file)
        },
        onDownload = { cat ->
            val p = pack
            if (p != null) scope.launch {
                downloading = cat
                failed = null
                try {
                    withContext(Dispatchers.IO) { plays.soundPack.download(p, cat) }
                    hereTick += 1
                } catch (e: Exception) {
                    failed = cat
                } finally {
                    downloading = null
                }
            }
        },
        onRetry = { packTick += 1 },
        onRecordOwn = {
            if (recordingOwn) stopOwn()
            else if (stub || ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) beginOwn()
            else ownPermission.launch(Manifest.permission.RECORD_AUDIO)
        },
        onBring = { bring.launch(arrayOf("audio/*")) },
        onHear = { hearInPlace(slot) },
        onRemoveOwn = { id -> plays.ownSounds.remove(id); mine = plays.ownSounds.list() },
        onRecordIt = { board = false; recordCue() },
    )

    // A bed draws a rule in the margin from its first line to its last.
    val bedLines = remember(slots) {
        val set = HashSet<Int>()
        for (s in slots) for (x in s.sounds) if (x.at == "bed") {
            val a = lineAt[s.line] ?: continue
            val b = lineAt[x.until ?: s.line] ?: a
            for (i in a..maxOf(a, b)) set += i
        }
        set
    }
    val slotsByLine = remember(slots) { slots.groupBy { it.line } }
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }

    Scaffold(
        topBar = {
            // The part is finished from here, as every part is: Sound may leave cues empty and never blocks the play (§3.1 item 4).
            val finishable = production.state(PartID.SOUND).status == com.example.appname.plays.PartState.Status.Recording && !session.isBusy
            SoundTopBar(onBack, onDone = if (finishable) ({
                latest()?.let { p ->
                    runCatching { com.example.appname.plays.Relay.finish(PartID.SOUND, SoundCore.prune(p), script) }.onSuccess { store.save(it); onBack() }
                }
            }) else null)
        },
        bottomBar = {
            SoundDock(
                headline = current?.let { c ->
                    val x = c.sounds.firstOrNull()
                    "Cue $number of ${slots.size}" + (x?.let { " · ${titleOf(it, production).first} · ${SoundCore.PLACEMENT_LABEL[it.at]}" } ?: "")
                } ?: "No cues in this play",
                hasCue = current != null,
                recording = listening,
                gate = gate, started = started, roomTone = roomTone, roomToneLeft = (phase as? RecordingSession.Phase.RoomTone)?.secondsLeft ?: 0,
                failure = (phase as? RecordingSession.Phase.Failed)?.message,
                onBoard = { current?.let { open(it) }; board = true },
                onPrevious = { move(-1) }, onNext = { move(1) },
                onRecord = { if (started) recordCue() else startRecording() },
                onSettings = { context.startActivity(android.content.Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null))) },
                onCheckHeadphones = { begin(false) },
                onWithout = { begin(true) },
            )
        },
    ) { pad ->
        BoxWithConstraints(Modifier.padding(pad).fillMaxSize()) {
            val wide = maxWidth >= WIDE_DP.dp
            Row(
                Modifier.fillMaxSize().focusRequester(focus).focusable().onPreviewKeyEvent { e ->
                    if (e.type != KeyEventType.KeyDown) return@onPreviewKeyEvent false
                    when (e.key) {
                        Key.J -> { move(1); true }
                        Key.K -> { move(-1); true }
                        Key.S -> { current?.let { open(it) }; board = true; true }
                        Key.Spacebar -> { if (started) recordCue() else startRecording(); true }
                        else -> false
                    }
                },
            ) {
                LazyColumn(Modifier.weight(1f).fillMaxHeight(), state = listState) {
                    itemsIndexed(script.lines, key = { _, l -> l.id }) { i, line ->
                        LineRow(
                            line = line, mine = slotsByLine[line.id].orEmpty(), bed = i in bedLines,
                            currentKey = current?.key, picking = picking, numberOf = { k -> slots.indexOfFirst { it.key == k } + 1 },
                            menu = menuFor == line.id,
                            onMenu = { menuFor = it },
                            onTap = {
                                if (picking) {
                                    val sid = (current?.sounds?.firstOrNull { it.id == selId } ?: current?.sounds?.firstOrNull())?.id
                                    val cid = current?.id
                                    if (sid != null && cid != null) edit { SoundCore.updateSound(it, cid, sid, SoundCore.Patch(until = line.id)) }
                                    picking = false
                                    board = true
                                }
                            },
                            onSlot = { s -> currentKey = s.key; selId = null; haptics(Haptic.Selection) },
                            onAdd = {
                                menuFor = null
                                val p = latest() ?: return@LineRow
                                val (made, id) = SoundCore.addSlot(p, line.id)
                                store.save(SoundCore.prune(made, keep = id))
                                currentKey = id
                                selId = null
                                board = true
                            },
                        )
                    }
                }
                if (wide && board && current != null) {
                    Surface(Modifier.width(360.dp).fillMaxHeight(), color = MaterialTheme.colorScheme.surfaceContainer) {
                        SoundBoard(boardModel(current), act(current), Modifier.padding(top = Spacing.S2.dp))
                    }
                }
            }
            if (!wide && board && current != null) {
                ModalBottomSheet(onDismissRequest = { board = false; stopHear(); player.stop(); auditioning = null }, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = false)) {
                    SoundBoard(boardModel(current), act(current))
                }
            }
        }
    }
    if (picking) {
        Box(Modifier.fillMaxSize().navigationBarsPadding(), contentAlignment = Alignment.BottomCenter) {
            Surface(Modifier.padding(Spacing.S4.dp), shape = MaterialTheme.shapes.large, color = MaterialTheme.colorScheme.inverseSurface) {
                Row(Modifier.padding(horizontal = Spacing.S4.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text("Tap the last line this sound sits under", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.inverseOnSurface)
                    TextButton(onClick = { picking = false; board = true }) { Text("Cancel") }
                }
            }
        }
    }
}

/** One script line as the Sound part draws it: its words, the slots at it, a bed's rule in the margin, a long press for Add a sound here. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
internal fun LineRow(
    line: ScriptLine,
    mine: List<SoundCore.Slot>,
    bed: Boolean,
    currentKey: String?,
    picking: Boolean,
    numberOf: (String) -> Int,
    menu: Boolean,
    onMenu: (String?) -> Unit,
    onTap: () -> Unit,
    onSlot: (SoundCore.Slot) -> Unit,
    onAdd: () -> Unit,
) {
    val ink = MaterialTheme.colorScheme.onSurface
    val muted = MaterialTheme.colorScheme.onSurfaceVariant
    val rule = MaterialTheme.colorScheme.primary
    Box {
        Row(
            Modifier.fillMaxWidth().height(androidx.compose.foundation.layout.IntrinsicSize.Min)
                .combinedClickable(role = Role.Button, onClickLabel = if (picking) "Sound sits under this line" else null, onClick = onTap, onLongClickLabel = "Add a sound here", onLongClick = { onMenu(line.id) })
                .padding(end = Spacing.S4.dp),
        ) {
            Box(Modifier.width(3.dp).fillMaxHeight().background(if (bed) rule else Color.Transparent))
            Column(Modifier.padding(start = Spacing.S4.dp - 3.dp, top = Spacing.S2.dp, bottom = Spacing.S2.dp), verticalArrangement = Arrangement.spacedBy(Spacing.S1.dp)) {
                if (line.kind == ScriptLine.Kind.Speech && !line.role.isNullOrEmpty()) {
                    Text(line.role.uppercase(), style = MaterialTheme.typography.labelMedium, color = muted)
                }
                Text(lineText(line, ink, muted), style = MaterialTheme.typography.bodyMedium)
                mine.forEach { s -> SlotRow(s, numberOf(s.key), s.key == currentKey, onClick = { onSlot(s) }) }
            }
        }
        DropdownMenu(expanded = menu, onDismissRequest = { onMenu(null) }) {
            DropdownMenuItem(text = { Text("Add a sound here") }, onClick = onAdd)
        }
    }
}

private fun lineText(line: ScriptLine, ink: Color, muted: Color): AnnotatedString = buildAnnotatedString {
    if (line.kind != ScriptLine.Kind.Speech) {
        withStyle(SpanStyle(fontStyle = FontStyle.Italic, color = muted)) { append(lineWords(line)) }
        return@buildAnnotatedString
    }
    line.parts.orEmpty().forEachIndexed { i, part ->
        if (i > 0) append(" ")
        when (part) {
            is LinePart.Say -> withStyle(SpanStyle(color = ink)) { append(part.text) }
            else -> withStyle(SpanStyle(fontStyle = FontStyle.Italic, color = muted)) { append(part.text) }
        }
    }
}

/** A slot under its line: the ring (empty, the number of sounds in it, or a dash for Leave silent), the cue's words, the chosen sounds. */
@Composable
internal fun SlotRow(slot: SoundCore.Slot, number: Int, current: Boolean, onClick: () -> Unit) {
    val ink = MaterialTheme.colorScheme.onSurface
    val shape = MaterialTheme.shapes.small
    Row(
        Modifier.fillMaxWidth().clip(shape)
            .combinedClickable(role = Role.Button, onClick = onClick)
            .semantics(mergeDescendants = true) {
                contentDescription = "Cue $number" + when {
                    slot.silent -> ", left silent"
                    slot.sounds.isNotEmpty() -> ", ${slot.sounds.size} sounds"
                    else -> ", empty"
                }
            }
            .then(if (current) Modifier.background(MaterialTheme.colorScheme.surfaceContainerHigh) else Modifier)
            .padding(Spacing.S2.dp),
        horizontalArrangement = Arrangement.spacedBy(Spacing.S3.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Surface(
            Modifier.size(24.dp), shape = CircleShape, color = if (slot.sounds.isEmpty()) Color.Transparent else ink,
            border = BorderStroke(if (current) 2.dp else 1.dp, if (current || slot.sounds.isNotEmpty()) ink else MaterialTheme.colorScheme.outline),
        ) {
            Box(contentAlignment = Alignment.Center) {
                Text(
                    when {
                        slot.silent -> "\u2013"
                        slot.sounds.isNotEmpty() -> "${slot.sounds.size}"
                        else -> ""
                    },
                    style = MaterialTheme.typography.labelMedium, color = if (slot.sounds.isEmpty()) ink else MaterialTheme.colorScheme.surface, textAlign = TextAlign.Center,
                )
            }
        }
        Column(Modifier.weight(1f)) {
            Text(
                slot.text.ifBlank { "Sound here" },
                style = MaterialTheme.typography.bodySmall.copy(fontStyle = FontStyle.Italic), color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

/** The dock (§3.1 item 5): one status row, then Sounds, Previous, the round record control, Next. Before the first cue is taken, the gate. */
@Composable
internal fun SoundDock(
    headline: String,
    hasCue: Boolean,
    recording: Boolean,
    gate: StudioGate,
    started: Boolean,
    roomTone: Boolean,
    roomToneLeft: Int,
    failure: String?,
    onBoard: () -> Unit,
    onPrevious: () -> Unit,
    onNext: () -> Unit,
    onRecord: () -> Unit,
    onSettings: () -> Unit,
    onCheckHeadphones: () -> Unit,
    onWithout: () -> Unit,
) {
    Surface(color = MaterialTheme.colorScheme.surfaceContainer, tonalElevation = 2.dp) {
        Column(Modifier.fillMaxWidth().navigationBarsPadding().padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp), verticalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
            Text(headline, style = MaterialTheme.typography.bodyMedium, maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis, modifier = Modifier.semantics { contentDescription = headline })
            when {
                roomTone -> Row(horizontalArrangement = Arrangement.spacedBy(Spacing.S3.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text("Quiet, please. Recording the room.", style = MaterialTheme.typography.titleMedium)
                    Text("$roomToneLeft", style = MaterialTheme.typography.displaySmall)
                }
                gate == StudioGate.MicrophoneDenied -> {
                    Text("Ear Drama needs the microphone to record a sound.", style = MaterialTheme.typography.bodySmall, color = AppSemantics.colors.error)
                    OutlinedButton(onClick = onSettings, colors = wayColors()) { Text("Open settings") }
                }
                gate == StudioGate.NeedsHeadphones -> {
                    Text("Plug in headphones.", style = MaterialTheme.typography.bodySmall, color = AppSemantics.colors.error)
                    Row(horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
                        Button(onClick = onCheckHeadphones) { Text("Check again") }
                        TextButton(onClick = onWithout) { Text("Record without headphones") }
                    }
                }
                else -> Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly, verticalAlignment = Alignment.CenterVertically) {
                    DockButton("Sounds", Icons.Filled.GraphicEq, hasCue, onBoard)
                    IconButton(onClick = onPrevious, enabled = hasCue) { Icon(Icons.Filled.SkipPrevious, contentDescription = "Previous cue") }
                    if (!hasCue) {
                        Spacer(Modifier.size(52.dp))
                    } else if (!started) {
                        Button(onClick = onRecord, colors = recordButtonColors()) {
                            Icon(Icons.Filled.Mic, contentDescription = null)
                            Text("Perform it", Modifier.padding(start = Spacing.S2.dp))
                        }
                    } else {
                        RoundControl(
                            if (recording) "Stop" else "Record", if (recording) Icons.Filled.Stop else Icons.Filled.Mic,
                            OnAir.colors.record, OnAir.colors.onRecord, true, onRecord,
                        )
                    }
                    IconButton(onClick = onNext, enabled = hasCue) { Icon(Icons.Filled.SkipNext, contentDescription = "Next cue") }
                }
            }
            if (!started && !roomTone && gate == StudioGate.Ready && hasCue) {
                Row(horizontalArrangement = Arrangement.spacedBy(Spacing.S1.dp), verticalAlignment = Alignment.CenterVertically, modifier = Modifier.align(Alignment.CenterHorizontally)) {
                    Icon(Icons.Filled.Headphones, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(18.dp))
                    Text("Headphones on", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            failure?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = AppSemantics.colors.error) }
        }
    }
}

@Composable
private fun DockButton(label: String, icon: androidx.compose.ui.graphics.vector.ImageVector, enabled: Boolean, onClick: () -> Unit) {
    OutlinedButton(onClick = onClick, enabled = enabled, colors = wayColors()) {
        Icon(icon, contentDescription = null)
        Text(label, Modifier.padding(start = Spacing.S2.dp))
    }
}

/** Plays a file through MediaPlayer, once (the board's audition); a recording stops it first. */
internal class Auditioner(private val muted: Boolean, private val onEnd: () -> Unit) {
    private var player: MediaPlayer? = null

    fun play(file: File) {
        stop()
        player = runCatching {
            MediaPlayer().apply {
                setDataSource(file.path)
                if (muted) setVolume(0f, 0f)
                setOnCompletionListener { stop(); onEnd() }
                prepare()
                start()
            }
        }.getOrNull()
    }

    fun stop() {
        player?.release()
        player = null
    }

    fun release() = stop()
}
