package com.example.appname.ui.screens

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.example.appname.data.EpisodeRow
import com.example.appname.data.SeriesRow
import com.example.appname.plays.DramaAudio
import com.example.appname.navigation.SiteLinks
import com.example.appname.plays.FinishedList
import com.example.appname.plays.FinishedPlay
import com.example.appname.plays.InviteView
import com.example.appname.plays.OpenInvite
import com.example.appname.plays.OpenPart
import com.example.appname.plays.OpenPlaysView
import com.example.appname.plays.PartID
import com.example.appname.plays.PlayScript
import com.example.appname.plays.PlaysException
import com.example.appname.plays.PlaysLibrary
import com.example.appname.plays.PlaysShare
import com.example.appname.ui.ActionRow
import com.example.appname.ui.EmptyAction
import com.example.appname.ui.EmptyMessage
import com.example.appname.ui.EventLine
import com.example.appname.ui.HeadBoard
import com.example.appname.ui.LocalAppContainer
import com.example.appname.ui.LocalIsTelevision
import com.example.appname.ui.OFFLINE_LINE
import com.example.appname.ui.PLAY_BOARD
import com.example.appname.ui.SectionHeader
import com.example.appname.ui.ShareButton
import com.example.appname.ui.SignInSheet
import com.example.appname.ui.TileGrid
import com.example.appname.ui.TileSpec
import com.example.appname.ui.formatCount
import com.example.appname.ui.theme.onBoardColor
import com.example.appname.ui.partMark
import com.example.appname.ui.playButtonColors
import com.example.appname.ui.theme.OnAir
import com.example.appname.ui.theme.Spacing
import com.example.appname.ui.tvFocusMark
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import java.io.File

// The invitation, the finished ear dramas and a finished drama's page (D3-7; owner rulings 2 and 3,
// 2026-10-29; DESIGN-LOOP.md). Stateless content on top, so an offline render draws every state.

// MARK: The voice strip, the mark under a drama's head board

/** One segment per part, as wide as its share of the play; a segment of a part nobody holds is faint. */
@Composable
fun VoiceStrip(segments: List<Pair<Float, Boolean>>, onBoard: Color, height: Dp, modifier: Modifier = Modifier) {
    if (segments.isEmpty()) return
    val total = segments.sumOf { it.first.toDouble() }.toFloat().coerceAtLeast(1f)
    Canvas(modifier.fillMaxWidth().height(height).semantics { contentDescription = "${segments.size} parts by size" }) {
        val gap = 2.dp.toPx()
        val room = size.width - gap * (segments.size - 1)
        var x = 0f
        segments.forEach { (weight, held) ->
            val w = room * weight / total
            drawRoundRect(
                onBoard.copy(alpha = if (held) 1f else 0.35f),
                Offset(x, 0f), Size(w.coerceAtLeast(1f), size.height), CornerRadius(2.dp.toPx()),
            )
            x += w + gap
        }
    }
}

// MARK: The invitation

/** What the invitation page knows of its read. */
sealed interface InviteState {
    data object Loading : InviteState
    data class Ready(val invite: OpenInvite) : InviteState
    data class Failed(val line: String) : InviteState
}

