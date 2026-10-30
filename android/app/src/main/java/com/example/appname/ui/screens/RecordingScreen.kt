package com.example.appname.ui.screens

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import android.view.accessibility.AccessibilityManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Headphones
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import com.example.appname.plays.AudioRoute
import com.example.appname.plays.DeviceLiveAudio
import com.example.appname.plays.PartID
import com.example.appname.plays.RecordingSession
import com.example.appname.plays.RecordingSession.Mode
import com.example.appname.plays.RecordingSession.Phase
import com.example.appname.plays.Relay
import com.example.appname.plays.SystemStandInVoice
import com.example.appname.plays.TakeAudio
import com.example.appname.ui.AccountRow
import com.example.appname.ui.Haptic
import com.example.appname.ui.LocalAppContainer
import com.example.appname.ui.recordButtonColors
import com.example.appname.ui.rememberHaptics
import com.example.appname.ui.theme.Spacing
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private enum class Preflight { Ready, MicrophoneDenied, NeedsHeadphones }

/**
 * Recording one part in one of three modes (PLAYS-DESIGN §2.3-2.4, owner ruling 4, ANDROID-DESIGN
 * §4.9b): Run through, Line by line, Step. The cue line plays labeled when the device voice reads it,
 * the performer's line stands on their part's board, and one round control records. A keyboard or
 * remote drives it too: Space or the headset key records, stops or pauses, Enter keeps the take and
 * moves on, the arrow keys move by line (§7).
 */
@Composable
fun RecordingScreen(productionId: String, part: PartID, onBack: () -> Unit, startLine: String? = null) {
    val container = LocalAppContainer.current
    val plays = container.plays
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val haptics = rememberHaptics()
    val script = rememberCastScript(productionId)
    var session by remember { mutableStateOf<RecordingSession?>(null) }
    var voice by remember { mutableStateOf<SystemStandInVoice?>(null) }
    var preflight by remember { mutableStateOf(Preflight.Ready) }
    var pendingEcho by remember { mutableStateOf(false) }
    var announcing by remember { mutableStateOf(false) }
    var index by remember { mutableIntStateOf(0) }
    var refusal by remember { mutableStateOf<String?>(null) }

    DisposableEffect(Unit) {
        onDispose {
            session?.end()
            voice?.close()
        }
    }

    /** The microphone is asked for here, at the moment of recording, never at launch. */
    fun begin(echoCancelled: Boolean) {
        val production = plays.store.production(productionId) ?: return
        val cast = script ?: return
        val audio = DeviceLiveAudio(context)
        if (audio.outputRoute() == AudioRoute.Speaker && !echoCancelled) {
            preflight = Preflight.NeedsHeadphones
            return
        }
        preflight = Preflight.Ready
        if (container.playback.state.value.isPlaying) container.playback.togglePlay()
        val standIn = voice ?: SystemStandInVoice(context).also { voice = it }
        val accessibility = context.getSystemService(AccessibilityManager::class.java)
        val s = RecordingSession(
            production, cast, part, plays.store, audio, standIn,
            announce = {
                // TalkBack speaks through the speaker the microphone hears, so it
                // says "Your line" before listening starts and nothing while it listens.
                if (accessibility?.isTouchExplorationEnabled == true) {
                    announcing = true
                    delay(1_200)
                }
            },
        )
        s.setMode(RecordingSession.Mode.remembered(context))
        session = s
        index = (if (startLine != null) s.lines.indexOfFirst { it.id == startLine } else s.lines.indexOfFirst { production.usableTake(it.id) == null }).coerceAtLeast(0)
        scope.launch { s.begin(echoCancelled) }
    }

    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) begin(pendingEcho) else preflight = Preflight.MicrophoneDenied
    }

    val account by container.accounts.account.collectAsState()

    fun start(echoCancelled: Boolean) {
        if (account == null) return
        pendingEcho = echoCancelled
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            begin(echoCancelled)
        } else {
            permission.launch(Manifest.permission.RECORD_AUDIO)
        }
    }

    val s = session
    val phase = s?.phase?.collectAsState()?.value
    val inRecorder = s != null && s.started && phase !is Phase.RoomTone
    Scaffold(topBar = { if (!inRecorder) BackBar(onBack, part.title) }) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            when {
                phase is Phase.RoomTone -> RoomTone(phase.secondsLeft)
                s != null && s.started -> Prompter(
                    session = s,
                    index = index,
                    announcing = announcing,
                    onIndex = { index = it.coerceIn(0, (s.lines.size - 1).coerceAtLeast(0)) },
                    onAnnounced = { announcing = false },
                    refusal = refusal,
                    loadWave = { take ->
                        withContext(Dispatchers.IO) {
                            runCatching {
                                takePeaks(TakeAudio.read(plays.store.takeFile(s.production.value, take)).first)
                            }.getOrNull()
                        }
                    },
                    onClose = {
                        s.end()
                        onBack()
                    },
                    onDone = {
                        val latest = plays.store.production(productionId)
                        if (latest != null && container.sharing.linkOf(productionId) != null) {
                            // A shared part is finished on the Worker, from the cast sheet, once its takes are up (§11.7 rule 5).
                            s.end()
                            onBack()
                        } else if (latest != null) {
                            try {
                                plays.store.save(Relay.finish(part, latest, s.script))
                                s.end()
                                onBack()
                            } catch (e: Relay.Refusal) {
                                refusal = e.text
                            }
                        }
                    },
                    haptics = haptics,
                )
                else -> StartPanel(
                    signedIn = account != null,
                    preflight = preflight,
                    failure = (phase as? Phase.Failed)?.message,
                    onStart = { start(echoCancelled = false) },
                    onWithoutHeadphones = { start(echoCancelled = true) },
                    onSettings = {
                        context.startActivity(
                            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null)),
                        )
                    },
                )
            }
        }
    }
}

