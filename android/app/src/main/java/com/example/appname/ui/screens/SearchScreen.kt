package com.example.appname.ui.screens

import com.example.appname.data.EpisodeRow
import androidx.compose.runtime.produceState
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
import androidx.compose.runtime.remember
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import com.example.appname.ui.ClaimTvFocus
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.example.appname.data.SearchResults
import com.example.appname.data.Transcript
import com.example.appname.ui.EmptyMessage
import com.example.appname.ui.EpisodeListItem
import com.example.appname.ui.LoadableContent
import com.example.appname.ui.LocalAppContainer
import com.example.appname.ui.PersonListItem
import com.example.appname.ui.SectionHeader
import com.example.appname.ui.SeriesListItem
import com.example.appname.ui.rememberCatalogQuery
import com.example.appname.ui.theme.Spacing
import kotlinx.coroutines.delay

/** Search: series, plays, and episodes, word-prefix (§3.4), never filtered by `recommendAnd`. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SearchScreen(
    onOpenSeries: (String) -> Unit,
    onOpenEpisode: (String) -> Unit,
    onOpenScript: (String) -> Unit,
    onOpenPerson: (String) -> Unit,
    incoming: String? = null,
    onIncomingTaken: () -> Unit = {},
) {
    val container = LocalAppContainer.current
    var query by rememberSaveable { mutableStateOf("") }
    var settled by rememberSaveable { mutableStateOf("") }
    // A search link (DEEP_LINKS.md `search?q=`) arrives through the inbox.
    LaunchedEffect(incoming) {
        if (incoming != null) {
            query = incoming
            settled = incoming.trim()
            onIncomingTaken()
        }
    }
    // On a TV the D-pad starts in the search field (§9.2).
    val field = remember { FocusRequester() }
    ClaimTvFocus(field, Unit)
    LaunchedEffect(query) {
        delay(250)
        settled = query.trim()
    }
    val allPlays = rememberCastablePlays()
    val plays = remember(settled, allPlays) { playsMatching(allPlays, settled) }
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
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp)
                .focusRequester(field),
        ) {}
        LoadableContent(results) { found ->
            when {
                settled.isEmpty() -> Unit
                found.isEmpty && plays.isEmpty() -> EmptyMessage("No matches for “$settled”.")
                else -> LazyColumn(Modifier.fillMaxSize()) {
                    if (found.series.isNotEmpty()) {
                        item(key = "series-h") { SectionHeader("Series") }
                        items(found.series, key = { "s:" + it.key }) { row ->
                            SeriesListItem(row, onOpen = { onOpenSeries(row.key) })
                        }
                    }
                    if (found.people.isNotEmpty()) {
                        item(key = "people-h") { SectionHeader("People") }
                        items(found.people, key = { "pe:" + it.person.id }) { row ->
                            PersonListItem(row, onOpen = { onOpenPerson(row.person.id) })
                        }
                    }
                    if (plays.isNotEmpty()) {
                        item(key = "plays-h") { SectionHeader("Plays") }
                        items(plays, key = { "p:" + it.id }) { script ->
                            PlayListItem(script, onOpen = { onOpenScript(script.id) })
                        }
                    }
                    val aired = found.aired
                    if (aired != null && aired.episodes.isNotEmpty()) {
                        item(key = "aired-h") { SectionHeader(aired.title) }
                        items(aired.episodes, key = { "a:" + it.id }) { row ->
                            EpisodeListItem(
                                row,
                                showSeries = true,
                                onOpen = { onOpenEpisode(row.id) },
                                onPlay = { container.playback.play(row) },
                            )
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
                    if (found.transcript.isNotEmpty()) {
                        val words = Transcript.searchWords(settled)
                        item(key = "transcript-h") { SectionHeader(Transcript.LABEL) }
                        items(found.transcript, key = { "t:" + it.id }) { row ->
                            TranscriptHitItem(
                                row,
                                words,
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

/**
 * Search's transcript match (ANDROID-DESIGN §4.5): the episode row and the line where the
 * words are said, read from the transcript's own URL; the row stands alone when it does not load.
 */
@Composable
private fun TranscriptHitItem(row: EpisodeRow, words: List<String>, onOpen: () -> Unit, onPlay: () -> Unit) {
    val container = LocalAppContainer.current
    val quote by produceState<String?>(null, row.id, words) {
        val url = row.transcriptUrl ?: return@produceState
        value = try {
            Transcript.snippet(container.api.text(url), words)
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: Exception) {
            null
        }
    }
    EpisodeListItem(row, showSeries = true, onOpen = onOpen, onPlay = onPlay, quote = quote)
}
