package com.example.appname.ui.screens

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Replay5
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEvent
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.isAltPressed
import androidx.compose.ui.input.key.isCtrlPressed
import androidx.compose.ui.input.key.isMetaPressed
import androidx.compose.ui.input.key.isShiftPressed
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.core.content.edit
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import com.example.appname.app.AppContainer
import com.example.appname.data.EpisodeDetail
import com.example.appname.data.Transcript
import com.example.appname.navigation.SiteLinks
import com.example.appname.playback.PlaybackEngine
import com.example.appname.plays.EarCore
import com.example.appname.plays.OwnCue
import com.example.appname.plays.OwnDoc
import com.example.appname.plays.OwnEar
import com.example.appname.plays.OwnEpisode
import com.example.appname.plays.OwnLine
import com.example.appname.plays.OwnMeta
import com.example.appname.plays.OwnOp
import com.example.appname.plays.OwnRecord
import com.example.appname.plays.OwnScript
import com.example.appname.plays.OwnTarget
import com.example.appname.plays.OwnWho
import com.example.appname.plays.OwnWords
import com.example.appname.plays.PlayLibraryFeed
import com.example.appname.plays.ReadAlong
import com.example.appname.ui.EmptyAction
import com.example.appname.ui.EmptyMessage
import com.example.appname.ui.Haptic
import com.example.appname.ui.LocalAppContainer
import com.example.appname.ui.LocalOnline
import com.example.appname.ui.episodeTitle
import com.example.appname.ui.formatClock
import com.example.appname.ui.rememberHaptics
import com.example.appname.ui.theme.OnAir
import com.example.appname.ui.theme.Spacing
import java.io.IOException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// Casting an episode by ear (ANDROID-DESIGN §4.23 item 4, PLAYS-DESIGN §13 item 10; Decision 088.3): the automatic transcript in
// lines, the episode playing in the session's own player, the line being said lit, and a tap on a part for who is saying it.
// What a tap does is EarCore's; what is kept is OwnScripts'. The page proposes no speaker and keeps no sound.

private sealed interface EarLoad {
    data object Loading : EarLoad
    data object Missing : EarLoad
    data class Failed(val offline: Boolean) : EarLoad
    data class Castable(val script: String) : EarLoad
    class Ready(val model: EarModel) : EarLoad
}

/** This device's script of an episode, by the id it has now or one it had when the casting began. */
internal suspend fun castingOf(container: AppContainer, episodeId: String): OwnRecord? {
    val forwarding = container.catalog.db?.forwarding()
    return withContext(Dispatchers.IO) {
        container.plays.own.ofEpisode { it == episodeId || forwarding?.resolve(it) == episodeId }?.let { container.plays.own.get(it.id) }
    }
}

/**
 * Whether Record this is sure to open a casting here: the transcript's times were read, or one was begun on this device.
 * False otherwise, and nothing is said: 88% of episodes have no transcript.
 */
internal suspend fun canCastByEar(container: AppContainer, d: EpisodeDetail): Boolean {
    if (d.transcriptUrl == null || d.recordings.isEmpty()) return false
    return try {
        castingOf(container, d.episode.id) != null || EarCore.refusalOf(OwnScript.fromCues(container.api.transcriptCues(d.transcriptUrl))) == null
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        false
    }
}

@Composable
fun EarScreen(episodeId: String, onBack: () -> Unit, onOpenScript: (String) -> Unit) {
    val container = LocalAppContainer.current
    val context = LocalContext.current
    val online = LocalOnline.current
    var attempt by remember { mutableIntStateOf(0) }
    val load by produceState<EarLoad>(EarLoad.Loading, episodeId, attempt) {
        value = EarLoad.Loading
        value = try {
            loadEar(container, context, episodeId)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            EarLoad.Failed(!online)
        }
    }
    when (val l = load) {
        is EarLoad.Ready -> EarPage(l.model, onBack, onOpenScript)
        is EarLoad.Castable -> LaunchedEffect(l) { onOpenScript(l.script) }
        else -> Scaffold(topBar = { EarBar("Record this", null, onBack) }) { padding ->
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                when (l) {
                    EarLoad.Missing -> EmptyMessage("Not in the catalog.")
                    is EarLoad.Failed -> EmptyMessage(if (l.offline) "You are offline." else "This did not load.", action = EmptyAction("Try again") { attempt++ })
                    else -> CircularProgressIndicator(Modifier.semantics { contentDescription = "Loading" })
                }
            }
        }
    }
}

