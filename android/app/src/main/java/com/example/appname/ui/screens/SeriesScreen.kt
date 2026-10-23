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
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.appname.ui.EmptyMessage
import com.example.appname.ui.LoadableContent
import com.example.appname.ui.LocalAppContainer
import com.example.appname.ui.Loadable
import com.example.appname.ui.EpisodeListItem
import com.example.appname.ui.Meta
import com.example.appname.ui.rememberCatalogQuery
import com.example.appname.ui.seasonLabel
import com.example.appname.ui.seriesYears
import com.example.appname.ui.theme.Spacing

/** A series page: its broadcast seasons as a segmented scope (not a push), episodes oldest first (R1). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SeriesScreen(key: String, onBack: () -> Unit, onOpenEpisode: (String) -> Unit) {
    val container = LocalAppContainer.current
    val page by rememberCatalogQuery(key) { db -> db.seriesPage(key) }
    // A season is chosen by the listener; until then the oldest is shown.
    var picked by rememberSaveable(key) { mutableStateOf<String?>(null) }
    var pickedAny by rememberSaveable(key) { mutableStateOf(false) }
    val ready = (page as? Loadable.Ready)?.value
    val season = if (pickedAny) picked else ready?.seasons?.firstOrNull()?.season
    val episodes by rememberCatalogQuery(key, season, ready != null) { db ->
        if (ready == null) emptyList() else db.seasonEpisodes(key, season)
    }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(ready?.series?.name ?: "", maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
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
            LazyColumn(Modifier.fillMaxSize(), contentPadding = padding) {
                item(key = "meta") {
                    val years = seriesYears(seriesPage.series)
                    Meta(
                        listOfNotNull(years, "${seriesPage.series.episodes} episodes").joinToString(" · "),
                        Modifier.padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp),
                    )
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
                                    onClick = { picked = s.season; pickedAny = true },
                                    label = { Text(seasonLabel(s.season)) },
                                )
                            }
                        }
                    }
                }
                val rows = (episodes as? Loadable.Ready)?.value.orEmpty()
                items(rows, key = { it.id }) { row ->
                    EpisodeListItem(
                        row,
                        showSeries = false,
                        onOpen = { onOpenEpisode(row.id) },
                        onPlay = { container.playback.play(row) },
                    )
                }
            }
        }
    }
}
