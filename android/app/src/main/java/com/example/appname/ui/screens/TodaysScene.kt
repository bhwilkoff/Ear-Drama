package com.example.appname.ui.screens

import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.foundation.background
import androidx.compose.ui.Alignment
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.example.appname.plays.OpeningSpeech
import com.example.appname.plays.PlayLibraryFeed
import com.example.appname.plays.PlayListing
import com.example.appname.plays.PlayScript
import com.example.appname.plays.StudioOpen
import com.example.appname.radio.RadioClock
import com.example.appname.ui.ActionRow
import com.example.appname.ui.CastHandle
import com.example.appname.ui.EventLine
import com.example.appname.ui.FoldButton
import com.example.appname.ui.LocalAppContainer
import com.example.appname.ui.PLAY_BOARD
import com.example.appname.ui.partMark
import com.example.appname.ui.playButtonColors
import com.example.appname.ui.rememberCast
import com.example.appname.ui.rememberDeviceVoices
import com.example.appname.ui.theme.OnAir
import com.example.appname.ui.theme.PrintGroundDark
import com.example.appname.ui.theme.PrintGroundLight
import com.example.appname.ui.theme.Spacing
import com.example.appname.ui.theme.boardColor
import com.example.appname.ui.theme.onBoardColor
import com.example.appname.ui.tvFocusMark
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

// Today's scene (ANDROID-DESIGN §4.1 and §4.9a, Decision 079): a short play for two on the drama board, its opening
// as a page in the play's own words, then Try a line, Hear it and Read. Not on a TV.

/** Opens the reader with the studio: the play, the line to open at, the production, the raw part. */
typealias OpenStudio = (scriptId: String, line: String?, production: String, part: String) -> Unit

/** The day's scene from the library, or why there is none; nothing at all when the library has no play. */
@Composable
fun TodaysScene(
    onOpenScript: (String) -> Unit,
    onRead: (String) -> Unit,
    onOpenStudio: OpenStudio,
    heading: (@Composable () -> Unit)? = null,
    wide: Boolean = false,
) {
    val plays = LocalAppContainer.current.plays
    val state = rememberPlayRows()
    val scope = rememberCoroutineScope()
    when (state) {
        PlayLibraryFeed.Rows.Loading -> { heading?.invoke(); RowSpinner() }
        PlayLibraryFeed.Rows.Unavailable -> {
            heading?.invoke()
            RowProblem("The plays could not be read.", onRetry = { scope.launch { plays.feed.retry(); plays.loadRows() } })
        }
        is PlayLibraryFeed.Rows.Ready -> {
            val row = remember(state) { PlayScript.todaysScene(state.rows, RadioClock.localDate()) } ?: return
            val whole by produceState<PlayScript?>(null, row.id) {
                value = try {
                    plays.script(row.id)
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    println("[Scene] ${row.id} script unreachable: ${e.message}")
                    null
                }
            }
            heading?.invoke()
            SceneCard(row, whole, onOpenScript, onRead, onOpenStudio, wide)
        }
    }
}

