package com.example.appname.ui

import android.content.ActivityNotFoundException
import android.content.Intent
import android.os.StatFs
import android.provider.Settings
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.example.appname.kokoro.KokoroModelStore
import com.example.appname.navigation.VoicesStepDoor
import com.example.appname.plays.VoiceCastEntry
import com.example.appname.plays.VoicesOffer
import com.example.appname.ui.screens.KokoroSection
import com.example.appname.ui.screens.KokoroUi
import com.example.appname.ui.screens.VoiceSettingsActions
import com.example.appname.ui.screens.rememberVoicesState
import com.example.appname.ui.theme.AppSemantics
import com.example.appname.ui.theme.Spacing

/**
 * The Better voices step (PLAYS-DESIGN §2.8 rule 13, Decision 090; ANDROID-DESIGN §4.6b): stateless, so a render shows every
 * state. The download control is Library's own ([KokoroSection]); [freeBytes] null means the space is not known.
 */
@Composable
fun VoicesStepContent(
    kokoro: KokoroUi,
    actions: VoiceSettingsActions,
    freeBytes: Long?,
    systemVoicesLine: Boolean,
    onOpenSettings: () -> Unit,
    onClose: () -> Unit,
) {
    val size = (kokoro as? KokoroUi.Absent)?.bytes ?: 0L
    val low = freeBytes != null && VoicesOffer.lowSpace(freeBytes, size)
    Column(
        Modifier.fillMaxWidth().padding(bottom = Spacing.S4.dp),
        verticalArrangement = Arrangement.spacedBy(Spacing.S2.dp),
    ) {
        Text(
            "Better voices",
            Modifier.padding(horizontal = Spacing.S4.dp).semantics { heading() },
            style = MaterialTheme.typography.headlineSmall,
        )
        Text(
            "Downloaded voices read the parts nobody has cast.",
            Modifier.padding(horizontal = Spacing.S4.dp),
            style = MaterialTheme.typography.bodyMedium,
        )
        KokoroSection(kokoro, actions, canDownload = !low)
        if (low && freeBytes != null) {
            Text(
                "Not enough space: ${KokoroModelStore.megabytes(freeBytes)} free.",
                Modifier.padding(horizontal = Spacing.S4.dp),
                style = MaterialTheme.typography.bodyMedium,
                color = AppSemantics.colors.warning,
            )
        }
        if (systemVoicesLine) {
            Row(Modifier.fillMaxWidth().padding(start = Spacing.S4.dp, end = Spacing.S2.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Better system voices are added in Settings.", Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
                TextButton(onClick = onOpenSettings) { Text("Open Settings") }
            }
        }
        Row(Modifier.fillMaxWidth().padding(horizontal = Spacing.S2.dp), horizontalArrangement = Arrangement.End) {
            TextButton(onClick = onClose) { Text(if (kokoro is KokoroUi.Ready) "Done" else "Not now") }
        }
    }
}

/** The sheet over the app: Library's Voices state and actions, the device's free space, Android's speech settings. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun VoicesStepSheet(onDismiss: () -> Unit) {
    val context = LocalContext.current
    val (ui, actions) = rememberVoicesState()
    val free = remember(ui.kokoro) { runCatching { StatFs(context.filesDir.path).availableBytes }.getOrNull() }
    val device = ui.ordered.filter { it.engine == VoiceCastEntry.SYSTEM }
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        VoicesStepContent(
            kokoro = ui.kokoro,
            actions = actions,
            freeBytes = free,
            systemVoicesLine = VoicesOffer.wantsSystemVoices(device),
            onOpenSettings = {
                val tts = Intent("com.android.settings.TTS_SETTINGS").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                try {
                    context.startActivity(tts)
                } catch (_: ActivityNotFoundException) {
                    try { context.startActivity(Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) } catch (_: ActivityNotFoundException) { }
                }
            },
            onClose = onDismiss,
        )
    }
}

/**
 * Offers the step (§4.6b): once at launch, once more at the first reader, cast or recorder ([firstUse]), never on a TV or where
 * the voices cannot run, never once a download began. The DEBUG doors skip it or force it without touching the record.
 */
@Composable
fun VoicesStepHost(firstUse: Boolean) {
    val container = LocalAppContainer.current
    val context = LocalContext.current
    val supported = remember {
        com.example.appname.BuildConfig.KOKORO_VOICES && !container.isTelevision &&
            android.os.Build.SUPPORTED_64_BIT_ABIS.any { it == "arm64-v8a" }
    }
    if (!supported) return
    val offer = remember { VoicesOffer(com.example.appname.plays.PrefsVoicesOfferStore(context)) }
    val storeState by container.kokoro.store.state.collectAsState()
    val moduleState by container.kokoroModule.state.collectAsState()
    val eligible = VoicesOffer.eligible(true, storeState, moduleState)
    var shown by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(storeState, moduleState) { if (VoicesOffer.begun(storeState, moduleState)) offer.downloadBegan() }
    LaunchedEffect(Unit) {
        val force = VoicesStepDoor.force
        VoicesStepDoor.force = false
        if (offer.atLaunch(eligible, force = force, skip = VoicesStepDoor.skip)) shown = true
    }
    LaunchedEffect(firstUse) {
        if (firstUse && !shown && !VoicesStepDoor.skip && offer.atFirstUse(eligible)) shown = true
    }
    if (shown) VoicesStepSheet(onDismiss = { shown = false })
}
