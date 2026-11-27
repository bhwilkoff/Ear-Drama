package com.example.appname.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.AssistChip
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.example.appname.plays.FindCore
import com.example.appname.plays.PlayCollections
import com.example.appname.plays.PlayLibraryFeed
import com.example.appname.plays.PlayRow
import com.example.appname.plays.PlaySearchModel
import com.example.appname.ui.EmptyAction
import com.example.appname.ui.EmptyMessage
import com.example.appname.ui.LocalAppContainer
import com.example.appname.ui.LocalOnline
import com.example.appname.ui.offlineLine
import kotlinx.coroutines.launch
import com.example.appname.ui.PlayTile
import com.example.appname.ui.TILE_WIDTH_DP
import com.example.appname.ui.formatCount
import com.example.appname.ui.innerWidth
import com.example.appname.ui.playTiles
import com.example.appname.ui.rememberNameHeight
import com.example.appname.ui.theme.OnAir
import com.example.appname.ui.theme.Spacing
import com.example.appname.ui.theme.boardColor
import com.example.appname.ui.theme.onBoardColor
import com.example.appname.ui.tvFocusMark

// Finding a play (B31 §3.1-3.6; ANDROID-DESIGN §4.9a, §4.5): Record's Plays with its search field, the facets as menu chips counted
// against each other, Filters, the ways in as rails whose heading is their rule, the grid under the sort's name, the four states; the
// search's Plays, Characters and Lines; a collection and the scenes for N voices as pushed pages. The rules are FindCore's (the web's
// js/find-core.js); this file only draws them.

// MARK: - The facets

object FindText {
    /** A facet value in its menu: "1-2 voices (27)", "Comedy (214)". */
    fun option(f: FindCore.Facet, o: FindCore.Option): String = "${value(f, o)} (${formatCount(o.count)})"

    private fun value(f: FindCore.Facet, o: FindCore.Option) = if (f.key == "voices") "${o.label} ${if (o.label == "1") "voice" else "voices"}" else o.label

    /** The chip's title: the chosen value's words, else the facet's name. */
    fun chip(f: FindCore.Facet, picked: String?): String {
        val o = f.values.firstOrNull { it.value == picked } ?: return f.label
        return value(f, o)
    }

    fun any(f: FindCore.Facet): String = when (f.key) { "voices" -> "Any number"; "length" -> "Any length"; else -> "Any" }

    fun plays(n: Int): String = if (n == 1) "1 play" else "${formatCount(n)} plays"

    /** The Filters sheet's heading for a facet. */
    fun section(f: FindCore.Facet): String = if (f.key == "era") "Era of the playwright" else f.label
}

/** The four facets a performer asks first (B31 §3.1), in order, and Filters for the rest; each a menu whose values carry their counts against the other picks. */
val FACET_CHIPS = listOf("voices", "length", "form", "era")

/**
 * The facet chips as one sideways row: Clear when anything is chosen, Voices, Length, Form, Era, Sort, then Filters. A value with no
 * plays is not offered unless chosen (no choice yields nothing).
 */
@Composable
fun PlayFacetRow(
    rows: List<PlayRow>,
    facets: List<FindCore.Facet>,
    state: FindCore.State,
    onState: (FindCore.State) -> Unit,
    modifier: Modifier = Modifier,
) {
    val counted = remember(rows, facets, state.picks) { FindCore.counts(rows, facets, state.picks) }
    var filters by remember { mutableStateOf(false) }
    LazyRow(modifier, contentPadding = PaddingValues(horizontal = Spacing.S4.dp), horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
        if (state.isActive) {
            item(key = "clear") {
                AssistChip(onClick = { onState(state.cleared) }, label = { Text("Clear") }, modifier = Modifier.tvFocusMark().semantics { contentDescription = "Clear filters" })
            }
        }
        for (f in counted.filter { it.key in FACET_CHIPS }) {
            item(key = f.key) {
                MenuChip(
                    label = FindText.chip(f, state.picks[f.key]),
                    selected = state.picks[f.key] != null,
                    choices = listOf<Pair<String?, String>>(null to FindText.any(f)) + f.values.map { it.value to FindText.option(f, it) },
                    onChoose = { onState(state.with(f.key, it)) },
                )
            }
        }
        // An order, not a filter: never filled, never cleared.
        item(key = "sort") {
            MenuChip(
                label = "Sort: ${FindCore.sortTitle(state.sort)}",
                selected = false,
                choices = FindCore.SORTS.map { it.first to it.second },
                onChoose = { onState(state.copy(sort = it)) },
            )
        }
        if (facets.any { it.filter }) {
            item(key = "filters") {
                val n = facets.count { it.filter && state.picks[it.key] != null }
                FilterChip(
                    selected = n > 0, onClick = { filters = true }, label = { Text(if (n > 0) "Filters · $n" else "Filters") },
                    modifier = Modifier.tvFocusMark(),
                )
            }
        }
    }
    if (filters) PlayFiltersSheet(rows, facets, state, onDone = { filters = false }, onState = onState)
}

