package com.example.appname.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.unit.dp
import com.example.appname.data.BrowseFilter
import com.example.appname.data.DisplayVocabulary
import com.example.appname.data.SeriesSort
import com.example.appname.ui.ClaimTvFocus
import com.example.appname.ui.EmptyMessage
import com.example.appname.ui.Haptic
import com.example.appname.ui.Loadable
import com.example.appname.ui.LoadableContent
import com.example.appname.ui.SeriesListItem
import com.example.appname.ui.rememberCatalogQuery
import com.example.appname.ui.rememberHaptics
import com.example.appname.ui.tvFocusMark
import com.example.appname.ui.theme.Spacing
import java.text.NumberFormat
import java.util.Locale

private const val PAGE = 200

/**
 * Series (§4.2): browse by network, decade, and genre, in one of the web's
 * three orders (§5 `seriesBrowse`; the listener drives it, so no
 * `recommendAnd`). Every facet comes from the data, each counted against the
 * others' selection, so no choice offered yields zero rows.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SeriesBrowseScreen(onOpenSeries: (String) -> Unit) {
    var genre by rememberSaveable { mutableStateOf<String?>(null) }
    var decade by rememberSaveable { mutableStateOf<Int?>(null) }
    var network by rememberSaveable { mutableStateOf<String?>(null) }
    var sort by rememberSaveable { mutableStateOf(SeriesSort.Name) }
    var pages by rememberSaveable(genre, decade, network, sort) { mutableIntStateOf(1) }
    val haptics = rememberHaptics()
    val genres by rememberCatalogQuery(decade, network) { db -> db.genres(decade, network) }
    val decades by rememberCatalogQuery(genre, network) { db -> db.seriesDecades(genre, network) }
    val networks by rememberCatalogQuery(genre, decade) { db -> db.networks(genre, decade) }
    val series by rememberCatalogQuery(genre, decade, network, sort, pages) { db ->
        db.seriesBrowse(BrowseFilter(genre = genre, network = network, decade = decade, sort = sort), limit = PAGE * pages)
    }
    Scaffold(topBar = { TopAppBar(title = { Text("Series") }) }) { padding ->
        LoadableContent(series, Modifier.padding(padding)) { rows ->
            val listState = rememberLazyListState()
            val nearEnd by remember {
                derivedStateOf {
                    val last = listState.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0
                    last >= listState.layoutInfo.totalItemsCount - 20
                }
            }
            LaunchedEffect(nearEnd, rows.size) {
                if (nearEnd && rows.size >= PAGE * pages) pages += 1
            }
            // On a TV the D-pad starts on the first filter chip (§9.2).
            val chips = remember { FocusRequester() }
            ClaimTvFocus(chips, Unit)
            LazyColumn(Modifier.fillMaxSize(), state = listState, contentPadding = padding) {
                item(key = "filters") {
                    LazyRow(
                        modifier = Modifier.focusRequester(chips),
                        contentPadding = PaddingValues(horizontal = Spacing.S4.dp),
                        horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp),
                    ) {
                        item(key = "sort") {
                            MenuChip(
                                label = sort.label,
                                selected = sort != SeriesSort.Name,
                                choices = SeriesSort.entries.map { it to it.label },
                                onChoose = { if (it != sort) { sort = it; haptics(Haptic.Selection) } },
                            )
                        }
                        item(key = "network") {
                            val counts = (networks as? Loadable.Ready)?.value.orEmpty()
                            val number = NumberFormat.getIntegerInstance(Locale.US)
                            MenuChip(
                                label = network ?: "Network",
                                selected = network != null,
                                choices = listOf<Pair<String?, String>>(null to "All networks") +
                                    counts.map { it.value to "${it.value} (${number.format(it.series)})" },
                                onChoose = { if (it != network) { network = it; haptics(Haptic.Selection) } },
                            )
                        }
                        val decadeList = (decades as? Loadable.Ready)?.value.orEmpty()
                        items(decadeList, key = { "d$it" }) { d ->
                            FilterChip(
                                selected = decade == d,
                                onClick = { decade = if (decade == d) null else d; haptics(Haptic.Selection) },
                                label = { Text("${d}s") },
                                modifier = Modifier.tvFocusMark(),
                            )
                        }
                        val genreList = (genres as? Loadable.Ready)?.value.orEmpty()
                            .mapNotNull { g -> DisplayVocabulary.genreName(g)?.let { g to it } }
                        items(genreList, key = { "g${it.first}" }) { (g, name) ->
                            FilterChip(
                                selected = genre == g,
                                onClick = { genre = if (genre == g) null else g; haptics(Haptic.Selection) },
                                label = { Text(name) },
                                modifier = Modifier.tvFocusMark(),
                            )
                        }
                    }
                }
                if (rows.isEmpty()) {
                    item(key = "empty") { EmptyMessage("No series match these filters.") }
                }
                items(rows, key = { it.key }) { row ->
                    SeriesListItem(row, onOpen = { onOpenSeries(row.key) })
                }
            }
        }
    }
}

/** A filter chip that opens its choices in a menu (Material's dropdown filter chip). */
@Composable
private fun <T> MenuChip(label: String, selected: Boolean, choices: List<Pair<T, String>>, onChoose: (T) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        FilterChip(
            selected = selected,
            onClick = { open = true },
            label = { Text(label) },
            trailingIcon = { Icon(Icons.Filled.ArrowDropDown, contentDescription = null) },
            modifier = Modifier.tvFocusMark(),
        )
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            choices.forEach { (value, text) ->
                DropdownMenuItem(text = { Text(text) }, onClick = { open = false; onChoose(value) })
            }
        }
    }
}
