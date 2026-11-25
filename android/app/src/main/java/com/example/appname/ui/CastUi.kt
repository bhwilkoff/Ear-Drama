package com.example.appname.ui

import android.content.ActivityNotFoundException
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.selection.selectable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedIconButton
import androidx.compose.material3.RadioButton
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
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.example.appname.BuildConfig
import com.example.appname.kokoro.KokoroLive
import com.example.appname.kokoro.KokoroModelStore
import com.example.appname.kokoro.KokoroModule
import com.example.appname.kokoro.KokoroReader
import com.example.appname.plays.CastSpeaker
import com.example.appname.plays.CastVoice
import com.example.appname.plays.DeviceVoiceSource
import com.example.appname.plays.PartID
import com.example.appname.plays.PlayScript
import com.example.appname.plays.PrefsCastStore
import com.example.appname.plays.PrefsDefaultsStore
import com.example.appname.plays.VoiceDefaultsStore
import com.example.appname.plays.Resolved
import com.example.appname.plays.VoiceCast
import com.example.appname.plays.VoiceCasting
import com.example.appname.plays.VoiceCastEntry
import com.example.appname.plays.chipVoiceName
import com.example.appname.plays.soleAccent
import com.example.appname.plays.pitchText
import com.example.appname.plays.speedText
import com.example.appname.ui.theme.AppSemantics
import com.example.appname.ui.theme.Spacing
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch

// The voices on the cast sheet and in the reader (ANDROID-DESIGN §4.9b, PLAYS-DESIGN §2.8, Decision 076 S2): the chip
// that says a part's voice, the picker that changes it, the reader's list of every part. All three draw over one VoiceCast,
// so a choice made in either is the voice every player on this device reads.

/** This device's voice engine, held for a screen: the list is re-read when the engine is up and on every resume (no broadcast says a voice arrived). */
@Composable
fun rememberDeviceVoices(): DeviceVoiceSource {
    val context = LocalContext.current
    val source = remember { DeviceVoiceSource(context) }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(source, lifecycle) {
        val observer = LifecycleEventObserver { _, event -> if (event == Lifecycle.Event.ON_RESUME) source.refreshOffMain() }
        lifecycle.addObserver(observer)
        onDispose {
            lifecycle.removeObserver(observer)
            source.close()
        }
    }
    return source
}

/** One cast and its speaker for a screen; [tick] changes whenever a choice or the voice list does, so chips repaint. */
@Stable
class CastHandle(
    val source: DeviceVoiceSource,
    val cast: VoiceCast,
    val speaker: CastSpeaker,
    val kokoro: KokoroReader? = null,
    val playId: String = "",
) {
    var tick by mutableIntStateOf(0)
        private set

    fun changed() { tick += 1 }
}

/**
 * The cast over a production (seeded from its play's cast) or, with no production, over the play itself
 * (the reader's). Null until the script is known.
 */
@Composable
fun rememberCast(source: DeviceVoiceSource, script: PlayScript?, productionId: String?): CastHandle? {
    val context = LocalContext.current
    val muted = com.example.appname.navigation.LocalPlayerMuted.current
    // Behind a flag (PARITY "Downloadable voices"): none at all when off.
    val container = LocalAppContainer.current
    // An own script has no published phonemes: its parts are read by the device's own voices (PLAYS-DESIGN §13 item 8).
    val kokoro = container.takeIf { BuildConfig.KOKORO_VOICES && script?.isOwn != true }?.kokoro
    val defaultsStore = remember { PrefsDefaultsStore(context) }
    val handle = remember(source, script?.id, productionId) {
        script?.let {
            val cast = VoiceCast(
                key = productionId?.let(VoiceCasting::productionKey) ?: VoiceCasting.scriptKey(it.id),
                parts = it.castParts.map { p -> p.id },
                voices = source::voices,
                store = PrefsCastStore(context),
                seed = productionId?.let { _ -> VoiceCasting.scriptKey(it.id) },
                downloaded = { kokoro?.voices().orEmpty() },
                defaults = { VoiceDefaultsStore.load(defaultsStore) },
            )
            CastHandle(source, cast, CastSpeaker(source, cast, kokoro?.let(::KokoroLive), it.id), kokoro, it.id)
        }
    }
    if (handle != null) {
        handle.speaker.muted = muted
        LaunchedEffect(handle) { source.rev.collect { handle.changed() } }
        if (kokoro != null) LaunchedEffect(handle) {
            kokoro.store.state.distinctUntilChanged { a, b -> a::class == b::class }.collect { s ->
                if (s is KokoroModelStore.State.Ready) kokoro.prepare(handle.playId)
                handle.changed()
            }
        }
        if (kokoro != null) LaunchedEffect(handle) {
            container.kokoroModule.state.distinctUntilChanged { a, b -> a::class == b::class }.collect { handle.changed() }
        }
    }
    return handle
}

