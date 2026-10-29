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
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Stop
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
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.lifecycle.repeatOnLifecycle
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
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
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
import com.example.appname.plays.LiveListen
import com.example.appname.plays.MixPlayback
import com.example.appname.plays.PartID
import com.example.appname.plays.PartState
import com.example.appname.plays.PlayScript
import com.example.appname.plays.PlaysLibrary
import com.example.appname.plays.PlaysShare
import com.example.appname.plays.Production
import com.example.appname.plays.Relay
import com.example.appname.ui.AccountRow
import com.example.appname.ui.ArtTile
import com.example.appname.ui.EmptyMessage
import com.example.appname.ui.Haptic
import com.example.appname.ui.LocalAppContainer
import com.example.appname.ui.LocalIsTelevision
import com.example.appname.ui.tvFocusMark
import com.example.appname.ui.SectionHeader
import com.example.appname.ui.formatClock
import com.example.appname.ui.rememberHaptics
import com.example.appname.ui.theme.AppSemantics
import com.example.appname.ui.theme.OnAir
import com.example.appname.ui.playButtonColors
import com.example.appname.ui.theme.Spacing
import java.io.File
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// Ear dramas, phase 1, pass the phone (docs/PLAYS-DESIGN.md, binding; ANDROID-DESIGN
// §4.9). The same seven verbs as iPhone, iPad, and the Mac (§2): pick a play,
// read the cast sheet, take a part, record line by line, pass the phone, listen
// through, finish and keep it, in Material's own components.

// MARK: Where an ear drama starts (Decision 068)

// There is no Plays tab: a play is a row in Browse and Search and a pick on
// Surprise, and the person's productions are Library's Ear dramas. A TV records
// nothing (PLAYS-DESIGN §2), so there none of these is offered.

/** The castable plays, or none on a TV. */
@Composable
fun rememberCastablePlays(): List<PlayScript> {
    val television = LocalIsTelevision.current
    val plays = LocalAppContainer.current.plays
    val state by plays.state.collectAsState()
    LaunchedEffect(television) { if (!television) plays.load() }
    if (television) return emptyList()
    return (state as? PlaysLibrary.State.Ready)?.scripts.orEmpty()
}

/** Word-prefix, as every search here (§3.4): each typed word begins a word of the title or author. */
fun playsMatching(scripts: List<PlayScript>, query: String): List<PlayScript> {
    fun words(text: String) = text.lowercase().split(Regex("[^\\p{L}\\p{N}]+")).filter { it.isNotEmpty() }
    val typed = words(query)
    if (typed.isEmpty()) return emptyList()
    return scripts.filter { script ->
        val have = words("${script.title} ${script.authorLine}")
        typed.all { w -> have.any { it.startsWith(w) } }
    }
}

/** A play as a list row: its title, then author and part count; it opens the play's page. */
@Composable
fun PlayListItem(script: PlayScript, onOpen: () -> Unit) {
    val speaking = script.castParts.count { it.id.isSpeaking }
    ListItem(
        // R11a: a play's row leads with its tile, the title's letter (plays carry no genre).
        leadingContent = { ArtTile(script.title, null, null) },
        headlineContent = { Text(script.title, style = MaterialTheme.typography.titleMedium) },
        supportingContent = {
            Text(
                listOf(script.authorLine, "$speaking parts").filter { it.isNotEmpty() }.joinToString(" · "),
                style = MaterialTheme.typography.bodyMedium,
            )
        },
        modifier = Modifier.clickable(onClickLabel = "Open play", onClick = onOpen).tvFocusMark(),
    )
}

