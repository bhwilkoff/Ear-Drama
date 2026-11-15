package com.example.appname.ui.screens

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Shuffle
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.unit.dp
import androidx.compose.ui.focus.focusRequester
import com.example.appname.plays.FinishedList
import com.example.appname.data.EpisodeRow
import com.example.appname.data.SeriesRow
import com.example.appname.data.dayYears
import com.example.appname.data.nightShows
import com.example.appname.ui.ClaimTvFocus
import com.example.appname.ui.DayBoard
import com.example.appname.ui.EpisodeListItem
import com.example.appname.ui.Loadable
import com.example.appname.ui.LocalAppContainer
import com.example.appname.ui.LocalIsTelevision
import com.example.appname.ui.SectionHeader
import com.example.appname.ui.SectionHeading
import com.example.appname.ui.TextLink
import com.example.appname.ui.TileGrid
import com.example.appname.ui.TileSpec
import com.example.appname.ui.VoicesShelf
import com.example.appname.ui.episodeTitle
import com.example.appname.ui.formatCount
import com.example.appname.ui.formatLength
import com.example.appname.ui.rememberCatalogQuery
import com.example.appname.ui.theme.Spacing
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale

/** Every broadcast that aired on today's month and day, and the series each belongs to. */
private data class DayData(val rows: List<EpisodeRow>, val series: Map<String, SeriesRow>)

private const val NIGHT_FIRST = 6
private const val TOP = 12