/** What the chip and the picker say about a part's voice now. */
internal class VoiceLine(val resolved: Resolved, val text: String, val warn: Boolean, val label: String, val tune: String, val isDefault: Boolean = false)

internal fun describeVoice(handle: CastHandle, part: PartID): VoiceLine {
    @Suppress("UNUSED_EXPRESSION") handle.tick
    val r = handle.cast.resolve(part)
    val title = part.title
    if (r.none) return VoiceLine(r, "No Voice", false, "Voice for $title: no voice on this device", "")
    if (!r.read) return VoiceLine(r, "Not read", false, "Voice for $title: not read", "")
    val voice = r.voice!!
    val tune = listOfNotNull(
        if (r.rate != 1.0) speedText(r.rate) else null,
        if (r.pitch != 1.0) "pitch ${pitchText(r.pitch)}" else null,
    ).joinToString(", ")
    val label = if (r.missing != null) {
        "Voice for $title: ${r.missing} is not on this device; ${voice.name} reads instead"
    } else {
        "Voice for $title: ${voice.name}"
    }
    val said = if (tune.isEmpty()) label else "$label, $tune"
    return VoiceLine(r, voice.name, r.missing != null, if (r.isDefault) "$said, Default" else said, tune, r.isDefault)
}

/** The voice chip: the voice's name, "Not read", or the warning glyph and the voice reading instead. */
@Composable
fun VoiceChip(handle: CastHandle, part: PartID, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val d = describeVoice(handle, part)
    val muted = MaterialTheme.colorScheme.onSurfaceVariant
    AssistChip(
        onClick = onClick,
        label = {
            Text(
                buildAnnotatedString {
                    append(chipVoiceName(d.text, handle.cast.soleAccent()))
                    if (d.isDefault) withStyle(SpanStyle(color = muted)) { append("  Default") }
                    if (d.tune.isNotEmpty()) withStyle(SpanStyle(color = muted)) { append("  ${d.tune}") }
                },
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        },
        leadingIcon = if (d.warn) ({
            Icon(Icons.Filled.Warning, contentDescription = null, tint = AppSemantics.colors.warning, modifier = Modifier.size(AssistChipDefaults.IconSize))
        }) else null,
        trailingIcon = { Icon(Icons.Filled.ArrowDropDown, contentDescription = null, modifier = Modifier.size(AssistChipDefaults.IconSize)) },
        modifier = modifier.semantics { contentDescription = d.label },
    )
}

private fun firstLine(script: PlayScript, part: PartID): String =
    script.lines(part).map { it.spokenText }.firstOrNull { it.isNotBlank() } ?: part.title

/** A − value + stepper over a VoiceCast range. */
@Composable
internal fun Stepper(label: String, value: Double, range: ClosedFloatingPointRange<Double>, enabled: Boolean, show: (Double) -> String, onChange: (Double) -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(label, Modifier.widthIn(min = 72.dp), softWrap = false, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        OutlinedIconButton(onClick = { onChange(Math.round((value - VoiceCasting.STEP) * 100) / 100.0) }, enabled = enabled && value > range.start + 1e-9) {
            Icon(Icons.Filled.Remove, contentDescription = "$label lower")
        }
        Text(
            show(value),
            Modifier.width(72.dp).semantics { stateDescription = show(value) },
            style = MaterialTheme.typography.titleMedium,
            color = if (enabled) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
        )
        OutlinedIconButton(onClick = { onChange(Math.round((value + VoiceCasting.STEP) * 100) / 100.0) }, enabled = enabled && value < range.endInclusive - 1e-9) {
            Icon(Icons.Filled.Add, contentDescription = "$label higher")
        }
    }
}

/**
 * The voice picker for one part (ANDROID-DESIGN §4.9b): the missing-voice warning, Speed and Pitch,
 * then "On this device" with a radio row per voice and a play button that reads the part's own first
 * line in that voice. Every change is kept at once; leaving stops a preview.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun VoicePickerSheet(handle: CastHandle, script: PlayScript, part: PartID, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val haptics = rememberHaptics()
    val scope = rememberCoroutineScope()
    val d = describeVoice(handle, part)
    val voices = handle.cast.voices()
    val entry = handle.cast.entry(part) ?: VoiceCastEntry.NOT_READ
    val reading = entry.engine != VoiceCastEntry.NONE
    val isDefault = d.resolved.isDefault
    val current = if (isDefault) "default" else if (!reading) "none" else d.resolved.voice?.id ?: entry.voice
    val text = remember(script, part) { firstLine(script, part) }
    var hearing by remember { mutableStateOf<String?>(null) }
    var job by remember { mutableStateOf<Job?>(null) }
    val install = remember(handle) { handle.source.installIntent() }
    val kokoroState by (handle.kokoro?.store?.state ?: remember { kotlinx.coroutines.flow.MutableStateFlow<KokoroModelStore.State>(KokoroModelStore.State.Absent) })
        .collectAsState()
    val moduleState by LocalAppContainer.current.kokoroModule.state.collectAsState()

    fun stopHearing() {
        job?.cancel()
        job = null
        hearing = null
        handle.speaker.cancel()
    }
    DisposableEffect(Unit) { onDispose { job?.cancel(); handle.speaker.cancel() } }

    fun change(change: VoiceCastEntry.() -> VoiceCastEntry) {
        handle.cast.set(part, change)
        handle.changed()
    }

    fun hear(v: CastVoice) {
        if (hearing == v.id) { stopHearing(); return }
        stopHearing()
        hearing = v.id
        job = scope.launch {
            try {
                handle.speaker.speakAs(text, v, if (reading) entry.rate else 1.0, if (reading) entry.pitch else 1.0)
            } finally {
                if (hearing == v.id) { hearing = null; job = null }
            }
        }
    }

    ModalBottomSheet(onDismissRequest = { stopHearing(); onDismiss() }, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        LazyColumn(Modifier.fillMaxWidth().heightIn(max = 640.dp), contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = Spacing.S4.dp)) {
            item(key = "head") {
                Text(part.title.uppercase(), Modifier.padding(horizontal = Spacing.S4.dp), style = MaterialTheme.typography.headlineSmall, maxLines = 2)
            }
            if (d.warn) {
                item(key = "missing") {
                    Row(Modifier.padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Filled.Warning, contentDescription = null, tint = AppSemantics.colors.warning, modifier = Modifier.size(18.dp))
                        Text(
                            "${d.resolved.missing} is not on this device.",
                            Modifier.padding(start = Spacing.S2.dp),
                            style = MaterialTheme.typography.bodyMedium,
                            color = AppSemantics.colors.warning,
                        )
                    }
                }
            }
            item(key = "steppers") {
                Column(Modifier.padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp)) {
                    Stepper("Speed", entry.rate, VoiceCasting.RATE, reading && voices.isNotEmpty(), ::speedText) { v -> change { copy(rate = v) } }
                    Stepper("Pitch", entry.pitch, VoiceCasting.PITCH, reading && voices.isNotEmpty(), ::pitchText) { v -> change { copy(pitch = v) } }
                }
            }
            val kokoro = handle.kokoro
            if (kokoro != null && kokoroState is KokoroModelStore.State.Ready && moduleState is KokoroModule.State.Installed) {
                item(key = "downloaded") {
                    Text(
                        "Downloaded",
                        Modifier.padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp),
                        style = MaterialTheme.typography.titleMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                if (kokoro.hasPhonemes(handle.playId) == false) {
                    item(key = "kokoro-none") {
                        Text(
                            "Not available for this play.",
                            Modifier.padding(horizontal = Spacing.S4.dp),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                } else {
                    items(kokoro.voices(), key = { "k:" + it.id }) { v ->
                        VoiceRow(v.name, null, current == v.id, v.id, hearing == v.id, v.id, onHear = { hear(v) }) {
                            val e = handle.cast.entry(part)
                            val base = if (e == null || e.engine == VoiceCastEntry.NONE) VoiceCastEntry(VoiceCastEntry.KOKORO, v.id, v.name) else e
                            change { base.copy(engine = VoiceCastEntry.KOKORO, voice = v.id, name = v.name) }
                            haptics(Haptic.Selection)
                        }
                    }
                }
            }
            item(key = "group") {
                Text(
                    "On this device",
                    Modifier.padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp),
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (voices.isEmpty()) {
                item(key = "none") {
                    Text(
                        "This device has no voice installed.",
                        Modifier.padding(horizontal = Spacing.S4.dp),
                        style = MaterialTheme.typography.bodyMedium,
                        color = AppSemantics.colors.error,
                    )
                }
            }
            item(key = "default") {
                VoiceRow("Default", handle.cast.defaultEntry(part)?.takeIf { it.engine != VoiceCastEntry.NONE }?.name, isDefault, "default", false, "Default", onHear = null) {
                    handle.cast.reset(part)
                    handle.changed()
                    haptics(Haptic.Selection)
                }
            }
            if (!part.isSpeaking) {
                item(key = "not-read") {
                    VoiceRow("Not read", null, current == "none", null, false, "Not read", onHear = null) {
                        change { VoiceCastEntry.NOT_READ }
                        haptics(Haptic.Selection)
                    }
                }
            }
            items(voices, key = { it.id }) { v ->
                VoiceRow(
                    v.name, v.qualityNote, current == v.id, v.id, hearing == v.id, v.id,
                    onHear = { hear(v) },
                ) {
                    val e = handle.cast.entry(part)
                    val base = if (e == null || e.engine == VoiceCastEntry.NONE) VoiceCastEntry(VoiceCastEntry.SYSTEM, v.id, v.name) else e
                    change { base.copy(engine = VoiceCastEntry.SYSTEM, voice = v.id, name = v.name) }
                    haptics(Haptic.Selection)
                }
            }
            if (install != null) {
                item(key = "more") {
                    TextButton(
                        onClick = { try { context.startActivity(install) } catch (_: ActivityNotFoundException) { } },
                        Modifier.padding(horizontal = Spacing.S2.dp),
                    ) { Text("Get more voices") }
                }
            }
            if (handle.kokoro != null && BetterVoicesOffered(kokoroState, moduleState)) {
                item(key = "better") {
                    val open = com.example.appname.ui.screens.LocalReadNav.current.openVoiceSettings
                    TextButton(onClick = { stopHearing(); onDismiss(); open() }, Modifier.padding(horizontal = Spacing.S2.dp)) { Text("Better voices") }
                }
            }
        }
    }
}

/**
 * Settings > Voices' Kokoro controls (PLAYS-DESIGN §2.8 rules 6 and 11, Decision 078; ANDROID-DESIGN §4.11): before the voices are
 * here, one Download voices button with the size of the engine module and the model together; while Play fetches the
 * module and then the app fetches the model, one progress line over both and Cancel (Play's own confirmation when it
 * asks first); once here, Delete and the attribution the model's licenses ask for.
 */
fun androidx.compose.foundation.lazy.LazyListScope.kokoroControls(
    kokoro: KokoroReader,
    state: KokoroModelStore.State,
    module: KokoroModule.State,
) {
    val here = state is KokoroModelStore.State.Ready && module is KokoroModule.State.Installed
    when {
        here -> {
            item(key = "kokoro-delete") {
                val container = LocalAppContainer.current
                TextButton(onClick = { container.deleteVoices() }, Modifier.padding(horizontal = Spacing.S2.dp)) {
                    Text("Delete downloaded voices (${KokoroModelStore.megabytes(kokoro.store.downloadBytes())})")
                }
            }
            item(key = "kokoro-credit") {
                Text(
                    KOKORO_CREDIT,
                    Modifier.padding(horizontal = Spacing.S4.dp, vertical = Spacing.S1.dp),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        module is KokoroModule.State.NeedsConfirmation -> item(key = "kokoro-confirm") {
            val container = LocalAppContainer.current
            val launcher = androidx.activity.compose.rememberLauncherForActivityResult(
                androidx.activity.result.contract.ActivityResultContracts.StartIntentSenderForResult(),
            ) { }
            Row(Modifier.fillMaxWidth().padding(horizontal = Spacing.S4.dp, vertical = Spacing.S1.dp), verticalAlignment = Alignment.CenterVertically) {
                androidx.compose.material3.OutlinedButton(onClick = { container.kokoroModule.confirm(module, launcher) }) { Text("Continue download") }
                TextButton(onClick = { container.cancelVoiceDownload() }) { Text("Cancel") }
            }
        }
        module is KokoroModule.State.Pending || module is KokoroModule.State.Installing ||
            module is KokoroModule.State.Downloading || state is KokoroModelStore.State.Downloading -> item(key = "kokoro-progress") {
            val container = LocalAppContainer.current
            val modelBytes = kokoro.store.downloadBytes()
            // Module and model as one download: Play's bytes first, then the model's after them.
            val (done, total) = when {
                module is KokoroModule.State.Downloading -> module.done to module.total + modelBytes
                state is KokoroModelStore.State.Downloading -> {
                    val m = container.kokoroModule.bytesThisInstall
                    (m + state.done) to (m + state.total)
                }
                else -> -1L to 0L
            }
            val said = when {
                module is KokoroModule.State.Pending -> "Waiting"
                module is KokoroModule.State.Installing -> "Installing"
                else -> "${KokoroModelStore.megabytes(done)} of ${KokoroModelStore.megabytes(total.coerceAtLeast(1))}"
            }
            Column(Modifier.fillMaxWidth().padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp)) {
                val label = Modifier.fillMaxWidth().semantics { contentDescription = "Downloading voices, $said" }
                if (done >= 0) {
                    androidx.compose.material3.LinearProgressIndicator(
                        progress = { (done.toFloat() / total.coerceAtLeast(1)).coerceIn(0f, 1f) },
                        modifier = label,
                    )
                } else {
                    androidx.compose.material3.LinearProgressIndicator(modifier = label)
                }
                Row(Modifier.fillMaxWidth().padding(top = Spacing.S1.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(said, Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
                    TextButton(onClick = { container.cancelVoiceDownload() }) { Text("Cancel") }
                }
            }
        }
        else -> {
            val failed = state is KokoroModelStore.State.Failed || module is KokoroModule.State.Failed
            if (failed) {
                item(key = "kokoro-failed") {
                    Text(
                        "The download failed.",
                        Modifier.padding(horizontal = Spacing.S4.dp),
                        style = MaterialTheme.typography.bodyMedium,
                        color = AppSemantics.colors.error,
                    )
                }
            }
            item(key = "kokoro-download") {
                val container = LocalAppContainer.current
                val bytes = (if (state is KokoroModelStore.State.Ready) 0L else kokoro.store.downloadBytes()) +
                    (if (module is KokoroModule.State.Installed) 0L else container.kokoroModule.downloadBytes())
                androidx.compose.material3.OutlinedButton(
                    onClick = { container.downloadVoices() },
                    Modifier.padding(horizontal = Spacing.S4.dp, vertical = Spacing.S1.dp),
                ) {
                    Icon(Icons.Filled.Download, contentDescription = null, modifier = Modifier.size(18.dp))
                    Text(
                        "${if (failed) "Try again" else "Download voices"} (${KokoroModelStore.megabytes(bytes)})",
                        Modifier.padding(start = Spacing.S2.dp),
                    )
                }
            }
        }
    }
}

/** "Better voices" is offered while Kokoro could run here and is not downloaded. */
fun BetterVoicesOffered(state: KokoroModelStore.State, module: KokoroModule.State): Boolean =
    !(state is KokoroModelStore.State.Ready && module is KokoroModule.State.Installed)

/** The attribution Kokoro-82M's card and the CC BY data sets in its training ask for (R2-kokoro-feasibility §2). */
const val KOKORO_CREDIT = "Kokoro-82M by hexgrad, Apache-2.0. Trained in part on Koniwa (CC BY 3.0) and SIWIS (CC BY 4.0)."

@Composable
internal fun VoiceRow(name: String, note: String?, selected: Boolean, rawId: String?, hearing: Boolean, hint: String, onHear: (() -> Unit)?, onPick: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .selectable(selected = selected, role = Role.RadioButton, onClick = onPick)
            .padding(start = Spacing.S4.dp, end = Spacing.S2.dp)
            .semantics { if (rawId != null) stateDescription = if (selected) "Selected" else "Not selected" },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        RadioButton(selected = selected, onClick = null)
        Column(Modifier.weight(1f).padding(start = Spacing.S3.dp)) {
            Text(name, style = MaterialTheme.typography.bodyMedium)
            if (note != null) Text(note, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        if (onHear != null) {
            IconButton(onClick = onHear) {
                Icon(
                    if (hearing) Icons.Filled.Stop else Icons.Filled.PlayArrow,
                    contentDescription = if (hearing) "Stop $name" else "Hear $name",
                )
            }
        }
    }
}

/** The reader's Voices: every part with its chip, then Recast all. A chip opens that part's picker. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun VoicesSheet(handle: CastHandle, script: PlayScript, onPick: (PartID) -> Unit, onDismiss: () -> Unit) {
    val haptics = rememberHaptics()
    val kokoroState by (handle.kokoro?.store?.state ?: remember { kotlinx.coroutines.flow.MutableStateFlow<KokoroModelStore.State>(KokoroModelStore.State.Absent) })
        .collectAsState()
    val moduleState by LocalAppContainer.current.kokoroModule.state.collectAsState()
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        LazyColumn(Modifier.fillMaxWidth().heightIn(max = 640.dp)) {
            item(key = "head") {
                Text("Voices", Modifier.padding(horizontal = Spacing.S4.dp), style = MaterialTheme.typography.headlineSmall)
            }
            items(script.castParts, key = { it.id.raw }) { p ->
                Row(
                    Modifier.fillMaxWidth().padding(horizontal = Spacing.S4.dp, vertical = Spacing.S1.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp),
                ) {
                    Column(Modifier.weight(1f)) {
                        Text(p.title, style = MaterialTheme.typography.bodyMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(
                            lineCountText(p.lineCount),
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    VoiceChip(handle, p.id, onClick = { onPick(p.id) }, modifier = Modifier.weight(1.2f))
                }
            }
            item(key = "recast") {
                TextButton(
                    onClick = { handle.cast.recast(); handle.changed(); haptics(Haptic.Selection) },
                    Modifier.padding(horizontal = Spacing.S2.dp),
                ) { Text("Recast all") }
            }
            if (handle.kokoro != null && BetterVoicesOffered(kokoroState, moduleState)) {
                item(key = "better") {
                    val open = com.example.appname.ui.screens.LocalReadNav.current.openVoiceSettings
                    TextButton(onClick = { onDismiss(); open() }, Modifier.padding(horizontal = Spacing.S2.dp)) { Text("Better voices") }
                }
            }
        }
    }
}
