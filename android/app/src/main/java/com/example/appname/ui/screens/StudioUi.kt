package com.example.appname.ui.screens

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.accessibility.AccessibilityManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Headphones
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.RadioButtonChecked
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.Replay
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import com.example.appname.BuildConfig
import com.example.appname.navigation.StudioDoor
import com.example.appname.plays.AudioRoute
import com.example.appname.plays.CueAudio
import com.example.appname.plays.DeviceLiveAudio
import com.example.appname.plays.LineEndDetector
import com.example.appname.plays.LiveAudio
import com.example.appname.plays.LiveListen
import com.example.appname.plays.MicrophoneCapture
import com.example.appname.plays.PartID
import com.example.appname.plays.PlayScript
import com.example.appname.plays.RecordingSession
import com.example.appname.plays.RecordingSession.Mode
import com.example.appname.plays.RecordingSession.Phase
import com.example.appname.plays.Relay
import com.example.appname.plays.StandInAudio
import com.example.appname.plays.StandInVoice
import com.example.appname.plays.StudioController
import com.example.appname.plays.StudioCore
import com.example.appname.plays.KokoroStandIn
import com.example.appname.plays.SystemStandInVoice
import com.example.appname.plays.Take
import com.example.appname.plays.TakeAudio
import com.example.appname.plays.VoiceCast
import com.example.appname.ui.CastHandle
import com.example.appname.ui.Haptic
import com.example.appname.ui.LocalAppContainer
import com.example.appname.ui.VoiceChip
import com.example.appname.ui.rememberHaptics
import com.example.appname.ui.theme.AppSemantics
import com.example.appname.ui.theme.OnAir
import com.example.appname.ui.theme.Spacing
import com.example.appname.ui.wayColors
import java.util.Locale
import kotlin.math.PI
import kotlin.math.sin
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// The studio inside the reader (PLAYS-DESIGN §2.9 binding; ANDROID-DESIGN §4.17; Decision 076 S3). One model, three homes:
// a dock under the page on a phone (the take list, cast and the rest in a bottom sheet), a supporting pane once the reader
// has 860 dp or more, and below the hinge in tabletop posture. The engine and the take model are the recorder's
// (RecordingSession, Production); StudioController moves the current line. Red is the record control's and the
// microphone's only (Decision 064).

/** Where the studio records: the production and the part (PLAYS-DESIGN §2.9 rule 1's one seam). */
data class StudioTarget(val production: String, val part: PartID)

enum class StudioGate { Ready, MicrophoneDenied, NeedsHeadphones }

@Stable
class StudioModel(
    val target: StudioTarget,
    val script: PlayScript,
    val session: RecordingSession,
    val studio: StudioController,
    val audio: LiveAudio,
    val stubbed: Boolean,
    private val voice: LazyStandIn?,
) {
    val part: PartID get() = target.part
    var gate by mutableStateOf(StudioGate.Ready)
    /** The phone's sheet: takes, cast, listen through, delete unused, done. */
    var sheet by mutableStateOf(false)
    var refusal by mutableStateOf<String?>(null)
    var confirmingUnused by mutableStateOf(false)
    var announcing by mutableStateOf(false)
    var pendingEcho = false
    var listen by mutableStateOf<LiveListen?>(null)
    private var listenJob: Job? = null
    var doorTaken = false
    var pendingDoor by mutableStateOf<String?>(null)

    /** The microphone is asked for before this, at Start recording, never at launch; the route is checked and refused (§4.3). */
    fun begin(echoCancelled: Boolean, scope: CoroutineScope, pause: () -> Unit) {
        if (audio.outputRoute() == AudioRoute.Speaker && !echoCancelled) {
            gate = StudioGate.NeedsHeadphones
            return
        }
        gate = StudioGate.Ready
        pause()
        scope.launch { session.begin(echoCancelled) }
    }

    /** Listen through from the current line: takes from their files, the rest in the cast's device voices, live; the reader follows. */
    fun listenFromHere(scope: CoroutineScope, handle: CastHandle, store: com.example.appname.plays.ProductionStore, muted: Boolean, follow: (String) -> Unit) {
        listen?.let { stopListen(); return }
        val production = session.production.value
        val at = script.lines.indexOfFirst { it.id == studio.current.value }.coerceAtLeast(0)
        val ids = script.lines.drop(at).map { it.id }.toSet()
        val plan = Relay.listenPlan(production, script) { !it.isSpeaking && handle.cast.resolve(it).read }.filter { it.lineID in ids }
        val live = LiveListen(store.takesFolder(production.id), handle.speaker).also { it.muted = muted }
        listen = live
        listenJob = scope.launch {
            val follower = launch { live.current.collect { it?.let { e -> follow(e.lineID) } } }
            try {
                live.run(plan)
            } finally {
                follower.cancel()
                if (listen === live) {
                    live.close()
                    listen = null
                    listenJob = null
                }
            }
        }
    }

    fun stopListen() {
        listenJob?.cancel()
        listen?.close()
        listen = null
        listenJob = null
    }

    /** Leaving the reader ends the session and closes the microphone, as leaving the recorder did. */
    fun close() {
        stopListen()
        session.end()
        voice?.close()
    }
}