/** Filters (B31 §3.1): every facet, each value with its count against the others, applied with "Show N plays". */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PlayFiltersSheet(rows: List<PlayRow>, facets: List<FindCore.Facet>, state: FindCore.State, onDone: () -> Unit, onState: (FindCore.State) -> Unit) {
    var pending by remember { mutableStateOf(state.picks) }
    val counted = remember(rows, facets, pending) { FindCore.counts(rows, facets, pending) }
    val n = remember(rows, facets, pending) { FindCore.filter(rows, facets, pending).size }
    ModalBottomSheet(onDismissRequest = onDone, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        PlayFiltersBody(
            counted, pending, n,
            onToggle = { key, value -> pending = if (pending[key] == value) pending - key else pending + (key to value) },
            onClear = { pending = emptyMap() },
            onShow = { onState(state.copy(picks = pending)); onDone() },
        )
    }
}

/** The sheet's contents: a section per facet with its values counted against the others, Clear filters, and Show N plays. */
@Composable
fun PlayFiltersBody(
    counted: List<FindCore.Facet>,
    pending: Map<String, String>,
    n: Int,
    onToggle: (String, String) -> Unit,
    onClear: () -> Unit,
    onShow: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier.fillMaxWidth()) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = Spacing.S4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text("Filters", style = MaterialTheme.typography.headlineSmall, modifier = Modifier.semantics { heading() })
            TextButton(onClick = onClear, enabled = pending.isNotEmpty()) { Text("Clear filters") }
        }
        LazyColumn(Modifier.weight(1f, fill = false)) {
            for (f in counted.filter { it.values.isNotEmpty() }) {
                item(key = "h:${f.key}") {
                    Text(FindText.section(f), style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp))
                }
                items(f.values, key = { "v:${f.key}:${it.value}" }) { o ->
                    val on = pending[f.key] == o.value
                    Row(
                        Modifier.fillMaxWidth().heightIn(min = 48.dp)
                            .clickable(onClickLabel = if (on) "Remove ${o.label}" else "Choose ${o.label}") { onToggle(f.key, o.value) }
                            .padding(horizontal = Spacing.S4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(o.label, Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
                        Text(formatCount(o.count), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Box(Modifier.width(32.dp), contentAlignment = Alignment.Center) {
                            if (on) Icon(Icons.Filled.Check, contentDescription = "Chosen")
                        }
                    }
                }
            }
        }
        Row(Modifier.fillMaxWidth().padding(Spacing.S4.dp), horizontalArrangement = Arrangement.End) {
            androidx.compose.material3.Button(onClick = onShow) { Text("Show ${FindText.plays(n)}") }
        }
    }
}

// MARK: - The ways in

