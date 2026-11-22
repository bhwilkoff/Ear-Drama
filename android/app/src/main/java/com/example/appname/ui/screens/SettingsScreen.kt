package com.example.appname.ui.screens

import android.content.ActivityNotFoundException
import android.content.Intent
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.Checkbox
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.example.appname.BuildConfig
import com.example.appname.kokoro.KokoroModelStore
import com.example.appname.kokoro.KokoroModule
import com.example.appname.plays.CastVoice
import com.example.appname.plays.PlayLibraryFeed
import com.example.appname.plays.PlayScript
import com.example.appname.plays.PrefsDefaultsStore
import com.example.appname.plays.VoiceCastEntry
import com.example.appname.plays.VoiceCasting
import com.example.appname.plays.VoiceDefaults
import com.example.appname.plays.VoiceDefaultsStore
import com.example.appname.plays.speedText
import com.example.appname.radio.RadioClock
import com.example.appname.ui.KOKORO_CREDIT
import com.example.appname.ui.LocalAppContainer
import com.example.appname.ui.SectionHeader
import com.example.appname.ui.Stepper
import com.example.appname.ui.rememberCast
import com.example.appname.ui.rememberDeviceVoices
import com.example.appname.ui.theme.AppSemantics
import com.example.appname.ui.theme.Spacing
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

/** What Library's Voices section shows of the Kokoro download (ANDROID-DESIGN §4.11): the same states the picker once did, in one place. */
sealed interface KokoroUi {
    /** A device that cannot run the engine (no arm64-v8a) or a build without it: one refusal. */
    data object Unsupported : KokoroUi
    data class Absent(val bytes: Long, val failed: Boolean = false) : KokoroUi
    /** Waiting on Play, or installing: no byte count yet. */
    data class Waiting(val said: String) : KokoroUi
    data class Progress(val done: Long, val total: Long) : KokoroUi
    /** Play asks the person first (a large download, or on a metered network). */
    data object Confirm : KokoroUi
    data class Ready(val bytes: Long) : KokoroUi
}

/** What the screen draws: nothing here reads a store or an engine, so a render needs only these. */
class VoiceSettingsUi(
    val kokoro: KokoroUi,
    val defaults: VoiceDefaults,
    /** Every voice in the Default order (Kokoro first). */
    val ordered: List<CastVoice>,
    val hearing: String? = null,
    val canHear: Boolean = true,
    val canGetMore: Boolean = true,
)

class VoiceSettingsActions(
    val onDownload: () -> Unit = {},
    val onCancel: () -> Unit = {},
    val onConfirm: () -> Unit = {},
    val onDelete: () -> Unit = {},
    val onRate: (Double) -> Unit = {},
    val onUse: (CastVoice, Boolean) -> Unit = { _, _ -> },
    val onMove: (CastVoice, Int) -> Unit = { _, _ -> },
    val onHear: (CastVoice) -> Unit = {},
    val onGetMore: () -> Unit = {},
)

/** The key of the section's first row: Better voices scrolls Library to it. */
const val VOICES_KEY = "voices"

/** Kokoro's quality as a row says it: its own grade, or "High quality" from an engine that reports it. */
fun qualityNote(v: CastVoice): String? = v.grade?.let { "Grade ${it.replace('-', '−')}" } ?: v.qualityNote

/**
 * Library's Voices section (Decision 086; PLAYS-DESIGN §2.8 rule 11; owner 2026-11-22: Library carries it, there is no Settings
 * screen): the device's voice defaults. The state and what each control does; [voicesItems] draws it.
 */
