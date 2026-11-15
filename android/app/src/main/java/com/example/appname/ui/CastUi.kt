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
import com.example.appname.kokoro.KokoroReader
import com.example.appname.plays.CastSpeaker
import com.example.appname.plays.CastVoice
import com.example.appname.plays.DeviceVoiceSource
import com.example.appname.plays.PartID
import com.example.appname.plays.PlayScript
import com.example.appname.plays.PrefsCastStore
import com.example.appname.plays.Resolved
import com.example.appname.plays.VoiceCast
import com.example.appname.plays.VoiceCasting
import com.example.appname.plays.VoiceCastEntry
import com.example.appname.plays.chipVoiceName
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
    // Behind a flag until the S6a gate passes on the Pixel 8a (PARITY "Downloadable voices"): none at all when off.
    val kokoro = LocalAppContainer.current.takeIf { BuildConfig.KOKORO_VOICES }?.kokoro
    val handle = remember(source, script?.id, productionId) {
        script?.let {
            val cast = VoiceCast(
                key = productionId?.let(VoiceCasting::productionKey) ?: VoiceCasting.scriptKey(it.id),
                parts = it.castParts.map { p -> p.id },
                voices = source::voices,
                store = PrefsCastStore(context),
                seed = productionId?.let { _ -> VoiceCasting.scriptKey(it.id) },
                downloaded = { kokoro?.voices().orEmpty() },
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
    }
    return handle
}

/** What the chip and the picker say about a part's voice now. */
internal class VoiceLine(val resolved: Resolved, val text: String, val warn: Boolean, val label: String, val tune: String)

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
    return VoiceLine(r, voice.name, r.missing != null, if (tune.isEmpty()) label else "$label, $tune", tune)
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
                    append(chipVoiceName(d.text))
                    if (d.tune.isNotEmpty()) withStyle(SpanStyle(color = muted)) { append("  ${d.tune}") }
                },
                maxLines = 1,
                overflow = TextOverflow.StartEllipsis,
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
private fun Stepper(label: String, value: Double, range: ClosedFloatingPointRange<Double>, enabled: Boolean, show: (Double) -> String, onChange: (Double) -> Unit) {
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
    val text = remember(script, part) { firstLine(script, part) }
    var hearing by remember { mutableStateOf<String?>(null) }
    var job by remember { mutableStateOf<Job?>(null) }
    val install = remember(handle) { handle.source.installIntent() }
    val kokoroState by (handle.kokoro?.store?.state ?: remember { kotlinx.coroutines.flow.MutableStateFlow<KokoroModelStore.State>(KokoroModelStore.State.Absent) })
        .collectAsState()

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
            val current = if (!reading) "none" else d.resolved.voice?.id ?: entry.voice
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
            val kokoro = handle.kokoro
            if (kokoro != null) {
                downloadedGroup(kokoro, kokoroState, handle.playId, current, hearing, onHear = { hear(it) }) { v ->
                    val e = handle.cast.entry(part)
                    val base = if (e == null || e.engine == VoiceCastEntry.NONE) VoiceCastEntry(VoiceCastEntry.KOKORO, v.id, v.name) else e
                    change { base.copy(engine = VoiceCastEntry.KOKORO, voice = v.id, name = v.name) }
                    haptics(Haptic.Selection)
                }
            }
        }
    }
}

/**
 * The picker's "Downloaded" group (PLAYS-DESIGN §2.8 rule 6, Decision 078; ANDROID-DESIGN §4.9b): before the model is
 * here, one Download voices button with its size; while it downloads, the progress and Cancel; once here, the 28 Kokoro
 * voices with their previews, Delete, and the attribution the model's licenses ask for. A play the catalog published no
 * phonemes for says so instead of listing voices that would not read it.
 */
private fun androidx.compose.foundation.lazy.LazyListScope.downloadedGroup(
    kokoro: KokoroReader,
    state: KokoroModelStore.State,
    playId: String,
    current: String?,
    hearing: String?,
    onHear: (CastVoice) -> Unit,
    onPick: (CastVoice) -> Unit,
) {
    item(key = "downloaded") {
        Text(
            "Downloaded",
            Modifier.padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp),
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
    when (val s = state) {
        is KokoroModelStore.State.Ready -> {
            if (kokoro.hasPhonemes(playId) == false) {
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
                    VoiceRow(v.name, null, current == v.id, v.id, hearing == v.id, v.id, onHear = { onHear(v) }) { onPick(v) }
                }
            }
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
        is KokoroModelStore.State.Downloading -> item(key = "kokoro-progress") {
            val container = LocalAppContainer.current
            val total = s.total.coerceAtLeast(1)
            val said = "${KokoroModelStore.megabytes(s.done)} of ${KokoroModelStore.megabytes(total)}"
            Column(Modifier.fillMaxWidth().padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp)) {
                androidx.compose.material3.LinearProgressIndicator(
                    progress = { (s.done.toFloat() / total).coerceIn(0f, 1f) },
                    modifier = Modifier.fillMaxWidth().semantics { contentDescription = "Downloading voices, $said" },
                )
                Row(Modifier.fillMaxWidth().padding(top = Spacing.S1.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(said, Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
                    TextButton(onClick = { container.cancelVoiceDownload() }) { Text("Cancel") }
                }
            }
        }
        is KokoroModelStore.State.Absent, is KokoroModelStore.State.Failed -> {
            if (s is KokoroModelStore.State.Failed) {
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
                androidx.compose.material3.OutlinedButton(
                    onClick = { container.downloadVoices() },
                    Modifier.padding(horizontal = Spacing.S4.dp, vertical = Spacing.S1.dp),
                ) {
                    Icon(Icons.Filled.Download, contentDescription = null, modifier = Modifier.size(18.dp))
                    Text(
                        "${if (s is KokoroModelStore.State.Failed) "Try again" else "Download voices"} (${KokoroModelStore.megabytes(kokoro.store.downloadBytes())})",
                        Modifier.padding(start = Spacing.S2.dp),
                    )
                }
            }
        }
    }
}

/** The attribution Kokoro-82M's card and the CC BY data sets in its training ask for (R2-kokoro-feasibility §2). */
const val KOKORO_CREDIT = "Kokoro-82M by hexgrad, Apache-2.0. Trained in part on Koniwa (CC BY 3.0) and SIWIS (CC BY 4.0)."

@Composable
private fun VoiceRow(name: String, note: String?, selected: Boolean, rawId: String?, hearing: Boolean, hint: String, onHear: (() -> Unit)?, onPick: () -> Unit) {
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
        }
    }
}
