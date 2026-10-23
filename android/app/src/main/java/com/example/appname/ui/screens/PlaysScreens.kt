package com.example.appname.ui.screens

import android.content.Context
import android.content.Intent
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withLink
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import com.example.appname.plays.CastPart
import com.example.appname.plays.MixPlayback
import com.example.appname.plays.PartID
import com.example.appname.plays.PartState
import com.example.appname.plays.PlayScript
import com.example.appname.plays.PlaysLibrary
import com.example.appname.plays.Production
import com.example.appname.plays.Relay
import com.example.appname.ui.EmptyMessage
import com.example.appname.ui.Haptic
import com.example.appname.ui.LocalAppContainer
import com.example.appname.ui.SectionHeader
import com.example.appname.ui.formatClock
import com.example.appname.ui.rememberHaptics
import com.example.appname.ui.theme.AppSemantics
import com.example.appname.ui.theme.Spacing
import java.io.File
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// Plays phase 1, pass the phone (docs/PLAYS-DESIGN.md, binding; ANDROID-DESIGN
// §4.9). The same seven verbs as iPhone, iPad, and the Mac (§2): pick a play,
// read the cast sheet, take a part, record line by line, pass the phone, listen
// through, finish and keep it, in Material's own components.

// MARK: Pick a play

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PlaysScreen(onOpenScript: (String) -> Unit, onOpenProduction: (String) -> Unit) {
    val plays = LocalAppContainer.current.plays
    val state by plays.state.collectAsState()
    LaunchedEffect(Unit) { plays.load() }
    Scaffold(topBar = { TopAppBar(title = { Text("Plays") }) }) { padding ->
        val ready = state as? PlaysLibrary.State.Ready
        if (ready == null) {
            if (state == PlaysLibrary.State.Loading) {
                Column(Modifier.fillMaxSize().padding(padding), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                    CircularProgressIndicator(Modifier.semantics { contentDescription = "Loading" })
                }
            } else {
                EmptyMessage("No plays on this device.", Modifier.padding(padding))
            }
            return@Scaffold
        }
        val productions by plays.store.productions.collectAsState()
        LazyColumn(Modifier.fillMaxSize(), contentPadding = padding) {
            if (productions.isNotEmpty()) {
                item(key = "yours-h") { SectionHeader("Your plays") }
                items(productions, key = { "p:" + it.id }) { production ->
                    ProductionRow(production, onOpen = { onOpenProduction(production.id) })
                }
            }
            item(key = "cast-h") { SectionHeader("Plays you can cast") }
            items(ready.scripts, key = { "s:" + it.id }) { script ->
                ListItem(
                    headlineContent = { Text(script.title, style = MaterialTheme.typography.titleMedium) },
                    supportingContent = {
                        Column {
                            val speaking = script.castParts.count { it.id.isSpeaking }
                            Text(
                                listOf(script.authorLine, "$speaking parts").filter { it.isNotEmpty() }.joinToString(" · "),
                                style = MaterialTheme.typography.bodyMedium,
                            )
                            RightsLine(script)
                        }
                    },
                    modifier = Modifier.clickable(onClickLabel = "Open play") { onOpenScript(script.id) },
                )
            }
        }
    }
}

@Composable
private fun ProductionRow(production: Production, onOpen: () -> Unit) {
    val script = rememberCastScript(production.id)
    var confirming by remember { mutableStateOf(false) }
    ListItem(
        headlineContent = { Text(production.title, style = MaterialTheme.typography.titleMedium) },
        supportingContent = { Text(progressLine(production, script), style = MaterialTheme.typography.labelMedium) },
        trailingContent = {
            IconButton(onClick = { confirming = true }) {
                Icon(Icons.Outlined.Delete, contentDescription = "Delete production")
            }
        },
        modifier = Modifier.clickable(onClickLabel = "Open production", onClick = onOpen),
    )
    if (confirming) DeleteProductionDialog(production, onDismiss = { confirming = false }, onDeleted = {})
}

private fun progressLine(production: Production, script: PlayScript?): String {
    if (production.isFinished) return "Finished"
    script ?: return ""
    val total = script.speechLineIDs.size
    return "${total - Relay.missingSpeech(production, script).size} of $total lines recorded"
}

@Composable
fun rememberCastScript(productionId: String): PlayScript? {
    val plays = LocalAppContainer.current.plays
    val script by produceState(plays.cachedCastScript(productionId), productionId) {
        value = plays.castScript(productionId)
    }
    return script
}

