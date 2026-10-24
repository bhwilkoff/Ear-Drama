package com.example.appname.ui.screens

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Sensors
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.appname.data.EpisodeDetail
import com.example.appname.radio.RadioClock
import com.example.appname.radio.RadioEvening
import com.example.appname.radio.RadioLoad
import com.example.appname.radio.RadioSlot
import com.example.appname.radio.Station
import com.example.appname.radio.StationClock
import com.example.appname.ui.CenteredBox
import com.example.appname.ui.ClaimTvFocus
import com.example.appname.ui.EmptyMessage
import com.example.appname.ui.Haptic
import com.example.appname.ui.LocalAppContainer
import com.example.appname.ui.LocalIsTelevision
import com.example.appname.ui.LocalOnline
import com.example.appname.ui.OFFLINE_LINE
import com.example.appname.ui.episodeTitle
import com.example.appname.ui.rememberHaptics
import com.example.appname.ui.liveButtonColors
import com.example.appname.ui.theme.OnAir
import com.example.appname.ui.theme.Spacing
import com.example.appname.ui.tvFocusMark
import java.time.Instant
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** How often the slot on the air is re-read from the clock. */
private const val REPAINT_MS = 15_000L

/**
 * Stations (ANDROID-DESIGN §4.10): a row a station, Tonight in 19xx first and
 * then the genre stations, each with what is on now and Listen live; then the
 * evening published for the listener's own date as a list of its slots on the
 * one clock. On a TV every slot is a focus stop and the first Listen live
 * takes focus on entry (§9.2).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RadioScreen(onOpenEpisode: (String) -> Unit) {
    val container = LocalAppContainer.current
    val online = LocalOnline.current
    val haptics = rememberHaptics()
    var now by remember { mutableStateOf(Instant.now()) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(REPAINT_MS)
            now = Instant.now()
        }
    }
    val date = RadioClock.localDate(now)
    val dbVersion by container.catalog.dbVersion.collectAsState()
    var attempt by remember { mutableIntStateOf(0) }
    // Decision 067: the year the listener picked for today, or null for the published one.
    var picked by remember(date) { mutableStateOf<String?>(null) }
    val load by produceState<RadioLoad>(RadioLoad.Loading, date, dbVersion, attempt, picked) {
        if (value is RadioLoad.Failed) value = RadioLoad.Loading
        value = RadioLoad.load(
            fetch = { container.api.tonight() },
            db = { container.catalog.awaitDb() },
            date = date,
            picked = picked,
        )
    }
    // A missing or unreachable stations file leaves Tonight alone, as before any station existed.
    val stations by produceState(emptyList<Station>(), attempt) {
        value = try {
            container.api.stations()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            println("[Radio] stations.json unreachable: ${e.message}")
            emptyList()
        }
    }
    val failed = load is RadioLoad.Failed
    LaunchedEffect(failed) { if (failed) haptics(Haptic.Error) }

    Scaffold(topBar = { TopAppBar(title = { Text("Stations") }) }) { padding ->
        when (val state = load) {
            RadioLoad.Loading -> CenteredBox(Modifier.padding(padding)) {
                CircularProgressIndicator(Modifier.semantics { contentDescription = "Loading" })
            }
            RadioLoad.Nothing -> if (stations.isNotEmpty()) {
                val first = remember { FocusRequester() }
                ClaimTvFocus(first, stations.size)
                LazyColumn(Modifier.padding(padding).fillMaxSize()) { stationRows(null, stations, now, first) }
            } else {
                EmptyMessage("No evening is published for today.", Modifier.padding(padding))
            }
            RadioLoad.Failed -> CenteredBox(Modifier.padding(padding)) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(
                        if (online) "Tonight could not load." else OFFLINE_LINE,
                        style = MaterialTheme.typography.bodyMedium,
                        textAlign = TextAlign.Center,
                    )
                    Spacer(Modifier.height(Spacing.S4.dp))
                    Button(onClick = { attempt += 1 }) { Text("Try again") }
                }
            }
            is RadioLoad.Evening -> Evening(state.evening, stations, now, Modifier.padding(padding), onOpenEpisode) {
                picked = it
            }
        }
    }
}

@Composable
private fun Evening(
    evening: RadioEvening,
    stations: List<Station>,
    now: Instant,
    modifier: Modifier,
    onOpenEpisode: (String) -> Unit,
    onPickYear: (String) -> Unit,
) {
    val container = LocalAppContainer.current
    val television = LocalIsTelevision.current
    val uri = LocalUriHandler.current
    val liveDay by container.live.day.collectAsState()
    val day = evening.day
    val slots = day.slots
    val onAir = RadioClock.onAir(slots, now)
    val isLive = liveDay == day

    val liveButton = remember { FocusRequester() }
    val firstSlot = remember { FocusRequester() }
    val canListen = stationActions(evening, stations, now).any { it }
    ClaimTvFocus(if (canListen) liveButton else firstSlot, canListen)

    LazyColumn(modifier.fillMaxSize()) {
        stationRows(evening, stations, now, liveButton)
        item(key = "header") {
            Column(Modifier.padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp)) {
                Text(
                    "Tonight in ${day.year}",
                    style = MaterialTheme.typography.headlineSmall,
                    modifier = Modifier.semantics { heading() },
                )
                Text(RadioClock.longDate(day.evening), style = MaterialTheme.typography.bodyMedium)
                day.stationLine?.let {
                    Text(it, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                if (evening.choices.size > 1) {
                    YearMenu(evening.day.evening, evening.choices) { year ->
                        if (isLive) container.live.stop()
                        onPickYear(year)
                    }
                }
            }
        }
        itemsIndexed(slots, key = { _, slot -> slot.utcStart.toString() }) { index, slot ->
            val detail = evening.detail(slot)
            SlotRow(
                slot = slot,
                zone = evening.zone,
                detail = detail,
                isNow = index == onAir.index,
                television = television,
                modifier = if (index == 0) Modifier.focusRequester(firstSlot) else Modifier,
                onOpen = { detail?.let { onOpenEpisode(it.episode.id) } },
                onPlay = {
                    if (detail != null) {
                        container.live.stop()
                        container.playback.play(detail.episode, startMs = 0)
                    }
                },
            )
        }
        day.witnessLine?.let { line ->
            item(key = "witness") {
                val url = day.witness?.url
                val link = !television && url != null
                Text(
                    "Schedule: $line",
                    style = MaterialTheme.typography.labelMedium,
                    color = if (link) OnAir.colors.link else MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier
                        .then(if (link) Modifier.clickable { uri.openUri(url) } else Modifier)
                        .padding(horizontal = Spacing.S4.dp, vertical = Spacing.S3.dp),
                )
            }
        }
    }
}

/** Which rows of [stationRows] can listen live now, in order: Tonight's (when [evening] is set), then each station's. */
private fun stationActions(evening: RadioEvening?, stations: List<Station>, now: Instant): List<Boolean> =
    listOfNotNull(evening?.let { e -> RadioClock.onAir(e.day.slots, now).index?.let { e.detail(e.day.slots[it]) } != null }) +
        stations.map { StationClock.onNow(it.slots, now)?.slot?.playableEpisode != null }