/** The device voice for cues, built on first use (a text-to-speech engine is not started for a studio that never records). */
class LazyStandIn(
    private val context: Context,
    private val cast: VoiceCast,
    private val kokoro: com.example.appname.kokoro.KokoroReader? = null,
    private val playId: String = "",
) : StandInVoice {
    private var inner: SystemStandInVoice? = null
    private val system = object : StandInVoice {
        override suspend fun render(text: String, part: PartID, rate: Float): StandInAudio? =
            (inner ?: SystemStandInVoice(context, cast).also { inner = it }).render(text, part, rate)
    }
    private val downloaded = KokoroStandIn(cast, system) { text, id, speed -> kokoro?.render(playId, text, id, speed) }

    override suspend fun render(text: String, part: PartID, rate: Float): StandInAudio? = downloaded.render(text, part, rate)

    fun close() { inner?.close() }
}

private class SilentStandIn : StandInVoice {
    override suspend fun render(text: String, part: PartID, rate: Float): StandInAudio? = null
}

/**
 * DEBUG only (appname_studio_stub): opens no microphone and plays nothing. A line "heard" is a synthetic tone, never room
 * audio, so the take path can be seen working without anyone being recorded. [hold] keeps the tone going until Stop.
 */
private class StubLiveAudio(private val hold: Boolean) : LiveAudio {
    private val main = Handler(Looper.getMainLooper())
    private var ticker: Runnable? = null
    private var captures = 0
    private var heard = FloatArray(48_000 * 4)
    private var heardCount = 0

    override fun outputRoute() = AudioRoute.Headphones
    override fun start(echoCancelled: Boolean) {}
    override suspend fun play(cue: CueAudio) { delay(300) }
    override fun stop() { ticker?.let(main::removeCallbacks) }

    override fun beginCapture(onChunk: (FloatArray) -> Unit) {
        captures += 1
        heardCount = 0
        ticker?.let(main::removeCallbacks)
        if (captures == 1) return
        var n = 0
        val run = object : Runnable {
            override fun run() {
                val loud = n >= 10 && (hold || n < 60)
                val chunk = FloatArray(960) { i ->
                    if (!loud) 0f else {
                        val swell = 0.55f + 0.45f * sin(n * 0.35f)
                        0.12f * swell * sin(2 * PI * 160 * (n * 960 + i) / 48_000.0).toFloat()
                    }
                }
                n += 1
                if (heardCount + chunk.size > heard.size) heard = heard.copyOf(heard.size * 2)
                chunk.copyInto(heard, heardCount)
                heardCount += chunk.size
                onChunk(chunk)
                main.postDelayed(this, 20)
            }
        }
        ticker = run
        main.post(run)
    }

    override fun endCapture(): MicrophoneCapture {
        ticker?.let(main::removeCallbacks)
        ticker = null
        return MicrophoneCapture(heard.copyOf(heardCount), TakeAudio.SAMPLE_RATE.toDouble()).also { heardCount = 0 }
    }
}

@Composable
fun rememberStudio(target: StudioTarget?, script: PlayScript, line: String?, handle: CastHandle?): StudioModel? {
    val container = LocalAppContainer.current
    val context = LocalContext.current
    val muted = com.example.appname.navigation.LocalPlayerMuted.current
    val model = remember(target, script.id, handle) {
        if (target == null || handle == null) return@remember null
        val production = container.plays.store.production(target.production) ?: return@remember null
        val stub = BuildConfig.DEBUG && StudioDoor.stub
        val audio: LiveAudio = if (stub) StubLiveAudio(hold = StudioDoor.phase == "listening") else DeviceLiveAudio(context)
        val voice = if (stub) null else LazyStandIn(context, handle.cast, handle.kokoro, handle.playId)
        lateinit var holder: StudioModel
        val accessibility = context.getSystemService(AccessibilityManager::class.java)
        val session = RecordingSession(
            production, script, target.part, container.plays.store, audio, voice ?: SilentStandIn(),
            wait = if (stub) ({ delay(150) }) else ({ ms -> delay(ms) }),
            announce = {
                // TalkBack speaks through the speaker the microphone hears, so it says "Your line" before listening starts.
                if (accessibility?.isTouchExploration() == true) {
                    holder.announcing = true
                    delay(1_200)
                }
            },
        )
        session.setMode(Mode.remembered(context))
        val controller = StudioController(session, container.plays.store, line)
        StudioModel(target, script, session, controller, audio, stub, voice).also { holder = it }
    }
    if (model != null) {
        (model.audio as? DeviceLiveAudio)?.muted = muted
        DisposableEffect(model) {
            val id = model.target.production
            container.plays.store.hold(id)
            onDispose {
                model.close()
                container.plays.store.release(id)
                container.plays.leftStudio(id)
            }
        }
    }
    return model
}