@Composable
private fun StartPanel(
    signedIn: Boolean,
    preflight: Preflight,
    failure: String?,
    onStart: () -> Unit,
    onWithoutHeadphones: () -> Unit,
    onSettings: () -> Unit,
) {
    Column(
        Modifier.fillMaxSize().padding(Spacing.S6.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Spacing.S4.dp, Alignment.CenterVertically),
    ) {
        when {
            !signedIn -> {
                Text("Recording needs an account.", textAlign = TextAlign.Center, style = MaterialTheme.typography.bodyMedium)
                AccountRow()
            }
            preflight == Preflight.Ready -> {
                Icon(Icons.Filled.Headphones, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(48.dp))
                Button(onClick = onStart, colors = recordButtonColors()) {
                    Icon(Icons.Filled.Mic, contentDescription = null)
                    Text("Start recording", Modifier.padding(start = Spacing.S2.dp))
                }
            }
            preflight == Preflight.MicrophoneDenied -> {
                Text("Ear Drama needs the microphone to record your part.", textAlign = TextAlign.Center, style = MaterialTheme.typography.bodyMedium)
                OutlinedButton(onClick = onSettings) { Text("Open settings") }
            }
            else -> {
                Text(
                    "Plug in headphones.",
                    textAlign = TextAlign.Center,
                    style = MaterialTheme.typography.bodyMedium,
                )
                Button(onClick = onStart) { Text("Check again") }
                TextButton(onClick = onWithoutHeadphones) { Text("Record without headphones") }
            }
        }
        failure?.let { ErrorLine(it) }
    }
}

@Composable
private fun RoomTone(seconds: Int) {
    Column(
        Modifier.fillMaxSize().semantics(mergeDescendants = true) {},
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Spacing.S3.dp, Alignment.CenterVertically),
    ) {
        Text("Quiet, please. Recording the room.", style = MaterialTheme.typography.titleMedium)
        Text("$seconds", style = MaterialTheme.typography.displaySmall)
    }
}