/** The record's own evidence, verbatim and linked so a reader can check it (§2.1), then the source. */
@Composable
private fun RightsLine(script: PlayScript) {
    val link = TextLinkStyles(SpanStyle(color = MaterialTheme.colorScheme.primary, textDecoration = TextDecoration.Underline))
    val text = buildAnnotatedString {
        val claims = script.rights.evidence.filter { it.claim != null }
        claims.forEachIndexed { i, evidence ->
            if (i > 0) append(" · ")
            val src = evidence.src
            if (src != null) withLink(LinkAnnotation.Url(src, link)) { append(evidence.claim!!) } else append(evidence.claim!!)
        }
        if (claims.isNotEmpty()) append(" · ")
        withLink(LinkAnnotation.Url(script.source.url, link)) { append(script.source.name) }
    }
    Text(text, style = MaterialTheme.typography.labelMedium)
}

// MARK: The script

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ScriptScreen(id: String, onBack: () -> Unit, onOpenProduction: (String) -> Unit) {
    val plays = LocalAppContainer.current.plays
    LaunchedEffect(Unit) { plays.load() }
    val state by plays.state.collectAsState()
    val script = (state as? PlaysLibrary.State.Ready)?.scripts?.firstOrNull { it.id == id }
    val scope = rememberCoroutineScope()
    var error by remember { mutableStateOf<String?>(null) }
    Scaffold(topBar = { BackBar(onBack) }) { padding ->
        if (script == null) {
            if (state !is PlaysLibrary.State.Loading) EmptyMessage("This play is not on this device.", Modifier.padding(padding))
            return@Scaffold
        }
        val pad = Modifier.padding(horizontal = Spacing.S4.dp)
        LazyColumn(Modifier.fillMaxSize(), contentPadding = padding) {
            item(key = "head") {
                Column(pad, verticalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
                    Text(script.title, style = MaterialTheme.typography.headlineSmall, modifier = Modifier.semantics { heading() })
                    if (script.authorLine.isNotEmpty()) Text(script.authorLine, style = MaterialTheme.typography.bodyMedium)
                    RightsLine(script)
                    Button(onClick = {
                        scope.launch {
                            runCatching { plays.create(script) }
                                .onSuccess { onOpenProduction(it.id) }
                                .onFailure { error = it.message ?: "The production could not be saved." }
                        }
                    }) {
                        Icon(Icons.Filled.Groups, contentDescription = null)
                        Text("Cast this play", Modifier.padding(start = Spacing.S2.dp))
                    }
                    error?.let { ErrorLine(it) }
                }
            }
            item(key = "parts-h") { SectionHeader("Parts") }
            items(script.castParts, key = { "part:" + it.id.raw }) { part ->
                ListItem(
                    headlineContent = { Text(part.title) },
                    trailingContent = { Text(lineCount(part.lineCount), style = MaterialTheme.typography.bodySmall) },
                )
            }
        }
    }
}

private fun lineCount(n: Int) = if (n == 1) "1 line" else "$n lines"

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun BackBar(onBack: () -> Unit, title: String = "") {
    TopAppBar(
        title = { if (title.isNotEmpty()) Text(title) },
        navigationIcon = {
            IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back") }
        },
    )
}

@Composable
internal fun ErrorLine(text: String) {
    val haptics = rememberHaptics()
    LaunchedEffect(text) { haptics(Haptic.Error) }
    Text(text, style = MaterialTheme.typography.bodyMedium, color = AppSemantics.colors.error)
}

// MARK: The cast sheet

