package com.example.appname.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
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
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.appname.navigation.SiteLinks
import com.example.appname.ui.ClaimTvFocus
import com.example.appname.ui.SeriesDownloadAction
import com.example.appname.ui.ShareAction
import com.example.appname.ui.tvFocusMark
import kotlinx.coroutines.launch
import com.example.appname.ui.EmptyMessage
import com.example.appname.ui.Haptic
import com.example.appname.ui.rememberHaptics
import com.example.appname.ui.LoadableContent
import com.example.appname.ui.LocalAppContainer
import com.example.appname.ui.Loadable
import com.example.appname.ui.EpisodeListItem
import com.example.appname.ui.Meta
import com.example.appname.ui.rememberCatalogQuery
import com.example.appname.ui.seasonLabel
import com.example.appname.ui.seriesYears
import com.example.appname.ui.FaceFigure
import androidx.compose.foundation.layout.Box
import com.example.appname.ui.theme.Spacing

/** A series page (§4.3): Follow and Share, its broadcast seasons as a segmented scope (not a push), episodes oldest first (R1). */
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
    val season = if (pickedAny) picked else ready?.seasons?.firstOrNull()?.season
    val episodes by rememberCatalogQuery(key, season, ready != null) { db ->
        if (ready == null) emptyList() else db.seasonEpisodes(key, season)
    }
    val following by rememberCatalogQuery(key, watchUser = true) { container.user.isFollowing(key) }
    // Every episode id of the run, for the Download action (§4.3).
    val allIds by rememberCatalogQuery(key, ready != null) { db ->
        ready?.seasons?.flatMap { s -> db.seasonEpisodes(key, s.season).map { it.id } }.orEmpty()
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
                            seriesKey = key,
                            allIds = (allIds as? Loadable.Ready)?.value.orEmpty(),
                            season = season,
                            seasonIds = seasonIds.takeIf { ready.seasons.size > 1 },
                        )
                    }
                    ready?.series?.let { ShareAction(it.name, SiteLinks.series(it.key)) }
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
            LazyColumn(Modifier.fillMaxSize(), contentPadding = padding) {
                seriesPage.series.face?.let { face ->
                    item(key = "face") { Box(Modifier.padding(start = Spacing.S4.dp, top = Spacing.S2.dp)) { FaceFigure(face) } }
                }
                item(key = "meta") {
                    val years = seriesYears(seriesPage.series)
                    Meta(
                        listOfNotNull(years, "${seriesPage.series.episodes} episodes").joinToString(" · "),
                        Modifier.padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp),
                    )
                }
                item(key = "follow") {
                    // §4.3: the web's Follow and Following; the store is the one sync carries (§2.3).
                    val on = (following as? Loadable.Ready)?.value == true
                    val toggle: () -> Unit = { scope.launch { container.user.setFollowing(key, !on) } }
                    val modifier = Modifier.padding(horizontal = Spacing.S4.dp).tvFocusMark()
                    if (on) {
                        FilledTonalButton(onClick = toggle, modifier = modifier) {
                            Icon(Icons.Filled.Check, contentDescription = null)
                            Text("Following", Modifier.padding(start = Spacing.S2.dp))
                        }
                    } else {
                        OutlinedButton(onClick = toggle, modifier = modifier) {
                            Icon(Icons.Filled.Add, contentDescription = null)
                            Text("Follow", Modifier.padding(start = Spacing.S2.dp))
                        }
                    }
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