/**
 * The stations row (§4.10): Tonight first, then each genre station, each with
 * what is on now and one Listen live. [first] lands on the first row that can
 * listen, for the TV's focus on entry. A station's episodes are resolved only
 * when someone tunes in.
 */
private fun LazyListScope.stationRows(evening: RadioEvening?, stations: List<Station>, now: Instant, first: FocusRequester) {
    val actions = stationActions(evening, stations, now)
    val firstAction = actions.indexOfFirst { it }
    var row = 0
    if (evening != null) {
        val index = row++
        item(key = "station-tonight") {
            val container = LocalAppContainer.current
            val liveDay by container.live.day.collectAsState()
            val slots = evening.day.slots
            val onAir = RadioClock.onAir(slots, now)
            val slot = onAir.index?.let { slots[it] }
            val note = when (onAir.phase) {
                RadioClock.Phase.Before -> slots.firstOrNull()?.let { "Starts at ${RadioClock.clock(it.utcStart)}" }
                RadioClock.Phase.After -> RadioClock.end(slots)?.let { "Ended at ${RadioClock.clock(it)}" }
                RadioClock.Phase.During -> slot?.takeIf { evening.detail(it) == null }?.let { RadioClock.gapNote(it) }
            }
            StationRow(
                name = "Tonight in ${evening.day.year}",
                slot = slot?.takeIf { evening.detail(it) != null },
                note = note,
                isLive = liveDay == evening.day,
                canListen = actions[index],
                modifier = if (index == firstAction) Modifier.focusRequester(first) else Modifier,
                onListen = { container.live.tuneIn(evening) },
                onStop = { container.live.pauseAndStop() },
            )
        }
    }
    stations.forEach { station ->
        val index = row++
        item(key = "station-${station.genre}") {
            val container = LocalAppContainer.current
            val scope = rememberCoroutineScope()
            val liveStation by container.live.station.collectAsState()
            val on = StationClock.onNow(station.slots, now)
            StationRow(
                name = station.name,
                slot = on?.slot,
                note = on?.slot?.takeIf { it.playableEpisode == null }?.let { RadioClock.gapNote(it) },
                isLive = liveStation == station.genre,
                canListen = actions[index],
                modifier = if (index == firstAction) Modifier.focusRequester(first) else Modifier,
                onListen = {
                    scope.launch {
                        val slots = StationClock.ahead(station.slots, Instant.now())
                        val details = StationClock.details(slots, container.catalog.awaitDb())
                        container.live.tuneIn(station, slots, details)
                    }
                },
                onStop = { container.live.pauseAndStop() },
            )
        }
    }
}