/** "Start an ear drama" (PLAYS-DESIGN §2.1): makes the production and opens its cast sheet. */
@Composable
fun StartEarDramaButton(script: PlayScript, onOpenProduction: (String) -> Unit) {
    val plays = LocalAppContainer.current.plays
    val scope = rememberCoroutineScope()
    var error by remember { mutableStateOf<String?>(null) }
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
        Button(onClick = {
            scope.launch {
                runCatching { plays.create(script) }
                    .onSuccess { onOpenProduction(it.id) }
                    .onFailure { error = it.message ?: "The production could not be saved." }
            }
        }) {
            Icon(Icons.Filled.Groups, contentDescription = null)
            Text("Start an ear drama", Modifier.padding(start = Spacing.S2.dp))
        }
        error?.let { ErrorLine(it) }
    }
}

/**
 * Library's Ear dramas (§4.6, §4.16): the held invitation, this device's
 * productions, the shared ones this person is in that the device has not
 * opened, then Classes. None on a TV.
 */
fun LazyListScope.earDramasSection(
    rows: List<PlaysShare.LibraryRow>,
    invite: String?,
    classes: Boolean,
    onOpenProduction: (String) -> Unit,
) {
    if (rows.isEmpty() && invite == null && !classes) return
    item(key = "dramas-h") { SectionHeader("Ear dramas") }
    if (invite != null) item(key = "invitation") { InvitationItem(invite, onOpenProduction) }
    items(rows, key = { "d:" + (it.local?.id ?: it.pid) }) { row ->
        val production = row.local
        val remote = row.remote
        if (production != null) {
            ProductionRow(production, onOpen = { onOpenProduction(production.id) })
        } else if (remote != null) {
            RemoteProductionRow(remote, onOpenProduction)
        }
    }
    if (classes) item(key = "classes") { Column { ClassesBlock() } }
}