@Composable
fun rememberVoicesState(): Pair<VoiceSettingsUi, VoiceSettingsActions> {
    val container = LocalAppContainer.current
    val context = androidx.compose.ui.platform.LocalContext.current
    val scope = rememberCoroutineScope()
    val kokoro = container.takeIf { BuildConfig.KOKORO_VOICES }?.kokoro
    val store = remember { PrefsDefaultsStore(context) }
    var defaults by remember { mutableStateOf(VoiceDefaultsStore.load(store)) }
    val storeState by (kokoro?.store?.state ?: remember { kotlinx.coroutines.flow.MutableStateFlow<KokoroModelStore.State>(KokoroModelStore.State.Absent) })
        .collectAsState()
    val moduleState by container.kokoroModule.state.collectAsState()

    // Hear reads a line of today's scene, through the same cast and speaker the sheets use (live, never kept).
    val rows = rememberPlayRows()
    val sample by produceState<PlayScript?>(null, rows) {
        val ready = rows as? PlayLibraryFeed.Rows.Ready ?: return@produceState
        val row = PlayScript.todaysScene(ready.rows, RadioClock.localDate()) ?: return@produceState
        value = try {
            container.plays.script(row.id)
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            null
        }
    }
    val voices = rememberDeviceVoices()
    val handle = rememberCast(voices, sample, null)
    val rev by voices.rev.collectAsState()
    var hearing by remember { mutableStateOf<String?>(null) }
    var job by remember { mutableStateOf<Job?>(null) }
    androidx.compose.runtime.DisposableEffect(handle) { onDispose { job?.cancel(); handle?.speaker?.cancel() } }
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.StartIntentSenderForResult()) { }

    val here = kokoro != null && storeState is KokoroModelStore.State.Ready && moduleState is KokoroModule.State.Installed
    val ui = remember(storeState, moduleState, defaults, rev, hearing, handle, sample) {
        val all = (if (here) kokoro.voices() else emptyList()) + voices.voices()
        val bytes = (if (storeState is KokoroModelStore.State.Ready) 0L else kokoro?.store?.downloadBytes() ?: 0L) +
            (if (moduleState is KokoroModule.State.Installed) 0L else container.kokoroModule.downloadBytes())
        val k: KokoroUi = when {
            kokoro == null || Build.SUPPORTED_64_BIT_ABIS.none { it == "arm64-v8a" } -> KokoroUi.Unsupported
            here -> KokoroUi.Ready(kokoro.store.downloadBytes())
            moduleState is KokoroModule.State.NeedsConfirmation -> KokoroUi.Confirm
            moduleState is KokoroModule.State.Downloading -> {
                val m = moduleState as KokoroModule.State.Downloading
                KokoroUi.Progress(m.done, m.total + kokoro.store.downloadBytes())
            }
            storeState is KokoroModelStore.State.Downloading -> {
                val s = storeState as KokoroModelStore.State.Downloading
                val m = container.kokoroModule.bytesThisInstall
                KokoroUi.Progress(m + s.done, m + s.total)
            }
            moduleState is KokoroModule.State.Pending -> KokoroUi.Waiting("Waiting")
            moduleState is KokoroModule.State.Installing -> KokoroUi.Waiting("Installing")
            else -> KokoroUi.Absent(bytes, storeState is KokoroModelStore.State.Failed || moduleState is KokoroModule.State.Failed)
        }
        VoiceSettingsUi(
            k, defaults, VoiceCasting.ordered(all, defaults), hearing,
            canHear = handle != null && sample != null,
            canGetMore = true,
        )
    }

    fun hear(v: CastVoice) {
        val h = handle ?: return
        val first = sample?.let { PlayScript.openingOf(it, 1).firstOrNull() } ?: return
        if (hearing == v.key) { job?.cancel(); h.speaker.cancel(); hearing = null; return }
        job?.cancel()
        hearing = v.key
        job = scope.launch {
            try {
                h.speaker.speakAs(first.text, v, defaults.rate, 1.0)
            } finally {
                if (hearing == v.key) hearing = null
            }
        }
    }

    val actions = VoiceSettingsActions(
        onDownload = { container.downloadVoices() },
        onCancel = { container.cancelVoiceDownload() },
        onConfirm = { (moduleState as? KokoroModule.State.NeedsConfirmation)?.let { container.kokoroModule.confirm(it, launcher) } },
        onDelete = { job?.cancel(); handle?.speaker?.cancel(); container.deleteVoices() },
        onRate = { r -> defaults = defaults.copy(rate = r).normalized().also { VoiceDefaultsStore.save(store, it) } },
        onUse = { v, on -> defaults = defaults.copy(off = defaults.off + (v.key to !on)).also { VoiceDefaultsStore.save(store, it) } },
        onMove = { v, by -> defaults = VoiceCasting.move(ui.ordered, defaults, v, by).also { VoiceDefaultsStore.save(store, it) } },
        onHear = ::hear,
        onGetMore = {
            val intent = voices.installIntent() ?: Intent("com.android.settings.TTS_SETTINGS").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try { context.startActivity(intent) } catch (_: ActivityNotFoundException) { }
        },
    )

    return ui to actions
}

/** The Voices section's rows, stateless: the header, the Kokoro controls, Speed, then the voices in the Default order. */
fun androidx.compose.foundation.lazy.LazyListScope.voicesItems(ui: VoiceSettingsUi, actions: VoiceSettingsActions) {
    val hifi = ui.ordered.filter { it.engine == VoiceCastEntry.KOKORO }
    val device = ui.ordered.filter { it.engine == VoiceCastEntry.SYSTEM }
    run {
        item(key = VOICES_KEY) { SectionHeader("Voices") }
        item(key = "kokoro") { KokoroSection(ui.kokoro, actions) }
        item(key = "speed") {
            Column(Modifier.padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp)) {
                Stepper("Speed", ui.defaults.rate, VoiceCasting.RATE, true, ::speedText, actions.onRate)
            }
        }
        if (hifi.isNotEmpty()) {
            item(key = "downloaded-h") { GroupTitle("Downloaded") }
            items(hifi, key = { "k:" + it.id }) { VoiceDefaultRow(it, hifi, ui, actions) }
        }
        item(key = "device-h") { GroupTitle("On this device") }
        if (device.isEmpty()) {
            item(key = "none") {
                Text(
                    "This device has no voice installed.",
                    Modifier.padding(horizontal = Spacing.S4.dp),
                    style = MaterialTheme.typography.bodyMedium,
                    color = AppSemantics.colors.error,
                )
            }
        }
        items(device, key = { "s:" + it.id }) { VoiceDefaultRow(it, device, ui, actions) }
        if (ui.canGetMore) {
            item(key = "more") {
                TextButton(onClick = actions.onGetMore, Modifier.padding(horizontal = Spacing.S2.dp)) { Text("Get more voices") }
            }
        }
    }
}