/** A way in (B31 §3.2): its rule as the heading, its count beside it, All when it holds more, and its plays or scenes as a rail that scrolls sideways. */
@Composable
fun PlayRailSection(
    rail: FindCore.Rail,
    onOpenScript: (String) -> Unit,
    onReadAt: (String, String?) -> Unit,
    onRead: ((String) -> Unit)?,
    onAll: () -> Unit,
) {
    Column(Modifier.fillMaxWidth()) {
        Row(Modifier.fillMaxWidth().padding(end = Spacing.S2.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(
                rail.title, style = MaterialTheme.typography.headlineSmall,
                modifier = Modifier.weight(1f).padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp).semantics { heading() },
            )
            Text(formatCount(rail.count), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            TextButton(onClick = onAll, modifier = Modifier.tvFocusMark().semantics { contentDescription = "All ${rail.title}" }) { Text("All") }
        }
        rail.by?.let { Text(it, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(horizontal = Spacing.S4.dp)) }
        if (rail.kind == FindCore.RailKind.Scenes) {
            LazyRow(contentPadding = PaddingValues(horizontal = Spacing.S4.dp, vertical = Spacing.S1.dp), horizontalArrangement = Arrangement.spacedBy(Spacing.S3.dp)) {
                items(rail.scenes, key = { it.id }) { SceneCard(it, onClick = { onReadAt(it.row.id, it.scene.line) }) }
            }
        } else {
            PlayShelf(rail.plays, onOpenScript, onRead)
        }
    }
}

/** A shelf of play tiles in one row; the names share the tallest name's height. */
@Composable
fun PlayShelf(plays: List<PlayRow>, onOpen: (String) -> Unit, onRead: ((String) -> Unit)?, modifier: Modifier = Modifier, width: Dp = TILE_WIDTH_DP.dp) {
    val nameHeight = rememberNameHeight(plays.map { it.title }, innerWidth(width))
    LazyRow(modifier, contentPadding = PaddingValues(horizontal = Spacing.S4.dp), horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
        items(plays, key = { "p:" + it.id }) { r ->
            PlayTile(r, onOpen = { onOpen(r.id) }, width = width, nameHeight = nameHeight, onRead = onRead?.let { f -> { f(r.id) } })
        }
    }
}

/**
 * A scene for N voices (B31 §3.4): its heading as printed and its minutes, the play (not on the play's own page), the parts' names, on
 * the play's board. It opens the reader at the scene's first line. Not on a TV.
 */
@Composable
fun SceneCard(hit: FindCore.SceneHit, modifier: Modifier = Modifier, inPlay: Boolean = false, onClick: () -> Unit) {
    val dark = OnAir.colors.dark
    val ink = onBoardColor(hit.row.hue, dark)
    val s = hit.scene
    val kick = listOfNotNull(s.heading, if (s.minutes > 0) "${s.minutes} min" else null).joinToString(" · ")
    val spoken = listOfNotNull(if (inPlay) null else hit.row.title, s.heading, if (s.minutes > 0) "${s.minutes} min" else null, FindCore.names(s.parts)).joinToString(", ")
    Column(
        modifier
            .width(200.dp)
            .heightIn(min = if (inPlay) 72.dp else 104.dp)
            .clip(RoundedCornerShape(12.dp))
            .background(boardColor(hit.row.hue, dark))
            .tvFocusMark()
            .clickable(onClickLabel = "Open the reader at this scene", onClick = onClick)
            .padding(Spacing.S3.dp)
            .semantics(mergeDescendants = true) { contentDescription = spoken },
        verticalArrangement = Arrangement.spacedBy(Spacing.S1.dp),
    ) {
        if (kick.isNotEmpty()) Text(kick, style = MaterialTheme.typography.labelMedium, color = ink.copy(alpha = 0.8f))
        if (!inPlay) Text(hit.row.title, style = MaterialTheme.typography.titleMedium, color = ink, maxLines = 2, overflow = TextOverflow.Ellipsis)
        Text(FindCore.names(s.parts), style = MaterialTheme.typography.labelMedium, color = ink, maxLines = 2, overflow = TextOverflow.Ellipsis)
    }
}

// MARK: - A collection, the scenes for N voices

/** A collection whole (B31 §3.2): its title, the editor's credit and note when it has them, its plays in its own order. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PlayCollectionScreen(id: String, onBack: () -> Unit, onOpenScript: (String) -> Unit, onRead: ((String) -> Unit)?) {
    val plays = LocalAppContainer.current.plays
    val rows by plays.rows.collectAsState()
    val ready = rows as? PlayLibraryFeed.Rows.Ready
    // null while the file is being read, then its answer (an empty `PlayCollections` for a library with none).
    val collections by produceState<PlayCollections?>(null, ready?.published) {
        plays.loadRows()
        value = if (ready == null) null else plays.feed.collections() ?: PlayCollections()
    }
    val found = remember(ready, collections, id) { ready?.let { FindCore.collection(it.rows, collections, id) } }
    Scaffold(topBar = { BackBar(onBack, found?.first?.title ?: "Plays") }) { padding ->
        when {
            found != null -> {
                val list = found.second
                BoxWithTiles(padding) { cols, width ->
                    LazyVerticalGrid(GridCells.Fixed(cols), Modifier.fillMaxSize(), contentPadding = PaddingValues(Spacing.S4.dp), horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
                        found.first.by?.let { by -> item(span = { androidx.compose.foundation.lazy.grid.GridItemSpan(maxLineSpan) }) { Text(by, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) } }
                        found.first.note?.let { note -> item(span = { androidx.compose.foundation.lazy.grid.GridItemSpan(maxLineSpan) }) { Text(note, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(vertical = Spacing.S2.dp)) } }
                        item(span = { androidx.compose.foundation.lazy.grid.GridItemSpan(maxLineSpan) }) {
                            Text(FindText.plays(list.size), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(bottom = Spacing.S2.dp))
                        }
                        playTiles(list, cols, width, onOpen = { onOpenScript(it.id) }, onRead = onRead?.let { r -> { p -> r(p.id) } })
                    }
                }
            }
            rows is PlayLibraryFeed.Rows.Loading || (ready?.published == true && collections == null) ->
                Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) { CircularProgressIndicator(Modifier.semantics { contentDescription = "Loading" }) }
            else -> EmptyMessage("This collection is not in the library.", Modifier.padding(padding))
        }
    }
}

/** Every scene for N voices (B31 §3.4), one per play, plays A to Z. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PlayScenesScreen(voices: Int, onBack: () -> Unit, onReadAt: (String, String?) -> Unit) {
    val plays = LocalAppContainer.current.plays
    val rows by plays.rows.collectAsState()
    androidx.compose.runtime.LaunchedEffect(Unit) { plays.loadRows() }
    val all = remember(rows, voices) { (rows as? PlayLibraryFeed.Rows.Ready)?.let { FindCore.sceneRows(it.rows, voices) }.orEmpty() }
    val title = "Scenes for ${listOf("", "", "two", "three", "four").getOrElse(voices) { voices.toString() }} voices"
    Scaffold(topBar = { BackBar(onBack, title) }) { padding ->
        if (all.isEmpty() && rows !is PlayLibraryFeed.Rows.Loading) {
            EmptyMessage("No scenes for $voices voices yet.", Modifier.padding(padding))
        } else {
            LazyVerticalGrid(GridCells.Adaptive(200.dp), Modifier.fillMaxSize().padding(padding), contentPadding = PaddingValues(Spacing.S4.dp),
                horizontalArrangement = Arrangement.spacedBy(Spacing.S3.dp), verticalArrangement = Arrangement.spacedBy(Spacing.S3.dp)) {
                items(all.size, key = { all[it].id }) { i -> SceneCard(all[i], onClick = { onReadAt(all[i].row.id, all[i].scene.line) }) }
            }
        }
    }
}

@Composable
private fun BoxWithTiles(padding: PaddingValues, content: @Composable (Int, Dp) -> Unit) {
    androidx.compose.foundation.layout.BoxWithConstraints(Modifier.fillMaxSize().padding(padding)) {
        val (cols, width) = com.example.appname.ui.tileLayout(maxWidth)
        content(cols, width)
    }
}

// MARK: - A play's page: its neighbors (B31 §3.5)

/**
 * Under a library play's parts: its scenes for two voices, then Same voices and length (the rule as the heading: within one voice and 15
 * minutes), then More by the author's surname (All when the catalog publishes the author's collection). A section with nothing is absent.
 */
@Composable
fun PlayNeighbors(
    row: PlayRow,
    television: Boolean,
    onOpenScript: (String) -> Unit,
    onReadAt: (String, String?) -> Unit,
    onCollection: (String) -> Unit,
) {
    val plays = LocalAppContainer.current.plays
    val all by plays.rows.collectAsState()
    val rows = (all as? PlayLibraryFeed.Rows.Ready)?.rows.orEmpty()
    val collections by produceState<PlayCollections?>(null, rows.isNotEmpty()) { value = if (rows.isEmpty()) null else runCatching { plays.feed.collections() }.getOrNull() }
    PlayNeighbors(row, rows, collections, television, onOpenScript, onReadAt, onCollection)
}

/** The same over the library's rows and collections it was given. */
@Composable
fun PlayNeighbors(
    row: PlayRow,
    rows: List<PlayRow>,
    collections: PlayCollections?,
    television: Boolean,
    onOpenScript: (String) -> Unit,
    onReadAt: (String, String?) -> Unit,
    onCollection: (String) -> Unit,
) {
    val scenes = remember(row) { if (television) emptyList() else row.scenes.filter { it.voices == 2 && it.line.isNotEmpty() } }
    val same = remember(rows, row) { FindCore.sameShape(rows, row) }
    val by = remember(rows, collections, row) { FindCore.byAuthor(rows, collections, row) }
    val read: ((String) -> Unit)? = if (television) null else { id -> onReadAt(id, null) }
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.S1.dp)) {
        if (scenes.isNotEmpty()) {
            com.example.appname.ui.SectionHeader("Scenes for two voices")
            LazyRow(contentPadding = PaddingValues(horizontal = Spacing.S4.dp), horizontalArrangement = Arrangement.spacedBy(Spacing.S3.dp)) {
                items(scenes, key = { it.line }) { s -> SceneCard(FindCore.SceneHit(row, s), inPlay = true, onClick = { onReadAt(row.id, s.line) }) }
            }
        }
        if (same.isNotEmpty()) {
            com.example.appname.ui.SectionHeader("Same voices and length")
            PlayShelf(same, onOpenScript, read)
        }
        if (by.plays.isNotEmpty()) {
            val surname = com.example.appname.data.LabelMath.surnameOf(row.firstAuthor)
            val name = if (surname.isEmpty()) "the author" else surname.take(1) + surname.drop(1).lowercase()
            Row(Modifier.fillMaxWidth().padding(end = Spacing.S2.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("More by $name", style = MaterialTheme.typography.headlineSmall, modifier = Modifier.weight(1f).padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp).semantics { heading() })
                val id = by.id
                if (id != null && by.total > by.plays.size) TextButton(onClick = { onCollection(id) }, modifier = Modifier.tvFocusMark()) { Text("All") }
            }
            PlayShelf(by.plays, onOpenScript, read)
        }
    }
}

