package com.example.appname.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.fillMaxWidth
import com.example.appname.ui.offlineLine
import com.example.appname.ui.LocalOnline
import com.example.appname.navigation.FindDoor
import com.example.appname.plays.PlaySearchModel
import com.example.appname.plays.PlayRow
import com.example.appname.plays.PlayCollections
import com.example.appname.plays.FindCore
import kotlinx.coroutines.delay
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.Alignment
import androidx.compose.runtime.produceState
import androidx.compose.material3.SearchBarDefaults
import androidx.compose.material3.IconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.DockedSearchBar
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.Icons
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyGridScope
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.layout
import androidx.compose.ui.unit.dp
import com.example.appname.plays.PlayLibraryFeed
import com.example.appname.plays.PlaysShare
import com.example.appname.ui.EmptyAction
import com.example.appname.ui.EmptyMessage
import com.example.appname.ui.Haptic
import com.example.appname.ui.LocalAppContainer
import com.example.appname.ui.LocalIsTelevision
import com.example.appname.ui.SectionHeader
import com.example.appname.ui.formatCount
import com.example.appname.ui.playTiles
import com.example.appname.ui.rememberHaptics
import com.example.appname.ui.theme.Spacing
import com.example.appname.ui.tileLayout
import kotlinx.coroutines.launch

/** Lets a full-width row of the grid use the gutter the grid keeps for its tiles. */
private fun Modifier.bleed(): Modifier = layout { measurable, constraints ->
    val pad = Spacing.S4.dp.roundToPx()
    val wide = constraints.copy(minWidth = constraints.maxWidth + 2 * pad, maxWidth = constraints.maxWidth + 2 * pad)
    val placeable = measurable.measure(wide)
    layout(constraints.maxWidth, placeable.height) { placeable.place(-pad, 0) }
}

private fun LazyGridScope.wide(key: Any, content: @Composable () -> Unit) {
    item(key = key, span = { GridItemSpan(maxLineSpan) }) { Box(Modifier.bleed()) { content() } }
}

