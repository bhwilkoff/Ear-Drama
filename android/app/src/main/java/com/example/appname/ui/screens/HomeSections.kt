package com.example.appname.ui.screens

import androidx.compose.material.icons.outlined.MenuBook
import com.example.appname.plays.PlayLibraryFeed
import com.example.appname.plays.PlayListing
import com.example.appname.plays.SharedPlays
import com.example.appname.ui.ActionRow
import com.example.appname.ui.FoldButton
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.background
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Explore
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Radio
import androidx.compose.material.icons.filled.Sensors
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.example.appname.data.EpisodeRow
import com.example.appname.data.HomeShelf
import com.example.appname.data.SeriesRow
import com.example.appname.plays.PlaysLibrary
import com.example.appname.plays.PlayScript
import com.example.appname.radio.HomeLive
import com.example.appname.radio.RadioClock
import com.example.appname.radio.RadioEvening
import com.example.appname.radio.RadioLoad
import com.example.appname.radio.Station
import com.example.appname.radio.StationClock
import com.example.appname.ui.EventLine
import com.example.appname.ui.Haptic
import com.example.appname.ui.LocalAppContainer
import com.example.appname.ui.LocalIsTelevision
import com.example.appname.ui.LocalOnline
import com.example.appname.ui.Loadable
import com.example.appname.ui.OFFLINE_LINE
import com.example.appname.ui.PlayHeadBoard
import com.example.appname.ui.STATIONS_MEMO
import com.example.appname.ui.ScreenMemo
import com.example.appname.ui.SectionHeader
import com.example.appname.ui.SeriesKeyWindow
import com.example.appname.ui.ShowTile
import com.example.appname.ui.catalogProblem
import com.example.appname.ui.episodeTitle
import com.example.appname.ui.formatLength
import com.example.appname.ui.innerWidth
import com.example.appname.ui.playButtonColors
import com.example.appname.ui.rememberCatalogQuery
import com.example.appname.ui.rememberHaptics
import com.example.appname.ui.rememberNameHeight
import com.example.appname.ui.theme.OnAir
import com.example.appname.ui.theme.Spacing
import com.example.appname.ui.tvFocusMark
import java.time.Instant
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// Home's sections (ANDROID-DESIGN §4.1, Decision 075): On the air, the three doors, the chip rows
// (Start a show, By length), and Today's play. Each has its own loading, error and offline state.

private const val REPAINT_MS = 15_000L
private val RailTileWidth = 220.dp

private sealed interface LiveLoad {
    data object Loading : LiveLoad
    data object Failed : LiveLoad
    data class Ready(val evening: RadioEvening?, val stations: List<Station>) : LiveLoad
}

private const val LIVE_MEMO = "home.live"

/** A problem in one row's own place: the line, then Try again. */
@Composable
internal fun RowProblem(text: String, onRetry: () -> Unit, modifier: Modifier = Modifier) {
    Column(
        modifier.fillMaxWidth().padding(horizontal = Spacing.S4.dp, vertical = Spacing.S3.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Spacing.S2.dp),
    ) {
        Text(text, style = MaterialTheme.typography.bodyMedium, textAlign = TextAlign.Center)
        OutlinedButton(onClick = onRetry, modifier = Modifier.tvFocusMark()) { Text("Try again") }
    }
}

@Composable
internal fun RowSpinner(modifier: Modifier = Modifier) {
    Box(modifier.fillMaxWidth().height(96.dp), contentAlignment = Alignment.Center) {
        CircularProgressIndicator(Modifier.semantics { contentDescription = "Loading" })
    }
}

/**
 * On the air: tonight's slot on now, else the first genre station with a playable slot, as a
 * window and name over an event line ("{episode} · N min in"), then Listen live and All stations.
 * Absent when nothing is on. [onSettled] tells the screen whether the block is drawn, so a TV's
 * focus lands on Listen live ([liveFocus]) or, without it, on the first row.
 */
