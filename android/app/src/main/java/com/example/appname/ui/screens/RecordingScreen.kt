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
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.FiberManualRecord
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Headphones
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import com.example.appname.plays.DeviceLiveAudio
import com.example.appname.plays.LinePart
import com.example.appname.plays.PartID
import com.example.appname.plays.Production
import com.example.appname.plays.RecordingSession
import com.example.appname.plays.RecordingSession.Phase
import com.example.appname.plays.Relay
import com.example.appname.plays.ScriptLine
import com.example.appname.plays.SystemStandInVoice
import com.example.appname.plays.Take
import com.example.appname.plays.AudioRoute
import com.example.appname.ui.Haptic
import com.example.appname.ui.LocalAppContainer
import com.example.appname.ui.rememberHaptics
import com.example.appname.ui.theme.AppSemantics
import com.example.appname.ui.theme.Spacing
import java.util.Locale
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private enum class Preflight { Ready, MicrophoneDenied, NeedsHeadphones }

/**
 * Recording one part, line by line (PLAYS-DESIGN §2.3-2.4): the cue line as it
 * plays (labeled when the device voice reads it), the performer's line large,
 * the next one dim, and one record control. A keyboard or remote drives it
 * too: Space or the headset key records or stops, Enter keeps the take and
 * moves on, the arrow keys move by line (§7).
 */