private fun AccessibilityManager.isTouchExploration() = isTouchExplorationEnabled

// MARK: The dock (compact)

/** Under the page on a phone (§2.9 rule 6): the mode, one status row, the transport; before the first take, the gate. */
@Composable
fun StudioDock(model: StudioModel, onTakes: (String) -> Unit, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth().padding(horizontal = Spacing.S4.dp).padding(top = Spacing.S2.dp), verticalArrangement = Arrangement.spacedBy(Spacing.S1.dp)) {
        StudioControls(model, onTakes)
    }
}

/** The mode, the status row and the transport, or before the first take the gate. One composable for the dock and the pane. */
@Composable
fun StudioControls(model: StudioModel, onTakes: (String) -> Unit) {
    val session = model.session
    val phase by session.phase.collectAsState()
    // phase is read first, always: session.started is not state, so only the phase flow tells this composable to run again.
    val now = phase
    val started = session.started && now !is Phase.RoomTone && !(now is Phase.Failed && !session.started)
    if (!started) {
        StudioGateView(model)
        return
    }
    val haptics = rememberHaptics()
    val context = LocalContext.current
    val current by model.studio.current.collectAsState()
    val mode by session.mode.collectAsState()
    val run by session.run.collectAsState()
    val production by session.production.collectAsState()
    @Suppress("UNUSED_EXPRESSION") production
    LaunchedEffect(model.pendingDoor) {
        val door = model.pendingDoor ?: return@LaunchedEffect
        model.pendingDoor = null
        when (door) {
            "listening" -> {
                session.setMode(Mode.Lines)
                model.studio.primary()
            }
            "takes" -> model.sheet = true
        }
    }
    val locked = model.studio.locked
    ModeRow(mode, enabled = !locked) { m ->
        if (session.setMode(m)) { m.remember(context); haptics(Haptic.Selection) }
    }
    LaunchedEffect(phase is Phase.Listening) { if (phase is Phase.Listening) haptics(Haptic.Selection) }
    StudioStatus(model, phase, current, onTakes)
    StudioTransport(model, phase, mode, run != null, current)
}

private val ModeLabels = listOf(Mode.Run to "Run through", Mode.Lines to "Line by line", Mode.Step to "Step")

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ModeRow(mode: Mode, enabled: Boolean, onMode: (Mode) -> Unit) {
    val primary = MaterialTheme.colorScheme.primary
    val colors = SegmentedButtonDefaults.colors(
        activeContainerColor = primary,
        activeContentColor = MaterialTheme.colorScheme.onPrimary,
        activeBorderColor = primary,
        inactiveContainerColor = Color.Transparent,
        inactiveContentColor = primary,
        inactiveBorderColor = MaterialTheme.colorScheme.outline,
        disabledActiveContainerColor = primary,
        disabledActiveContentColor = MaterialTheme.colorScheme.onPrimary,
        disabledActiveBorderColor = primary,
        disabledInactiveContainerColor = Color.Transparent,
        disabledInactiveContentColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
        disabledInactiveBorderColor = MaterialTheme.colorScheme.outline,
    )
    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
        ModeLabels.forEachIndexed { i, (m, label) ->
            SegmentedButton(
                selected = mode == m,
                onClick = { onMode(m) },
                shape = SegmentedButtonDefaults.itemShape(i, ModeLabels.size),
                enabled = enabled,
                colors = colors,
                icon = {},
                label = { Text(label, style = MaterialTheme.typography.labelMedium, maxLines = 1, overflow = TextOverflow.Ellipsis) },
            )
        }
    }
}

// MARK: The gate

