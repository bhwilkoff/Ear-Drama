package com.example.appname.ui.screens

import androidx.core.content.edit
import android.content.Context
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.example.appname.ui.LoadableContent
import com.example.appname.data.EpisodeRow
import com.example.appname.data.Progress
import com.example.appname.plays.ClassRow
import com.example.appname.plays.MarksDatabase
import com.example.appname.plays.PlaysShare
import com.example.appname.plays.SharedPlays
import com.example.appname.ui.EmptyMessage
import com.example.appname.ui.EpisodeListItem
import com.example.appname.ui.LocalAppContainer
import com.example.appname.ui.LocalIsTelevision
import com.example.appname.ui.QueueRow
import com.example.appname.ui.SectionHeader
import com.example.appname.ui.formatClock
import com.example.appname.ui.rememberCatalogQuery
import com.example.appname.ui.theme.Spacing
import com.example.appname.ui.tvFocusMark

/** Library's pure shaping (owner 2026-11-23, direction B): what the sides list, merged and grouped. */
object LibraryModel {
    const val PREFS = "ed.library"
    const val SIDE_KEY = "ed.library.side"
    const val LISTENING = "listening"
    const val MAKING = "making"
    const val PREVIEW = 5

    /** The remembered side; Listening for a new person and for anything unreadable. */
    fun side(stored: String?): String = if (stored == MAKING) MAKING else LISTENING

    /** One Up next row: a started episode with its progress, or a queued one. */
    class Up(val row: EpisodeRow, val progress: Progress?)

    /** Started episodes first, then the queue in the person's order; an episode in both shows once, as started. */
    fun upNext(inProgress: List<Pair<EpisodeRow, Progress>>, queued: List<EpisodeRow>): List<Up> {
        val started = inProgress.map { Up(it.first, it.second) }
        val seen = started.map { it.row.id }.toSet()
        return started + queued.filter { it.id !in seen }.distinctBy { it.id }.map { Up(it, null) }
    }

    /** One play's productions: a row each in Library, never one row per production. */
    class Group(val scriptId: String, val title: String, val rows: List<PlaysShare.LibraryRow>) {
        val count: Int get() = rows.size
        val newest: PlaysShare.LibraryRow get() = rows.first()
        val state: String
            get() = newest.local?.let { if (it.isFinished) "Finished" else "In progress" } ?: "Shared"

        /** "Finished" for one; "9 productions · newest finished" for several. */
        val line: String
            get() = if (count == 1) state else "$count productions · newest ${state.lowercase()}"
    }

    /** [rows] arrive newest first (PlaysShare.libraryRows); groups keep the order of their newest row. */
    fun groups(rows: List<PlaysShare.LibraryRow>): List<Group> {
        fun scriptOf(r: PlaysShare.LibraryRow): String =
            r.local?.scriptID?.takeIf { it.isNotBlank() } ?: r.remote?.scriptId?.takeIf { it.isNotBlank() } ?: (r.local?.id ?: r.pid ?: "")
        fun titleOf(r: PlaysShare.LibraryRow): String = r.local?.title ?: r.remote?.title ?: ""
        return rows.groupBy(::scriptOf).map { (id, rs) -> Group(id, titleOf(rs.first()), rs) }
    }
}

/** The side this device last showed (`ed.library.side`). */
@Composable
fun rememberLibrarySide(): Pair<String, (String) -> Unit> {
    val context = LocalContext.current
    val prefs = remember { context.getSharedPreferences(LibraryModel.PREFS, Context.MODE_PRIVATE) }
    var side by remember { mutableStateOf(LibraryModel.side(runCatching { prefs.getString(LibraryModel.SIDE_KEY, null) }.getOrNull())) }
    val choose: (String) -> Unit = { next ->
        side = next
        runCatching { prefs.edit { putString(LibraryModel.SIDE_KEY, next) } }
    }
    return side to choose
}

@Composable
fun LibrarySideSwitch(side: String, onSide: (String) -> Unit) {
    val choices = listOf(LibraryModel.LISTENING to "Listening", LibraryModel.MAKING to "Making")
    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp)) {
        choices.forEachIndexed { i, (key, label) ->
            SegmentedButton(
                selected = side == key,
                onClick = { onSide(key) },
                shape = SegmentedButtonDefaults.itemShape(i, choices.size),
            ) { Text(label) }
        }
    }
}