// MARK: - Search (B31 §3.3)

/**
 * The search's play sections (B31 §3.3, ANDROID-DESIGN §4.5): Plays (title and author), Characters, Lines (the words in order before
 * scattered words), each absent when empty; More lines reads the next scripts. The caller runs the search ([PlaySearchModel.run])
 * from the page, once per query: a section that composes never starts it.
 */
@Composable
fun PlaySearchSections(
    query: String,
    model: PlaySearchModel,
    onOpenScript: (String) -> Unit,
    onReadAt: (String, String?) -> Unit,
    onMore: () -> Unit,
    offersAdd: Boolean = false,
    onAdd: () -> Unit = {},
    /** Record's search says "No plays match" itself; the Search tab says it once for every kind. */
    emptyLine: Boolean = true,
) {
    val s by model.state.collectAsState()
    val q = query.trim()
    Column(Modifier.fillMaxWidth()) {
        if (s.query != q || s.phase == PlaySearchModel.Phase.Loading) {
            Box(Modifier.fillMaxWidth().heightIn(min = 96.dp), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(Modifier.semantics { contentDescription = "Loading" })
            }
            return@Column
        }
        if (s.titled.isNotEmpty()) {
            com.example.appname.ui.SectionHeader("Plays")
            s.titled.take(30).forEach { r -> PlayListItem(r, onOpen = { onOpenScript(r.id) }) }
        }
        if (s.characters.isNotEmpty()) {
            com.example.appname.ui.SectionHeader("Characters")
            s.characters.forEach { h ->
                val n = h.lines
                PlayListItem(h.row, onOpen = { onOpenScript(h.row.id) }, sub = listOf(FindCore.titleCase(h.role), if (n == 1) "1 line" else "${formatCount(n)} lines", h.row.firstAuthor.ifEmpty { null }))
            }
        }
        if (s.shown.isNotEmpty() || (s.reading && !s.foundAny)) {
            com.example.appname.ui.SectionHeader("Lines")
            s.shown.forEach { h ->
                PlayListItem(h.row, onOpen = { onReadAt(h.row.id, h.line) }, sub = listOf(h.role.ifEmpty { null }, h.row.firstAuthor.ifEmpty { null }),
                    quote = FindCore.snippet(h.text, q), openLabel = "Open the reader at this line")
            }
            if (s.reading) {
                Box(Modifier.fillMaxWidth().heightIn(min = 64.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator(Modifier.semantics { contentDescription = "Loading" }) }
            } else if (s.left > 0) {
                MoreLines(s.left, onMore)
            }
        } else if (s.left > 0 && !s.reading) {
            MoreLines(s.left, onMore)
        }
        if (emptyLine && !s.foundAny && !s.reading && s.left <= 0) {
            EmptyMessage(
                "No plays match “$q”.", action = if (offersAdd) EmptyAction("Add a script", onAdd) else null, claimTvFocus = false,
            )
        }
    }
}

@Composable
private fun MoreLines(left: Int, onMore: () -> Unit) {
    OutlinedButton(onClick = onMore, modifier = Modifier.padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp).tvFocusMark()) {
        Text("More lines (${FindText.plays(left)})")
    }
}