private suspend fun loadEar(container: AppContainer, context: Context, episodeId: String): EarLoad {
    val db = container.catalog.awaitDb() ?: return EarLoad.Failed(offline = false)
    val d = db.episodeDetail(episodeId)?.takeIf { it.recordings.isNotEmpty() } ?: return EarLoad.Missing
    val rec = castingOf(container, d.episode.id)
    if (rec == null && d.script != null) {
        container.plays.loadRows()
        if ((container.plays.rows.value as? PlayLibraryFeed.Rows.Ready)?.rows?.any { it.id == d.script } == true) return EarLoad.Castable(d.script)
    }
    val cues: List<OwnCue>?
    val doc: OwnDoc
    if (rec != null) {
        cues = null
        doc = rec.doc
    } else {
        // The episode is in the catalog, so a transcript that is not there did not load.
        cues = container.api.transcriptCues(d.transcriptUrl)
        doc = OwnScript.fromCues(cues)
        if (EarCore.refusalOf(doc) != null) throw IOException("no lines in ${d.transcriptUrl}")
    }
    val taken = rec?.let { withContext(Dispatchers.IO) { container.plays.own.takes(it.id) } }.orEmpty()
    return EarLoad.Ready(EarModel(container, context, d, rec, doc, taken, cues?.let(EarCore::signature).orEmpty()))
}

/** One line playing on its own: until when, and the place it goes back to. */
internal class EarSample(val k: Int, val until: Long, val backMs: Long, val backPlaying: Boolean) {
    var begun = false
}

