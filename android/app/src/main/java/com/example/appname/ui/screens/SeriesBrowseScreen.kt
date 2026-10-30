package com.example.appname.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.layout.layout
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.example.appname.data.BrowseFilter
import com.example.appname.data.DisplayVocabulary
import com.example.appname.data.SeriesRow
import com.example.appname.data.SeriesSort
import com.example.appname.data.azLetter
import com.example.appname.data.azLetters
import com.example.appname.data.decadeField
import com.example.appname.ui.ClaimTvFocus
import com.example.appname.ui.DecadeFieldView
import com.example.appname.ui.EmptyAction
import com.example.appname.ui.EmptyMessage
import com.example.appname.ui.Haptic
import com.example.appname.ui.LetterRail
import com.example.appname.ui.Loadable
import com.example.appname.ui.isTelevision
import com.example.appname.ui.LoadableContent
import com.example.appname.ui.SectionHeading
import com.example.appname.ui.PLAY_BOARD
import com.example.appname.ui.ShowTile
import com.example.appname.ui.TextLink
import com.example.appname.ui.TileSpec
import com.example.appname.ui.formatCount
import com.example.appname.ui.innerWidth
import com.example.appname.ui.rememberCatalogQuery
import com.example.appname.ui.rememberHaptics
import com.example.appname.ui.rememberNameHeights
import com.example.appname.ui.theme.Spacing
import com.example.appname.ui.tileLayout
import com.example.appname.ui.tvFocusMark
import kotlinx.coroutines.launch
import java.text.NumberFormat
import java.util.Locale

private const val PAGE = 200

/** What Browse lists (Decision 068): radio series, stage plays, or both. */
private enum class BrowseKind(val label: String) { Series("Series"), Plays("Plays") }

