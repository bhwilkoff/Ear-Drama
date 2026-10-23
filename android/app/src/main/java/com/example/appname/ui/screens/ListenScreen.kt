package com.example.appname.ui.screens

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.appname.data.EpisodeRow
import com.example.appname.data.ShelfRule
import com.example.appname.data.DisplayVocabulary
import com.example.appname.ui.EmptyMessage
import com.example.appname.ui.Loadable
import com.example.appname.ui.LoadableContent
import com.example.appname.ui.LocalAppContainer
import com.example.appname.ui.SectionHeader
import com.example.appname.ui.episodeTitle
import com.example.appname.ui.formatAirDate
import com.example.appname.ui.rememberCatalogQuery
import com.example.appname.ui.theme.Spacing
import java.time.LocalDate
import java.time.format.DateTimeFormatter

private data class Shelf(val key: String, val title: String, val rows: List<EpisodeRow>)

/** Listen: Continue listening, then shelves by rule from data (each applies `recommendAnd`). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ListenScreen(onOpenEpisode: (String) -> Unit) {
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
    val ruled by rememberCatalogQuery(today) { db ->
        buildList {
            add(Shelf("thisday", "This day in radio", db.shelf(ShelfRule.ThisDay(today))))
            db.genres().forEach { genre ->
                add(Shelf("genre:$genre", DisplayVocabulary.genreName(genre), db.shelf(ShelfRule.Genre(genre))))
            }
        }
    }
    Scaffold(topBar = { TopAppBar(title = { Text("Listen") }) }) { padding ->
        LoadableContent(ruled, Modifier.padding(padding)) { rules ->
            val first = (continuing as? Loadable.Ready)?.value
            val list = (listOfNotNull(first) + rules).filter { it.rows.isNotEmpty() }
            if (list.isEmpty()) {
                EmptyMessage("Nothing to list yet.", Modifier.padding(padding))
            } else {
                LazyColumn(Modifier.fillMaxSize(), contentPadding = padding) {
                    items(list, key = { it.key }) { shelf ->
                        SectionHeader(shelf.title)
                        LazyRow(contentPadding = PaddingValues(horizontal = Spacing.S4.dp)) {
                            items(shelf.rows, key = { it.id }) { row ->
                                EpisodeCard(row, onOpen = { onOpenEpisode(row.id) })
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
private fun EpisodeCard(row: EpisodeRow, onOpen: () -> Unit) {
    OutlinedCard(
        onClick = onOpen,
        modifier = Modifier.padding(end = Spacing.S3.dp).width(220.dp),
    ) {
        Column(Modifier.padding(Spacing.S3.dp)) {
            formatAirDate(row.airDate)?.let {
                Text(it, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
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
