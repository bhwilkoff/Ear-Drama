package com.example.appname.ui.screens

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Shuffle
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.appname.data.EpisodeRow
import com.example.appname.data.DisplayVocabulary
import com.example.appname.ui.ClaimTvFocus
import com.example.appname.ui.EmptyMessage
import com.example.appname.ui.Loadable
import com.example.appname.ui.LoadableContent
import com.example.appname.ui.LocalAppContainer
import com.example.appname.ui.SectionHeader
import com.example.appname.ui.episodeTitle
import com.example.appname.ui.formatAirDate
import com.example.appname.ui.rememberCatalogQuery
import com.example.appname.ui.tvFocusMark
import com.example.appname.ui.theme.Spacing
import java.time.LocalDate
import java.time.format.DateTimeFormatter

private data class Shelf(val key: String, val title: String, val rows: List<EpisodeRow>)

/**
 * Home (was Listen): Continue listening, then shelves by rule from data (each
 * applies `recommendAnd`). The top bar's one action opens Surprise (§3.1).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ListenScreen(onOpenEpisode: (String) -> Unit, onSurprise: () -> Unit) {
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
            val list = (listOfNotNull(first) + rules).filter { it.rows.isNotEmpty() }
            if (list.isEmpty()) {
                EmptyMessage("Nothing to list yet.", Modifier.padding(padding))
            } else {
                // On a TV the D-pad starts on the first row's first card.
                val firstCard = remember { FocusRequester() }
                val firstKey = list.first().let { it.key to it.rows.first().id }
                ClaimTvFocus(firstCard, firstKey)
                LazyColumn(Modifier.fillMaxSize(), contentPadding = padding) {
                    items(list, key = { it.key }) { shelf ->
                        SectionHeader(shelf.title)
                        LazyRow(contentPadding = PaddingValues(horizontal = Spacing.S4.dp)) {
                            items(shelf.rows, key = { it.id }) { row ->
                                EpisodeCard(
                                    row,
                                    onOpen = { onOpenEpisode(row.id) },
                                    modifier = if (shelf.key to row.id == firstKey) {
                                        Modifier.focusRequester(firstCard)
                                    } else {
                                        Modifier
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

/** A typographic card (R11): date, title, series. No art is invented. */
@Composable
private fun EpisodeCard(row: EpisodeRow, onOpen: () -> Unit, modifier: Modifier = Modifier) {
    OutlinedCard(
        onClick = onOpen,
        modifier = Modifier.padding(end = Spacing.S3.dp).width(220.dp).tvFocusMark().then(modifier),
    ) {
        Column(Modifier.padding(Spacing.S3.dp)) {
            formatAirDate(row.airDate)?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Text(
                episodeTitle(row),
                style = MaterialTheme.typography.titleMedium,
                maxLines = 2,
                minLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                row.seriesName,
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}