/** The invitation held for this session, read with no account; a signed-in reader also learns whether they are in. */
@Composable
fun InvitationScreen(onBack: () -> Unit, onOpenProduction: (String) -> Unit) {
    val container = LocalAppContainer.current
    val sharing = container.sharing
    val token by sharing.invite.collectAsState()
    val account by container.accounts.account.collectAsState()
    val signedIn = account != null
    val plays = container.plays
    LaunchedEffect(Unit) { plays.load() }
    val library by plays.state.collectAsState()
    var attempt by remember { mutableIntStateOf(0) }
    var state by remember { mutableStateOf<InviteState>(InviteState.Loading) }
    var view by remember { mutableStateOf<InviteView?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var name by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var asking by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val player = remember { InvitePlayer() }
    DisposableEffect(Unit) { onDispose { player.stop() } }

    LaunchedEffect(token, attempt) {
        val t = token ?: return@LaunchedEffect
        state = InviteState.Loading
        state = try {
            InviteState.Ready(container.openPlays.openInvite(t))
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            InviteState.Failed(PlaysShare.line(e))
        }
    }
    LaunchedEffect(token, signedIn) {
        view = null
        val t = token ?: return@LaunchedEffect
        if (signedIn) view = runCatching { sharing.viewInvite(t) }.getOrNull()
    }
    val context = LocalContext.current
    Scaffold(topBar = { BackBar(onBack) }) { padding ->
        val t = token
        val s = state
        when {
            t == null -> EmptyMessage("This invitation is no longer open.", Modifier.padding(padding))
            s is InviteState.Loading -> Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(Modifier.semantics { contentDescription = "Loading" })
            }
            s is InviteState.Failed -> EmptyMessage(s.line, Modifier.padding(padding), action = EmptyAction("Try again") { attempt++ })
            s is InviteState.Ready -> {
                val inv = s.invite
                val script = (library as? PlaysLibrary.State.Ready)?.scripts?.let { PlaysShare.scriptFor(it, inv.scriptID, inv.scriptRevision) }
                val lineOrder = remember(script) { script?.lines?.map { it.id }.orEmpty() }
                InviteContent(
                    inv = inv,
                    script = script,
                    signedIn = signedIn,
                    member = view?.member == true,
                    playing = player.playing,
                    hearing = player.fetching,
                    error = error ?: player.error,
                    name = name,
                    onName = { name = it },
                    onPlayPart = { part ->
                        if (player.playing == part) player.stop()
                        else player.play(part, OpenPlaysView.playOrder(inv, lineOrder, part), scope, context.cacheDir) { id -> container.openPlays.audio(t, id) }
                    },
                    onListenAll = {
                        if (player.playing == ALL) player.stop()
                        else player.play(ALL, OpenPlaysView.playOrder(inv, lineOrder), scope, context.cacheDir) { id -> container.openPlays.audio(t, id) }
                    },
                    onTake = { part ->
                        val v = view
                        when {
                            !signedIn -> asking = true
                            busy || v == null -> Unit
                            else -> {
                                busy = true
                                error = null
                                scope.launch {
                                    try {
                                        onOpenProduction(sharing.join(t, part, name, v.scriptID, v.scriptRevision).id)
                                    } catch (e: CancellationException) {
                                        throw e
                                    } catch (e: Exception) {
                                        error = PlaysShare.line(e)
                                    } finally {
                                        busy = false
                                    }
                                }
                            }
                        }
                    },
                    onOpen = {
                        val v = view ?: return@InviteContent
                        scope.launch {
                            try {
                                onOpenProduction(sharing.openRemote(v.id).id)
                            } catch (e: CancellationException) {
                                throw e
                            } catch (e: Exception) {
                                error = PlaysShare.line(e)
                            }
                        }
                    },
                    contentPadding = padding,
                )
            }
        }
    }
    if (asking) SignInSheet("Taking a part needs an account.") { asking = false }
}

internal const val ALL = "*"

/**
 * The page: the head board (the play, who directs, the voice strip), Listen through, and a row per
 * part with who holds it and a play control for its takes. Signed out it is all here; only Take part
 * asks for an account, through [onTake].
 */