/** The page's state and its one hold on the app's player. */
@Stable
internal class EarModel(
    private val container: AppContainer,
    context: Context,
    val d: EpisodeDetail,
    rec: OwnRecord?,
    doc: OwnDoc,
    takes: Set<String>,
    private val signature: String,
) {
    private val engine: PlaybackEngine = container.playback
    private val prefs = context.getSharedPreferences("ed.ear", Context.MODE_PRIVATE)
    val session = EarCore.Session(doc, rec?.extras.orEmpty(), takes)
    val title: String = episodeTitle(d.episode)

    /** The default copy is the one the transcript was made from: a fall to another would put every time off, so none is offered. */
    val copy: String = d.recordings.first().url
    val began: OwnEar? = rec?.ear

    /** Bumped at each change of the cast. */
    var version by mutableIntStateOf(0)
    var lit by mutableIntStateOf(0)
    var sample by mutableStateOf<EarSample?>(null)
    var place by mutableLongStateOf(EarCore.placeOf(rec?.ear, doc))
    var playing by mutableStateOf(false)
    var speed by mutableFloatStateOf(prefs.getFloat("speed", EarCore.SPEED))
    var audioProblem by mutableStateOf<String?>(null)
    var said by mutableStateOf("" to 0)
        private set
    private var rec: OwnRecord? = rec
    private var mine = false
    private var starting = false

    val keeper = OwnKeeper(container.plays.own, container.appScope) { record() }

    fun say(words: String) { said = words to said.second + 1 }

    /** The player is on this episode's own copy: its clock is this page's. */
    private fun here(): Boolean = engine.roomView()?.let { it.episodeId == d.episode.id && it.copyUrl == copy } == true
    private fun position(): Long = engine.roomView()?.positionMs ?: place

    /** The place being cast; a line played on its own is not it. */
    private fun nowMs(): Long = sample?.backMs ?: if (here()) position() else place

    /** The script as it stands, begun at the first change and never by looking. */
    private fun record(): OwnRecord? {
        val at = nowMs()
        val begun = rec ?: container.plays.own.begin(
            title, session.doc, OwnEpisode(d.episode.id, SiteLinks.episode(d.episode.id)), OwnEar(signature, copy),
        )
        return begun.copy(doc = session.doc, extras = session.names, ear = (begun.ear ?: OwnEar(signature, copy)).copy(place = at)).also { rec = it }
    }

    fun opened() {
        if (here()) {
            place = position()
            hold()
        } else if (engine.state.value.isPlaying && !container.together.isGuest) {
            engine.pause()
        }
        engine.onSeek = { if (sample == null) session.jumped() }
        session.tick(place, false)
        lit = session.lit
    }

    private fun hold() {
        engine.hold(speed)
        mine = true
    }

    /** Where the audio is now. True when the cast changed. */
    fun sync() {
        val s = sample
        playing = here() && engine.isPlayingNow
        audioProblem = if (here() && engine.state.value.failed) { if (engine.state.value.offline) "You are offline." else "This recording did not load." } else audioProblem?.takeIf { !here() }
        if (s != null) {
            if (here() && engine.isPlayingNow) s.begun = true
            if ((here() && s.begun && position() >= s.until) || (s.begun && !playing) || audioProblem != null) endSample()
            return
        }
        if (here()) {
            starting = false
            place = position()
        }
        val got = session.tick(place, playing)
        if (got.moved) {
            lit = session.lit
            if (!playing) session.line(lit)?.let { say(it.text) }
        }
        if (got.heard) {
            version++
            keeper.soon()
        }
    }

    /** A press starts it: the episode, at this page's place and speed. */
    fun start() {
        if (container.together.isGuest) {
            audioProblem = GUEST
            return
        }
        audioProblem = null
        if (here() && !engine.state.value.failed) {
            hold()
            engine.resume()
        } else {
            starting = true
            session.jumped()
            engine.playHeld(d.episode, copy, place, speed)
            mine = true
        }
    }

    fun toggle() {
        when {
            sample != null -> endSample()
            playing -> { engine.pause(); if (rec != null) keeper.soon() }
            else -> start()
        }
        playing = here() && engine.isPlayingNow
    }

    fun back() {
        if (sample != null) { endSample(); return }
        val to = (nowMs() - EarCore.BACK_MS).coerceAtLeast(0)
        session.jumped()
        if (here()) engine.seekTo(to)
        place = to
        sync()
    }

    fun setTheSpeed(x: Float) {
        speed = x
        prefs.edit { putFloat("speed", x) }
        if (here()) hold()
        say("Speed ${speedName(x)}")
    }

    /** Plays one line on its own, then goes back to the place it left. */
    fun hear(l: OwnLine?) {
        val at = l?.at ?: return
        if (container.together.isGuest) {
            audioProblem = GUEST
            return
        }
        val was = sample
        val (from, until) = EarCore.spanOf(at)
        sample = EarSample(l.k, until, was?.backMs ?: nowMs(), was?.backPlaying ?: playing)
        engine.keepsPlace = false
        audioProblem = null
        if (here()) {
            hold()
            engine.seekTo(from)
            engine.resume()
        } else {
            engine.playHeld(d.episode, copy, from, speed)
            mine = true
        }
    }

    fun endSample(goOn: Boolean = true) {
        val s = sample ?: return
        sample = null
        if (here()) {
            engine.pause()
            engine.seekTo(s.backMs)
            session.jumped()
            engine.keepsPlace = true
            if (goOn && s.backPlaying) engine.resume()
        }
        engine.keepsPlace = true
        place = s.backMs
        playing = here() && engine.isPlayingNow
    }

    /** From one line on. */
    fun playFrom(l: OwnLine) {
        val at = l.at ?: return
        if (sample != null) endSample(false)
        place = at.first
        session.jumped()
        if (here()) engine.seekTo(at.first)
        session.tick(place, false)
        lit = session.lit
        start()
    }

    fun pause() { if (playing && sample == null) engine.pause(); playing = here() && engine.isPlayingNow }

    /** One press of the cast: a refusal's code, or null. */
    fun press(spoken: String, does: () -> String?): String? {
        if (sample != null) endSample() else sync()
        does()?.let { return it }
        lit = session.lit
        version++
        keeper.soon()
        say(spoken)
        return null
    }

    suspend fun finish(): Pair<String?, String?> {
        if (sample != null) endSample(false)
        val before = session.doc
        val doc = OwnScript.done(before, keepOpen = true)
        val id = rec?.id ?: "own-00000000-0000-4000-8000-000000000000"
        OwnScript.refusalOf(OwnScript.toScript(doc, OwnMeta(id, title, d.episode.id, SiteLinks.episode(d.episode.id))))?.let { return null to it }
        val was = rec
        session.replace(doc)
        record()
        rec = rec?.copy(done = true)
        if (!keeper.write()) {
            session.replace(before)
            rec = was
            return null to null
        }
        finished = true
        return rec?.id to null
    }

    private var finished = false

    suspend fun retakes() {
        val id = rec?.id ?: return
        session.takes = withContext(Dispatchers.IO) { container.plays.own.takes(id) }
    }

    fun leave() {
        if (sample != null) endSample(false)
        engine.onSeek = null
        engine.keepsPlace = true
        if (rec != null && !finished && kotlin.math.abs((rec?.ear?.place ?: 0) - nowMs()) > 1000) keeper.soon()
        keeper.flush()
        if (mine) engine.release()
    }

    companion object {
        const val GUEST = "Leave Listen together to play this."
        fun speedName(x: Float): String = java.math.BigDecimal(x.toString()).stripTrailingZeros().toPlainString() + "×"
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun EarBar(title: String, under: String?, onClose: () -> Unit, refused: Boolean = false, actions: @Composable () -> Unit = {}) {
    TopAppBar(
        title = {
            Column {
                Text(title, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                if (under != null) {
                    Text(
                        under, style = MaterialTheme.typography.bodySmall, maxLines = 1, overflow = TextOverflow.Ellipsis,
                        color = if (refused) com.example.appname.ui.theme.AppSemantics.colors.error else MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = if (refused) Modifier.semantics { liveRegion = LiveRegionMode.Assertive } else Modifier,
                    )
                }
            }
        },
        navigationIcon = { IconButton(onClick = onClose) { Icon(Icons.Filled.Close, contentDescription = "Close") } },
        actions = { actions() },
    )
}

private sealed interface EarSheet {
    data class Line(val k: Int) : EarSheet
}

@Composable
private fun EarPage(model: EarModel, onBack: () -> Unit, onOpenScript: (String) -> Unit) {
    val container = LocalAppContainer.current
    val haptics = rememberHaptics()
    val scope = rememberCoroutineScope()
    val list = rememberLazyListState()
    val focus = remember { FocusRequester() }
    val follow = remember { ReadAlong.Follow() }
    var away by remember { mutableStateOf(false) }
    var sheet by remember { mutableStateOf<EarSheet?>(null) }
    var naming by remember { mutableStateOf(false) }
    var resumeAfter by remember { mutableStateOf(false) }
    var refused by remember { mutableStateOf<Pair<String, Int>?>(null) }
    var note by remember { mutableStateOf<String?>(null) }
    var finishing by remember { mutableStateOf(false) }

    DisposableEffect(model) {
        model.opened()
        onDispose { model.leave() }
    }
    LaunchedEffect(model) {
        while (isActive) {
            model.sync()
            delay(if (model.playing) 40 else 120)
        }
    }
    LifecycleEventEffect(Lifecycle.Event.ON_STOP) { model.keeper.flush() }
    LifecycleEventEffect(Lifecycle.Event.ON_START) { scope.launch { model.retakes() } }
    // A kept casting keeps its own lines. When archive.org has made the transcript or the copy again since, that is said.
    LaunchedEffect(model) {
        val ear = model.began ?: return@LaunchedEffect
        if (ear.copy.isNotEmpty() && ear.copy != model.copy) note = "The recording has changed. The times may be off."
        else if (model.d.transcriptUrl != null) {
            val cues = try { container.api.transcriptCues(model.d.transcriptUrl) } catch (e: CancellationException) { throw e } catch (_: Exception) { null }
            if (cues != null && ear.sig.isNotEmpty() && EarCore.signature(cues) != ear.sig) note = "The transcript has changed. Your lines are kept."
        }
    }
    LaunchedEffect(refused) {
        if (refused != null) {
            delay(2500)
            refused = null
        }
    }

    val rows = remember(model.version) { EarCore.rows(model.session.doc) }
    val index = remember(rows) { rows.withIndex().associate { it.value.k to it.index } }
    val parts = remember(model.version) { model.session.parts() }
    val hues = remember(parts) { parts.mapIndexed { i, p -> p.name to hueKeyAt(i) }.toMap() }
    val lit = model.sample?.k ?: model.lit
    val who = remember(model.version, model.lit) { if (model.lit != 0) model.session.who(model.lit) else null }
    val count = remember(model.version) { model.session.count() }

    suspend fun bring(k: Int, animate: Boolean = true) {
        val i = index[k] ?: return
        val view = list.layoutInfo.viewportSize.height
        val at = -(view * 0.4f).toInt()
        val far = kotlin.math.abs(i - list.firstVisibleItemIndex) > 30
        if (animate && !far) list.animateScrollToItem(i + 1, at) else list.scrollToItem(i + 1, at)
    }
    var first by remember { mutableStateOf(true) }
    LaunchedEffect(lit, model.sample == null) {
        if (model.sample != null || lit == 0) return@LaunchedEffect
        val step = follow.line(lit.toString())
        away = step.back
        if (step.turn) bring(lit, animate = !first)
        first = false
    }
    fun goAway() {
        if (model.lit != 0) {
            follow.away()
            away = true
        }
    }
    fun refollow() {
        follow.back()
        away = false
        scope.launch { bring(model.lit) }
    }
    val userScroll = remember {
        object : NestedScrollConnection {
            override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
                if (source == NestedScrollSource.UserInput && available.y != 0f) goAway()
                return Offset.Zero
            }
        }
    }

    fun refuse(code: String) {
        haptics(Haptic.Error)
        refused = OwnWords.say(code) to (refused?.second ?: 0) + 1
    }
    fun press(spoken: String, does: () -> String?) {
        val before = if (model.lit != 0) model.session.who(model.lit) else null
        val why = model.press(spoken, does)
        if (why != null) refuse(why) else if (before != (if (model.lit != 0) model.session.who(model.lit) else null)) haptics(Haptic.Selection)
    }
    fun give(name: String) = press(name) { model.session.give(name) }
    fun undo() { if (model.session.canUndo) press("Undone") { model.session.undo() } }
    /** The audio waits while a sheet is open, and goes on when it closes if it was playing. */
    fun openSheet(then: () -> Unit) {
        resumeAfter = model.playing && model.sample == null
        if (resumeAfter) model.pause()
        then()
    }
    fun closeSheet(goOn: Boolean = true) {
        sheet = null
        naming = false
        if (model.sample != null) model.endSample(false)
        if (resumeAfter && goOn) model.start()
        resumeAfter = false
        runCatching { focus.requestFocus() }
    }
    fun finish() {
        finishing = true
        scope.launch {
            val (id, why) = model.finish()
            finishing = false
            if (id != null) onOpenScript(id) else if (why != null) refuse(why)
        }
    }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }

    val large = largeText()
    val under = refused?.first ?: OwnWords.castLine(count.cast, count.lines)
    val problem = model.keeper.problem ?: model.audioProblem
    val lines: @Composable (Modifier) -> Unit = { m ->
        Box(m, contentAlignment = Alignment.TopCenter) {
            LazyColumn(
                Modifier.widthIn(max = 720.dp).fillMaxSize().nestedScroll(userScroll), state = list,
                contentPadding = PaddingValues(horizontal = Spacing.S2.dp, vertical = Spacing.S2.dp),
            ) {
                item(key = "auto") {
                    Text(Transcript.LABEL, Modifier.padding(horizontal = Spacing.S2.dp, vertical = Spacing.S1.dp), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                items(rows, key = { it.k }) { row ->
                    EarLine(row, (row.who as? OwnWho.Role)?.let { hues[it.name] }, row.k == lit) { openSheet { sheet = EarSheet.Line(row.k) } }
                }
            }
            if (away && model.sample == null) {
                OutlinedButton(onClick = ::refollow, Modifier.align(Alignment.BottomCenter).padding(Spacing.S2.dp).background(MaterialTheme.colorScheme.surface, CircleShape)) {
                    Icon(Icons.AutoMirrored.Filled.Undo, contentDescription = null)
                    Text("Back to the line", Modifier.padding(start = Spacing.S1.dp))
                }
            }
        }
    }
    val lineBody: @Composable (Int) -> Unit = { k ->
        val l = model.session.line(k)
        if (l == null) LaunchedEffect(k) { closeSheet() } else androidx.compose.runtime.key(k) {
            EarLineBody(model, l, parts, hues, onDone = { closeSheet() }, onHold = { closeSheet(goOn = false) }, onRefuse = { haptics(Haptic.Error) }, onStep = { haptics(Haptic.Selection) }, follow = { follow.back(); away = false })
        }
    }

    BoxWithConstraints(Modifier.fillMaxSize()) {
        val wide = maxWidth >= OwnWide
        androidx.activity.compose.BackHandler(enabled = wide && sheet != null) { closeSheet() }
        // A turn of the device keeps the line being said in view.
        LaunchedEffect(wide) { if (!first && follow.following && model.lit != 0) bring(model.lit, animate = false) }
        Scaffold(
            modifier = Modifier.focusRequester(focus).onKeyEvent { e ->
                if (sheet != null || naming || e.type != KeyEventType.KeyDown) return@onKeyEvent false
                when (val key = keyOf(e) ?: return@onKeyEvent false) {
                    EarCore.Key.Toggle -> if (e.nativeKeyEvent.repeatCount == 0) model.toggle()
                    EarCore.Key.Back -> model.back()
                    EarCore.Key.Undo -> undo()
                    is EarCore.Key.Part -> parts.getOrNull(key.n)?.let { give(it.name) }
                }
                true
            }.focusable(),
            topBar = {
                EarBar(model.title, under.takeUnless { large }, onBack, refused = refused != null) {
                    IconButton(onClick = ::undo, enabled = remember(model.version) { model.session.canUndo }) { Icon(Icons.AutoMirrored.Filled.Undo, contentDescription = "Undo") }
                    OutlinedButton(onClick = ::finish, enabled = !finishing, modifier = Modifier.padding(end = Spacing.S3.dp)) { Text("Done") }
                }
            },
            bottomBar = {
                if (!wide) Surface(color = MaterialTheme.colorScheme.surfaceContainer) {
                    Column(Modifier.fillMaxWidth().navigationBarsPadding().padding(horizontal = Spacing.S3.dp, vertical = Spacing.S1.dp)) {
                        EarDockParts(parts, hues, who, model.lit != 0, onGive = ::give, onNew = { openSheet { naming = true } }, onOut = { press("Left out") { model.session.leaveOut() } })
                        EarTransport(model)
                    }
                }
            },
        ) { padding ->
            Column(Modifier.fillMaxSize().padding(padding)) {
                Announcer(model.said.first, model.said.second)
                if (large) UnderBar(under, refused != null)
                if (problem != null) ProblemBar(problem, when {
                    model.keeper.problem != null -> ({ scope.launch { model.keeper.write() } })
                    problem == EarModel.GUEST -> null
                    else -> ({ model.start() })
                })
                note?.let { Text(it, Modifier.fillMaxWidth().padding(horizontal = Spacing.S4.dp, vertical = Spacing.S1.dp), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                Row(Modifier.fillMaxSize()) {
                    lines(Modifier.weight(1f).fillMaxHeight())
                    if (wide) {
                        val now = sheet
                        if (now is EarSheet.Line) SidePane("Line", onDismiss = { closeSheet() }) { lineBody(now.k) } else {
                            Surface(Modifier.width(360.dp).fillMaxHeight(), color = MaterialTheme.colorScheme.surfaceContainer) {
                                Column(Modifier.padding(Spacing.S2.dp)) {
                                    EarRail(parts, hues, who, Modifier.weight(1f), onGive = ::give, onHear = { model.hear(model.session.sample(it)) })
                                    EarVerbs(who == OwnWho.Out, model.lit != 0, onNew = { openSheet { naming = true } }, onOut = { press("Left out") { model.session.leaveOut() } })
                                    EarTransport(model)
                                }
                            }
                        }
                    }
                }
            }
        }
        if (!wide) (sheet as? EarSheet.Line)?.let { now -> OwnBottomSheet("Line", onDismiss = { closeSheet() }) { lineBody(now.k) } }
    }
    if (naming) NameDialog("New part", "Name", "Add", OwnScript.MAX_PART_NAME, act = { v ->
        var why: String? = null
        val before = if (model.lit != 0) model.session.who(model.lit) else null
        val got = model.session.add(v)
        if (got.refusal != null) why = OwnWords.name(got.refusal) else {
            model.press(got.name) { null }
            if (model.lit != 0 && before != model.session.who(model.lit)) haptics(Haptic.Selection)
            closeSheet()
        }
        why
    }, onDismiss = { closeSheet() })
}

private fun keyOf(e: KeyEvent): EarCore.Key? {
    val name = when (e.key) {
        Key.Spacebar -> " "
        Key.DirectionLeft -> "ArrowLeft"
        Key.U -> "u"
        Key.Z -> "z"
        Key.One, Key.NumPad1 -> "1"
        Key.Two, Key.NumPad2 -> "2"
        Key.Three, Key.NumPad3 -> "3"
        Key.Four, Key.NumPad4 -> "4"
        Key.Five, Key.NumPad5 -> "5"
        Key.Six, Key.NumPad6 -> "6"
        Key.Seven, Key.NumPad7 -> "7"
        Key.Eight, Key.NumPad8 -> "8"
        Key.Nine, Key.NumPad9 -> "9"
        else -> return null
    }
    return EarCore.keyOf(name, e.isCtrlPressed, e.isMetaPressed, e.isAltPressed, e.isShiftPressed)
}

/** A line: its speaker's name where the speaker changes, muted while it is nobody's, struck when left out, outlined in ink while it is said. */
@Composable
private fun EarLine(row: EarCore.Row, hue: String?, lit: Boolean, onOpen: () -> Unit) {
    val out = row.who == OwnWho.Out
    val name = (row.who as? OwnWho.Role)?.name
    val label = if (out) "Left out" else name
    val aside = row.kind == "direction" || row.kind == "sound" || row.kind == "music"
    val shape = RoundedCornerShape(8.dp)
    Column(
        Modifier.fillMaxWidth().padding(vertical = 1.dp)
            .background(if (lit) MaterialTheme.colorScheme.surfaceVariant else Color.Transparent, shape)
            .border(2.dp, if (lit) OnAir.colors.play else Color.Transparent, shape)
            .clip(shape)
            .clickable(onClickLabel = "Change this line", onClick = onOpen)
            .semantics(mergeDescendants = true) {
                selected = lit
                if (!row.named && label != null) stateDescription = label
            }
            .heightIn(min = 40.dp)
            .padding(horizontal = Spacing.S2.dp, vertical = 5.dp),
        verticalArrangement = Arrangement.Center,
    ) {
        if (row.named && label != null) Text(label, style = MaterialTheme.typography.titleMedium, color = if (out) MaterialTheme.colorScheme.onSurfaceVariant else hueColor(hue))
        Text(
            row.text,
            style = MaterialTheme.typography.bodyMedium.copy(
                textDecoration = if (out) TextDecoration.LineThrough else null,
                fontStyle = if (aside) androidx.compose.ui.text.font.FontStyle.Italic else null,
            ),
            color = if (name != null) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

/** The parts at the foot of a phone: chips, two rows that scroll from five on; + Part and Leave out are always in reach. */
@Composable
private fun EarDockParts(parts: List<EarCore.Part>, hues: Map<String, String?>, who: OwnWho?, lit: Boolean, onGive: (String) -> Unit, onNew: () -> Unit, onOut: () -> Unit) {
    val many = parts.size > 4
    if (parts.isNotEmpty()) {
        ChipFlow(Modifier.fillMaxWidth().then(if (many) Modifier.heightIn(max = 108.dp).verticalScroll(rememberScrollState()) else Modifier)) {
            parts.forEach { p ->
                OwnPartChip(p.name, hues[p.name], onClick = { onGive(p.name) }, selected = (who as? OwnWho.Role)?.name == p.name, label = "${p.name}, ${OwnWords.lines(p.lines)}")
            }
        }
    }
    EarVerbs(who == OwnWho.Out, lit, onNew, onOut)
}

@Composable
private fun EarVerbs(out: Boolean, lit: Boolean, onNew: () -> Unit, onOut: () -> Unit) {
    ChipFlow {
        PlainChip("Part", onNew, Modifier.semantics { contentDescription = "New part" }, icon = { Icon(Icons.Outlined.Add, contentDescription = null) })
        androidx.compose.material3.FilterChip(
            selected = out, onClick = onOut, enabled = lit, modifier = Modifier.heightIn(min = 40.dp),
            label = { Text("Leave out", Modifier.padding(vertical = Spacing.S1.dp), style = MaterialTheme.typography.bodyMedium) },
        )
    }
}

/** The parts beside a wide page: the number a keyboard gives them, the count, and a play button that plays the next of their lines. */
@Composable
private fun EarRail(parts: List<EarCore.Part>, hues: Map<String, String?>, who: OwnWho?, modifier: Modifier, onGive: (String) -> Unit, onHear: (String) -> Unit) {
    Column(modifier.fillMaxWidth().verticalScroll(rememberScrollState())) {
        parts.forEachIndexed { i, p ->
            val on = (who as? OwnWho.Role)?.name == p.name
            val shape = RoundedCornerShape(8.dp)
            Row(
                Modifier.fillMaxWidth().padding(vertical = 2.dp).border(2.dp, if (on) OnAir.colors.play else Color.Transparent, shape).clip(shape)
                    .clickable(onClickLabel = "Give the line to ${p.name}") { onGive(p.name) }
                    .semantics { selected = on }.heightIn(min = 48.dp).padding(start = Spacing.S2.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp),
            ) {
                Text(if (i < 9) "${i + 1}" else "", Modifier.width(12.dp), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                HueDot(hues[p.name])
                Column(Modifier.weight(1f).padding(vertical = Spacing.S1.dp)) {
                    Text(p.name, style = MaterialTheme.typography.titleMedium, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    Text(OwnWords.lines(p.lines), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                IconButton(onClick = { onHear(p.name) }, enabled = p.lines > 0) { Icon(Icons.Filled.PlayArrow, contentDescription = "Hear ${p.name}") }
            }
        }
    }
}

/** The clock, back 5 seconds, play, the speed. */
@Composable
private fun EarTransport(model: EarModel) {
    var speeds by remember { mutableStateOf(false) }
    val guest = LocalAppContainer.current.together.isGuest
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(formatClock(model.place), Modifier.weight(1f), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        IconButton(onClick = { model.back() }, enabled = !guest) { Icon(Icons.Filled.Replay5, contentDescription = "Back 5 seconds") }
        FilledIconButton(
            onClick = { model.toggle() }, modifier = Modifier.size(56.dp),
            colors = IconButtonDefaults.filledIconButtonColors(containerColor = OnAir.colors.play, contentColor = OnAir.colors.onPlay),
        ) { Icon(if (model.playing) Icons.Filled.Pause else Icons.Filled.PlayArrow, contentDescription = if (model.playing) "Pause" else "Play") }
        Box(Modifier.weight(1f), contentAlignment = Alignment.CenterEnd) {
            TextButton(onClick = { speeds = true }, enabled = !guest, modifier = Modifier.semantics { contentDescription = "Speed, ${EarModel.speedName(model.speed)}" }) { Text(EarModel.speedName(model.speed)) }
            DropdownMenu(speeds, { speeds = false }) {
                PlaybackEngine.SPEEDS.forEach { s -> DropdownMenuItem(text = { Text(EarModel.speedName(s)) }, onClick = { speeds = false; model.setTheSpeed(s) }) }
            }
        }
    }
}

/** The line sheet (§4.23 item 2's, with Hear it and Play from here). What it gives a line is that line's alone. */
@Composable
private fun EarLineBody(
    model: EarModel, l: OwnLine, parts: List<EarCore.Part>, hues: Map<String, String?>,
    onDone: () -> Unit, onHold: () -> Unit, onRefuse: () -> Unit, onStep: () -> Unit, follow: () -> Unit,
) {
    var refusal by remember { mutableStateOf<String?>(null) }
    var editing by remember { mutableStateOf(false) }
    var cut by remember(l.text) { mutableIntStateOf(-1) }
    val s = model.session
    fun act(spoken: String, does: () -> String?) {
        if (model.sample != null) model.endSample(false)
        val why = does()
        if (why != null) {
            refusal = OwnWords.say(why)
            onRefuse()
            return
        }
        model.version++
        model.keeper.soon()
        model.say(spoken)
        onStep()
        onDone()
    }
    if (editing) {
        WordsEditor(l.text, refusal, onSave = { act("Words changed") { s.apply(OwnOp("words", line = l.k, text = it)) } }, onCancel = onDone)
        return
    }
    val hear: Pair<String, () -> Unit>? = if (l.at != null) "Hear it" to { model.hear(s.line(l.k)) } else null
    val from: Pair<String, () -> Unit>? = if (l.at != null) "Play from here" to { onHold(); follow(); model.playFrom(l) } else null
    val edit: Pair<String, () -> Unit> = "Edit words" to { if (model.sample != null) model.endSample(false); editing = true }
    if (l.id != null && l.id in s.takes) {
        Text(flowed(l.text), style = MaterialTheme.typography.bodyMedium)
        Refusal(OwnWords.say("line_has_take"))
        StepGrid(listOfNotNull(hear, edit, from))
        return
    }
    val who = s.who(l.k)
    Cutter(l.text, cut, { cut = it })
    ChipFlow {
        parts.forEach { p ->
            OwnPartChip(p.name, hues[p.name], onClick = { act(p.name) { s.assign(l.k, OwnTarget.Role(p.name)) } }, selected = (who as? OwnWho.Role)?.name == p.name)
        }
        listOf("direction" to "Direction", "sound" to "Sound").forEach { (kind, word) ->
            if (l.kind == kind) OwnPartChip(word, null, onClick = onDone, selected = true) else PlainChip(word, { act(word) { s.assign(l.k, OwnTarget.KindOf(kind)) } })
        }
    }
    val split: Pair<String, (() -> Unit)?>? = if (l.text.trim().any { it.isWhitespace() }) {
        "Split here" to (if (cut >= 0) ({ act("Split") { s.apply(OwnOp("split", line = l.k, at = cut)) } }) else null)
    } else null
    val join: Pair<String, () -> Unit>? = if (s.doc.lines.first().k != l.k) "Join to line above" to { act("Joined") { s.apply(OwnOp("join", line = l.k)) } } else null
    StepGrid(listOfNotNull(hear, edit, split, join, "Leave out" to { act("Left out") { s.leaveOutLine(l.k) } }, from))
    refusal?.let { Refusal(it) }
}