/** A station's row: its name, what is on now (series, title), and Listen live or Listening live. */
@Composable
private fun StationRow(
    name: String,
    slot: RadioSlot?,
    note: String?,
    isLive: Boolean,
    canListen: Boolean,
    modifier: Modifier,
    onListen: () -> Unit,
    onStop: () -> Unit,
) {
    val episode = slot?.playableEpisode
    val muted = MaterialTheme.colorScheme.onSurfaceVariant
    ListItem(
        headlineContent = { Text(name, style = MaterialTheme.typography.titleMedium) },
        supportingContent = {
            Column {
                episode?.let { Text(it.series, style = MaterialTheme.typography.bodyMedium, maxLines = 1, overflow = TextOverflow.Ellipsis) }
                episode?.title?.let { Text(it, style = MaterialTheme.typography.labelMedium, color = muted, maxLines = 1, overflow = TextOverflow.Ellipsis) }
                note?.let { Text(it, style = MaterialTheme.typography.labelMedium, color = muted) }
            }
        },
        trailingContent = when {
            isLive -> {
                {
                    OutlinedButton(
                        onClick = onStop,
                        modifier = modifier.semantics { stateDescription = "On" },
                        colors = ButtonDefaults.outlinedButtonColors(contentColor = OnAir.colors.live),
                        border = BorderStroke(1.dp, OnAir.colors.live),
                    ) {
                        Icon(Icons.Filled.Sensors, contentDescription = null, Modifier.size(ButtonDefaults.IconSize))
                        Spacer(Modifier.width(ButtonDefaults.IconSpacing))
                        Text("Listening live")
                    }
                }
            }
            canListen -> {
                {
                    Button(
                        onClick = onListen,
                        modifier = modifier.semantics { contentDescription = "Listen live to $name" },
                        colors = liveButtonColors(),
                    ) {
                        Icon(Icons.Filled.PlayArrow, contentDescription = null, Modifier.size(ButtonDefaults.IconSize))
                        Spacer(Modifier.width(ButtonDefaults.IconSpacing))
                        Text("Listen live")
                    }
                }
            }
            else -> null
        },
    )
}