@Composable
fun OnAirBlock(
    onOpenStations: () -> Unit,
    onOpenEpisode: (String) -> Unit,
    liveFocus: FocusRequester,
    onSettled: (Boolean) -> Unit,
) {
    val container = LocalAppContainer.current
    val online = LocalOnline.current
    val haptics = rememberHaptics()
    val scope = rememberCoroutineScope()
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
    // Back on Home, the last block draws at once while it reloads behind it.
    val load by produceState(ScreenMemo.get<LiveLoad.Ready>(LIVE_MEMO) ?: LiveLoad.Loading, date, dbVersion, attempt) {
        if (value is LiveLoad.Failed) value = LiveLoad.Loading
        // A stations file that is missing or unreachable leaves tonight alone (as Stations does).
        val stations = try {
            container.api.stations().also { ScreenMemo.put(STATIONS_MEMO, it) }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            println("[Home] stations.json unreachable: ${e.message}")
            emptyList()
        }
        value = when (val r = RadioLoad.load({ container.api.tonight() }, { container.catalog.awaitDb() }, date)) {
            RadioLoad.Failed -> LiveLoad.Failed
            is RadioLoad.Evening -> LiveLoad.Ready(r.evening, stations)
            else -> LiveLoad.Ready(null, stations)
        }.also { if (it is LiveLoad.Ready) ScreenMemo.put(LIVE_MEMO, it) }
    }
    val state = load
    val on = (state as? LiveLoad.Ready)?.let { HomeLive.now(it.evening, it.stations, now) }
    val loading = state is LiveLoad.Loading
    LaunchedEffect(loading, on != null) { if (!loading) onSettled(on != null) }
    val failed = state is LiveLoad.Failed
    LaunchedEffect(failed) { if (failed) haptics(Haptic.Error) }
    when {
        loading -> RowSpinner()
        failed -> RowProblem(if (online) "Tonight could not load." else OFFLINE_LINE, onRetry = { attempt += 1 })
        on != null -> {
            val liveDay by container.live.day.collectAsState()
            val liveStation by container.live.station.collectAsState()
            val tuned = on.station?.let { liveStation == it.genre } ?: (liveDay == on.evening?.day)
            val episode = on.slot.playableEpisode!!
            ElevatedCard(Modifier.fillMaxWidth().padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp)) {
                Column(Modifier.padding(Spacing.S4.dp), verticalArrangement = Arrangement.spacedBy(Spacing.S3.dp)) {
                    Text(
                        on.kicker.uppercase(),
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.semantics { heading() },
                    )
                    Row(
                        Modifier.fillMaxWidth().tvFocusMark()
                            // Down goes to Listen live, never past it to All stations (§9.2).
                            .focusProperties { down = liveFocus }
                            .clickable(onClickLabel = "Open episode") { onOpenEpisode(episode.id) },
                        horizontalArrangement = Arrangement.spacedBy(Spacing.S3.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        SeriesKeyWindow(episode.id.substringBefore('|'), episode.series, Modifier.size(64.dp))
                        Column(Modifier.weight(1f)) {
                            Text(episode.series, style = MaterialTheme.typography.titleMedium, maxLines = 2)
                            EventLine(listOf(episode.title, "${on.minutesIn(now)} min in"))
                        }
                    }
                    on.note?.let { Text(it, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                    Row(horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp), verticalAlignment = Alignment.CenterVertically) {
                        Button(
                            onClick = {
                                when {
                                    tuned -> container.live.pauseAndStop()
                                    on.station != null -> scope.launch {
                                        val slots = StationClock.ahead(on.station.slots, Instant.now())
                                        val details = StationClock.details(slots, container.catalog.awaitDb())
                                        container.live.tuneIn(on.station, slots, details)
                                    }
                                    else -> container.live.tuneIn(on.evening!!)
                                }
                            },
                            colors = playButtonColors(),
                            modifier = Modifier.focusRequester(liveFocus).tvFocusMark().semantics {
                                contentDescription = if (tuned) "Listening live to ${on.kicker}, stop" else "Listen live to ${on.kicker}"
                            },
                        ) {
                            Icon(Icons.Filled.Sensors, contentDescription = null)
                            Text(if (tuned) "Listening live" else "Listen live", Modifier.padding(start = Spacing.S2.dp), maxLines = 1)
                        }
                        OutlinedButton(onClick = onOpenStations, modifier = Modifier.tvFocusMark()) {
                            Text("All stations", maxLines = 1)
                        }
                    }
                }
            }
        }
    }
}

/** The three doors: the app's three jobs on one row, a Material icon over a verb each; a TV has no Record. */
@Composable
fun HomeDoors(onListen: () -> Unit, onFind: () -> Unit, onRecord: () -> Unit) {
    val television = LocalIsTelevision.current
    Row(
        Modifier.fillMaxWidth().padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp),
        horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp),
    ) {
        Door("Listen", Icons.Filled.Radio, onListen, Modifier.weight(1f))
        Door("Find a show", Icons.Filled.Explore, onFind, Modifier.weight(1f))
        if (!television) Door("Record a play", Icons.Filled.Mic, onRecord, Modifier.weight(1f))
    }
}