/** Feeds the stateless recorder from the session's flows and carries its actions back to the session. */
@Composable
private fun Prompter(
    session: RecordingSession,
    index: Int,
    announcing: Boolean,
    onIndex: (Int) -> Unit,
    onAnnounced: () -> Unit,
    refusal: String?,
    loadWave: suspend (com.example.appname.plays.Take) -> FloatArray?,
    onClose: () -> Unit,
    onDone: () -> Unit,
    haptics: (Haptic) -> Unit,
) {
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val phase by session.phase.collectAsState()
    val production by session.production.collectAsState()
    val mode by session.mode.collectAsState()
    val run by session.run.collectAsState()
    val lines = session.lines
    if (lines.isEmpty()) {
        Text("No lines in this part.", Modifier.padding(Spacing.S6.dp), style = MaterialTheme.typography.bodyMedium)
        return
    }
    var rate by remember { mutableStateOf(session.standInRate) }
    val levels = remember { mutableStateListOf<Float>() }
    var seconds by remember { mutableIntStateOf(0) }
    val listening = phase is Phase.Listening
    LaunchedEffect(listening) {
        levels.clear()
        seconds = 0
        if (!listening) return@LaunchedEffect
        var elapsed = 0
        while (true) {
            delay(60)
            levels.add(session.level.value)
            if (levels.size > 48) levels.removeAt(0)
            elapsed += 60
            seconds = elapsed / 1_000
        }
    }
    LaunchedEffect(phase) {
        if (phase is Phase.Listening) haptics(Haptic.Selection) else onAnnounced()
    }
    // A run moves through the part's lines by itself: the screen follows the line being listened to, or the next own line after the cue.
    LaunchedEffect(phase, run) {
        val ph = phase
        if (run == null) return@LaunchedEffect
        val target = when {
            ph is Phase.Listening -> ph.lineID
            ph is Phase.Cue && ph.run -> {
                val at = session.script.lines.indexOfFirst { it.id == ph.lineID }
                lines.firstOrNull { l -> session.script.lines.indexOfFirst { it.id == l.id } > at }?.id
            }
            else -> null
        }
        target?.let { id -> onIndex(lines.indexOfFirst { it.id == id }) }
    }
    val at = index.coerceIn(0, lines.size - 1)
    val current = lines[at]
    val running = run != null && phase !is Phase.RunReview && phase !is Phase.Failed

    fun primary() {
        when {
            running -> session.pause()
            listening -> session.stopListening()
            phase is Phase.Cue -> session.cancel()
            session.isBusy -> Unit
            mode == Mode.Run -> scope.launch { session.runThrough(current.id) }
            else -> scope.launch { session.record(current.id) }
        }
    }
    fun keep() {
        if (session.isBusy) return
        if (at + 1 < lines.size) onIndex(at + 1) else session.setMode(mode)
    }
    val ui = RecorderUi(
        script = session.script,
        part = session.part,
        production = production,
        phase = phase,
        mode = mode,
        runTakes = session.runTakes().let { if (run == null) emptyList() else it },
        running = run != null,
        index = at,
        levels = levels.toList(),
        seconds = seconds,
        announcing = announcing,
        rate = rate,
        refusal = refusal,
    )
    val actions = RecorderActions(
        onClose = onClose,
        onMode = { if (session.setMode(it)) { it.remember(context); haptics(Haptic.Selection) } },
        onSelect = { onIndex(it); haptics(Haptic.Selection) },
        onMove = { step -> if (!session.isBusy) onIndex(at + step) },
        onRecord = { primary() },
        onStop = { primary() },
        onCancel = { primary() },
        onRunFrom = { primary() },
        onPause = { primary() },
        onKeep = { keep() },
        onAgain = { id -> scope.launch { session.record(id) } },
        onWithCue = { take -> scope.launch { session.playWithCue(take) } },
        onPlayTake = { take -> scope.launch { session.playTake(take) } },
        onChoose = { take -> session.choose(take) },
        onCue = { id -> scope.launch { session.playCue(id) } },
        onRunUp = { scope.launch { session.record(current.id, runUp = true) } },
        onHearRead = { scope.launch { session.hearItRead(current.id) } },
        onRate = { rate = it; session.standInRate = it },
        onKeepRun = { session.keepRun() },
        onDiscardRun = { session.discardRun() },
        onDone = onDone,
        loadWave = loadWave,
    )
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
    RecorderView(
        ui, actions,
        Modifier
            .focusRequester(focus)
            .focusable()
            .onPreviewKeyEvent { event ->
                if (event.type != KeyEventType.KeyDown) return@onPreviewKeyEvent false
                when (event.key) {
                    Key.Spacebar, Key.HeadsetHook, Key.MediaPlayPause -> { primary(); true }
                    Key.Enter, Key.NumPadEnter -> { if (phase is Phase.Review) keep(); true }
                    Key.DirectionLeft, Key.DirectionUp -> { if (!session.isBusy && run == null && at > 0) onIndex(at - 1); true }
                    Key.DirectionRight, Key.DirectionDown -> { if (!session.isBusy && run == null) onIndex(at + 1); true }
                    else -> false
                }
            },
    )
}