/** Who takes which part (§2.2-2.5). Parts are listed largest first; only the relay's next part can be taken, one at a time (pending owner, C7). */
@Composable
fun ProductionScreen(id: String, onBack: () -> Unit, onRecord: (PartID) -> Unit) {
    val plays = LocalAppContainer.current.plays
    val productions by plays.store.productions.collectAsState()
    val production = productions.firstOrNull { it.id == id }
    val script = rememberCastScript(id)
    var refusal by remember { mutableStateOf<String?>(null) }
    var taking by remember { mutableStateOf<PartID?>(null) }
    var confirmingDelete by remember { mutableStateOf(false) }
    val haptics = rememberHaptics()

    fun apply(change: (Production) -> Production): Boolean {
        val latest = plays.store.production(id) ?: return false
        return try {
            plays.store.save(change(latest))
            refusal = null
            true
        } catch (e: Relay.Refusal) {
            refusal = e.text
            false
        } catch (e: Exception) {
            refusal = e.message
            false
        }
    }

    Scaffold(topBar = { BackBar(onBack, production?.title.orEmpty()) }) { padding ->
        if (production == null || script == null) {
            if (production == null) EmptyMessage("This production is not on this device.", Modifier.padding(padding))
            return@Scaffold
        }
        val next = Relay.next(production, script)
        val current = Relay.current(production, script)
        LazyColumn(Modifier.fillMaxSize(), contentPadding = padding) {
            items(script.castParts, key = { "part:" + it.id.raw }) { part ->
                CastRow(
                    part = part,
                    state = production.state(part.id),
                    status = partStatus(part, production, script),
                    isNext = part.id == next,
                    canReopen = current == null,
                    onRecord = { onRecord(part.id) },
                    onTake = { taking = part.id },
                    onLeaveSilent = { apply { Relay.leaveSilent(part.id, it, script) } },
                    onReopen = { if (apply { Relay.reopen(part.id, it, script) }) haptics(Haptic.Selection) },
                )
            }
            refusal?.let { item(key = "refusal") { Column(Modifier.padding(horizontal = Spacing.S4.dp)) { ErrorLine(it) } } }
            item(key = "listen-h") { SectionHeader("Listen") }
            item(key = "listen") { ListenThrough(production, script) }
            item(key = "manage") {
                Column(Modifier.padding(horizontal = Spacing.S4.dp, vertical = Spacing.S4.dp)) {
                    if (production.unusedTakes.isNotEmpty()) {
                        TextButton(onClick = { runCatching { plays.store.discardUnusedTakes(id) }.onFailure { refusal = it.message } }) {
                            Text("Discard unused takes")
                        }
                    }
                    TextButton(onClick = { confirmingDelete = true }) {
                        Text("Delete production", color = AppSemantics.colors.error)
                    }
                }
            }
        }
        taking?.let { part ->
            TakePartDialog(
                part = part,
                onDismiss = { taking = null },
                onTake = { name ->
                    taking = null
                    if (apply { Relay.take(part, name, it, script) }) onRecord(part)
                },
            )
        }
        if (confirmingDelete) DeleteProductionDialog(production, onDismiss = { confirmingDelete = false }, onDeleted = onBack)
    }
}

private fun partStatus(part: CastPart, production: Production, script: PlayScript): String {
    val state = production.state(part.id)
    val lines = lineCount(part.lineCount)
    val name = state.performer?.let { " · $it" } ?: ""
    return when (state.status) {
        PartState.Status.Open -> lines
        PartState.Status.Recording -> "${part.lineCount - Relay.missingLines(part.id, production, script).size} of $lines recorded$name"
        PartState.Status.Done -> "Recorded$name"
        PartState.Status.Silent -> "Left silent"
    }
}

@Composable
private fun CastRow(
    part: CastPart,
    state: PartState,
    status: String,
    isNext: Boolean,
    canReopen: Boolean,
    onRecord: () -> Unit,
    onTake: () -> Unit,
    onLeaveSilent: () -> Unit,
    onReopen: () -> Unit,
) {
    ListItem(
        headlineContent = { Text(part.title, style = MaterialTheme.typography.titleMedium) },
        supportingContent = { Text(status, style = MaterialTheme.typography.labelMedium) },
        trailingContent = {
            Row(horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp), verticalAlignment = Alignment.CenterVertically) {
                when (state.status) {
                    PartState.Status.Recording -> Button(onClick = onRecord) { Text("Record") }
                    PartState.Status.Open -> if (isNext) {
                        if (!part.id.isSpeaking) OutlinedButton(onClick = onLeaveSilent) { Text("Leave silent") }
                        Button(onClick = onTake) { Text("Take part") }
                    }
                    PartState.Status.Done, PartState.Status.Silent -> {
                        var open by remember { mutableStateOf(false) }
                        IconButton(onClick = { open = true }, enabled = canReopen) {
                            Icon(Icons.Filled.MoreVert, contentDescription = "More for ${part.title}")
                        }
                        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
                            DropdownMenuItem(text = { Text("Open part") }, onClick = { open = false; onReopen() })
                        }
                    }
                }
            }
        },
    )
}

