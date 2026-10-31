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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.unit.dp
import com.example.appname.data.BrowseFilter
import com.example.appname.data.EpisodeRow
import com.example.appname.data.SeriesRow
import com.example.appname.data.SeriesSort
import com.example.appname.data.dayYears
import com.example.appname.data.nightShows
import com.example.appname.data.resolveFollowing
import com.example.appname.ui.ClaimTvFocus
import com.example.appname.ui.DayBoard
import com.example.appname.ui.EmptyMessage
import com.example.appname.ui.EpisodeListItem
import com.example.appname.ui.Loadable
import com.example.appname.ui.LoadableContent
import com.example.appname.ui.LocalAppContainer
import com.example.appname.ui.SectionHeader
import com.example.appname.ui.SectionHeading
import com.example.appname.ui.ShowShelf
import com.example.appname.ui.TextLink
import com.example.appname.ui.VoicesShelf
import com.example.appname.ui.TileGrid
import com.example.appname.ui.TileSpec
import com.example.appname.ui.episodeTitle
import com.example.appname.ui.formatCount
import com.example.appname.ui.formatLength
import com.example.appname.ui.rememberCatalogQuery
import com.example.appname.ui.theme.Spacing
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale

private data class Shelf(
    val key: String,
    val title: String,
    val rows: List<EpisodeRow>,
    val series: List<SeriesRow> = emptyList(),
) {
    val isEmpty get() = rows.isEmpty() && series.isEmpty()
    val firstCardId get() = rows.firstOrNull()?.id ?: series.firstOrNull()?.let { "s:" + it.key }
}

/** Every broadcast that aired on today's month and day, and the series each belongs to. */
private data class DayData(val rows: List<EpisodeRow>, val series: Map<String, SeriesRow>)

/** Most downloaded: the first shows by downloads, and how many shows there are. */
private data class TopShows(val shows: List<SeriesRow>, val total: Int)

private const val NIGHT_FIRST = 6
private const val TOP = 12

/**
 * Home (was Listen): Continue listening, Following (the series the listener follows, newest follow
 * first, drawn only with rows), then the day board, the night of the selected year, and Most
 * downloaded (R11c; the old episode shelves are replaced). The top bar's one action opens Surprise (§3.1).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ListenScreen(
    onOpenEpisode: (String) -> Unit,
    onOpenSeries: (String) -> Unit,
    onSurprise: () -> Unit,
    onBrowse: () -> Unit,
    onOpenDrama: (String) -> Unit = {},
    onDramas: () -> Unit = onBrowse,
    onOpenPerson: (String) -> Unit = {},
    onVoices: () -> Unit = onBrowse,
) {
    val container = LocalAppContainer.current
    val today = remember { LocalDate.now().format(DateTimeFormatter.ofPattern("MM-dd")) }
    val dateLabel = remember { LocalDate.now().format(DateTimeFormatter.ofPattern("MMMM d", Locale.US)) }
    // Continue re-runs on every saved position; the rest only on a catalog swap.
    val continuing by rememberCatalogQuery(watchUser = true) { db ->
        Shelf(
            "continue",
            "Continue listening",
            db.episodes(container.user.inProgress().map { it.episodeId }).distinctBy { it.id },
        )
    }
    val following by rememberCatalogQuery(watchUser = true) { db ->
        Shelf("following", "Following", emptyList(), resolveFollowing(container.user.followed()) { db.series(it) })
    }
    val day by rememberCatalogQuery(today) { db ->
        val rows = db.dayRows(today)
        DayData(rows, rows.map { it.seriesKey }.distinct().mapNotNull { k -> db.series(k)?.let { k to it } }.toMap())
    }
    val top by rememberCatalogQuery { db ->
        TopShows(
            db.seriesBrowse(BrowseFilter(sort = SeriesSort.Popular, showLine = true), limit = TOP),
            db.seriesCounts(BrowseFilter()).first,
        )
    }
    val voices by rememberCatalogQuery { db -> db.voices(TOP) }
    var picked by rememberSaveable(today) { mutableStateOf<Int?>(null) }
    var allNight by rememberSaveable(today, picked) { mutableStateOf(false) }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Home") },
                actions = {
                    IconButton(onClick = onSurprise) { Icon(Icons.Filled.Shuffle, contentDescription = "Surprise") }
                },
            )
        },
    ) { padding ->
        LoadableContent(day, Modifier.padding(padding)) { dayData ->
            val first = (continuing as? Loadable.Ready)?.value
            val followed = (following as? Loadable.Ready)?.value
            val list = listOfNotNull(first, followed).filter { !it.isEmpty }
            val topShows = (top as? Loadable.Ready)?.value
            val years = remember(dayData) {
                dayYears(dayData.rows, { it.airDate }, { dayData.series[it.seriesKey]?.genre ?: it.seriesGenre })
            }
            val year = picked ?: years.peak
            val night = remember(dayData, year) {
                nightShows(
                    dayData.rows.filter { year != null && it.airDate?.startsWith("$year") == true },
                    { it.title },
                    { dayData.series[it.seriesKey]?.episodes },
                )
            }
            if (list.isEmpty() && year == null && topShows?.shows.isNullOrEmpty()) {
                EmptyMessage("Nothing to list yet.", Modifier.padding(padding))
            } else {
                // On a TV the D-pad starts on the first row's first card.
                val firstCard = remember { FocusRequester() }
                val firstKey = list.firstOrNull()?.let { it.key to it.firstCardId }
                if (firstKey != null) ClaimTvFocus(firstCard, firstKey)
                LazyColumn(Modifier.fillMaxSize(), contentPadding = padding) {
                    list.forEach { shelf ->
                        item(key = "h:" + shelf.key) { SectionHeader(shelf.title) }
                        // R11b: episodes are rows (the series' window, the date, the length, Play); series are tiles.
                        items(shelf.rows, key = { shelf.key + "|" + it.id }) { row ->
                            EpisodeListItem(
                                row,
                                showSeries = true,
                                onOpen = { onOpenEpisode(row.id) },
                                onPlay = { container.playback.play(row) },
                                modifier = if (shelf.key to row.id == firstKey) Modifier.focusRequester(firstCard) else Modifier,
                            )
                        }
                        if (shelf.series.isNotEmpty()) {
                            item(key = "s:" + shelf.key) {
                                ShowShelf(
                                    shelf.series,
                                    onOpen = { onOpenSeries(it.key) },
                                    tileModifier = { row ->
                                        if (shelf.key to "s:" + row.key == firstKey) Modifier.focusRequester(firstCard) else Modifier
                                    },
                                )
                            }
                        }
                    }
                    if (year != null) {
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
                            SectionHeading("Most heard voices") { TextLink("All", onClick = onVoices) }
                        }
                        item(key = "voices") { VoicesShelf(heard, onOpenPerson) }
                    }
                    item(key = "new-dramas") { NewEarDramas(onOpen = onOpenDrama, onAll = onDramas) }
                    if (topShows != null && topShows.shows.isNotEmpty()) {
                        item(key = "top-h") {
                            SectionHeading("Most downloaded") {
                                TextLink("All ${formatCount(topShows.total)} shows", onClick = onBrowse)
                            }
                        }
                        item(key = "top") {
                            TileGrid(topShows.shows.map { s -> TileSpec("t:" + s.key, s, onOpen = { onOpenSeries(s.key) }) })
                        }
                    }
                }
            }
        }
    }
}