/** One line that opens a full list: its name, its count. */
@Composable
fun CountLine(label: String, count: String, onOpen: () -> Unit) {
    ListItem(
        modifier = Modifier.fillMaxWidth().tvFocusMark().clickable(onClickLabel = "Open $label", onClick = onOpen),
        headlineContent = { Text(label) },
        trailingContent = { Text(count, style = MaterialTheme.typography.labelMedium) },
    )
}

/** Up next: five rows, then "All N" (owner 2026-11-23). Started episodes show their progress; queued ones swipe away. */
fun LazyListScope.upNextItems(up: List<LibraryModel.Up>, onOpenEpisode: (String) -> Unit, onAll: () -> Unit): Int {
    if (up.isEmpty()) return 0
    item(key = "upnext-h") { SectionHeader("Up next") }
    items(up.take(LibraryModel.PREVIEW), key = { "u:" + it.row.id }) { u -> UpNextRow(u, onOpenEpisode) }
    if (up.size > LibraryModel.PREVIEW) {
        item(key = "upnext-all") { CountLine("All ${up.size}", "", onAll) }
    }
    return 1 + minOf(up.size, LibraryModel.PREVIEW) + if (up.size > LibraryModel.PREVIEW) 1 else 0
}

@Composable
private fun UpNextRow(u: LibraryModel.Up, onOpenEpisode: (String) -> Unit) {
    val container = LocalAppContainer.current
    if (u.progress != null) {
        EpisodeListItem(
            u.row,
            showSeries = true,
            onOpen = { onOpenEpisode(u.row.id) },
            onPlay = { container.playback.play(u.row) },
            supporting = "${formatClock(u.progress.positionMs)} of ${formatClock(u.progress.durationMs)}",
        )
    } else {
        QueueRow(u.row, onOpenEpisode) { container.playback.play(it) }
    }
}

const val LIST_UP = "upnext"
const val LIST_HISTORY = "history"

/** A full list from Library: every Up next row, or every finished episode. */
@Composable
fun LibraryListScreen(kind: String, onBack: () -> Unit, onOpenEpisode: (String) -> Unit) {
    val container = LocalAppContainer.current
    val upKind = kind == LIST_UP
    val data by rememberCatalogQuery(watchUser = true) { db ->
        if (upKind) {
            val progress = container.user.inProgress(limit = 100)
            val byId = progress.associateBy { it.episodeId }
            val inProgress = db.episodes(progress.map { it.episodeId }).mapNotNull { row -> byId[row.id]?.let { row to it } }.distinctBy { it.first.id }
            val queued = db.episodes(container.user.queue()).distinctBy { it.id }
            LibraryModel.upNext(inProgress, queued) to emptyList<EpisodeRow>()
        } else {
            emptyList<LibraryModel.Up>() to db.episodes(container.user.finished().map { it.episodeId }).distinctBy { it.id }
        }
    }
    Scaffold(topBar = { BackBar(onBack, if (upKind) "Up next" else "History") }) { padding ->
        LoadableContent(data, Modifier.padding(padding)) { (up, finished) ->
            LazyColumn(Modifier.fillMaxSize()) {
                items(up, key = { "u:" + it.row.id }) { u -> UpNextRow(u, onOpenEpisode) }
                items(finished, key = { "f:" + it.id }) { row ->
                    EpisodeListItem(row, showSeries = true, onOpen = { onOpenEpisode(row.id) }, onPlay = { container.playback.play(row) })
                }
            }
        }
    }
}