@Composable
private fun TakePartDialog(part: PartID, onDismiss: () -> Unit, onTake: (String) -> Unit) {
    var name by remember { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(part.title) },
        text = {
            OutlinedTextField(value = name, onValueChange = { name = it }, label = { Text("Your name") }, singleLine = true)
        },
        confirmButton = { TextButton(onClick = { onTake(name) }) { Text("Take part") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

/** Deleting a production deletes its folder: every take, the room tone, the mix (§6). */
@Composable
private fun DeleteProductionDialog(production: Production, onDismiss: () -> Unit, onDeleted: () -> Unit) {
    val plays = LocalAppContainer.current.plays
    val scope = rememberCoroutineScope()
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Delete ${production.title}?") },
        text = { Text("Every take is removed from this device.") },
        confirmButton = {
            TextButton(onClick = {
                onDismiss()
                scope.launch {
                    plays.delete(production.id)
                    onDeleted()
                }
            }) { Text("Delete", color = AppSemantics.colors.error) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

// MARK: Listen through, finish, keep

/**
 * Pending owner (C5): a half-recorded play is not previewed outside the
 * recording flow. Listening through is offered only when every speaking line
 * has a human take, so it never holds a device voice; reaching the end of it
 * without skipping ahead finishes the play (§2.6-2.7).
 */
@Composable
private fun ListenThrough(production: Production, script: PlayScript) {
    val container = LocalAppContainer.current
    val plays = container.plays
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val haptics = rememberHaptics()
    val mix = remember { MixPlayback() }
    var mixing by remember { mutableStateOf(false) }
    var loaded by remember { mutableStateOf(false) }
    var playing by remember { mutableStateOf(false) }
    var position by remember { mutableFloatStateOf(0f) }
    var error by remember { mutableStateOf<String?>(null) }
    var listenedFrom by remember { mutableStateOf<String?>(null) }
    val missing = Relay.missingSpeech(production, script).size

    DisposableEffect(production.chosenFingerprint) {
        onDispose {
            mix.stop()
            loaded = false
            playing = false
        }
    }
    LaunchedEffect(loaded) {
        while (loaded) {
            position = mix.positionMs.toFloat()
            playing = mix.isPlaying
            delay(500)
        }
    }

    Column(Modifier.fillMaxWidth().padding(horizontal = Spacing.S4.dp), verticalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
        when {
            missing > 0 -> Text(
                if (missing == 1) "1 line still needs a voice." else "$missing lines still need a voice.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            mixing -> CircularProgressIndicator(Modifier.semantics { contentDescription = "Mixing" })
            loaded -> {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.S4.dp)) {
                    IconButton(onClick = {
                        if (container.playback.state.value.isPlaying) container.playback.togglePlay()
                        mix.toggle()
                        playing = mix.isPlaying
                        haptics(Haptic.Selection)
                    }) {
                        Icon(
                            if (playing) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                            contentDescription = if (playing) "Pause" else "Play",
                        )
                    }
                    if (production.isFinished) {
                        OutlinedButton(onClick = { shareMix(context, plays.store.mixFile(production.id)) }) {
                            Icon(Icons.Filled.Share, contentDescription = null)
                            Text("Export", Modifier.padding(start = Spacing.S2.dp))
                        }
                    }
                }
                val duration = mix.durationMs.coerceAtLeast(1).toFloat()
                val clock = "${formatClock(position.toLong())} of ${formatClock(duration.toLong())}"
                if (production.isFinished) {
                    Slider(
                        value = position.coerceIn(0f, duration),
                        onValueChange = { position = it; mix.seek(it.toInt()) },
                        valueRange = 0f..duration,
                        modifier = Modifier.semantics { contentDescription = "Position"; stateDescription = clock },
                    )
                } else {
                    LinearProgressIndicator(
                        progress = { (position / duration).coerceIn(0f, 1f) },
                        modifier = Modifier.fillMaxWidth().semantics { stateDescription = clock },
                    )
                }
            }
            else -> Button(onClick = {
                scope.launch {
                    mixing = true
                    try {
                        val file = plays.renderMix(production.id)
                        listenedFrom = plays.store.production(production.id)?.chosenFingerprint
                        mix.onEnded = {
                            playing = false
                            val from = listenedFrom
                            if (!mix.skipped && from != null) plays.store.markListenedThrough(production.id, from)
                        }
                        mix.load(file)
                        loaded = true
                        error = null
                        if (container.playback.state.value.isPlaying) container.playback.togglePlay()
                        mix.toggle()
                        playing = true
                    } catch (e: Exception) {
                        error = e.message ?: "The play could not be mixed."
                    } finally {
                        mixing = false
                    }
                }
            }) {
                Icon(Icons.Filled.PlayArrow, contentDescription = null)
                Text(if (production.isFinished) "Play" else "Listen through", Modifier.padding(start = Spacing.S2.dp))
            }
        }
        error?.let { ErrorLine(it) }
    }
}

/** The person's own act, through the share sheet (§2.7); only a finished play is offered. */
private fun shareMix(context: Context, file: File) {
    val uri = FileProvider.getUriForFile(context, context.packageName + ".plays", file)
    val send = Intent(Intent.ACTION_SEND)
        .setType("audio/mp4")
        .putExtra(Intent.EXTRA_STREAM, uri)
        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    context.startActivity(Intent.createChooser(send, null))
}