@Composable
private fun SceneCard(
    row: PlayListing,
    whole: PlayScript?,
    onOpenScript: (String) -> Unit,
    onRead: (String) -> Unit,
    onOpenStudio: OpenStudio,
    wide: Boolean = false,
) {
    val container = LocalAppContainer.current
    val plays = container.plays
    val scope = rememberCoroutineScope()
    val dark = OnAir.colors.dark
    val on = onBoardColor(PLAY_BOARD, dark)
    val opening = remember(row, whole) { PlayScript.openingOf(whole ?: row, 4) }
    val voices = rememberDeviceVoices()
    val cast = rememberCast(voices, whole, null)
    var hearing by remember { mutableStateOf<Job?>(null) }
    var lit by remember { mutableIntStateOf(-1) }
    var trying by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    fun stop() {
        hearing?.cancel()
        hearing = null
        cast?.speaker?.cancel()
        lit = -1
    }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(lifecycle) {
        val observer = LifecycleEventObserver { _, event -> if (event == Lifecycle.Event.ON_STOP) stop() }
        lifecycle.addObserver(observer)
        onDispose {
            lifecycle.removeObserver(observer)
            stop()
        }
    }

    fun hear(handle: CastHandle) {
        if (hearing != null) { stop(); return }
        if (container.playback.state.value.isPlaying) container.playback.pause()
        hearing = scope.launch {
            try {
                for ((i, speech) in opening.withIndex()) {
                    lit = i
                    handle.speaker.speak(speech.text, speech.part)
                }
            } finally {
                lit = -1
                hearing = null
            }
        }
    }

    fun tryLine() {
        if (trying) return
        stop()
        trying = true
        error = null
        scope.launch {
            try {
                val script = whole ?: plays.script(row.id) ?: error("not found")
                val lines = PlayScript.openingOf(script, 4)
                val part = PlayScript.answeringPart(lines, script) ?: error("no part")
                val line = lines.firstOrNull { it.part == part }?.lineId ?: script.lines(part).firstOrNull()?.id
                StudioOpen.resolve(plays, script, part)?.let { onOpenStudio(script.id, line, it, part.raw) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                println("[Scene] Try a line failed: ${e.message}")
                error = "The production could not be saved."
            } finally {
                trying = false
            }
        }
    }

    val headBlock: @Composable (androidx.compose.ui.graphics.Color, Modifier) -> Unit = { ink, pad ->
        Column(
            Modifier.fillMaxWidth().tvFocusMark().clickable(onClickLabel = "Open play") { onOpenScript(row.id) }.then(pad),
            verticalArrangement = Arrangement.spacedBy(Spacing.S1.dp),
        ) {
            Text("TODAY’S SCENE", style = MaterialTheme.typography.labelMedium.copy(letterSpacing = 1.sp), color = ink)
            Text(
                row.title,
                style = MaterialTheme.typography.headlineSmall,
                color = ink,
                maxLines = 3,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.semantics { heading() },
            )
            val v = row.voices
            EventLine(listOf(row.authorLine.ifEmpty { null }, "$v ${if (v == 1) "voice" else "voices"}", "About ${row.minutes} min"), color = ink)
        }
    }
    val buttons: @Composable (androidx.compose.ui.graphics.Color, Modifier) -> Unit = { ink, pad ->
        ActionRow(pad) { fit ->
            Button(
                onClick = ::tryLine,
                enabled = !trying,
                colors = playButtonColors(),
                modifier = Modifier.tvFocusMark(),
            ) {
                Icon(Icons.Filled.Mic, contentDescription = null)
                Text("Try a line", Modifier.padding(start = Spacing.S2.dp), maxLines = 1)
            }
            @Suppress("UNUSED_EXPRESSION") cast?.tick
            if (cast != null && opening.isNotEmpty() && voices.voices().isNotEmpty()) {
                OutlinedButton(
                    onClick = { hear(cast) },
                    colors = androidx.compose.material3.ButtonDefaults.outlinedButtonColors(contentColor = ink),
                    modifier = Modifier.tvFocusMark(),
                ) { Text(if (hearing != null) "Stop" else "Hear it", maxLines = 1) }
            }
            FoldButton(Icons.AutoMirrored.Outlined.MenuBook, "Read", fit.folded, { stop(); onRead(row.id) }, description = "Read ${row.title}")
        }
    }
    if (wide) {
        // WEB-DESIGN §4.2r rule 6: the drama board holds only the opening; the words and buttons stand on the page
        // ground, beside it once the column is wide enough, under it on a phone.
        val ink = MaterialTheme.colorScheme.onSurface
        BoxWithConstraints(Modifier.fillMaxWidth().padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp)) {
            val beside = maxWidth >= 560.dp
            val boardBox: @Composable (Modifier) -> Unit = { m ->
                if (opening.isNotEmpty()) {
                    Box(m.clip(RoundedCornerShape(12.dp)).background(boardColor(PLAY_BOARD, dark)).padding(Spacing.S3.dp)) {
                        OpeningPage(opening, whole, lit)
                    }
                }
            }
            val words: @Composable (Modifier) -> Unit = { m ->
                Column(m, verticalArrangement = Arrangement.spacedBy(Spacing.S3.dp)) {
                    headBlock(ink, Modifier)
                    buttons(ink, Modifier)
                    error?.let { ErrorLine(it) }
                }
            }
            if (beside) {
                Row(horizontalArrangement = Arrangement.spacedBy(Spacing.S6.dp), verticalAlignment = Alignment.CenterVertically) {
                    boardBox(Modifier.width(320.dp))
                    words(Modifier.weight(1f))
                }
            } else {
                Column(verticalArrangement = Arrangement.spacedBy(Spacing.S3.dp)) {
                    words(Modifier.fillMaxWidth())
                    boardBox(Modifier.fillMaxWidth())
                }
            }
        }
        return
    }
    Column(
        Modifier.fillMaxWidth().padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp)
            .clip(RoundedCornerShape(12.dp)).background(boardColor(PLAY_BOARD, dark)),
    ) {
        headBlock(on, Modifier.padding(start = Spacing.S4.dp, end = Spacing.S4.dp, top = Spacing.S4.dp, bottom = Spacing.S3.dp))
        if (opening.isNotEmpty()) {
            OpeningPage(opening, whole, lit, Modifier.padding(horizontal = Spacing.S4.dp))
        }
        buttons(on, Modifier.padding(Spacing.S4.dp))
        error?.let { Box(Modifier.padding(start = Spacing.S4.dp, end = Spacing.S4.dp, bottom = Spacing.S4.dp)) { ErrorLine(it) } }
    }
}

/** The opening as a page on the print ground: each speech its role name over its said words, a rule in the part's hue. */
@Composable
private fun OpeningPage(opening: List<OpeningSpeech>, whole: PlayScript?, lit: Int, modifier: Modifier = Modifier) {
    val dark = OnAir.colors.dark
    Surface(
        modifier.fillMaxWidth(),
        shape = RoundedCornerShape(4.dp),
        color = if (dark) PrintGroundDark else PrintGroundLight,
        contentColor = MaterialTheme.colorScheme.onSurface,
    ) {
        Column(Modifier.padding(Spacing.S3.dp), verticalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
            opening.forEachIndexed { i, speech ->
                val hue = whole?.let { partMark(it, speech.part) } ?: MaterialTheme.colorScheme.outline
                Row(
                    Modifier.fillMaxWidth().height(IntrinsicSize.Min)
                        .background(if (i == lit) MaterialTheme.colorScheme.surfaceContainerHighest else androidx.compose.ui.graphics.Color.Transparent)
                        .semantics(mergeDescendants = true) { selected = i == lit },
                    horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp),
                ) {
                    Box(Modifier.width(3.dp).fillMaxHeight().background(hue))
                    Column(Modifier.weight(1f)) {
                        Text(speech.name, style = MaterialTheme.typography.labelMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(speech.text, style = MaterialTheme.typography.bodyMedium, maxLines = 3, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
        }
    }
}
