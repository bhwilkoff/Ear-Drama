package com.example.appname.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
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
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.example.appname.plays.PlayFacets
import com.example.appname.plays.PlayScript
import com.example.appname.plays.PlaysLibrary
import com.example.appname.plays.PlaysShare
import com.example.appname.ui.EmptyAction
import com.example.appname.ui.EmptyMessage
import com.example.appname.ui.Haptic
import com.example.appname.ui.LocalAppContainer
import com.example.appname.ui.PlayGrid
import com.example.appname.ui.SectionHeader
import com.example.appname.ui.formatCount
import com.example.appname.ui.rememberHaptics
import com.example.appname.ui.theme.Spacing
import kotlinx.coroutines.launch

/**
 * Record (ANDROID-DESIGN §4.9a, Decision 075; not on a TV): Yours (this device's productions and the
 * shared ones not yet opened; absent when none), Today's play, Plays under three facets and a sort, then
 * Made here. Each section has its own states; a section whose rule yields nothing is not drawn.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RecordScreen(
    onOpenScript: (String) -> Unit,
    onOpenProduction: (String) -> Unit,
    onOpenDrama: (String) -> Unit,
    onDramas: () -> Unit,
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
    val state = rememberCastableState()
    val haptics = rememberHaptics()
    val scope = rememberCoroutineScope()
    Scaffold(topBar = { TopAppBar(title = { Text("Record") }) }) { padding ->
        LazyColumn(Modifier.fillMaxSize(), contentPadding = padding) {
            if (yours.isNotEmpty()) {
                item(key = "yours-h") { SectionHeader("Yours") }
                items(yours, key = { "y:" + (it.local?.id ?: it.pid) }) { row ->
                    val production = row.local
                    val shared = row.remote
                    if (production != null) {
                        ProductionRow(production, onOpen = { onOpenProduction(production.id) })
                    } else if (shared != null) {
                        RemoteProductionRow(shared, onOpenProduction)
                    }
                }
            }
            item(key = "today") { TodaysPlay(onOpenScript, onOpenProduction) }
            item(key = "plays-h") { SectionHeader("Plays") }
            when (state) {
                PlaysLibrary.State.Loading -> item(key = "plays-wait") { RowSpinner() }
                PlaysLibrary.State.Unavailable -> item(key = "plays-problem") {
                    RowProblem("The plays could not be read.", onRetry = { scope.launch { container.plays.load() } })
                }
                is PlaysLibrary.State.Ready -> {
                    val scripts = state.scripts
                    if (scripts.isEmpty()) {
                        item(key = "plays-none") { EmptyMessage("No plays yet.", Modifier.padding(Spacing.S4.dp), claimTvFocus = false) }
                    } else {
                        item(key = "facets") {
                            LazyRow(
                                contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = Spacing.S4.dp),
                                horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp),
                            ) {
                                item(key = "voices") {
                                    FacetChip("Voices", "Any number", PlayFacets.Facet.Voices, PlayFacets.VOICES, scripts, filter) {
                                        voices = it; haptics(Haptic.Selection)
                                    }
                                }
                                item(key = "length") {
                                    FacetChip("Length", "Any length", PlayFacets.Facet.Length, PlayFacets.LENGTH, scripts, filter) {
                                        length = it; haptics(Haptic.Selection)
                                    }
                                }
                                item(key = "kind") {
                                    FacetChip("Kind", "Any kind", PlayFacets.Facet.Kind, PlayFacets.KIND, scripts, filter) {
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
                        val list = PlayFacets.sorted(PlayFacets.matching(scripts, filter), sort)
                        item(key = "count") {
                            Text(
                                "${formatCount(list.size)} ${if (list.size == 1) "play" else "plays"} · ${PlayFacets.SORT.getValue(sort)}",
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp),
                            )
                        }
                        if (list.isEmpty()) {
                            item(key = "plays-empty") {
                                EmptyMessage(
                                    "Nothing matches these filters.",
                                    action = EmptyAction("Clear filters") { voices = null; length = null; kind = null; haptics(Haptic.Selection) },
                                    claimTvFocus = false,
                                )
                            }
                        } else {
                            item(key = "grid") { PlayGrid(list, onOpen = { onOpenScript(it.id) }) }
                        }
                    }
                }
            }
            item(key = "made") { NewEarDramas(onOpen = onOpenDrama, onAll = onDramas) }
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
    scripts: List<PlayScript>,
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
