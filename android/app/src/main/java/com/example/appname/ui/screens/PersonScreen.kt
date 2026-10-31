package com.example.appname.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
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
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.appname.ui.ClaimTvFocus
import com.example.appname.ui.EmptyMessage
import com.example.appname.ui.EpisodeListItem
import com.example.appname.data.PersonShows
import com.example.appname.ui.HeadBoard
import com.example.appname.ui.ShowTile
import com.example.appname.ui.TILE_WIDTH_DP
import com.example.appname.ui.innerWidth
import com.example.appname.ui.rememberNameHeight
import com.example.appname.ui.seriesYears
import com.example.appname.ui.Haptic
import com.example.appname.ui.Loadable
import com.example.appname.ui.LoadableContent
import com.example.appname.ui.LocalAppContainer
import com.example.appname.ui.SectionHeader
import com.example.appname.ui.episodeCount
import com.example.appname.ui.rememberCatalogQuery
import com.example.appname.ui.rememberHaptics
import com.example.appname.ui.tvFocusMark
import com.example.appname.ui.theme.Spacing

/**
 * A person's page (`withPerson`, ANDROID-DESIGN §4.15): the portrait when one is
 * served, the years and episode count from the data, a segmented Oldest or
 * Newest first, then every served episode crediting them, by series, each row
 * naming the roles. No bio is written.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PersonScreen(id: String, onBack: () -> Unit, onOpenEpisode: (String) -> Unit, onOpenSeries: (String) -> Unit = {}) {
    val container = LocalAppContainer.current
    val haptics = rememberHaptics()
    val page by rememberCatalogQuery(id) { db -> db.personPage(id) }
    var newestFirst by rememberSaveable(id) { mutableStateOf(false) }
    val ready = (page as? Loadable.Ready)?.value
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(ready?.person?.name ?: "", maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { padding ->
        LoadableContent(page, Modifier.padding(padding)) { personPage ->
            if (personPage == null) {
                EmptyMessage("This person is not in the catalog.", Modifier.padding(padding))
                return@LoadableContent
            }
            val groups = remember(personPage, newestFirst) { personPage.groups(newestFirst) }
            val showsLoad by rememberCatalogQuery(personPage.person.id, groups.size) { db ->
                groups.mapNotNull { g -> db.series(g.seriesKey)?.let { g.seriesKey to it } }.toMap()
            }
            val shows = (showsLoad as? Loadable.Ready)?.value ?: emptyMap()
            // On a TV the D-pad starts on the first episode (§9.2).
            val firstRow = remember { FocusRequester() }
            val firstId = groups.firstOrNull()?.episodes?.firstOrNull()?.episode?.id
            ClaimTvFocus(firstRow, firstId)
            LazyColumn(Modifier.fillMaxSize(), contentPadding = padding) {
                item(key = "head") {
                    HeadBoard(
                        name = personPage.person.name, genre = null, art = personPage.person.art, kicker = null,
                        facts = listOf(
                            personPage.person.years, episodeCount(personPage.episodes.size),
                            if (groups.size > 1) "${groups.size} shows" else null,
                        ),
                        first = PersonShows.first(personPage.episodes), last = PersonShows.last(personPage.episodes),
                        years = PersonShows.yearCounts(personPage.episodes),
                    )
                }
                if (groups.size > 1) {
                    item(key = "shows") {
                        val tiles = remember(groups, shows) {
                            groups.map { PersonShows.tile(shows[it.seriesKey], it.seriesKey, it.seriesName, it.episodes) }
                        }
                        val nameHeight = rememberNameHeight(tiles.map { it.name }, innerWidth(TILE_WIDTH_DP.dp))
                        LazyRow(
                            contentPadding = PaddingValues(horizontal = Spacing.S4.dp, vertical = Spacing.S3.dp),
                            horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp),
                        ) {
                            items(tiles, key = { "s:" + it.key }) { tile ->
                                ShowTile(
                                    tile, onOpen = { onOpenSeries(tile.key) }, nameHeight = nameHeight,
                                    facts = listOf(seriesYears(tile) ?: "Undated", episodeCount(tile.episodes)),
                                )
                            }
                        }
                    }
                }
                if (personPage.episodes.size > 1) {
                    item(key = "order") {
                        SingleChoiceSegmentedButtonRow(Modifier.padding(horizontal = Spacing.S4.dp)) {
                            listOf(false to "Oldest first", true to "Newest first").forEachIndexed { i, (value, label) ->
                                SegmentedButton(
                                    selected = newestFirst == value,
                                    onClick = {
                                        if (newestFirst != value) haptics(Haptic.Selection)
                                        newestFirst = value
                                    },
                                    shape = SegmentedButtonDefaults.itemShape(i, 2),
                                    modifier = Modifier.tvFocusMark(),
                                ) { Text(label) }
                            }
                        }
                    }
                }
                groups.forEach { group ->
                    item(key = "h:" + group.seriesKey) { SectionHeader(group.seriesName) }
                    items(group.episodes, key = { "e:" + it.episode.id }) { item ->
                        EpisodeListItem(
                            item.episode,
                            showSeries = false,
                            onOpen = { onOpenEpisode(item.episode.id) },
                            onPlay = { container.playback.play(item.episode) },
                            supporting = item.rolesLine,
                            modifier = if (item.episode.id == firstId) Modifier.focusRequester(firstRow) else Modifier,
                        )
                    }
                }
            }
        }
    }
}