@Composable
fun RecordingScreen(productionId: String, part: PartID, onBack: () -> Unit) {
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
        session = s
        index = s.lines.indexOfFirst { it.id !in production.chosen }.coerceAtLeast(0)
        scope.launch { s.begin(echoCancelled) }
    }

    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) begin(pendingEcho) else preflight = Preflight.MicrophoneDenied
    }

    fun start(echoCancelled: Boolean) {
        pendingEcho = echoCancelled
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            begin(echoCancelled)
        } else {
            permission.launch(Manifest.permission.RECORD_AUDIO)
        }
    }

    Scaffold(topBar = { BackBar(onBack, part.title) }) { padding ->
        val s = session
        val phase = s?.phase?.collectAsState()?.value
        Column(Modifier.fillMaxSize().padding(padding)) {
            when {
                phase is Phase.RoomTone -> RoomTone(phase.secondsLeft)
                s != null && s.started -> Prompter(
                    session = s,
                    index = index,
                    announcing = announcing,
                    onMove = { step -> index = (index + step).coerceIn(0, (s.lines.size - 1).coerceAtLeast(0)) },
                    onAnnounced = { announcing = false },
                    refusal = refusal,
                    onDone = {
                        val latest = plays.store.production(productionId)
                        if (latest != null) {
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
        when (preflight) {
            Preflight.Ready -> {
                Icon(Icons.Filled.Headphones, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(48.dp))
                Button(onClick = onStart) {
                    Icon(Icons.Filled.Mic, contentDescription = null)
                    Text("Start recording", Modifier.padding(start = Spacing.S2.dp))
                }
            }
            Preflight.MicrophoneDenied -> {
                Text("Ear Drama needs the microphone to record your part.", textAlign = TextAlign.Center, style = MaterialTheme.typography.bodyMedium)
                OutlinedButton(onClick = onSettings) { Text("Open settings") }
            }
            Preflight.NeedsHeadphones -> {
                Text(
                    "Plug in headphones so the device voice stays out of your recording.",
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

@Composable
private fun Prompter(
    session: RecordingSession,
    index: Int,
    announcing: Boolean,
    onMove: (Int) -> Unit,
    onAnnounced: () -> Unit,
    refusal: String?,
    onDone: () -> Unit,
    haptics: (Haptic) -> Unit,
) {
    val scope = rememberCoroutineScope()
    val phase by session.phase.collectAsState()
    val production by session.production.collectAsState()
    val lines = session.lines
    if (lines.isEmpty()) {
        Text("No lines in this part.", Modifier.padding(Spacing.S6.dp), style = MaterialTheme.typography.bodyMedium)
        return
    }
    val current = lines[index.coerceIn(0, lines.size - 1)]
    val listening = phase == Phase.Listening(current.id)
    val busy = session.isBusy
    LaunchedEffect(phase) {
        if (phase is Phase.Listening) haptics(Haptic.Selection) else onAnnounced()
    }
    fun record() {
        if (listening) session.stopListening() else if (!busy) scope.launch { session.record(current.id) }
    }
    fun keep() {
        if (!busy && production.chosen[current.id] != null && index + 1 < lines.size) onMove(1)
    }
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
    Column(
        Modifier
            .fillMaxSize()
            .focusRequester(focus)
            .focusable()
            .onPreviewKeyEvent { event ->
                if (event.type != KeyEventType.KeyDown) return@onPreviewKeyEvent false
                when (event.key) {
                    Key.Spacebar, Key.HeadsetHook, Key.MediaPlayPause -> { record(); true }
                    Key.Enter, Key.NumPadEnter -> { keep(); true }
                    Key.DirectionLeft -> { if (!busy && index > 0) onMove(-1); true }
                    Key.DirectionRight -> { if (!busy) onMove(1); true }
                    else -> false
                }
            }
            .padding(Spacing.S4.dp),
        verticalArrangement = Arrangement.spacedBy(Spacing.S4.dp),
    ) {
        Cue(session, phase, current, announcing)
        Column(
            Modifier.weight(1f).fillMaxWidth().widthIn(max = 720.dp).verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(Spacing.S4.dp),
        ) {
            LineText(current, large = true)
            lines.getOrNull(index + 1)?.let { LineText(it, Modifier.alpha(0.45f)) }
        }
        Takes(session, production, phase, current)
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = { onMove(-1) }, enabled = index > 0 && !busy) {
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, contentDescription = "Previous line")
            }
            Spacer(Modifier.weight(1f))
            IconButton(onClick = { record() }, enabled = listening || !busy, modifier = Modifier.size(72.dp)) {
                Icon(
                    if (listening) Icons.Filled.Stop else Icons.Filled.FiberManualRecord,
                    contentDescription = if (listening) "Stop" else "Record",
                    tint = AppSemantics.colors.error,
                    modifier = Modifier.size(56.dp),
                )
            }
            Spacer(Modifier.weight(1f))
            IconButton(onClick = { onMove(1) }, enabled = index + 1 < lines.size && !busy) {
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = "Next line")
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
            TextButton(onClick = { scope.launch { session.record(current.id, runUp = true) } }, enabled = !busy) { Text("Run-up") }
            TextButton(onClick = { scope.launch { session.hearItRead(current.id) } }, enabled = !busy) { Text("Hear it read") }
            SpeedMenu(session)
            Spacer(Modifier.weight(1f))
            TextButton(onClick = { keep() }, enabled = !busy && production.chosen[current.id] != null && index + 1 < lines.size) {
                Text("Keep")
            }
        }
        val missing = Relay.missingLines(session.part, production, session.script).size
        OutlinedButton(onClick = onDone, enabled = !busy && !(session.part.isSpeaking && missing > 0), modifier = Modifier.fillMaxWidth()) {
            Text("Done with this part")
        }
        if (session.part.isSpeaking && missing > 0) {
            Text(if (missing == 1) "1 line to go" else "$missing lines to go", style = MaterialTheme.typography.labelMedium)
        }
        refusal?.let { ErrorLine(it) }
        (phase as? Phase.Failed)?.let { ErrorLine(it.message) }
    }
}

/** The line that cues this one, with its speaker, labeled whenever the device voice reads it, so a stand-in never passes as a person. */
@Composable
private fun Cue(session: RecordingSession, phase: Phase, line: ScriptLine, announcing: Boolean) {
    when {
        phase is Phase.Listening || announcing -> Row(
            Modifier.semantics(mergeDescendants = true) { liveRegion = LiveRegionMode.Polite },
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Filled.Mic, contentDescription = null, tint = AppSemantics.colors.error)
            Text("Your line", Modifier.padding(start = Spacing.S2.dp), style = MaterialTheme.typography.titleMedium, color = AppSemantics.colors.error)
        }
        phase is Phase.Cue -> session.script.lines.firstOrNull { it.id == phase.lineID }?.let { cue ->
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.S1.dp)) {
                if (phase.deviceVoice) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Filled.GraphicEq, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                        Text("Device voice", Modifier.padding(start = Spacing.S1.dp), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
                    }
                }
                LineText(cue)
            }
        }
        else -> Relay.cueLines(line.id, session.script, runUp = false).lastOrNull()?.let { LineText(it, Modifier.alpha(0.6f)) }
    }
}

@Composable
private fun Takes(session: RecordingSession, production: Production, phase: Phase, line: ScriptLine) {
    val scope = rememberCoroutineScope()
    val takes = production.takes(line.id)
    if (takes.isEmpty()) return
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.S1.dp)) {
        if (session.lastTakeBleed && phase == Phase.Review(line.id)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Outlined.WarningAmber, contentDescription = null, tint = AppSemantics.colors.warning)
                Text(
                    "The device voice is in this take. Re-take it with headphones.",
                    Modifier.padding(start = Spacing.S2.dp),
                    style = MaterialTheme.typography.labelMedium,
                    color = AppSemantics.colors.warning,
                )
            }
        }
        takes.forEachIndexed { number, take ->
            TakeRow(number, take, chosen = production.chosen[line.id] == take.id, busy = session.isBusy,
                onPlay = { scope.launch { session.playTake(take) } }, onChoose = { session.choose(take) })
        }
    }
}