/**
 * Home (Decision 075, ANDROID-DESIGN §4.1): On the air with Listen live, Continue (only with
 * history), the three doors, Start a show, By length, Record a play (not on a TV), This day in
 * radio, Most heard voices, and Made here. Every row is filled by one published rule and has its
 * own states; a row whose rule yields nothing is not drawn. The top bar's one action opens Surprise.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ListenScreen(
    onOpenEpisode: (String) -> Unit,
    onOpenSeries: (String) -> Unit,
    onSurprise: () -> Unit,
    onBrowse: () -> Unit,
    onOpenStations: () -> Unit,
    onOpenRecord: () -> Unit,
    onOpenScript: (String) -> Unit,
    onOpenProduction: (String) -> Unit,
    onRead: (String) -> Unit = {},
    onOpenDrama: (String) -> Unit = {},
    onDramas: () -> Unit = onBrowse,
    onOpenPerson: (String) -> Unit = {},
    onVoices: () -> Unit = onBrowse,
    onOpenStudio: OpenStudio = { _, _, _, _ -> },
) {
    val container = LocalAppContainer.current
    val television = LocalIsTelevision.current
    // Made here leads, under the doors, while there are one to five finished ear dramas (Decision 079).
    val finished by container.finished.state.collectAsState()
    LaunchedEffect(television) { if (!television) container.finished.load() }
    val madeLeads = !television && ((finished as? FinishedList.State.Ready)?.plays?.size ?: 0) in 1..MADE_HERE_LEADS
    val today = remember { LocalDate.now().format(DateTimeFormatter.ofPattern("MM-dd")) }
    val dateLabel = remember { LocalDate.now().format(DateTimeFormatter.ofPattern("MMMM d", Locale.US)) }
    // Continue re-runs on every saved position; the rest only on a catalog swap.
    val continuing by rememberCatalogQuery(watchUser = true, memo = "home.continue") { db ->
        db.episodes(container.user.inProgress().map { it.episodeId }).distinctBy { it.id }
    }
    val day by rememberCatalogQuery(today, memo = "home.day") { db ->
        val rows = db.dayRows(today)
        DayData(rows, rows.map { it.seriesKey }.distinct().mapNotNull { k -> db.series(k)?.let { k to it } }.toMap())
    }
    val shelves by rememberCatalogQuery(memo = "home.shelves") { db -> db.homeShelves() }
    val voices by rememberCatalogQuery(memo = "home.voices") { db -> db.voices(TOP) }
    var picked by rememberSaveable(today) { mutableStateOf<Int?>(null) }
    var allNight by rememberSaveable(today, picked) { mutableStateOf(false) }
    val cont = (continuing as? Loadable.Ready)?.value.orEmpty()
    val dayData = (day as? Loadable.Ready)?.value
    val years = remember(dayData) {
        dayData?.let { d -> dayYears(d.rows, { it.airDate }, { d.series[it.seriesKey]?.genre ?: it.seriesGenre }) }
    }
    val year = picked ?: years?.peak
    val night = remember(dayData, year) {
        dayData?.let { d ->
            nightShows(
                d.rows.filter { year != null && it.airDate?.startsWith("$year") == true },
                { it.title },
                { d.series[it.seriesKey]?.episodes },
            )
        }
    }
    // On a TV the D-pad starts on Listen live, else on the first Continue row.
    val liveFocus = remember { FocusRequester() }
    val firstRow = remember { FocusRequester() }
    var liveShown by remember { mutableStateOf<Boolean?>(null) }
    if (liveShown == true) ClaimTvFocus(liveFocus, true)
    else if (liveShown == false && cont.isNotEmpty()) ClaimTvFocus(firstRow, cont.first().id)
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Ear Drama") },
                actions = {
                    IconButton(onClick = onSurprise) { Icon(Icons.Filled.Shuffle, contentDescription = "Surprise") }
                },
            )
        },
    ) { padding ->
        LazyColumn(Modifier.fillMaxSize(), contentPadding = padding) {
            item(key = "live") { OnAirBlock(onOpenStations, onOpenEpisode, liveFocus, onSettled = { liveShown = it }) }
            if (cont.isNotEmpty()) {
                item(key = "cont-h") { SectionHeader("Continue") }
                // R11b: episodes are rows (the series' window, the date, the length, Play).
                items(cont, key = { "c|" + it.id }) { row ->
                    EpisodeListItem(
                        row,
                        showSeries = true,
                        onOpen = { onOpenEpisode(row.id) },
                        onPlay = { container.playback.play(row) },
                        modifier = if (row.id == cont.first().id) Modifier.focusRequester(firstRow) else Modifier,
                    )
                }
            }
            item(key = "doors") { HomeDoors(onListen = onOpenStations, onFind = onBrowse, onRecord = onOpenRecord) }
            if (madeLeads) item(key = "made") { NewEarDramas(onOpen = onOpenDrama, onAll = onDramas) }
            val published = (shelves as? Loadable.Ready)?.value
            if (published == null) {
                if (shelves is Loadable.Loading) item(key = "start-wait") { RowSpinner() }
            } else {
                item(key = "start") { ChipShelfRow("Start a show", published.start, onOpenEpisode, onOpenSeries) }
            }
            if (!television) {
                item(key = "record") { RecordAPlayHome(onOpenScript, onOpenProduction, onRead, onOpenStudio) }
            }
            if (published != null) {
                item(key = "length") { ChipShelfRow("By length", published.length, onOpenEpisode, onOpenSeries) }
            }
            if (year != null && years != null && night != null && dayData != null) {
                item(key = "day") {
                    Box(Modifier.padding(top = Spacing.S2.dp)) {
                        DayBoard(dateLabel, years, year, onSelect = { picked = it })
                    }
                }
                item(key = "night-h") {
                    SectionHeading("$dateLabel, $year") {
                        if (night.singles > 0) {
                            Text(
                                "${formatCount(night.singles)} single recordings",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                maxLines = 1,
                            )
                        }
                    }
                }
                item(key = "night") {
                    val shown = if (allNight) night.shows else night.shows.take(NIGHT_FIRST)
                    TileGrid(
                        shown.map { r ->
                            TileSpec(
                                "n:" + r.id,
                                dayData.series[r.seriesKey]
                                    ?: SeriesRow(r.seriesKey, r.seriesName, r.seriesGenre, null, null, 0),
                                facts = listOfNotNull(episodeTitle(r), formatLength(r.lengthSeconds)),
                                openLabel = "Open episode",
                                onOpen = { onOpenEpisode(r.id) },
                            )
                        },
                    )
                }
                if (!allNight && night.shows.size > NIGHT_FIRST) {
                    item(key = "night-more") {
                        TextLink(
                            "All ${formatCount(night.shows.size)} shows that night",
                            onClick = { allNight = true },
                            modifier = Modifier.padding(horizontal = Spacing.S4.dp),
                        )
                    }
                }
            }
            val heard = (voices as? Loadable.Ready)?.value.orEmpty()
            if (heard.isNotEmpty()) {
                item(key = "voices-h") {
                    SectionHeading("Most heard voices") { TextLink("All voices", onClick = onVoices) }
                }
                item(key = "voices") { VoicesShelf(heard, onOpenPerson) }
            }
            if (!madeLeads) item(key = "made") { NewEarDramas(onOpen = onOpenDrama, onAll = onDramas) }
        }
    }
}

private const val MADE_HERE_LEADS = 5

/** Record a play on Home: today's scene with Try a line, Hear it and Read, then this person's open parts. */
@Composable
private fun RecordAPlayHome(onOpenScript: (String) -> Unit, onOpenProduction: (String) -> Unit, onRead: (String) -> Unit, onOpenStudio: OpenStudio) {
    androidx.compose.foundation.layout.Column {
        TodaysScene(onOpenScript, onRead, onOpenStudio, heading = { SectionHeader("Record a play") })
        OpenPartsRows(onOpenProduction)
    }
}