/** Decision 067: another published year for the same date; picking one ends listening live. */
@Composable
private fun YearMenu(current: String, choices: List<String>, onPick: (String) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        TextButton(
            onClick = { open = true },
            modifier = Modifier.tvFocusMark().semantics { contentDescription = "Year ${current.take(4)}" },
        ) {
            Text("Year ${current.take(4)}")
            Icon(Icons.Filled.ArrowDropDown, contentDescription = null)
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            choices.forEach { choice ->
                DropdownMenuItem(
                    text = { Text(choice.take(4)) },
                    onClick = {
                        open = false
                        if (choice != current) onPick(choice)
                    },
                    modifier = Modifier.semantics { selected = choice == current },
                )
            }
        }
    }
}

/**
 * A surviving slot opens its episode and, off a TV, has Play; a gap is muted
 * and says why, never the paper's printed text (R9). On a TV each row is one
 * focus stop, gaps included.
 */
@Composable
private fun SlotRow(
    slot: RadioSlot,
    zone: String,
    detail: EpisodeDetail?,
    isNow: Boolean,
    television: Boolean,
    modifier: Modifier,
    onOpen: () -> Unit,
    onPlay: () -> Unit,
) {
    val (local, eastern) = RadioClock.timeLabel(slot, zone)
    val muted = MaterialTheme.colorScheme.onSurfaceVariant
    val gap = detail == null
    val headline = if (detail == null) slot.knownSeries ?: RadioClock.gapNote(slot) else slot.playableEpisode?.series ?: detail.episode.seriesName
    val caption = listOfNotNull(
        "Now".takeIf { isNow },
        RadioClock.gapNote(slot).takeIf { gap && slot.knownSeries != null },
        "${slot.lengthMin} min",
    ).joinToString(" · ")
    val action = when {
        !gap -> Modifier.clickable(onClickLabel = "Open episode", onClick = onOpen)
        television -> Modifier.focusable()
        else -> Modifier
    }
    val liveEdge = OnAir.colors.live
    ListItem(
        modifier = modifier
            .tvFocusMark()
            .then(action)
            .semantics { selected = isNow }
            // The slot on the air wears the live red as its leading edge (§6.1a, the web's slot-now).
            .then(
                if (isNow) {
                    Modifier.drawWithContent {
                        drawContent()
                        drawRect(liveEdge, size = Size(4.dp.toPx(), size.height))
                    }
                } else {
                    Modifier
                },
            ),
        colors = if (isNow) {
            ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.surfaceVariant)
        } else {
            ListItemDefaults.colors()
        },
        leadingContent = {
            Column(Modifier.widthIn(min = 88.dp)) {
                Text(local, style = MaterialTheme.typography.bodySmall)
                eastern?.let { Text(it, style = MaterialTheme.typography.labelMedium, color = muted) }
            }
        },
        headlineContent = {
            Text(
                headline,
                style = MaterialTheme.typography.titleMedium,
                color = if (gap) muted else MaterialTheme.colorScheme.onSurface,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        },
        supportingContent = {
            Column {
                detail?.let {
                    Text(
                        episodeTitle(it.episode),
                        style = MaterialTheme.typography.bodyMedium,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                Text(caption, style = MaterialTheme.typography.labelMedium, color = muted)
            }
        },
        trailingContent = if (detail != null && !television) {
            {
                IconButton(onClick = onPlay) {
                    Icon(Icons.Filled.PlayArrow, contentDescription = "Play ${episodeTitle(detail.episode)}, $headline")
                }
            }
        } else {
            null
        },
    )
}