@Composable
private fun Door(label: String, icon: ImageVector, onClick: () -> Unit, modifier: Modifier) {
    OutlinedCard(onClick = onClick, modifier = modifier.tvFocusMark()) {
        Column(
            Modifier.fillMaxWidth().padding(vertical = Spacing.S3.dp, horizontal = Spacing.S1.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(Spacing.S1.dp),
        ) {
            Icon(icon, contentDescription = null)
            Text(label, style = MaterialTheme.typography.labelMedium, maxLines = 1)
        }
    }
}

private data class ShelfTiles(val rows: List<EpisodeRow>, val series: Map<String, SeriesRow>)

/**
 * A row of chips over a rail of first episodes: each chip a published shelf (Start a show, By length).
 * One shelf has no chips and heads the row "{title}: {label}"; no shelves, no row. The tile is the show
 * tile (series window, name, episode title, length) with Play on the window's corner.
 */
@Composable
fun ChipShelfRow(
    title: String,
    shelves: List<HomeShelf>,
    onOpenEpisode: (String) -> Unit,
    onOpenSeries: (String) -> Unit,
) {
    if (shelves.isEmpty()) return
    var pickedKey by rememberSaveable(title) { mutableStateOf<String?>(null) }
    val on = shelves.firstOrNull { it.key == pickedKey } ?: shelves.first()
    val haptics = rememberHaptics()
    val container = LocalAppContainer.current
    val online = LocalOnline.current
    var attempt by remember { mutableIntStateOf(0) }
    SectionHeader(if (shelves.size == 1) "$title: ${on.label}" else title)
    if (shelves.size > 1) {
        LazyRow(
            contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = Spacing.S4.dp),
            horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp),
        ) {
            items(shelves, key = { it.key }) { s ->
                FilterChip(
                    selected = s == on,
                    onClick = { if (s != on) { pickedKey = s.key; haptics(Haptic.Selection) } },
                    label = { Text(s.label) },
                    modifier = Modifier.tvFocusMark(),
                )
            }
        }
        Spacer(Modifier.height(Spacing.S2.dp))
    }
    val tiles by rememberCatalogQuery(on.key, attempt) { db ->
        val rows = db.episodes(on.ids).distinctBy { it.id }
        ShelfTiles(rows, rows.map { it.seriesKey }.distinct().mapNotNull { k -> db.series(k)?.let { k to it } }.toMap())
    }
    when (val state = tiles) {
        Loadable.Loading -> RowSpinner()
        Loadable.NoCatalog, Loadable.Failed ->
            RowProblem(catalogProblem(state, online) ?: "", onRetry = { attempt += 1 })
        is Loadable.Ready -> {
            val rows = state.value.rows
            if (rows.isEmpty()) {
                Text("Nothing here yet.", Modifier.padding(horizontal = Spacing.S4.dp), style = MaterialTheme.typography.bodyMedium)
            } else {
                val names = rows.map { it.seriesName }
                val nameHeight = rememberNameHeight(names, innerWidth(RailTileWidth))
                LazyRow(
                    contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = Spacing.S4.dp),
                    horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp),
                ) {
                    items(rows, key = { on.key + "|" + it.id }) { ep ->
                        val series = state.value.series[ep.seriesKey] ?: SeriesRow(ep.seriesKey, ep.seriesName, ep.seriesGenre, null, null, 0)
                        EpisodeRailTile(
                            ep, series, nameHeight,
                            onOpen = { onOpenEpisode(ep.id) },
                            onPlay = { container.playback.play(ep) },
                        )
                    }
                }
            }
        }
    }
}