@Composable
private fun StudioGateView(model: StudioModel) {
    val container = LocalAppContainer.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val phase by model.session.phase.collectAsState()

    fun begin(echo: Boolean) {
        model.begin(echo, scope) { if (container.playback.state.value.isPlaying) container.playback.togglePlay() }
    }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) begin(model.pendingEcho) else model.gate = StudioGate.MicrophoneDenied
    }
    fun start(echo: Boolean) {
        model.pendingEcho = echo
        if (model.stubbed || ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            begin(echo)
        } else {
            permission.launch(Manifest.permission.RECORD_AUDIO)
        }
    }
    LaunchedEffect(model) { model.openDoor { start(false) } }

    Column(
        Modifier.fillMaxWidth().padding(vertical = Spacing.S2.dp).semantics(mergeDescendants = false) { contentDescription = "Studio" },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Spacing.S2.dp),
    ) {
        val p = phase
        when {
            p is Phase.RoomTone -> Row(
                Modifier.semantics(mergeDescendants = true) {},
                horizontalArrangement = Arrangement.spacedBy(Spacing.S3.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("Quiet, please. Recording the room.", style = MaterialTheme.typography.titleMedium)
                Text("${p.secondsLeft}", style = MaterialTheme.typography.displaySmall)
            }
            else -> when (model.gate) {
                StudioGate.Ready -> {
                    Button(onClick = { start(false) }, colors = com.example.appname.ui.recordButtonColors()) {
                        Icon(Icons.Filled.Mic, contentDescription = null)
                        Text("Start recording", Modifier.padding(start = Spacing.S2.dp))
                    }
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.S1.dp)) {
                        Icon(Icons.Filled.Headphones, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(18.dp))
                        Text("Headphones on", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                StudioGate.MicrophoneDenied -> {
                    Text("Ear Drama needs the microphone to record your part.", textAlign = TextAlign.Center, style = MaterialTheme.typography.bodyMedium, color = AppSemantics.colors.error)
                    OutlinedButton(onClick = {
                        context.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null)))
                    }, colors = wayColors()) { Text("Open settings") }
                }
                StudioGate.NeedsHeadphones -> {
                    Text("Plug in headphones.", textAlign = TextAlign.Center, style = MaterialTheme.typography.bodyMedium, color = AppSemantics.colors.error)
                    Row(horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
                        Button(onClick = { start(false) }) { Text("Check again") }
                        TextButton(onClick = { start(true) }) { Text("Record without headphones") }
                    }
                }
            }
        }
        (p as? Phase.Failed)?.let {
            Text(it.message, textAlign = TextAlign.Center, style = MaterialTheme.typography.bodySmall, color = AppSemantics.colors.error)
        }
    }
}

/** APP door `appname_studio_phase` with the stub engine only (DEBUG): the studio starts, then a take opens or the list shows. */
private fun StudioModel.openDoor(start: () -> Unit) {
    val phase = StudioDoor.phase
    if (!BuildConfig.DEBUG || !stubbed || doorTaken || phase == null || phase == "gate") return
    doorTaken = true
    start()
    pendingDoor = phase
}

// MARK: Status

private fun clock(seconds: Int) = String.format(Locale.US, "%d:%02d", seconds / 60, seconds % 60)

@Composable
private fun StudioStatus(model: StudioModel, phase: Phase, current: String?, onTakes: (String) -> Unit) {
    val session = model.session
    val record = OnAir.colors.record
    val listening = phase is Phase.Listening
    val levels = remember { mutableStateListOf<Float>() }
    var seconds by remember { mutableIntStateOf(0) }
    LaunchedEffect(listening) {
        levels.clear()
        seconds = 0
        if (!listening) return@LaunchedEffect
        var elapsed = 0
        while (true) {
            delay(60)
            levels.add(session.level.value)
            if (levels.size > 24) levels.removeAt(0)
            elapsed += 60
            seconds = elapsed / 1_000
        }
    }
    LaunchedEffect(phase) { if (!listening) model.announcing = false }
    Row(Modifier.fillMaxWidth().heightIn(min = 40.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.S3.dp)) {
        when {
            phase is Phase.Failed -> Text(phase.message, style = MaterialTheme.typography.bodySmall, color = AppSemantics.colors.error)
            model.announcing && !listening -> Text(
                "Your line", style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite },
            )
            listening -> {
                Box(Modifier.size(10.dp).clip(CircleShape).background(record))
                Text(
                    "Recording ${clock(seconds)}", style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.SemiBold), color = record,
                    modifier = Modifier.semantics { contentDescription = "Recording ${clock(seconds)}" },
                )
                LevelMeter(levels.toList(), record, Modifier.weight(1f))
            }
            phase is Phase.Cue -> {
                val line = model.script.lines.firstOrNull { it.id == phase.lineID }
                val hue = line?.let { com.example.appname.ui.theme.genreColor(model.script.partHue(it.part), OnAir.colors.dark) }
                Text(
                    line?.part?.title.orEmpty(), style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.SemiBold),
                    color = hue ?: MaterialTheme.colorScheme.onSurface, maxLines = 1, overflow = TextOverflow.Ellipsis,
                )
                if (phase.deviceVoice) Text("Device voice", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            else -> {
                val place = model.studio.place
                Text("Line ${place.first} of ${place.second}", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Box(Modifier.weight(1f))
                val state = current?.let { model.studio.lineState(it) }
                if (state != null) TakesButton(state, model, onClick = { onTakes(current) })
            }
        }
    }
}