@Composable
internal fun ProductionRow(production: Production, onOpen: () -> Unit) {
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
    val link = TextLinkStyles(SpanStyle(color = OnAir.colors.link, textDecoration = TextDecoration.Underline))
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
                    if (script.authorLine.isNotEmpty()) Text(script.authorWithYears, style = MaterialTheme.typography.bodyMedium)
                    Text(
                        listOfNotNull(script.year?.toString(), script.lengthLine).joinToString(" \u00b7 "),
                        style = MaterialTheme.typography.labelMedium,
                    )
                    RightsLine(script)
                    if (!LocalIsTelevision.current) StartEarDramaButton(script, onOpenProduction)
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

/** Who takes which part (§2.2-2.5). Parts are listed largest first; any open part can be taken, one recording at a time (Decision 067, C7). */
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
    val container = LocalAppContainer.current
    val sharing = container.sharing
    val television = LocalIsTelevision.current
    val account by container.accounts.account.collectAsState()
    val me = account?.userId
    val links by sharing.links.collectAsState()
    val records by sharing.records.collectAsState()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    // A TV plays back only (PLAYS-DESIGN §11.7): a shared production there is just a local one.
    val link = remember(id, links, television) { if (television) null else links[id] ?: sharing.linkOf(id) }
    val rec = records[id]
    val sheet = if (link != null && script != null) {
        remember(id, script) { SharedSheet(id, script, sharing, scope, context, onRecord) }
    } else {
        null
    }
    var syncError by remember { mutableStateOf<String?>(null) }
    var shareError by remember { mutableStateOf<String?>(null) }
    val lifecycle = androidx.lifecycle.compose.LocalLifecycleOwner.current.lifecycle
    LaunchedEffect(link?.pid, me, lifecycle) {
        if (link == null || me == null) return@LaunchedEffect
        // Re-read on every return to the screen and while it shows, never in the background (§11.7 rule 7).
        lifecycle.repeatOnLifecycle(androidx.lifecycle.Lifecycle.State.STARTED) {
            while (true) {
                try {
                    sharing.refresh(id)
                    syncError = null
                } catch (e: kotlinx.coroutines.CancellationException) {
                    throw e
                } catch (e: Exception) {
                    syncError = PlaysShare.line(e)
                }
                delay(20_000)
            }
        }
    }

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
        val pendingByPart = remember(production, rec, me) {
            if (rec == null) emptyMap() else PlaysShare.pending(production, script, rec, me).groupingBy { it.part.raw }.eachCount()
        }
        LazyColumn(Modifier.fillMaxSize(), contentPadding = padding) {
            if (!television && link == null) {
                item(key = "share") {
                    ShareEntry(
                        signedIn = account != null,
                        error = shareError,
                        onShare = { name ->
                            shareError = null
                            scope.launch {
                                try {
                                    sharing.share(id, script, name)
                                } catch (e: kotlinx.coroutines.CancellationException) {
                                    throw e
                                } catch (e: Exception) {
                                    shareError = PlaysShare.line(e)
                                }
                            }
                        },
                    )
                }
            }
            if (link != null && me == null) {
                item(key = "shared-signed-out") {
                    Column(Modifier.padding(horizontal = Spacing.S4.dp), verticalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
                        Text("Sharing needs an account.", style = MaterialTheme.typography.bodyMedium)
                        AccountRow()
                    }
                }
            }
            if (link != null && sheet != null) {
                syncError?.let { item(key = "sync-error") { Column(Modifier.padding(horizontal = Spacing.S4.dp)) { ErrorLine(it) } } }
                sharedCastRows(sheet, rec, me, pendingByPart, onRecord)
            }
            if (link == null) items(script.castParts, key = { "part:" + it.id.raw }) { part ->
                CastRow(
                    part = part,
                    state = production.state(part.id),
                    status = partStatus(part, production, script),
                    isNext = part.id == next,
                    canTake = current == null,
                    canReopen = current == null,
                    onRecord = { onRecord(part.id) },
                    onTake = { taking = part.id },
                    onLeaveSilent = { apply { Relay.leaveSilent(part.id, it, script) } },
                    onReopen = { if (apply { Relay.reopen(part.id, it, script) }) haptics(Haptic.Selection) },
                )
            }
            refusal?.let { item(key = "refusal") { Column(Modifier.padding(horizontal = Spacing.S4.dp)) { ErrorLine(it) } } }
            item(key = "listen-h") { SectionHeader("Listen") }
            item(key = "listen") { ListenThrough(production, script, sheet) }
            if (rec != null && rec.hiddenTakes > 0) {
                item(key = "hidden") {
                    Text(
                        if (rec.hiddenTakes == 1) "1 take is hidden from you." else "${rec.hiddenTakes} takes are hidden from you.",
                        Modifier.padding(horizontal = Spacing.S4.dp),
                        style = MaterialTheme.typography.labelMedium,
                    )
                }
            }
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
    canTake: Boolean,
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
                    PartState.Status.Open -> {
                        if (!part.id.isSpeaking) OutlinedButton(onClick = onLeaveSilent) { Text("Leave silent") }
                        if (canTake) {
                            if (isNext) Button(onClick = onTake) { Text("Take part") } else OutlinedButton(onClick = onTake) { Text("Take part") }
                        }
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
 * Listening is open at any time (Decision 067). A complete play plays its mix;
 * reaching the end without skipping ahead finishes it (§2.6-2.7). Any other
 * play runs live: takes from their files, every other speech line read by the
 * device voice, labeled, writing nothing and never finishing the play.
 * Export is offered whenever the play is complete.
 */
@Composable
private fun ListenThrough(production: Production, script: PlayScript, shared: SharedSheet?) {
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
    var live by remember { mutableStateOf<LiveListen?>(null) }
    var liveJob by remember { mutableStateOf<Job?>(null) }
    var reportingTake by remember { mutableStateOf<String?>(null) }
    val complete = Relay.isComplete(production, script)

    fun stopLive() {
        liveJob?.cancel()
        live?.close()
        liveJob = null
        live = null
    }

    DisposableEffect(production.chosenFingerprint) {
        onDispose {
            mix.stop()
            stopLive()
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
        val running = live
        when {
            running != null -> LiveListenPanel(running, script, onStop = { stopLive() }, onReport = shared?.let { { id: String -> reportingTake = id } })
            mixing -> CircularProgressIndicator(Modifier.semantics { contentDescription = "Mixing" })
            complete && loaded -> {
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
                            tint = OnAir.colors.play,
                        )
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
                        colors = SliderDefaults.colors(thumbColor = OnAir.colors.play, activeTrackColor = OnAir.colors.play),
                    )
                } else {
                    LinearProgressIndicator(
                        progress = { (position / duration).coerceIn(0f, 1f) },
                        modifier = Modifier.fillMaxWidth().semantics { stateDescription = clock },
                        color = OnAir.colors.play,
                    )
                }
            }
            complete -> Button(onClick = {
                scope.launch {
                    mixing = true
                    try {
                        shared?.prepareListen()
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
            }, colors = playButtonColors()) {
                Icon(Icons.Filled.PlayArrow, contentDescription = null)
                Text(if (production.isFinished) "Play" else "Listen through", Modifier.padding(start = Spacing.S2.dp))
            }
            else -> Button(onClick = {
                if (container.playback.state.value.isPlaying) container.playback.togglePlay()
                val listen = LiveListen(context, plays.store.takesFolder(production.id))
                live = listen
                liveJob = scope.launch {
                    try {
                        shared?.prepareListen()
                        listen.run(Relay.listenPlan(plays.store.production(production.id) ?: production, script))
                    } finally {
                        if (live === listen) {
                            listen.close()
                            live = null
                            liveJob = null
                        }
                    }
                }
            }, colors = playButtonColors()) {
                Icon(Icons.Filled.PlayArrow, contentDescription = null)
                Text("Listen through", Modifier.padding(start = Spacing.S2.dp))
            }
        }
        if (complete && running == null) {
            OutlinedButton(onClick = {
                scope.launch {
                    try {
                        shareMix(context, plays.renderMix(production.id))
                        error = null
                    } catch (e: Exception) {
                        error = e.message ?: "The play could not be mixed."
                    }
                }
            }, enabled = !mixing) {
                Icon(Icons.Filled.Share, contentDescription = null)
                Text("Export", Modifier.padding(start = Spacing.S2.dp))
            }
        }
        error?.let { ErrorLine(it) }
        shared?.error?.let { ErrorLine(it) }
    }
    reportingTake?.let { takeId ->
        ReportDialog(onDismiss = { reportingTake = null }, onReport = { reason, note ->
            reportingTake = null
            shared?.report(null, takeId, reason, note)
        })
    }
}

/** The line being heard, its speaker, and "Device voice" on a line the device reads, so a stand-in never passes as a person. */
@Composable
private fun LiveListenPanel(listen: LiveListen, script: PlayScript, onStop: () -> Unit, onReport: ((String) -> Unit)?) {
    val entry by listen.current.collectAsState()
    val line = entry?.let { e -> script.lines.firstOrNull { it.id == e.lineID } }
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.S2.dp), modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite }) {
        if (entry is Relay.ListenEntry.Voice) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.GraphicEq, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                Text("Device voice", Modifier.padding(start = Spacing.S1.dp), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
            }
        }
        line?.role?.let { Text(it, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        line?.let { Text(it.spokenText, style = MaterialTheme.typography.headlineSmall) }
    }
    OutlinedButton(onClick = onStop) {
        Icon(Icons.Filled.Stop, contentDescription = null)
        Text("Stop", Modifier.padding(start = Spacing.S2.dp))
    }
    // Another member's take arrived as m-{id}.wav (PlaysShare.bringHome): it can be reported from here.
    val heard = entry as? Relay.ListenEntry.TakeEntry
    if (onReport != null && heard != null && heard.take.file.startsWith("m-")) {
        TextButton(onClick = { onReport(heard.take.id) }) { Text("Report") }
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
