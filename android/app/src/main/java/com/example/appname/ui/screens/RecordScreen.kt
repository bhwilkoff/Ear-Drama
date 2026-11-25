package com.example.appname.ui.screens

import androidx.compose.foundation.layout.Arrangement
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
import com.example.appname.plays.PlayFacets
import com.example.appname.plays.PlayLibraryFeed
import com.example.appname.plays.PlayListing
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
 * Record (ANDROID-DESIGN §4.9a, Decision 075; not on a TV): Yours (this device's productions and the
 * shared ones not yet opened; absent when none), Today's scene, Plays under three facets and a sort, then
 * Made here. Each section has its own states; a section whose rule yields nothing is not drawn. The plays come
 * from the published library (contract §4.1), the bundle its floor, and are cells of a lazy grid: 650 and more.
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
    var voices by rememberSaveable { mutableStateOf<String?>(null) }
    var length by rememberSaveable { mutableStateOf<String?>(null) }
    var kind by rememberSaveable { mutableStateOf<String?>(null) }
    var sort by rememberSaveable { mutableStateOf("voices") }
    val filter = PlayFacets.Filter(voices, length, kind, sort)
    val state = rememberPlayRows()
    val list: List<PlayListing> = remember(state, voices, length, kind, sort) {
        (state as? PlayLibraryFeed.Rows.Ready)?.let { PlayFacets.sorted(PlayFacets.matching(it.rows, filter), sort) }.orEmpty()
    }
    val haptics = rememberHaptics()
    val scope = rememberCoroutineScope()
    val reads = !LocalIsTelevision.current
    val ownRows = rememberOwnRows()
    val bar = TopAppBarDefaults.enterAlwaysScrollBehavior()
    Scaffold(modifier = Modifier.nestedScroll(bar.nestedScrollConnection), topBar = {
        TopAppBar(
            title = { Text("Record") },
            actions = { if (reads) AddScriptButton(onAddScript) },
            scrollBehavior = bar,
        )
    }) { padding ->
        BoxWithConstraints(Modifier.fillMaxSize()) {
            val (cols, tileWidth) = tileLayout(maxWidth)
            LazyVerticalGrid(
                GridCells.Fixed(cols),
                Modifier.fillMaxSize(),
                contentPadding = PaddingValues(
                    start = Spacing.S4.dp, end = Spacing.S4.dp,
                    top = padding.calculateTopPadding(), bottom = padding.calculateBottomPadding(),
                ),
                horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp),
            ) {
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
                        RowProblem("The plays could not be read.", onRetry = { scope.launch { container.plays.feed.retry(); container.plays.loadRows() } })
                    }
                    is PlayLibraryFeed.Rows.Ready -> {
                        val rows: List<PlayListing> = state.rows
                        if (rows.isEmpty()) {
                            wide("plays-none") { EmptyMessage("No plays yet.", Modifier.padding(Spacing.S4.dp), claimTvFocus = false) }
                        } else {
                            wide("facets") {
                                LazyRow(
                                    contentPadding = PaddingValues(horizontal = Spacing.S4.dp),
                                    horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp),
                                ) {
                                    item(key = "voices") {
                                        FacetChip("Voices", "Any number", PlayFacets.Facet.Voices, PlayFacets.VOICES, rows, filter) {
                                            voices = it; haptics(Haptic.Selection)
                                        }
                                    }
                                    item(key = "length") {
                                        FacetChip("Length", "Any length", PlayFacets.Facet.Length, PlayFacets.LENGTH, rows, filter) {
                                            length = it; haptics(Haptic.Selection)
                                        }
                                    }
                                    item(key = "kind") {
                                        FacetChip("Kind", "Any kind", PlayFacets.Facet.Kind, PlayFacets.KIND, rows, filter) {
                                            kind = it; haptics(Haptic.Selection)
                                        }
                                    }
                                    item(key = "sort") {
                                        MenuChip(
                                            label = PlayFacets.SORT.getValue(sort),
                                            selected = sort != "voices",
                                            choices = PlayFacets.SORT.map { it.key to it.value },
                                            onChoose = { if (it != sort) { sort = it; haptics(Haptic.Selection) } },
                                        )
                                    }
                                }
                            }
                            wide("count") {
                                Text(
                                    "${formatCount(list.size)} ${if (list.size == 1) "play" else "plays"} · ${PlayFacets.SORT.getValue(sort)}",
                                    style = MaterialTheme.typography.labelMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    modifier = Modifier.padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp),
                                )
                            }
                            if (list.isEmpty()) {
                                wide("plays-empty") {
                                    EmptyMessage(
                                        "Nothing matches these filters.",
                                        action = EmptyAction("Clear filters") { voices = null; length = null; kind = null; haptics(Haptic.Selection) },
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

/** One facet as a menu chip: its choices counted with the other two applied, "Any ..." first. */
@Composable
private fun FacetChip(
    label: String,
    all: String,
    facet: PlayFacets.Facet,
    labels: Map<String, String>,
    scripts: List<PlayListing>,
    filter: PlayFacets.Filter,
    onChoose: (String?) -> Unit,
) {
    val chosen = filter.chosen(facet)
    val options = PlayFacets.options(scripts, filter, facet, labels)
    MenuChip(
        label = chosen?.let { labels[it] } ?: label,
        selected = chosen != null,
        choices = listOf<Pair<String?, String>>(null to all) + options.map { (key, text, n) -> key to "$text (${formatCount(n)})" },
        onChoose = onChoose,
    )
}
