package com.example.appname.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.appname.data.DisplayVocabulary
import com.example.appname.data.SeriesRow
import com.example.appname.navigation.SiteLinks
import com.example.appname.ui.ActionRow
import com.example.appname.ui.ClaimTvFocus
import com.example.appname.ui.EmptyMessage
import com.example.appname.ui.EpisodeListItem
import com.example.appname.ui.Haptic
import com.example.appname.ui.HeadBoard
import com.example.appname.ui.Loadable
import com.example.appname.ui.LoadableContent
import com.example.appname.ui.LocalAppContainer
import com.example.appname.ui.PictureCredit
import com.example.appname.ui.SeriesDownloadAction
import com.example.appname.ui.ShareButton
import com.example.appname.ui.episodeCount
import com.example.appname.ui.headSlot
import com.example.appname.ui.rememberCatalogQuery
import com.example.appname.ui.rememberHaptics
import com.example.appname.ui.seasonLabel
import com.example.appname.ui.seriesYears
import com.example.appname.ui.theme.Spacing
import com.example.appname.ui.tvFocusMark
import kotlinx.coroutines.launch

/**
 * A series page (§4.3, R11d): the head board, one button row (Follow, Share), the picture's credit
 * when its license asks, its broadcast seasons as a segmented scope (not a push), episodes oldest
 * first (R1).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SeriesScreen(key: String, onBack: () -> Unit, onOpenEpisode: (String) -> Unit) {
    val container = LocalAppContainer.current
    val haptics = rememberHaptics()
    val page by rememberCatalogQuery(key) { db -> db.seriesPage(key) }
    // A season is chosen by the listener; until then the oldest is shown.
    var picked by rememberSaveable(key) { mutableStateOf<String?>(null) }
    var pickedAny by rememberSaveable(key) { mutableStateOf(false) }
    val ready = (page as? Loadable.Ready)?.value
    // A key a later catalog moved opens the series it now is (contract §3.5); its key is the one stored.
    val seriesKey = ready?.series?.key ?: key
    val season = if (pickedAny) picked else ready?.seasons?.firstOrNull()?.season
    val episodes by rememberCatalogQuery(seriesKey, season, ready != null) { db ->
        if (ready == null) emptyList() else db.seasonEpisodes(seriesKey, season)
    }
    val following by rememberCatalogQuery(seriesKey, watchUser = true) { container.user.isFollowing(seriesKey) }
    // Every episode id of the run, for the Download action (§4.3).
    val allIds by rememberCatalogQuery(seriesKey, ready != null) { db ->
        ready?.seasons?.flatMap { s -> db.seasonEpisodes(seriesKey, s.season).map { it.id } }.orEmpty()
    }
    val scope = rememberCoroutineScope()
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(ready?.series?.name ?: "", maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    if (ready != null) {
                        val seasonIds = (episodes as? Loadable.Ready)?.value?.map { it.id }
                        SeriesDownloadAction(
                            seriesKey = seriesKey,
                            allIds = (allIds as? Loadable.Ready)?.value.orEmpty(),
                            season = season,
                            seasonIds = seasonIds.takeIf { ready.seasons.size > 1 },
                        )
                    }
                },
            )
        },
    ) { padding ->
        LoadableContent(page, Modifier.padding(padding)) { seriesPage ->
            if (seriesPage == null) {
                EmptyMessage("This series is not in the catalog.", Modifier.padding(padding))
                return@LoadableContent
            }
            // On a TV the D-pad starts on the first episode (§9.2); Follow and the seasons are above it.
            val firstRow = remember { FocusRequester() }
            val rows = (episodes as? Loadable.Ready)?.value.orEmpty()
            ClaimTvFocus(firstRow, rows.firstOrNull()?.id)
            val series = seriesPage.series
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
                LazyColumn(Modifier.widthIn(max = 720.dp).fillMaxSize(), contentPadding = padding) {
                    // §4.3: the web's Follow and Following; the store is the one sync carries (§2.3).
                    val on = (following as? Loadable.Ready)?.value == true
                    seriesHead(series, on) {
                        haptics(Haptic.Selection)
                        scope.launch { container.user.setFollowing(seriesKey, !on) }
                    }
                    if (seriesPage.seasons.size > 1) {
                        item(key = "seasons") {
                            LazyRow(
                                contentPadding = PaddingValues(horizontal = Spacing.S4.dp),
                                horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp),
                            ) {
                                items(seriesPage.seasons, key = { it.season ?: "\u0000undated" }) { s ->
                                    FilterChip(
                                        selected = s.season == season,
                                        onClick = {
                                            if (s.season != season) haptics(Haptic.Selection)
                                            picked = s.season
                                            pickedAny = true
                                        },
                                        label = { Text(seasonLabel(s.season)) },
                                        modifier = Modifier.tvFocusMark(),
                                    )
                                }
                            }
                        }
                    }
                    items(rows, key = { it.id }) { row ->
                        EpisodeListItem(
                            row,
                            showSeries = false,
                            onOpen = { onOpenEpisode(row.id) },
                            onPlay = { container.playback.play(row) },
                            modifier = if (row.id == rows.first().id) Modifier.focusRequester(firstRow) else Modifier,
                        )
                    }
                }
            }
        }
    }
}

/** The series page down to the picture's credit: the head board, then the one button row. */
fun LazyListScope.seriesHead(series: SeriesRow, following: Boolean, toggle: () -> Unit) {
    item(key = "head") {
        HeadBoard(
            name = series.name,
            genre = series.genre,
            art = series.windowArt,
            kicker = (listOfNotNull(series.genre?.let { DisplayVocabulary.genreName(it) }) + series.networks)
                .joinToString(" · ").ifEmpty { null },
            facts = listOf(seriesYears(series) ?: "Undated", episodeCount(series.episodes)),
            first = series.firstDate,
            last = series.lastDate,
        )
    }
    item(key = "follow") {
        ActionRow(Modifier.padding(horizontal = Spacing.S4.dp, vertical = Spacing.S3.dp)) { fit ->
            val grow = Modifier.weight(1f).tvFocusMark()
            if (following) {
                FilledTonalButton(onClick = toggle, modifier = grow) {
                    Icon(Icons.Filled.Check, contentDescription = null)
                    Text("Following", Modifier.padding(start = Spacing.S2.dp), maxLines = 1)
                }
            } else {
                OutlinedButton(onClick = toggle, modifier = grow) {
                    Icon(Icons.Filled.Add, contentDescription = null)
                    Text("Follow", Modifier.padding(start = Spacing.S2.dp), maxLines = 1)
                }
            }
            ShareButton(series.name, SiteLinks.series(series.key), fit.folded)
        }
    }
    item(key = "credit") {
        PictureCredit(listOf(series.windowArt), headSlot(), Modifier.padding(horizontal = Spacing.S4.dp))
    }
}
