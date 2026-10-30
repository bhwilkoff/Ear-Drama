package com.example.appname.ui.screens

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Shuffle
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import com.example.appname.data.EpisodeRow
import com.example.appname.data.DisplayVocabulary
import com.example.appname.data.SeriesRow
import com.example.appname.data.resolveFollowing
import com.example.appname.ui.ClaimTvFocus
import com.example.appname.ui.EmptyMessage
import com.example.appname.ui.Loadable
import com.example.appname.ui.LoadableContent
import com.example.appname.ui.LocalAppContainer
import com.example.appname.ui.EpisodeListItem
import com.example.appname.ui.SectionHeader
import com.example.appname.ui.ShowShelf
import com.example.appname.ui.rememberCatalogQuery
import java.time.LocalDate
import java.time.format.DateTimeFormatter

private data class Shelf(
    val key: String,
    val title: String,
    val rows: List<EpisodeRow>,
    val series: List<SeriesRow> = emptyList(),
) {
    val isEmpty get() = rows.isEmpty() && series.isEmpty()
    val firstCardId get() = rows.firstOrNull()?.id ?: series.firstOrNull()?.let { "s:" + it.key }
}

/**
 * Home (was Listen): Continue listening, Following (the series the listener
 * follows, newest follow first, drawn only with rows), then shelves by rule
 * from data (each applies `recommendAnd`). The top bar's one action opens Surprise (§3.1).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ListenScreen(onOpenEpisode: (String) -> Unit, onOpenSeries: (String) -> Unit, onSurprise: () -> Unit) {
    val container = LocalAppContainer.current
    val today = remember { LocalDate.now().format(DateTimeFormatter.ofPattern("MM-dd")) }
    // Continue re-runs on every saved position; the rule shelves only on a catalog swap.
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
    // The catalog's listenShelves, in its order (contract §5.1).
    val ruled by rememberCatalogQuery(today) { db ->
        db.listenShelves(today).map { s ->
            val title = s.heading ?: s.genre?.let { DisplayVocabulary.genreName(it) ?: it } ?: "This day in radio"
            Shelf(s.key, title, s.rows)
        }
    }
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
        LoadableContent(ruled, Modifier.padding(padding)) { rules ->
            val first = (continuing as? Loadable.Ready)?.value
            val followed = (following as? Loadable.Ready)?.value
            val list = (listOfNotNull(first, followed) + rules).filter { !it.isEmpty }
            if (list.isEmpty()) {
                EmptyMessage("Nothing to list yet.", Modifier.padding(padding))
            } else {
                // On a TV the D-pad starts on the first row's first card.
                val firstCard = remember { FocusRequester() }
                val firstKey = list.first().let { it.key to it.firstCardId }
                ClaimTvFocus(firstCard, firstKey)
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
                }
            }
        }
    }
}