@Composable
private fun TakeRow(number: Int, take: Take, chosen: Boolean, busy: Boolean, onPlay: () -> Unit, onChoose: () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        TextButton(onClick = onPlay, enabled = !busy) {
            Icon(Icons.Filled.PlayCircle, contentDescription = null)
            Text("Take ${number + 1}", Modifier.padding(start = Spacing.S2.dp))
        }
        Text(String.format(Locale.US, "%.1f s", take.seconds), style = MaterialTheme.typography.bodySmall)
        Spacer(Modifier.weight(1f))
        if (chosen) {
            Icon(Icons.Filled.CheckCircle, contentDescription = "Chosen", tint = MaterialTheme.colorScheme.primary)
        } else {
            TextButton(onClick = onChoose, enabled = !busy) { Text("Use this take") }
        }
    }
}

@Composable
private fun SpeedMenu(session: RecordingSession) {
    var open by remember { mutableStateOf(false) }
    var rate by remember { mutableFloatStateOf(session.standInRate) }
    IconButton(onClick = { open = true }) { Icon(Icons.Filled.Speed, contentDescription = "Device voice speed") }
    DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
        listOf("Slower" to 0.8f, "Normal" to 1f, "Faster" to 1.2f).forEach { (label, value) ->
            DropdownMenuItem(
                text = { Text(label) },
                leadingIcon = { if (rate == value) Icon(Icons.Filled.Check, contentDescription = null) },
                onClick = {
                    rate = value
                    session.standInRate = value
                    open = false
                },
            )
        }
    }
}

/** A script line with its printed directions kept apart from the words said (§3, Decision 059); nothing is rewritten. */
@Composable
private fun LineText(line: ScriptLine, modifier: Modifier = Modifier, large: Boolean = false) {
    val style = if (large) MaterialTheme.typography.headlineSmall else MaterialTheme.typography.bodyMedium
    val muted = MaterialTheme.colorScheme.onSurfaceVariant
    Column(modifier.semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(Spacing.S1.dp)) {
        line.role?.let { Text(it, style = MaterialTheme.typography.labelMedium, color = muted) }
        if (line.kind == ScriptLine.Kind.Speech) {
            val text = androidx.compose.ui.text.buildAnnotatedString {
                line.parts.orEmpty().forEachIndexed { i, piece ->
                    if (i > 0) append(" ")
                    if (piece is LinePart.Say) {
                        append(piece.text)
                    } else {
                        pushStyle(androidx.compose.ui.text.SpanStyle(fontStyle = FontStyle.Italic, color = muted))
                        append("(${piece.text})")
                        pop()
                    }
                }
            }
            Text(text, style = style)
        } else {
            Text(line.source.orEmpty(), style = style, fontStyle = FontStyle.Italic, color = muted)
        }
    }
}