@Composable
private fun TakesButton(state: StudioCore.LineState, model: StudioModel, onClick: () -> Unit) {
    val flagged = state.state == StudioCore.LineState.Kind.Flagged
    val hue = com.example.appname.ui.theme.genreColor(model.script.partHue(model.part), OnAir.colors.dark) ?: MaterialTheme.colorScheme.primary
    val tone = if (flagged) AppSemantics.colors.warning else hue
    OutlinedButton(
        onClick = onClick,
        colors = ButtonDefaults.outlinedButtonColors(contentColor = tone),
        contentPadding = ButtonDefaults.ButtonWithIconContentPadding,
        modifier = Modifier.heightIn(min = 40.dp).semantics { contentDescription = StudioCore.spoken(state) },
    ) {
        Icon(
            when (state.state) {
                StudioCore.LineState.Kind.None -> Icons.Filled.RadioButtonUnchecked
                StudioCore.LineState.Kind.Flagged -> Icons.Filled.Warning
                StudioCore.LineState.Kind.Chosen -> Icons.Filled.RadioButtonChecked
            },
            contentDescription = null, modifier = Modifier.size(18.dp),
        )
        Text(StudioCore.takesLabel(state), Modifier.padding(start = Spacing.S2.dp), maxLines = 1, style = MaterialTheme.typography.labelMedium)
    }
}

/** The live level while a line is taken: record-red bars, the newest at the right. */
@Composable
private fun LevelMeter(levels: List<Float>, red: Color, modifier: Modifier = Modifier) {
    Canvas(modifier.height(28.dp).clearAndSetSemantics {}) {
        val n = 24
        val gap = 2.dp.toPx()
        val w = (size.width - gap * (n - 1)) / n
        val shown = levels.takeLast(n)
        val off = n - shown.size
        for (i in 0 until n) {
            val v = if (i >= off) shown[i - off] else 0f
            val h = maxOf(3.dp.toPx(), size.height * v)
            drawRect(red, Offset(i * (w + gap), (size.height - h) / 2), Size(w, h))
        }
    }
}

// MARK: Transport

