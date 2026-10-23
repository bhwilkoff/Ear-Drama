package com.example.appname.ui.screens

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.DockedSearchBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.SearchBarDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.example.appname.data.SearchResults
import com.example.appname.ui.EmptyMessage
import com.example.appname.ui.EpisodeListItem
import com.example.appname.ui.LoadableContent
import com.example.appname.ui.LocalAppContainer
import com.example.appname.ui.SectionHeader
import com.example.appname.ui.SeriesListItem
import com.example.appname.ui.rememberCatalogQuery
import com.example.appname.ui.theme.Spacing
import kotlinx.coroutines.delay

/** Search: episodes and series, word-prefix (§3.4), never filtered by `recommendAnd`. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SearchScreen(onOpenSeries: (String) -> Unit, onOpenEpisode: (String) -> Unit) {
    val container = LocalAppContainer.current
    var query by rememberSaveable { mutableStateOf("") }
    var settled by rememberSaveable { mutableStateOf("") }
    LaunchedEffect(query) {
        delay(250)
        settled = query.trim()
    }
    val results by rememberCatalogQuery(settled) { db ->
        if (settled.isEmpty()) SearchResults(emptyList(), emptyList()) else db.search(settled)
    }
    Column(Modifier.fillMaxSize().statusBarsPadding()) {
        DockedSearchBar(
            inputField = {
                SearchBarDefaults.InputField(
                    query = query,
                    onQueryChange = { query = it },
                    onSearch = { settled = it.trim() },
                    expanded = false,
                    onExpandedChange = {},
                    placeholder = { Text("Titles, series, people") },
                    leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
                    trailingIcon = if (query.isEmpty()) null else {
                        {
                            IconButton(onClick = { query = ""; settled = "" }) {
                                Icon(Icons.Filled.Close, contentDescription = "Clear search")
                            }
                        }
                    },
                )
            },
            expanded = false,
            onExpandedChange = {},
            modifier = Modifier.fillMaxWidth().padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp),
        ) {}
        LoadableContent(results) { found ->
            when {
                settled.isEmpty() -> Unit
                found.isEmpty -> EmptyMessage("No matches for “$settled”.")
                else -> LazyColumn(Modifier.fillMaxSize()) {
                    if (found.series.isNotEmpty()) {
                        item(key = "series-h") { SectionHeader("Series") }
                        items(found.series, key = { "s:" + it.key }) { row ->
                            SeriesListItem(row, onOpen = { onOpenSeries(row.key) })
                        }
                    }
                    if (found.episodes.isNotEmpty()) {
                        item(key = "episodes-h") { SectionHeader("Episodes") }
                        items(found.episodes, key = { "e:" + it.id }) { row ->
                            EpisodeListItem(
                                row,
                                showSeries = true,
                                onOpen = { onOpenEpisode(row.id) },
                                onPlay = { container.playback.play(row) },
                            )
                        }
                    }
                }
            }
        }
    }
}