/** The Making side: Waiting on you, Productions grouped by play, Marks, Classes. Nothing empty is drawn. */
fun LazyListScope.makingItems(
    groups: List<LibraryModel.Group>,
    waiting: List<SharedPlays.OpenPart>,
    marksIn: Int,
    classes: List<ClassRow>,
    onOpenProduction: (String) -> Unit,
    onOpenPlay: (String) -> Unit,
    onOpenClass: (String) -> Unit,
): Int {
    if (waiting.isNotEmpty()) {
        item(key = "waiting-h") { SectionHeader("Waiting on you") }
        items(waiting, key = { "w:" + it.row.id }) { p ->
            RemoteProductionRow(p.row, onOpenProduction, detail = if (p.open == 1) "1 open part" else "${p.open} open parts")
        }
    }
    if (groups.isNotEmpty()) {
        item(key = "productions-h") { SectionHeader("Productions") }
        items(groups, key = { "g:" + it.scriptId }) { g ->
            if (g.count == 1) {
                val production = g.newest.local
                val remote = g.newest.remote
                if (production != null) ProductionRow(production, onOpen = { onOpenProduction(production.id) })
                else if (remote != null) RemoteProductionRow(remote, onOpenProduction)
            } else {
                ListItem(
                    modifier = Modifier.fillMaxWidth().clickable(onClickLabel = "Open ${g.title} productions") { onOpenPlay(g.scriptId) },
                    headlineContent = { Text(g.title, style = MaterialTheme.typography.titleMedium) },
                    supportingContent = { Text(g.line, style = MaterialTheme.typography.labelMedium) },
                )
            }
        }
    }
    if (marksIn > 0) {
        item(key = "marks") {
            ListItem(
                headlineContent = { Text("Marks") },
                trailingContent = { Text(if (marksIn == 1) "In 1 script" else "In $marksIn scripts", style = MaterialTheme.typography.labelMedium) },
            )
        }
    }
    if (classes.isNotEmpty()) {
        item(key = "classes-h") { SectionHeader("Classes") }
        items(classes, key = { "c:" + it.id }) { c ->
            val lines = listOfNotNull(
                c.code?.let { PlaysShare.classCodeDisplay(it) },
                "Waits for the school's consent".takeIf { c.under13 && c.code != null && !c.schoolConsent },
            )
            ClassItemContent(c, lines, if (c.code != null) Modifier.clickable { onOpenClass(c.id) } else Modifier)
        }
    }
    return (if (waiting.isEmpty()) 0 else 1 + waiting.size) + (if (groups.isEmpty()) 0 else 1 + groups.size) +
        (if (marksIn > 0) 1 else 0) + (if (classes.isEmpty()) 0 else 1 + classes.size)
}

/** How many scripts hold a mark on this device. */
@Composable
fun rememberMarkedScripts(): Int {
    val context = LocalContext.current
    val n by produceState(0) {
        value = runCatching { MarksDatabase.get(context).marks().all().map { it.scriptId }.distinct().size }.getOrDefault(0)
    }
    return n
}

/** Make a class and Join a class: a door on Record, not Library (owner 2026-11-23). Signed in, not a TV. */
@Composable
fun ClassDoors() {
    val container = LocalAppContainer.current
    val account by container.accounts.account.collectAsState()
    if (account == null || LocalIsTelevision.current) return
    var making by remember { mutableStateOf(false) }
    var joining by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    Row(Modifier.padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp), horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
        OutlinedButton(onClick = { making = true }) { Text("Make a class") }
        OutlinedButton(onClick = { joining = true }) { Text("Join a class") }
    }
    ClassDialogs(making, joining, { making = false }, { joining = false }, scope)
}

/** A play's productions, opened from Productions' one row per play. */
@Composable
fun PlayProductionsScreen(scriptId: String, onBack: () -> Unit, onOpenProduction: (String) -> Unit) {
    val container = LocalAppContainer.current
    val productions by container.plays.store.productions.collectAsState()
    val remote by container.sharing.remote.collectAsState()
    val rows = remember(productions, remote, scriptId) {
        LibraryModel.groups(PlaysShare.libraryRows(container.plays.store, remote)).firstOrNull { it.scriptId == scriptId }?.rows.orEmpty()
    }
    Scaffold(topBar = { BackBar(onBack, rows.firstOrNull()?.let { it.local?.title ?: it.remote?.title } ?: "") }) { padding ->
        if (rows.isEmpty()) {
            EmptyMessage("No productions of this play.", Modifier.padding(padding))
            return@Scaffold
        }
        LazyColumn(Modifier.fillMaxSize(), contentPadding = padding) {
            items(rows, key = { "p:" + (it.local?.id ?: it.pid) }) { row ->
                val production = row.local
                val shared = row.remote
                if (production != null) ProductionRow(production, onOpen = { onOpenProduction(production.id) })
                else if (shared != null) RemoteProductionRow(shared, onOpenProduction)
            }
        }
    }
}

/** A foot row that opens its content in place. */
@Composable
fun DisclosureRow(label: String, state: String?, open: Boolean, onToggle: () -> Unit) {
    ListItem(
        modifier = Modifier.fillMaxWidth().tvFocusMark().clickable(onClickLabel = if (open) "Hide $label" else "Show $label", onClick = onToggle),
        headlineContent = { Text(label) },
        supportingContent = if (state != null && !open) ({ Text(state) }) else null,
        trailingContent = { Icon(if (open) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore, contentDescription = null) },
    )
}