/**
 * Record (ANDROID-DESIGN §4.9a, Decision 075, B31; not on a TV): the search field, then with two letters or more the search's play
 * sections; else Yours (this device's productions and the shared ones not yet opened; absent when none), Today's scene, Plays (the
 * facets counted against each other, the ways in as rails whose heading is their rule, then the grid under the sort's name), then
 * Made here. Each section has its own states; a section whose rule yields nothing is not drawn. The plays come from the published
 * library (contract §4.1), the bundle its floor, and are cells of a lazy grid: 1,100 and more.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RecordScreen(
    onOpenScript: (String) -> Unit,
    onOpenProduction: (String) -> Unit,
    onOpenDrama: (String) -> Unit,
    onDramas: () -> Unit,
    onRead: (String) -> Unit = {},
    onOpenStudio: OpenStudio = { _, _, _, _ -> },
    onAddScript: () -> Unit = {},
    onOpenOwn: (com.example.appname.plays.OwnRow) -> Unit = {},
    onReadAt: (String, String?) -> Unit = { id, _ -> onRead(id) },
    onOpenCollection: (String) -> Unit = {},
    onOpenScenes: (Int) -> Unit = {},
) {
    val container = LocalAppContainer.current
    val productions by container.plays.store.productions.collectAsState()
    val account by container.accounts.account.collectAsState()
    val links by container.sharing.links.collectAsState()
    val remote by container.sharing.remote.collectAsState()
    LaunchedEffect(account?.userId) {
        if (account == null) container.sharing.forget() else runCatching { container.sharing.loadRemote() }
    }
    val yours = remember(productions, links, remote) { PlaysShare.libraryRows(container.plays.store, remote) }
    var query by rememberSaveable { mutableStateOf(FindDoor.query.orEmpty()) }
    var settled by rememberSaveable { mutableStateOf(FindDoor.query.orEmpty().trim()) }
    LaunchedEffect(query) {
        delay(250)
        settled = query.trim()
    }
    var picks by rememberSaveable { mutableStateOf<Map<String, String>>(FindDoor.picksOf(FindDoor.picks)) }
    var sort by rememberSaveable { mutableStateOf("voices") }
    val state = rememberPlayRows()
    val ready = state as? PlayLibraryFeed.Rows.Ready
    val facets = remember(ready?.facets) { FindCore.facets(ready?.facets) }
    // A value this library does not offer (an older choice, another library's band) is dropped.
    val find = remember(picks, sort, facets) { FindCore.State(FindCore.offered(picks, facets), sort) }
    val collections by produceState<PlayCollections?>(null, ready?.published) { value = if (ready?.published == true) container.plays.feed.collections() else null }
    val list: List<PlayRow> = remember(ready, find, facets) {
        ready?.let { FindCore.sorted(FindCore.filter(it.rows, facets, find.picks), find.sort) }.orEmpty()
    }
    val rails = remember(ready, collections) { ready?.let { FindCore.rails(it.rows, collections) }.orEmpty() }
    val haptics = rememberHaptics()
    val scope = rememberCoroutineScope()
    val reads = !LocalIsTelevision.current
    val ownRows = rememberOwnRows()
    val bar = TopAppBarDefaults.enterAlwaysScrollBehavior()
    val searching = settled.length >= 2
    // The search runs from the page, once per query: a section that composes never starts it again.
    val search = remember(container.plays.feed) { PlaySearchModel(container.plays.feed) }
    LaunchedEffect(settled, ready?.rows) {
        val rows = ready?.rows
        if (settled.length >= 2 && rows != null) search.run(settled, rows)
    }
    Scaffold(modifier = Modifier.nestedScroll(bar.nestedScrollConnection), topBar = {
        TopAppBar(
            title = { Text("Record") },
            actions = { if (reads) AddScriptButton(onAddScript) },
            scrollBehavior = bar,
        )
    }) { padding ->
        Column(Modifier.fillMaxSize().padding(top = padding.calculateTopPadding())) {
            PlayQueryField(query, onQuery = { query = it }, onClear = { query = ""; settled = "" }, Modifier.padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp))
            BoxWithConstraints(Modifier.fillMaxSize()) {
                val (cols, tileWidth) = tileLayout(maxWidth)
                LazyVerticalGrid(
                    GridCells.Fixed(cols),
                    Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(start = Spacing.S4.dp, end = Spacing.S4.dp, bottom = padding.calculateBottomPadding()),
                    horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp),
                ) {
                    if (searching) {
                        wide("search") {
                            PlaySearchSections(
                                settled, search, onOpenScript, onReadAt, onMore = { scope.launch { search.more() } },
                                offersAdd = reads, onAdd = onAddScript,
                            )
                        }
                        return@LazyVerticalGrid
                    }
                    if (yours.isNotEmpty()) {
                        wide("yours-h") { SectionHeader("Yours") }
                        for (row in yours) {
                            wide("y:" + (row.local?.id ?: row.pid)) {
                                val production = row.local
                                val shared = row.remote
                                if (production != null) {
                                    ProductionRow(production, onOpen = { onOpenProduction(production.id) })
                                } else if (shared != null) {
                                    RemoteProductionRow(shared, onOpenProduction)
                                }
                            }
                        }
                    }
                    if (ownRows.isNotEmpty()) {
                        wide("own-h") { SectionHeader("Your scripts") }
                        for (row in ownRows) wide("o:" + row.id) { OwnScriptRow(row, onOpen = { onOpenOwn(row) }) }
                    }
                    if (reads) wide("class-doors") { ClassDoors() }
                    wide("today") { TodaysScene(onOpenScript, onRead, onOpenStudio) }
                    wide("plays-h") { SectionHeader("Plays") }
                    when (state) {
                        PlayLibraryFeed.Rows.Loading -> wide("plays-wait") { RowSpinner() }
                        PlayLibraryFeed.Rows.Unavailable -> wide("plays-problem") {
                            RowProblem(
                                offlineLine(LocalOnline.current) ?: "This did not load.",
                                onRetry = { scope.launch { container.plays.feed.retry(); container.plays.loadRows() } },
                            )
                        }
                        is PlayLibraryFeed.Rows.Ready -> {
                            val rows: List<PlayRow> = state.rows
                            if (rows.isEmpty()) {
                                wide("plays-none") { EmptyMessage("No plays yet.", Modifier.padding(Spacing.S4.dp), claimTvFocus = false) }
                            } else {
                                wide("facets") {
                                    PlayFacetRow(rows, facets, find, onState = { n -> picks = n.picks.toMap(); sort = n.sort; haptics(Haptic.Selection) })
                                }
                                if (!find.isActive) {
                                    for (rail in rails) {
                                        wide("rail:" + rail.id) {
                                            PlayRailSection(
                                                rail, onOpenScript, onReadAt, onRead = if (reads) onRead else null,
                                                onAll = { if (rail.kind == FindCore.RailKind.Scenes) onOpenScenes(rail.voices) else onOpenCollection(rail.id) },
                                            )
                                        }
                                    }
                                }
                                wide("count") {
                                    Row(
                                        Modifier.fillMaxWidth().padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp),
                                        verticalAlignment = Alignment.CenterVertically,
                                    ) {
                                        Text(FindCore.sortTitle(find.sort), style = MaterialTheme.typography.headlineSmall, modifier = Modifier.weight(1f).semantics { heading() })
                                        Text(formatCount(list.size), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    }
                                }
                                if (list.isEmpty()) {
                                    wide("plays-empty") {
                                        EmptyMessage(
                                            "Nothing matches these filters.",
                                            action = EmptyAction("Clear filters") { picks = emptyMap(); haptics(Haptic.Selection) },
                                            claimTvFocus = false,
                                        )
                                    }
                                } else {
                                    playTiles(
                                        list, cols, tileWidth,
                                        onOpen = { onOpenScript(it.id) },
                                        onRead = if (reads) ({ onRead(it.id) }) else null,
                                    )
                                }
                            }
                        }
                    }
                    wide("made") { NewEarDramas(onOpen = onOpenDrama, onAll = onDramas) }
                }
            }
        }
    }
}

/** Record's and Search's field (B31 §3.3): always drawn, never replaced by a page, with the prompt that names what it finds. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PlayQueryField(query: String, onQuery: (String) -> Unit, onClear: () -> Unit, modifier: Modifier = Modifier) {
    DockedSearchBar(
        inputField = {
            SearchBarDefaults.InputField(
                query = query,
                onQueryChange = onQuery,
                onSearch = onQuery,
                expanded = false,
                onExpandedChange = {},
                placeholder = { Text("Titles, authors, characters, lines") },
                leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
                trailingIcon = if (query.isEmpty()) null else {
                    { IconButton(onClick = onClear) { Icon(Icons.Filled.Close, contentDescription = "Clear search") } }
                },
            )
        },
        expanded = false,
        onExpandedChange = {},
        modifier = modifier.fillMaxWidth(),
    ) {}
}