/** Previous, the one round control, Next; Step's review Again, With cue, Keep; a run's review Discard or Keep N. */
@Composable
private fun StudioTransport(model: StudioModel, phase: Phase, mode: Mode, running: Boolean, current: String?) {
    val session = model.session
    val studio = model.studio
    val scope = rememberCoroutineScope()
    val padded = Modifier.padding(bottom = Spacing.S2.dp)
    when {
        phase is Phase.Review -> Row(padded.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
            OutlinedButton(onClick = { scope.launch { studio.again(phase.lineID) } }, modifier = Modifier.weight(1f), colors = wayColors(), contentPadding = ButtonDefaults.TextButtonContentPadding) {
                Icon(Icons.Filled.Replay, contentDescription = null, modifier = Modifier.size(18.dp))
                Text("Again", Modifier.padding(start = Spacing.S1.dp), maxLines = 1)
            }
            OutlinedButton(
                onClick = { session.production.value.chosenTake(phase.lineID)?.let { t -> scope.launch { session.playWithCue(t) } } },
                modifier = Modifier.weight(1f), colors = wayColors(), contentPadding = ButtonDefaults.TextButtonContentPadding,
            ) {
                Icon(Icons.Filled.PlayArrow, contentDescription = null, modifier = Modifier.size(18.dp))
                Text("With cue", Modifier.padding(start = Spacing.S1.dp), maxLines = 1)
            }
            Button(onClick = { studio.keep() }, modifier = Modifier.weight(1f), colors = inkColors(), contentPadding = ButtonDefaults.TextButtonContentPadding) {
                Icon(Icons.Filled.Check, contentDescription = null, modifier = Modifier.size(18.dp))
                Text("Keep", Modifier.padding(start = Spacing.S1.dp), maxLines = 1)
            }
        }
        phase is Phase.RunReview -> {
            val n = session.runTakes().size
            Row(padded.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
                OutlinedButton(onClick = { session.discardRun() }, modifier = Modifier.weight(1f), colors = wayColors(), contentPadding = ButtonDefaults.TextButtonContentPadding) {
                    Text("Discard the run", maxLines = 1)
                }
                Button(onClick = { studio.keep() }, modifier = Modifier.weight(1f), colors = inkColors(), contentPadding = ButtonDefaults.TextButtonContentPadding) {
                    Icon(Icons.Filled.Check, contentDescription = null, modifier = Modifier.size(18.dp))
                    Text("Keep $n ${if (n == 1) "take" else "takes"}", Modifier.padding(start = Spacing.S1.dp), maxLines = 1)
                }
            }
        }
        else -> {
            val listening = phase is Phase.Listening
            val cueing = phase is Phase.Cue
            val (label, icon, red) = when {
                running && listening -> Triple("Stop", Icons.Filled.Stop, true)
                running -> Triple("Pause", Icons.Filled.Pause, false)
                listening -> Triple("Stop", Icons.Filled.Stop, true)
                cueing -> Triple("Cancel", Icons.Filled.Close, false)
                mode == Mode.Run -> Triple("From here", Icons.Filled.Mic, true)
                else -> Triple("Record", Icons.Filled.Mic, true)
            }
            val mine = studio.mine
            val locked = studio.locked
            Row(padded.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = { move(model, -1) }, enabled = !locked && current != mine.firstOrNull()) {
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, contentDescription = "Previous line")
                }
                Box(Modifier.weight(1f))
                RoundControl(
                    label = label, icon = icon,
                    container = if (red) OnAir.colors.record else OnAir.colors.play,
                    content = if (red) OnAir.colors.onRecord else OnAir.colors.onPlay,
                    enabled = !(session.isBusy && !listening && !cueing && !running),
                    onClick = { scope.launch { studio.primary() } },
                )
                Box(Modifier.weight(1f))
                IconButton(onClick = { move(model, 1) }, enabled = !locked && current != mine.lastOrNull()) {
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = "Next line")
                }
            }
        }
    }
}

private fun move(model: StudioModel, delta: Int) {
    if (model.studio.move(delta)) model.studio.current.value?.let { model.studio.onFollow?.invoke(it) }
}

@Composable
private fun inkColors() = ButtonDefaults.buttonColors(containerColor = OnAir.colors.play, contentColor = OnAir.colors.onPlay)

/** The round record control, 52 dp: Record (From here in Run through), Stop while the microphone is open, Cancel in ink while a cue plays, Pause during a run. */
@Composable
private fun RoundControl(label: String, icon: androidx.compose.ui.graphics.vector.ImageVector, container: Color, content: Color, enabled: Boolean, onClick: () -> Unit) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Box(
            Modifier
                .size(52.dp)
                .clip(CircleShape)
                .background(if (enabled) container else container.copy(alpha = 0.4f))
                .clickable(enabled = enabled, role = Role.Button, onClickLabel = label, onClick = onClick)
                .semantics { contentDescription = label },
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, contentDescription = null, tint = content, modifier = Modifier.size(26.dp))
        }
        Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

// MARK: The panel (the sheet, the pane)

/** The panel in a bottom sheet on a phone, from the Studio button or a line's takes (§2.9 rule 7). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StudioSheet(model: StudioModel, handle: CastHandle?, muted: Boolean, onPickVoice: (PartID) -> Unit, onFollow: (String) -> Unit, onDone: () -> Unit) {
    ModalBottomSheet(
        onDismissRequest = { model.sheet = false },
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = false),
    ) {
        StudioPanel(model, handle, muted, full = false, onPickVoice = onPickVoice, onFollow = onFollow, onDone = onDone, onTakes = {})
    }
}

/**
 * Takes for the current line, the cast, Listen through from here, Delete unused takes, Done with this part and the keys. [full]
 * (the pane, below the hinge) adds the mode, status and transport, since there is no dock there.
 */