@Composable
fun InviteContent(
    inv: OpenInvite,
    script: PlayScript?,
    signedIn: Boolean,
    member: Boolean,
    playing: String?,
    hearing: Boolean,
    error: String?,
    name: String,
    onName: (String) -> Unit,
    onPlayPart: (String) -> Unit,
    onListenAll: () -> Unit,
    onTake: (String) -> Unit,
    onOpen: () -> Unit,
    contentPadding: PaddingValues,
) {
    val anyRecording = inv.parts.any { it.status == "recording" }
    val speaking = inv.parts.filter { PartID(it.id).isSpeaking }
    val director = inv.members.firstOrNull { it.director }?.name?.takeIf { it.isNotBlank() }
    val facts = listOf(
        "${speaking.size} ${if (speaking.size == 1) "part" else "parts"}",
        speaking.count { it.status == "open" }.takeIf { it > 0 }?.let { "$it open" },
    )
    LazyColumn(Modifier.fillMaxSize(), contentPadding = contentPadding) {
        item(key = "head") {
            HeadBoard(
                name = inv.title,
                genre = PLAY_BOARD,
                art = null,
                kicker = "Ear drama · in progress",
                facts = facts,
                first = null,
                last = null,
                credits = director?.let { "Directed by $it" },
                mark = { h ->
                    val on = onBoardColor(PLAY_BOARD, OnAir.colors.dark)
                    Box(Modifier.height(h), contentAlignment = Alignment.BottomStart) {
                        VoiceStrip(speaking.map { it.lineCount.toFloat() to (it.status != "open") }, on, 10.dp)
                    }
                },
            )
        }
        if (inv.takes.isNotEmpty()) {
            item(key = "actions") {
                ActionRow(Modifier.padding(horizontal = Spacing.S4.dp, vertical = Spacing.S3.dp)) {
                    Button(onClick = onListenAll, colors = playButtonColors()) {
                        Icon(if (playing == ALL) Icons.Filled.Stop else Icons.Filled.PlayArrow, contentDescription = null)
                        Text(if (playing == ALL) "Stop" else "Listen through", Modifier.padding(start = Spacing.S2.dp), maxLines = 1)
                    }
                    if (hearing) CircularProgressIndicator(Modifier.size(24.dp).semantics { contentDescription = "Loading" })
                }
            }
        }
        if (member) {
            item(key = "member") {
                OutlinedButton(onClick = onOpen, Modifier.padding(horizontal = Spacing.S4.dp)) { Text("Open") }
            }
        } else if (signedIn && !anyRecording && inv.parts.any { it.status == "open" }) {
            item(key = "name") {
                OutlinedTextField(
                    value = name,
                    onValueChange = onName,
                    label = { Text("Your name") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth().padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp),
                )
            }
        }
        item(key = "parts-h") { SectionHeader("Parts") }
        items(inv.parts.size, key = { "p:" + inv.parts[it].id }) { i ->
            val part = inv.parts[i]
            InvitePartRow(
                part = part,
                script = script,
                hearable = OpenPlaysView.hearable(inv, part.id),
                playing = playing == part.id,
                takeable = !member && !anyRecording && part.status == "open",
                next = inv.next == part.id,
                onPlay = { onPlayPart(part.id) },
                onTake = { onTake(part.id) },
            )
        }
        if (error != null) {
            item(key = "error") {
                Box(Modifier.padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp)) { ErrorLine(error) }
            }
        }
    }
}