// MARK: - The TV's Plays scope (B31 §3.7)

/**
 * Browse's Plays scope on a TV: the data shelves (and the editor's) as focus shelves at the TV tile, each heading its rule and count; no
 * facets, no search, no scenes and no record door, since a TV records nothing. A play opens its page. The four states: a spinner, "This
 * did not load." with Try again (offline: "You are offline."), "No plays yet.".
 */
@Composable
fun PlaysScopeTv(onOpenScript: (String) -> Unit, modifier: Modifier = Modifier) {
    val container = LocalAppContainer.current
    val state = rememberPlayRows()
    val ready = state as? PlayLibraryFeed.Rows.Ready
    val collections by produceState<PlayCollections?>(null, ready?.published) { value = if (ready?.published == true) container.plays.feed.collections() else null }
    val rails = remember(ready, collections) {
        ready?.let { FindCore.rails(it.rows, collections, per = 16, withScenes = false, ids = FindCore.tvIds(collections)) }.orEmpty()
    }
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    Box(modifier.fillMaxSize()) {
        when {
            state is PlayLibraryFeed.Rows.Loading -> RowSpinner()
            state is PlayLibraryFeed.Rows.Unavailable -> RowProblem(
                offlineLine(LocalOnline.current) ?: "This did not load.",
                onRetry = { scope.launch { container.plays.feed.retry(); container.plays.loadRows() } },
            )
            ready != null && rails.isEmpty() -> EmptyMessage("No plays yet.", claimTvFocus = false)
            else -> PlayShelvesTv(rails, onOpenScript)
        }
    }
}

/** The TV's shelves: each its rule and count over a focus row of tiles. */
@Composable
fun PlayShelvesTv(rails: List<FindCore.Rail>, onOpenScript: (String) -> Unit, modifier: Modifier = Modifier) {
    LazyColumn(modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
        items(rails, key = { it.id }) { rail ->
            Column {
                Row(Modifier.fillMaxWidth().padding(end = Spacing.S4.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        rail.title, style = MaterialTheme.typography.headlineSmall,
                        modifier = Modifier.weight(1f).padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp).semantics { heading() },
                    )
                    Text(formatCount(rail.count), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                PlayShelf(rail.plays, onOpenScript, null, width = 200.dp)
            }
        }
    }
}