@Composable
fun StudioPanel(
    model: StudioModel,
    handle: CastHandle?,
    muted: Boolean,
    full: Boolean,
    onPickVoice: (PartID) -> Unit,
    onFollow: (String) -> Unit,
    onDone: () -> Unit,
    onTakes: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val container = LocalAppContainer.current
    val scope = rememberCoroutineScope()
    val studio = model.studio
    val session = model.session
    val phase by session.phase.collectAsState()
    val production by session.production.collectAsState()
    val current by studio.current.collectAsState()
    val run by session.run.collectAsState()
    @Suppress("UNUSED_EXPRESSION") production
    val hue = com.example.appname.ui.theme.genreColor(model.script.partHue(model.part), OnAir.colors.dark) ?: MaterialTheme.colorScheme.onSurface
    val shared = remember(model) { container.sharing.linkOf(model.target.production) != null }
    val started = phase.let { session.started && it !is Phase.RoomTone }
    val missing = Relay.missingLines(model.part, production, model.script).size
    val unused = studio.unused
    val keyboard = hasKeyboard()

    LazyColumn(modifier.fillMaxWidth().navigationBarsPadding(), contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = Spacing.S4.dp)) {
        item(key = "head") {
            Row(Modifier.fillMaxWidth().padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    model.part.title, style = MaterialTheme.typography.headlineSmall, color = hue, maxLines = 1,
                    overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f).semantics { heading() },
                )
                Text("${studio.kept} of ${studio.mine.size}", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        if (full) {
            item(key = "controls") {
                Column(Modifier.padding(horizontal = Spacing.S4.dp), verticalArrangement = Arrangement.spacedBy(Spacing.S1.dp)) {
                    StudioControls(model, onTakes)
                }
            }
        }
        if (phase is Phase.RunReview) {
            item(key = "run-h") { PanelHeader("This run") }
            items(session.runTakes(), key = { "run-" + it.id }) { take ->
                Row(Modifier.fillMaxWidth().padding(horizontal = Spacing.S4.dp).heightIn(min = 52.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text("Line ${(studio.mine.indexOf(take.lineID) + 1)}", Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
                    Text(seconds(take), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    IconButton(onClick = { scope.launch { session.playWithCue(take) } }, enabled = !session.isBusy) {
                        Icon(Icons.Filled.PlayArrow, contentDescription = "Play line ${studio.mine.indexOf(take.lineID) + 1} with its cue")
                    }
                    TextButton(onClick = { scope.launch { studio.again(take.lineID) } }, enabled = !session.isBusy) { Text("Again") }
                }
            }
        } else if (current != null) {
            val line = current!!
            val takes = production.takes(line)
            item(key = "takes-h") { PanelHeader("Takes · Line ${studio.mine.indexOf(line) + 1}") }
            if (takes.isEmpty()) {
                item(key = "no-takes") {
                    Text("No take", Modifier.padding(horizontal = Spacing.S4.dp, vertical = Spacing.S1.dp), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            items(takes.size, key = { "take-" + takes[it].id }) { n ->
                val take = takes[n]
                TakeRow(model, take, n + 1, production.chosen[line] == take.id, hue, started)
            }
            item(key = "again") {
                OutlinedButton(
                    onClick = { scope.launch { studio.again(line) } },
                    enabled = started && !session.isBusy && run == null,
                    modifier = Modifier.padding(horizontal = Spacing.S4.dp),
                    colors = wayColors(),
                ) {
                    Icon(Icons.Filled.Mic, contentDescription = null, modifier = Modifier.size(18.dp))
                    Text(if (takes.isEmpty()) "Record" else "Record again", Modifier.padding(start = Spacing.S2.dp))
                }
            }
        }
        item(key = "cast-h") { PanelHeader("Cast") }
        items(model.script.castParts, key = { "cast-" + it.id.raw }) { p ->
            Row(Modifier.fillMaxWidth().padding(horizontal = Spacing.S4.dp, vertical = Spacing.S1.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
                Text(p.title, Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                if (p.id == model.part) {
                    Text("You", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                } else if (handle != null) {
                    VoiceChip(handle, p.id, onClick = { onPickVoice(p.id) }, modifier = Modifier.weight(1.2f))
                }
            }
        }
        item(key = "actions") {
            Column(Modifier.padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp), verticalArrangement = Arrangement.spacedBy(Spacing.S1.dp)) {
                HorizontalDivider()
                if (handle != null) {
                    TextButton(
                        onClick = {
                            if (container.playback.state.value.isPlaying) container.playback.togglePlay()
                            model.listenFromHere(scope, handle, container.plays.store, muted, onFollow)
                        },
                        enabled = !session.isBusy,
                    ) {
                        Icon(if (model.listen != null) Icons.Filled.Stop else Icons.Filled.PlayArrow, contentDescription = null, modifier = Modifier.size(18.dp))
                        Text(if (model.listen != null) "Stop listening" else "Listen through from here", Modifier.padding(start = Spacing.S2.dp))
                    }
                }
                if (unused.isNotEmpty()) {
                    TextButton(onClick = { model.confirmingUnused = true }, enabled = !studio.locked, colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error)) {
                        Icon(Icons.Filled.Delete, contentDescription = null, modifier = Modifier.size(18.dp))
                        Text("Delete unused takes", Modifier.padding(start = Spacing.S2.dp))
                    }
                }
                if (!shared) {
                    OutlinedButton(onClick = onDone, enabled = !studio.locked && missing == 0, modifier = Modifier.fillMaxWidth()) { Text("Done with this part") }
                    if (missing > 0) {
                        Text(
                            if (missing == 1) "1 line to go" else "$missing lines to go",
                            style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
                model.refusal?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = AppSemantics.colors.error) }
            }
        }
        if (keyboard) {
            item(key = "keys-h") { PanelHeader("Keys") }
            item(key = "keys") {
                Column(Modifier.padding(horizontal = Spacing.S4.dp), verticalArrangement = Arrangement.spacedBy(Spacing.S1.dp)) {
                    KeyHint("Space", "Record, stop or cancel")
                    KeyHint("J  K", "My next or previous line")
                    KeyHint("R", "Record again")
                    KeyHint("Enter", "Keep")
                }
            }
        }
    }
    if (model.confirmingUnused) {
        val n = unused.size
        AlertDialog(
            onDismissRequest = { model.confirmingUnused = false },
            title = { Text(if (n == 1) "Delete 1 unused take?" else "Delete $n unused takes?") },
            text = { Text("The chosen take of each line stays.") },
            confirmButton = {
                TextButton(onClick = { studio.deleteUnused(); model.confirmingUnused = false }) { Text("Delete") }
            },
            dismissButton = { TextButton(onClick = { model.confirmingUnused = false }) { Text("Cancel") } },
        )
    }
}

@Composable
private fun hasKeyboard(): Boolean = LocalConfiguration.current.keyboard != Configuration.KEYBOARD_NOKEYS

@Composable
private fun PanelHeader(text: String) {
    Text(
        text, Modifier.padding(horizontal = Spacing.S4.dp).padding(top = Spacing.S3.dp, bottom = Spacing.S1.dp).semantics { heading() },
        style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

@Composable
private fun KeyHint(key: String, action: String) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
        Text(
            key, Modifier.clip(androidx.compose.foundation.shape.RoundedCornerShape(4.dp)).background(MaterialTheme.colorScheme.surfaceContainerHigh).padding(horizontal = 6.dp, vertical = 2.dp),
            style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.SemiBold, fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace),
        )
        Text(action, style = MaterialTheme.typography.labelMedium)
    }
}

private fun seconds(take: Take) = String.format(Locale.US, "%.1f s", take.seconds)

/** One take: choose it (a radio), "Take 2" over its length, Play, With cue, and Delete on an unchosen take only. */
@Composable
private fun TakeRow(model: StudioModel, take: Take, number: Int, chosen: Boolean, hue: Color, started: Boolean) {
    val session = model.session
    val scope = rememberCoroutineScope()
    val busy = session.isBusy
    Row(
        Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(start = Spacing.S4.dp, end = Spacing.S1.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(
            Modifier.weight(1f).heightIn(min = 48.dp)
                .selectable(selected = chosen, role = Role.RadioButton, onClick = { model.studio.choose(take) })
                .semantics { contentDescription = "Take $number" },
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                if (chosen) Icons.Filled.RadioButtonChecked else Icons.Filled.RadioButtonUnchecked,
                contentDescription = null, tint = if (chosen) hue else MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Column(Modifier.padding(start = Spacing.S3.dp)) {
                Text("Take $number", style = MaterialTheme.typography.titleMedium, maxLines = 1)
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.S1.dp)) {
                    Text(seconds(take), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    if (take.bleed) {
                        Icon(Icons.Filled.Warning, contentDescription = null, tint = AppSemantics.colors.warning, modifier = Modifier.size(14.dp))
                        Text("Re-take", style = MaterialTheme.typography.labelMedium, color = AppSemantics.colors.warning)
                    }
                }
            }
        }
        IconButton(onClick = { scope.launch { session.playTake(take) } }, enabled = started && !busy) {
            Icon(Icons.Filled.PlayArrow, contentDescription = "Play take $number")
        }
        TextButton(onClick = { scope.launch { session.playWithCue(take) } }, enabled = started && !busy, contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 8.dp)) {
            Text("With cue", maxLines = 1)
        }
        if (!chosen) {
            IconButton(onClick = { model.studio.deleteTake(take) }, enabled = !busy) {
                Icon(Icons.Filled.Delete, contentDescription = "Delete take $number")
            }
        } else {
            Box(Modifier.size(48.dp))
        }
    }
}