/** An episode as a show tile with Play on the window's corner: the series' window and name, the title and length. */
@Composable
private fun EpisodeRailTile(ep: EpisodeRow, series: SeriesRow, nameHeight: Dp, onOpen: () -> Unit, onPlay: () -> Unit) {
    val window = innerWidth(RailTileWidth)
    Box {
        ShowTile(
            series, onOpen = onOpen, width = RailTileWidth, nameHeight = nameHeight,
            facts = listOfNotNull(episodeTitle(ep), formatLength(ep.lengthSeconds)),
            openLabel = "Open episode",
        )
        IconButton(
            onClick = onPlay,
            modifier = Modifier
                .align(Alignment.TopStart)
                .padding(start = 6.dp + window - 48.dp - 4.dp, top = 6.dp + window - 48.dp - 4.dp)
                .size(48.dp)
                .tvFocusMark(),
        ) {
            Box(Modifier.size(36.dp).clip(CircleShape).background(OnAir.colors.play), contentAlignment = Alignment.Center) {
                Icon(
                    Icons.Filled.PlayArrow,
                    contentDescription = "Play ${episodeTitle(ep)}, ${series.name}",
                    tint = OnAir.colors.onPlay,
                )
            }
        }
    }
}

/**
 * The play library's rows for a section that tells loading from none (contract §4.1): the published index, else
 * the copy this device kept, else the bundled plays.
 */
@Composable
fun rememberPlayRows(): PlayLibraryFeed.Rows {
    val plays = LocalAppContainer.current.plays
    val rows by plays.rows.collectAsState()
    LaunchedEffect(Unit) { plays.loadRows() }
    return rows
}

/**
 * Today's play (Decision 075): `todaysPlay` of the day, as the head board with its cast window,
 * then "Record this", "Parts" and Read on one row. Absent with no plays; a library that failed reads as a
 * problem line with Try again.
 */
@Composable
fun TodaysPlayBoard(
    play: PlayListing,
    onOpenScript: (String) -> Unit,
    onOpenProduction: (String) -> Unit,
    onRead: (String) -> Unit = {},
) {
    Column {
        PlayHeadBoard(
            play,
            kicker = "Today\u2019s play",
            modifier = Modifier.clickable(onClickLabel = "Open play") { onOpenScript(play.id) },
        )
        ActionRow(Modifier.padding(horizontal = Spacing.S4.dp, vertical = Spacing.S3.dp)) { fit ->
            StartEarDramaButton(play, onOpenProduction)
            OutlinedButton(onClick = { onOpenScript(play.id) }, modifier = Modifier.tvFocusMark()) { Text("Parts") }
            if (!LocalIsTelevision.current) {
                FoldButton(Icons.Outlined.MenuBook, "Read", fit.folded, { onRead(play.id) }, description = "Read ${play.title}")
            }
        }
    }
}

/** The day's play from the library, or why there is none: [Ready] null means absent. */
@Composable
fun TodaysPlay(
    onOpenScript: (String) -> Unit,
    onOpenProduction: (String) -> Unit,
    onRead: (String) -> Unit = {},
    heading: (@Composable () -> Unit)? = null,
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
            val play = remember(state) { PlayScript.todaysPlay(state.rows, RadioClock.localDate()) }
            if (play != null) {
                heading?.invoke()
                TodaysPlayBoard(play, onOpenScript, onOpenProduction, onRead)
            }
        }
    }
}

/**
 * Open parts (WEB-DESIGN §4.2 item 7, owner 2026-11-14): shared productions someone else directs that this signed-in
 * person belongs to, each with a speaking part still open, at most five. A person's own productions are Record's Yours,
 * never here.
 */
@Composable
fun OpenPartsRows(onOpenProduction: (String) -> Unit) {
    val container = LocalAppContainer.current
    val account by container.accounts.account.collectAsState()
    val open by produceState(emptyList<SharedPlays.OpenPart>(), account?.userId) {
        value = if (account == null) emptyList() else runCatching { container.sharing.openParts() }.getOrDefault(emptyList())
    }
    if (open.isEmpty()) return
    SectionHeader("Open parts")
    open.forEach { p -> RemoteProductionRow(p.row, onOpenProduction, detail = if (p.open == 1) "1 open part" else "${p.open} open parts") }
}