/** A part's row: the face, the part, who holds it (or its lines), Play for its takes, Take part when open. */
@Composable
fun InvitePartRow(
    part: OpenPart,
    script: PlayScript?,
    hearable: Boolean,
    playing: Boolean,
    takeable: Boolean,
    next: Boolean,
    onPlay: () -> Unit,
    onTake: () -> Unit,
) {
    val id = PartID(part.id)
    val status = inviteStatus(part.status, part.lineCount)
    val who = part.performer?.takeIf { it.isNotBlank() }
    val sub = if (who != null && part.status != "open") listOf(who, status) else listOf(status)
    val mark = script?.let { partMark(it, id) } ?: MaterialTheme.colorScheme.surfaceContainerHigh
    val muted = MaterialTheme.colorScheme.onSurfaceVariant
    Row(
        Modifier.fillMaxWidth().heightIn(min = 64.dp).padding(start = Spacing.S4.dp, end = Spacing.S2.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(
            Modifier
                .weight(1f)
                .heightIn(min = 64.dp)
                .padding(vertical = Spacing.S2.dp)
                .semantics(mergeDescendants = true) { contentDescription = (listOf(id.title) + sub).joinToString(", ") },
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(Modifier.size(48.dp).clip(CircleShape).background(mark), contentAlignment = Alignment.Center) {
                val initial = who?.firstOrNull()?.uppercase()
                if (initial != null) {
                    Text(initial, style = MaterialTheme.typography.headlineSmall, color = muted, maxLines = 1)
                } else {
                    Icon(Icons.Filled.GraphicEq, contentDescription = null, tint = muted, modifier = Modifier.size(24.dp))
                }
            }
            Spacer(Modifier.width(Spacing.S3.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.Center) {
                Text(id.title, style = MaterialTheme.typography.titleMedium, maxLines = 2, overflow = TextOverflow.Ellipsis)
                EventLine(sub)
            }
        }
        if (hearable) {
            IconButton(onClick = onPlay, modifier = Modifier.size(48.dp).tvFocusMark()) {
                Box(Modifier.size(36.dp).clip(CircleShape).background(OnAir.colors.play), contentAlignment = Alignment.Center) {
                    Icon(
                        if (playing) Icons.Filled.Stop else Icons.Filled.PlayArrow,
                        contentDescription = (if (playing) "Stop " else "Play ") + id.title,
                        tint = OnAir.colors.onPlay,
                    )
                }
            }
        }
        if (takeable) {
            if (next) Button(onClick = onTake, Modifier.padding(start = Spacing.S1.dp)) { Text("Take part", maxLines = 1) }
            else OutlinedButton(onClick = onTake, Modifier.padding(start = Spacing.S1.dp)) { Text("Take part", maxLines = 1) }
        }
    }
}

/**
 * Plays an invitation's takes one after another, each fetched with the invite's header and played from
 * the cache directory; [playing] is the key of what is playing ([ALL] or a part id).
 */
class InvitePlayer {
    private val mix = com.example.appname.plays.MixPlayback()
    private var job: Job? = null
    var playing by mutableStateOf<String?>(null)
        private set
    var fetching by mutableStateOf(false)
        private set
    var error by mutableStateOf<String?>(null)
        private set

    fun play(
        key: String,
        takes: List<com.example.appname.plays.OpenTake>,
        scope: kotlinx.coroutines.CoroutineScope,
        cache: File,
        fetch: suspend (String) -> ByteArray,
    ) {
        stop()
        if (takes.isEmpty()) return
        error = null
        playing = key
        job = scope.launch {
            try {
                for (take in takes) {
                    fetching = true
                    val file = File(cache, "open-take-" + take.id.filter { it.isLetterOrDigit() } + ".wav")
                    file.writeBytes(fetch(take.id))
                    fetching = false
                    val done = CompletableDeferred<Unit>()
                    mix.load(file)
                    mix.onEnded = { done.complete(Unit) }
                    mix.toggle()
                    try {
                        done.await()
                    } finally {
                        mix.stop()
                        file.delete()
                    }
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                error = PlaysShare.line(e)
            } finally {
                fetching = false
                playing = null
            }
        }
    }

    fun stop() {
        job?.cancel()
        job = null
        mix.stop()
        playing = null
        fetching = false
    }
}

// MARK: Finished ear dramas

/** A finished drama as a tile in the show tile's grammar: the play's board, its title, the performers by their chosen names. */
fun FinishedPlay.tile(onOpen: () -> Unit): TileSpec = TileSpec(
    "drama:$id",
    SeriesRow("drama:$id", title, PLAY_BOARD, null, null, 0),
    facts = listOfNotNull(OpenPlaysView.creditLine(this), OpenPlaysView.published(publishedAt)),
    openLabel = "Open ear drama",
    onOpen = onOpen,
)

/** Home's New ear dramas: the newest three, nothing at all while there are none to show. */
@Composable
fun NewEarDramas(onOpen: (String) -> Unit, onAll: () -> Unit) {
    if (LocalIsTelevision.current) return
    val finished = LocalAppContainer.current.finished
    LaunchedEffect(Unit) { finished.load() }
    val state by finished.state.collectAsState()
    val plays = (state as? FinishedList.State.Ready)?.plays.orEmpty()
    if (plays.isEmpty()) return
    com.example.appname.ui.SectionHeading("New ear dramas") {
        com.example.appname.ui.TextLink("All ${formatCount(plays.size)}", onClick = onAll)
    }
    TileGrid(plays.take(3).map { p -> p.tile { onOpen(p.id) } })
}

/** Browse's Ear dramas scope: newest first, all four states. */
@Composable
fun EarDramasScope(onOpen: (String) -> Unit, modifier: Modifier = Modifier) {
    val finished = LocalAppContainer.current.finished
    var attempt by remember { mutableIntStateOf(0) }
    LaunchedEffect(attempt) { finished.load() }
    val state by finished.state.collectAsState()
    EarDramasList(state, onOpen, onRetry = { attempt++ }, modifier)
}

@Composable
fun EarDramasList(state: FinishedList.State, onOpen: (String) -> Unit, onRetry: () -> Unit, modifier: Modifier = Modifier) {
    when (state) {
        FinishedList.State.Loading -> Box(modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            CircularProgressIndicator(Modifier.semantics { contentDescription = "Loading" })
        }
        is FinishedList.State.Failed -> EmptyMessage(
            if (state.offline) OFFLINE_LINE else "Ear dramas could not be read.",
            modifier,
            action = EmptyAction("Try again", onRetry),
        )
        is FinishedList.State.Ready ->
            if (state.plays.isEmpty()) {
                EmptyMessage("No ear dramas are finished yet.", modifier)
            } else {
                Column(modifier.verticalScroll(rememberScrollState())) {
                    Row(
                        Modifier.fillMaxWidth().padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Text("${formatCount(state.plays.size)} ear dramas", style = MaterialTheme.typography.titleMedium, maxLines = 1)
                        Text("Newest first", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
                    }
                    TileGrid(state.plays.map { p -> p.tile { onOpen(p.id) } })
                }
            }
    }
}

// MARK: A finished ear drama's page

@Composable
fun DramaScreen(id: String, onBack: () -> Unit) {
    val container = LocalAppContainer.current
    var attempt by remember { mutableIntStateOf(0) }
    val result by androidx.compose.runtime.produceState<Result<FinishedPlay>?>(null, id, attempt) {
        value = null
        val cached = (container.finished.state.value as? FinishedList.State.Ready)?.plays?.firstOrNull { it.id == id }
        value = if (cached != null) Result.success(cached) else try {
            Result.success(container.openPlays.finished(id))
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
    Scaffold(topBar = { BackBar(onBack) }) { padding ->
        val r = result
        when {
            r == null -> Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(Modifier.semantics { contentDescription = "Loading" })
            }
            r.isFailure -> {
                val e = r.exceptionOrNull()
                val missing = e is PlaysException && e.kind == PlaysException.Kind.Refused
                EmptyMessage(
                    if (missing) "This ear drama is not listed." else PlaysShare.line(e),
                    Modifier.padding(padding),
                    action = if (missing) null else EmptyAction("Try again") { attempt++ },
                )
            }
            else -> {
                val play = r.getOrThrow()
                var audio by remember(play.id) { mutableStateOf<DramaAudio>(DramaAudio.Checking) }
                LaunchedEffect(play.id) { audio = container.finished.audioFor(play) }
                DramaContent(
                    play, padding, audio,
                    onPlay = { url ->
                        container.playback.playFile(
                            EpisodeRow("drama:${play.id}", "drama:${play.id}", play.title, null, null, null, play.title, null, PLAY_BOARD),
                            url,
                        )
                    },
                )
            }
        }
    }
}

/** The head board with the credits' voice strip, Listen and Share, then the bill. */
@Composable
fun DramaContent(play: FinishedPlay, contentPadding: PaddingValues, audio: DramaAudio = DramaAudio.Checking, onPlay: (String) -> Unit = {}) {
    val uri = LocalUriHandler.current
    val named = play.credits.filter { it.name.isNotBlank() }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = contentPadding) {
        item(key = "head") {
            HeadBoard(
                name = play.title,
                genre = PLAY_BOARD,
                art = null,
                kicker = "Ear drama",
                facts = listOf(OpenPlaysView.published(play.publishedAt), "${named.size} ${if (named.size == 1) "performer" else "performers"}".takeIf { named.isNotEmpty() }),
                first = null,
                last = null,
                credits = OpenPlaysView.creditLine(play, max = 3),
                mark = { h ->
                    val on = onBoardColor(PLAY_BOARD, OnAir.colors.dark)
                    Box(Modifier.height(h), contentAlignment = Alignment.BottomStart) {
                        VoiceStrip(play.credits.map { 1f to true }, on, 10.dp)
                    }
                },
            )
        }
        item(key = "actions") {
            ActionRow(Modifier.padding(horizontal = Spacing.S4.dp, vertical = Spacing.S3.dp)) { fit ->
                if (audio !is DramaAudio.Deriving) {
                    Button(
                        onClick = { (audio as? DramaAudio.Ready)?.let { onPlay(it.url) } },
                        enabled = audio is DramaAudio.Ready,
                        colors = playButtonColors(),
                    ) {
                        Icon(Icons.Filled.PlayArrow, contentDescription = null)
                        Text("Listen", Modifier.padding(start = Spacing.S2.dp), maxLines = 1)
                    }
                }
                ShareButton(play.title, SiteLinks.drama(play.id), fit.folded)
            }
        }
        item(key = "audio-line") {
            Column(Modifier.padding(horizontal = Spacing.S4.dp), verticalArrangement = Arrangement.spacedBy(Spacing.S1.dp)) {
                if (audio is DramaAudio.Deriving) Text("The audio is still being prepared.", style = MaterialTheme.typography.bodyMedium)
                if (audio is DramaAudio.Failed) Text("The audio could not be found.", style = MaterialTheme.typography.bodyMedium)
                TextButton(onClick = { uri.openUri(play.archiveUrl) }) { Text("View on archive.org") }
            }
        }
        if (named.isNotEmpty()) {
            item(key = "credits-h") { SectionHeader("Credits") }
            items(named.size, key = { "c:$it" }) { i ->
                val c = named[i]
                ListItem(
                    headlineContent = { Text(c.name) },
                    supportingContent = { Text(PartID(c.part).title) },
                )
            }
        }
    }
}
