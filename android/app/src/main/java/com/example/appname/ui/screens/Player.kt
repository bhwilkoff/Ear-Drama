package com.example.appname.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bedtime
import androidx.compose.material.icons.filled.FormatQuote
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconToggleButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.appname.playback.NowPlaying
import com.example.appname.playback.PlaybackEngine
import com.example.appname.playback.SleepMode
import com.example.appname.playback.SleepState
import com.example.appname.together.RoomStatus
import com.example.appname.data.Transcript
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import com.example.appname.ui.ClaimTvFocus
import com.example.appname.ui.Loadable
import com.example.appname.ui.NowPlayingArt
import com.example.appname.ui.LocalAppContainer
import com.example.appname.ui.tvFocusMark
import com.example.appname.ui.rememberCatalogQuery
import com.example.appname.ui.episodeTitle
import com.example.appname.ui.formatAirDate
import com.example.appname.ui.formatClock
import com.example.appname.ui.theme.OnAir
import com.example.appname.ui.theme.Spacing

/** §4.13: true while this device is a guest in a room, which listens and never drives. */
@Composable
private fun rememberIsRoomGuest(): Boolean {
    val room by LocalAppContainer.current.together.status.collectAsState()
    return (room as? RoomStatus.In)?.isHost == false
}

/** The bar above the tabs while an episode is loaded; tapping it opens the player sheet. */
@Composable
fun MiniPlayer(onExpand: () -> Unit) {
    val engine = LocalAppContainer.current.playback
    val now by engine.state.collectAsState()
    val episode = now.episode ?: return
    val title = episodeTitle(episode)
    Surface(color = MaterialTheme.colorScheme.surfaceContainerHigh, tonalElevation = 2.dp) {
        Column {
            if (now.durationMs > 0) {
                LinearProgressIndicator(
                    progress = { (now.positionMs.toFloat() / now.durationMs).coerceIn(0f, 1f) },
                    modifier = Modifier.fillMaxWidth(),
                    color = OnAir.colors.live,
                )
            }
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable(onClickLabel = "Open player", onClick = onExpand)
                    .padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(Modifier.weight(1f)) {
                    Text(title, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(
                        now.problem ?: episode.seriesName,
                        style = MaterialTheme.typography.labelMedium,
                        color = if (now.failed) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                // A guest's Play and Pause are their own (Decision 067): pause holds, play catches up.
                PlayPauseButton(now, engine, filled = false, enabled = true)
            }
        }
    }
}

@Composable
private fun PlayPauseButton(now: NowPlaying, engine: PlaybackEngine, filled: Boolean, enabled: Boolean, modifier: Modifier = Modifier) {
    val icon = if (now.isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow
    val label = if (now.isPlaying) "Pause" else "Play"
    if (filled) {
        FilledIconButton(
            onClick = engine::togglePlay,
            enabled = enabled,
            modifier = modifier.size(72.dp),
            colors = IconButtonDefaults.filledIconButtonColors(
                containerColor = OnAir.colors.live,
                contentColor = OnAir.colors.onLive,
            ),
        ) {
            Icon(icon, contentDescription = label, modifier = Modifier.size(40.dp))
        }
    } else {
        IconButton(onClick = engine::togglePlay, enabled = enabled) {
            Icon(icon, contentDescription = label, tint = if (enabled) OnAir.colors.live else LocalContentColor.current)
        }
    }
}

/** The player (R18): position, skip back 15 and forward 30, speed, and the sleep timer, all here. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PlayerSheet(
    onDismiss: () -> Unit,
    onOpenEpisode: (String) -> Unit,
    onOpenTranscript: (String) -> Unit,
    onListenTogether: () -> Unit,
) {
    val engine = LocalAppContainer.current.playback
    val now by engine.state.collectAsState()
    val room by LocalAppContainer.current.together.status.collectAsState()
    // The controls come back on handoff.
    val guest = rememberIsRoomGuest()
    val episode = now.episode
    val hasTranscript by rememberCatalogQuery(episode?.id) { db ->
        episode?.let { db.episodeDetail(it.id)?.transcriptUrl } != null
    }
    // Decision 069: the episode's face, else the series', else its typographic card.
    val face by rememberCatalogQuery(episode?.id) { db ->
        episode?.let { db.episodeDetail(it.id)?.face ?: it.seriesFace }
    }
    ModalBottomSheet(onDismissRequest = onDismiss) {
        if (episode == null) {
            Box(Modifier.padding(Spacing.S6.dp)) { Text("Nothing is playing.") }
            return@ModalBottomSheet
        }
        Column(
            Modifier.fillMaxWidth().padding(horizontal = Spacing.S6.dp).navigationBarsPadding(),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            NowPlayingArt(
                episode.seriesName, episode.seriesGenre, episode.airDate?.take(4),
                (face as? Loadable.Ready)?.value ?: episode.seriesFace,
            )
            Spacer(Modifier.height(Spacing.S3.dp))
            Text(
                episode.seriesName,
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                episodeTitle(episode),
                style = MaterialTheme.typography.headlineSmall,
                maxLines = 3,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.tvFocusMark().clickable(onClickLabel = "Open episode") { onOpenEpisode(episode.id) },
            )
            formatAirDate(episode.airDate)?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            now.problem?.let { problem ->
                Text(
                    problem,
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.padding(top = Spacing.S2.dp),
                )
            }
            PositionSlider(now, engine, enabled = !guest)
            // On a TV the sheet takes the D-pad on Play or Pause (§9.2); every control wears the ring.
            val playPause = remember { FocusRequester() }
            ClaimTvFocus(playPause, episode.id)
            Row(
                horizontalArrangement = Arrangement.spacedBy(Spacing.S6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                IconButton(onClick = engine::skipBack, enabled = !guest, modifier = Modifier.size(56.dp).tvFocusMark()) {
                    Icon(
                        painterResource(androidx.media3.session.R.drawable.media3_icon_skip_back_15),
                        contentDescription = "Back 15 seconds",
                        modifier = Modifier.size(32.dp),
                    )
                }
                PlayPauseButton(now, engine, filled = true, enabled = true, modifier = Modifier.focusRequester(playPause).tvFocusMark())
                IconButton(onClick = engine::skipForward, enabled = !guest, modifier = Modifier.size(56.dp).tvFocusMark()) {
                    Icon(
                        painterResource(androidx.media3.session.R.drawable.media3_icon_skip_forward_30),
                        contentDescription = "Forward 30 seconds",
                        modifier = Modifier.size(32.dp),
                    )
                }
            }
            Row(
                Modifier.fillMaxWidth().padding(vertical = Spacing.S4.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                SpeedMenu(now.speed, engine, enabled = !guest)
                if ((hasTranscript as? Loadable.Ready)?.value == true) {
                    IconButton(onClick = { onOpenTranscript(episode.id) }, modifier = Modifier.tvFocusMark()) {
                        Icon(Icons.Filled.FormatQuote, contentDescription = Transcript.LABEL)
                    }
                }
                IconButton(onClick = onListenTogether, modifier = Modifier.tvFocusMark()) {
                    Icon(
                        Icons.Filled.Groups,
                        contentDescription = "Listen together",
                        tint = if (room is RoomStatus.In) MaterialTheme.colorScheme.primary else LocalContentColor.current,
                    )
                }
                LevelToggle(engine)
                SleepMenu(now, engine)
            }
            if (now.upNext.isNotEmpty()) {
                HorizontalDivider()
                Text(
                    "Up next: ${episodeTitle(now.upNext.first())}",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.padding(vertical = Spacing.S3.dp),
                )
            }
            // Decision 067: at an arc's last part the next story is offered, never started by itself.
            val story = now.nextStory
            if (story != null && !guest) {
                OutlinedButton(
                    onClick = { engine.play(story) },
                    modifier = Modifier.padding(bottom = Spacing.S3.dp).tvFocusMark()
                        .semantics { contentDescription = "Next story: ${episodeTitle(story)}" },
                ) {
                    Icon(Icons.Filled.SkipNext, contentDescription = null)
                    Spacer(Modifier.size(Spacing.S2.dp))
                    Text("Next story")
                }
            }
        }
    }
}

/** Decision 067: volume leveled on the device as it plays, on by default; this turns it off and on. */
@Composable
private fun LevelToggle(engine: PlaybackEngine) {
    val on by engine.leveling.collectAsState()
    IconToggleButton(
        checked = on,
        onCheckedChange = engine::setLeveling,
        modifier = Modifier.tvFocusMark().semantics { stateDescription = if (on) "On" else "Off" },
    ) {
        Icon(
            Icons.Filled.GraphicEq,
            contentDescription = "Level volume",
            tint = if (on) MaterialTheme.colorScheme.secondary else LocalContentColor.current,
        )
    }
}

@Composable
private fun PositionSlider(now: NowPlaying, engine: PlaybackEngine, enabled: Boolean) {
    var dragging by remember { mutableStateOf(false) }
    var dragValue by remember { mutableFloatStateOf(0f) }
    val duration = now.durationMs.coerceAtLeast(1)
    val shown = if (dragging) dragValue else now.positionMs.toFloat().coerceIn(0f, duration.toFloat())
    Column(Modifier.fillMaxWidth().padding(top = Spacing.S4.dp)) {
        Slider(
            value = shown,
            onValueChange = { dragging = true; dragValue = it },
            onValueChangeFinished = { engine.seekTo(dragValue.toLong()); dragging = false },
            valueRange = 0f..duration.toFloat(),
            enabled = enabled && now.durationMs > 0,
            colors = SliderDefaults.colors(thumbColor = OnAir.colors.live, activeTrackColor = OnAir.colors.live),
            modifier = Modifier.semantics {
                contentDescription = "Position"
                stateDescription = "${formatClock(shown.toLong())} of ${formatClock(now.durationMs)}"
            },
        )
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(formatClock(shown.toLong()), style = MaterialTheme.typography.bodySmall)
            Text(
                if (now.durationMs > 0) "-" + formatClock(now.durationMs - shown.toLong()) else "",
                style = MaterialTheme.typography.bodySmall,
            )
        }
    }
}

private fun speedLabel(speed: Float): String =
    java.math.BigDecimal(speed.toString()).stripTrailingZeros().toPlainString() + "×"

@Composable
private fun SpeedMenu(speed: Float, engine: PlaybackEngine, enabled: Boolean) {
    var open by remember { mutableStateOf(false) }
    // A room's drift nudge (0.97, 1.03) is not a speed anyone chose; the label shows the chosen one.
    val shown = PlaybackEngine.SPEEDS.minBy { kotlin.math.abs(it - speed) }
    Box {
        TextButton(
            onClick = { open = true },
            enabled = enabled,
            modifier = Modifier.tvFocusMark().semantics { contentDescription = "Playback speed, ${speedLabel(shown)}" },
        ) { Text(speedLabel(shown)) }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            PlaybackEngine.SPEEDS.forEach { s ->
                DropdownMenuItem(
                    text = { Text(speedLabel(s)) },
                    onClick = { engine.setSpeed(s); open = false },
                )
            }
        }
    }
}

private fun sleepLabel(mode: SleepMode): String = when (mode) {
    SleepMode.EndOfEpisode -> "End of this episode"
    is SleepMode.Minutes -> "${mode.minutes} minutes"
}

@Composable
private fun SleepMenu(now: NowPlaying, engine: PlaybackEngine) {
    var open by remember { mutableStateOf(false) }
    val armed = now.sleep as? SleepState.Armed
    val status = when {
        armed?.mode == SleepMode.EndOfEpisode -> "End of episode"
        armed != null -> now.sleepRemainingMs?.let { formatClock(it) } ?: ""
        else -> ""
    }
    Box {
        TextButton(
            onClick = { open = true },
            modifier = Modifier.tvFocusMark().semantics {
                contentDescription = if (armed == null) "Sleep timer, off" else "Sleep timer, ${sleepLabel(armed.mode)}"
            },
        ) {
            Icon(Icons.Filled.Bedtime, contentDescription = null)
            if (status.isNotEmpty()) Text(" $status")
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            engine.sleepOptions.forEach { mode ->
                DropdownMenuItem(
                    text = { Text(sleepLabel(mode)) },
                    onClick = { engine.setSleep(mode); open = false },
                )
            }
            if (armed != null) {
                DropdownMenuItem(text = { Text("Turn off") }, onClick = { engine.setSleep(null); open = false })
            }
        }
    }
}