/**
 * Browse (§4.2; was Series): radio series and stage plays together, by kind,
 * "Has a script", network, decade, and genre, in one of the web's three orders
 * (§5 `seriesBrowse`; the listener drives it, so no `recommendAnd`). Every
 * series facet comes from the data, each counted against the others'
 * selection. A play carries no genre, decade, or network, so setting one
 * narrows to series; "Has a script" keeps the plays and the series with a
 * linked episode (§3.1). No plays on a TV. R11c: the results are show tiles
 * (the show line), with the decade by genre field above them, or beside them
 * at expanded widths.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SeriesBrowseScreen(
    onOpenSeries: (String) -> Unit,
    onOpenScript: (String) -> Unit,
    /** A genre the series page asked Browse to filter to; [onGenreRequestHandled] clears it. */
    genreRequest: String? = null,
    onGenreRequestHandled: () -> Unit = {},
    /** Home's "All" asked for the Ear dramas scope; [onDramasRequestHandled] clears it. */
    dramasRequest: Boolean = false,
    onDramasRequestHandled: () -> Unit = {},
    onOpenDrama: (String) -> Unit = {},
) {
    var dramas by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(dramasRequest) {
        if (dramasRequest) {
            dramas = true
            onDramasRequestHandled()
        }
    }
    var kind by rememberSaveable { mutableStateOf<BrowseKind?>(null) }
    var hasScript by rememberSaveable { mutableStateOf(false) }
    val allPlays = rememberCastablePlays()
    var genre by rememberSaveable { mutableStateOf<String?>(null) }
    var decade by rememberSaveable { mutableStateOf<Int?>(null) }
    var network by rememberSaveable { mutableStateOf<String?>(null) }
    var sort by rememberSaveable { mutableStateOf(SeriesSort.Popular) }
    var singles by rememberSaveable { mutableStateOf(false) }
    var pages by rememberSaveable(genre, decade, network, sort, singles) { mutableIntStateOf(1) }
    LaunchedEffect(genreRequest) {
        if (genreRequest != null) {
            kind = null; hasScript = false; decade = null; network = null; singles = false
            genre = genreRequest
            dramas = false
            onGenreRequestHandled()
        }
    }
    val scope = rememberCoroutineScope()
    val isTv = LocalContext.current.isTelevision()
    var headerItems by remember { mutableIntStateOf(1) }
    val haptics = rememberHaptics()
    val genres by rememberCatalogQuery(decade, network) { db -> db.genres(decade, network) }
    val decades by rememberCatalogQuery(genre, network) { db -> db.seriesDecades(genre, network) }
    val networks by rememberCatalogQuery(genre, decade) { db -> db.networks(genre, decade) }
    val series by rememberCatalogQuery(genre, decade, network, sort, pages, singles) { db ->
        db.seriesBrowse(
            BrowseFilter(genre = genre, network = network, decade = decade, sort = sort, showLine = !singles),
            limit = if (sort == SeriesSort.Name) Int.MAX_VALUE else PAGE * pages,
        )
    }
    val counts by rememberCatalogQuery(genre, decade, network) { db ->
        db.seriesCounts(BrowseFilter(genre = genre, network = network, decade = decade))
    }
    val fieldShows by rememberCatalogQuery(network) { db -> db.fieldShows(network) }
    val field = remember(fieldShows) { decadeField((fieldShows as? Loadable.Ready)?.value.orEmpty()) }
    val scripted by rememberCatalogQuery { db -> db.scriptedSeries() }
    val showsSeries = kind != BrowseKind.Plays
    val plays = if (kind != BrowseKind.Series && genre == null && decade == null && network == null) allPlays else emptyList()
    val (showCount, singleCount) = (counts as? Loadable.Ready)?.value ?: (0 to 0)
    val sectionTitle = when (sort) {
        SeriesSort.Popular -> "Most downloaded first"
        SeriesSort.Name -> "A to Z"
        SeriesSort.Episodes -> "Most episodes"
        SeriesSort.FirstAired -> "Oldest first"
    }
    Scaffold(topBar = { TopAppBar(title = { Text("Browse") }) }) { padding ->
      Column(Modifier.padding(padding)) {
        if (!isTv) {
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp)) {
                listOf(false to "Shows", true to "Ear dramas").forEachIndexed { i, (isDramas, label) ->
                    SegmentedButton(
                        selected = dramas == isDramas,
                        onClick = { if (dramas != isDramas) { dramas = isDramas; haptics(Haptic.Selection) } },
                        shape = SegmentedButtonDefaults.itemShape(i, 2),
                    ) { Text(label) }
                }
            }
        }
        if (dramas && !isTv) {
            EarDramasScope(onOpenDrama, Modifier.weight(1f))
        } else LoadableContent(series, Modifier.weight(1f)) { rows ->
            val gridState = rememberLazyGridState()
            val nearEnd by remember {
                derivedStateOf {
                    val last = gridState.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0
                    last >= gridState.layoutInfo.totalItemsCount - 20
                }
            }
            LaunchedEffect(nearEnd, rows.size) {
                if (nearEnd && rows.size >= PAGE * pages) pages += 1
            }
            // On a TV the D-pad starts on the first filter chip (§9.2).
            val chips = remember { FocusRequester() }
            ClaimTvFocus(chips, Unit)
            // "Has a script" keeps the series with an episode linked to a script this bundle holds (§4.2).
            val bundled = allPlays.mapTo(HashSet()) { it.id }
            val linked = (scripted as? Loadable.Ready)?.value.orEmpty()
            val seriesRows = when {
                !showsSeries -> emptyList()
                hasScript -> rows.filter { r -> linked[r.key].orEmpty().any { it in bundled } }
                else -> rows
            }
            val tiles = seriesRows.map { row ->
                TileSpec("s:" + row.key, row, onOpen = { onOpenSeries(row.key) })
            } + plays.map { script ->
                val speaking = script.castParts.count { it.id.isSpeaking }
                TileSpec(
                    "play:" + script.id,
                    SeriesRow("play:" + script.id, script.title, PLAY_BOARD, null, null, 0),
                    facts = listOf(script.authorLine, "$speaking parts").filter { it.isNotEmpty() },
                    openLabel = "Open play",
                    onOpen = { onOpenScript(script.id) },
                )
            }
            // A to Z: every letter that has a show; a letter jumps to its first tile.
            val azKeys = tiles.map { it.series.sortName ?: it.series.name }
            val letters = if (sort == SeriesSort.Name) azLetters(azKeys) else emptyList()
            val jumpTo: (String) -> Unit = { l ->
                val at = azKeys.indexOfFirst { azLetter(it) == l }
                if (at >= 0) {
                    val offset = headerItems + 1 + (if (tiles.isEmpty()) 1 else 0)
                    scope.launch { gridState.scrollToItem(offset + at) }
                }
            }
            val filters: @Composable () -> Unit = {
                LazyRow(
                    modifier = Modifier.focusRequester(chips),
                    contentPadding = PaddingValues(horizontal = Spacing.S4.dp),
                    horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp),
                ) {
                    if (allPlays.isNotEmpty()) {
                        item(key = "kind") {
                            MenuChip(
                                label = kind?.label ?: "Kind",
                                selected = kind != null,
                                choices = listOf<Pair<BrowseKind?, String>>(null to "Any kind") +
                                    BrowseKind.entries.map { it to it.label },
                                onChoose = { if (it != kind) { kind = it; haptics(Haptic.Selection) } },
                            )
                        }
                        item(key = "script") {
                            FilterChip(
                                selected = hasScript,
                                onClick = { hasScript = !hasScript; haptics(Haptic.Selection) },
                                label = { Text("Has a script") },
                                modifier = Modifier.tvFocusMark(),
                            )
                        }
                    }
                    item(key = "sort") {
                        MenuChip(
                            label = sort.label,
                            selected = sort != SeriesSort.Popular,
                            choices = SeriesSort.entries.map { it to it.label },
                            onChoose = { if (it != sort) { sort = it; haptics(Haptic.Selection) } },
                        )
                    }
                    item(key = "network") {
                        val facet = (networks as? Loadable.Ready)?.value.orEmpty()
                        val number = NumberFormat.getIntegerInstance(Locale.US)
                        MenuChip(
                            label = network ?: "Network",
                            selected = network != null,
                            choices = listOf<Pair<String?, String>>(null to "All networks") +
                                facet.map { it.value to "${it.value} (${number.format(it.series)})" },
                            onChoose = { if (it != network) { network = it; haptics(Haptic.Selection) } },
                        )
                    }
                    if (isTv && letters.size > 1) {
                        items(letters, key = { "az$it" }) { l ->
                            FilterChip(
                                selected = false,
                                onClick = { jumpTo(l); haptics(Haptic.Selection) },
                                label = { Text(l) },
                                modifier = Modifier.tvFocusMark(),
                            )
                        }
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
            val countLine: @Composable () -> Unit = {
                Row(
                    Modifier.fillMaxWidth().padding(horizontal = Spacing.S4.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    if (!showsSeries) {
                        Text("${formatCount(plays.size)} plays", style = MaterialTheme.typography.titleMedium, maxLines = 1)
                    } else if (singles) {
                        Text("${formatCount(singleCount)} single recordings", style = MaterialTheme.typography.titleMedium, maxLines = 1)
                        TextLink("${formatCount(showCount)} shows", onClick = { singles = false; haptics(Haptic.Selection) })
                    } else {
                        Text("${formatCount(showCount)} shows", style = MaterialTheme.typography.titleMedium, maxLines = 1)
                        TextLink("${formatCount(singleCount)} single recordings", onClick = { singles = true; haptics(Haptic.Selection) })
                    }
                }
            }
            val fieldBlock: @Composable () -> Unit = {
                if (showsSeries && field.genres.isNotEmpty()) {
                    Column {
                        SectionHeading("By decade and genre") {
                            if (field.none > 0) {
                                Text(
                                    "${formatCount(field.none)} with no genre",
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    maxLines = 1,
                                )
                            }
                        }
                        DecadeFieldView(
                            field, genre, decade,
                            onCell = { g, d -> genre = g; decade = d; haptics(Haptic.Selection) },
                            modifier = Modifier.padding(horizontal = Spacing.S4.dp),
                        )
                    }
                }
            }
            BoxWithConstraints(Modifier.fillMaxSize()) {
                val expanded = maxWidth >= 840.dp
                SideEffect { headerItems = if (expanded) 0 else 1 }
                val fieldWidth = 380.dp
                val (cols, tileWidth) = tileLayout(if (expanded) maxWidth - fieldWidth else maxWidth)
                val heights = rememberNameHeights(tiles.map { it.series.name }, innerWidth(tileWidth))
                val grid: @Composable (Modifier, (@Composable () -> Unit)?) -> Unit = { mod, header ->
                    LazyVerticalGrid(
                        columns = GridCells.Fixed(cols),
                        state = gridState,
                        modifier = mod,
                        contentPadding = PaddingValues(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp),
                        horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp),
                        verticalArrangement = Arrangement.spacedBy(Spacing.S2.dp),
                    ) {
                        if (header != null) item(key = "header", span = { GridItemSpan(maxLineSpan) }) { header() }
                        item(key = "heading", span = { GridItemSpan(maxLineSpan) }) {
                            Text(
                                sectionTitle,
                                style = MaterialTheme.typography.headlineSmall,
                                modifier = Modifier.padding(top = Spacing.S2.dp).semantics { heading() },
                            )
                        }
                        if (tiles.isEmpty()) {
                            item(key = "empty", span = { GridItemSpan(maxLineSpan) }) {
                                // The D-pad stays on the chip just pressed; the action is one step down.
                                EmptyMessage(
                                    "Nothing matches these filters.",
                                    action = EmptyAction("Clear filters") {
                                        kind = null; hasScript = false; genre = null; decade = null; network = null
                                        singles = false
                                        haptics(Haptic.Selection)
                                    },
                                    claimTvFocus = false,
                                )
                            }
                        }
                        itemsIndexed(tiles, key = { _, t -> t.key }) { i, t ->
                            val start = i / cols * cols
                            val nameHeight = (start until minOf(start + cols, tiles.size)).maxOf { heights[it] }
                            ShowTile(
                                t.series,
                                onOpen = t.onOpen,
                                width = tileWidth,
                                nameHeight = nameHeight,
                                facts = t.facts,
                                openLabel = t.openLabel,
                            )
                        }
                    }
                }
                if (expanded) {
                    Column(Modifier.fillMaxSize()) {
                        filters()
                        Spacer(Modifier.height(Spacing.S2.dp))
                        countLine()
                        Row(Modifier.fillMaxSize()) {
                            Column(Modifier.width(fieldWidth).verticalScroll(rememberScrollState())) { fieldBlock() }
                            grid(Modifier.weight(1f), null)
                        }
                    }
                } else {
                    grid(Modifier.fillMaxSize()) {
                        // The header spans the grid's own padding, so the chip row scrolls edge to edge.
                        Column(
                            Modifier.layout { m, c ->
                                val pad = Spacing.S4.dp.roundToPx()
                                val w = c.maxWidth + pad * 2
                                val p = m.measure(c.copy(minWidth = w, maxWidth = w))
                                layout(c.maxWidth, p.height) { p.place(-pad, 0) }
                            },
                        ) {
                            filters()
                            Spacer(Modifier.height(Spacing.S2.dp))
                            countLine()
                            fieldBlock()
                        }
                    }
                }
                if (!isTv && letters.size > 1) {
                    LetterRail(letters, jumpTo, Modifier.align(Alignment.CenterEnd))
                }
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