@Composable
private fun GroupTitle(text: String) {
    Text(
        text,
        Modifier.padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp),
        style = MaterialTheme.typography.titleMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

@Composable
private fun KokoroSection(state: KokoroUi, a: VoiceSettingsActions) {
    Column(Modifier.fillMaxWidth().padding(horizontal = Spacing.S4.dp, vertical = Spacing.S1.dp)) {
        when (state) {
            KokoroUi.Unsupported -> Text(
                "This device can’t run Kokoro voices.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            is KokoroUi.Absent -> {
                if (state.failed) {
                    Text("The download failed.", style = MaterialTheme.typography.bodyMedium, color = AppSemantics.colors.error)
                }
                OutlinedButton(onClick = a.onDownload) {
                    Icon(Icons.Filled.Download, contentDescription = null, modifier = Modifier.padding(end = 0.dp).heightIn(max = 18.dp))
                    Text(
                        "${if (state.failed) "Try again" else "Download voices"} (${KokoroModelStore.megabytes(state.bytes)})",
                        Modifier.padding(start = Spacing.S2.dp),
                    )
                }
            }
            KokoroUi.Confirm -> Row(verticalAlignment = Alignment.CenterVertically) {
                OutlinedButton(onClick = a.onConfirm) { Text("Continue download") }
                TextButton(onClick = a.onCancel) { Text("Cancel") }
            }
            is KokoroUi.Waiting -> Progress(null, state.said, a)
            is KokoroUi.Progress -> Progress(
                (state.done.toFloat() / state.total.coerceAtLeast(1)).coerceIn(0f, 1f),
                "${KokoroModelStore.megabytes(state.done)} of ${KokoroModelStore.megabytes(state.total.coerceAtLeast(1))}",
                a,
            )
            is KokoroUi.Ready -> {
                TextButton(onClick = a.onDelete) { Text("Delete downloaded voices (${KokoroModelStore.megabytes(state.bytes)})") }
                Text(KOKORO_CREDIT, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun Progress(fraction: Float?, said: String, a: VoiceSettingsActions) {
    val label = Modifier.fillMaxWidth().semantics { contentDescription = "Downloading voices, $said" }
    if (fraction != null) LinearProgressIndicator(progress = { fraction }, modifier = label) else LinearProgressIndicator(modifier = label)
    Row(Modifier.fillMaxWidth().padding(top = Spacing.S1.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(said, Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
        TextButton(onClick = a.onCancel) { Text("Cancel") }
    }
}

/** One voice in the Default order: its Use tick, name and quality, Move up and down within its engine, and Hear. */
@Composable
private fun VoiceDefaultRow(v: CastVoice, group: List<CastVoice>, ui: VoiceSettingsUi, a: VoiceSettingsActions) {
    val used = VoiceCasting.uses(v, ui.defaults)
    val i = group.indexOfFirst { it.key == v.key }
    val hearing = ui.hearing == v.key
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .toggleable(value = used, role = Role.Checkbox, onValueChange = { a.onUse(v, it) })
            .padding(start = Spacing.S4.dp, end = Spacing.S1.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Spacing.S1.dp),
    ) {
        Checkbox(checked = used, onCheckedChange = null)
        Column(Modifier.weight(1f).padding(start = Spacing.S2.dp)) {
            Text(v.name, style = MaterialTheme.typography.bodyMedium, maxLines = 2)
            qualityNote(v)?.let { Text(it, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        }
        IconButton(onClick = { a.onMove(v, -1) }, enabled = i > 0) {
            Icon(Icons.Filled.ArrowUpward, contentDescription = "Move ${v.name} up")
        }
        IconButton(onClick = { a.onMove(v, 1) }, enabled = i < group.size - 1) {
            Icon(Icons.Filled.ArrowDownward, contentDescription = "Move ${v.name} down")
        }
        IconButton(onClick = { a.onHear(v) }, enabled = ui.canHear) {
            Icon(if (hearing) Icons.Filled.Stop else Icons.Filled.PlayArrow, contentDescription = if (hearing) "Stop ${v.name}" else "Hear ${v.name}")
        }
    }
}
