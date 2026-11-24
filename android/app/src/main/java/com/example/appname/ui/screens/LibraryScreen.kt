package com.example.appname.ui.screens

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.TextButton
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import kotlinx.coroutines.launch
import com.example.appname.ui.ShowShelf
import com.example.appname.ui.SectionCaption
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Tv
import androidx.compose.material.icons.outlined.Info
import com.example.appname.ui.tvFocusMark
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import com.example.appname.ui.ClaimTvFocus
import androidx.compose.ui.Modifier
import com.example.appname.data.EpisodeRow
import com.example.appname.data.Progress
import com.example.appname.data.SeriesRow
import com.example.appname.data.resolveFollowing
import com.example.appname.ui.ListenTogetherRow
import com.example.appname.ui.SeriesListItem
import com.example.appname.plays.PlaysShare
import com.example.appname.ui.screens.voicesItems
import com.example.appname.ui.screens.rememberVoicesState
import com.example.appname.ui.AccountRow
import com.example.appname.ui.ExportRow
import com.example.appname.ui.EmptyAction
import com.example.appname.ui.EmptyMessage
import com.example.appname.ui.EpisodeListItem
import com.example.appname.ui.LoadableContent
import com.example.appname.ui.LocalAppContainer
import com.example.appname.ui.LocalIsTelevision
import com.example.appname.ui.SectionHeader
import com.example.appname.ui.siteLinksItem
import com.example.appname.ui.downloadsSection
import com.example.appname.ui.queueSection
import com.example.appname.ui.formatClock
import com.example.appname.ui.rememberCatalogQuery

private data class LibraryLists(
    val queued: List<EpisodeRow>,
    val inProgress: List<Pair<EpisodeRow, Progress>>,
    val finished: List<EpisodeRow>,
    val following: List<SeriesRow>,
)

/** Library: what the listener started, downloaded, played to the end, follows, and recorded (§4.6). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LibraryScreen(
    onOpenEpisode: (String) -> Unit,
    onOpenSeries: (String) -> Unit,
    onOpenProduction: (String) -> Unit,
    onListenTogether: () -> Unit,
    onOpenDownloads: () -> Unit,
    /** Moves each time Better voices asks for the Voices section. */
    voicesRequest: Int = 0,
    onBrowse: () -> Unit,
    onRecord: () -> Unit = {},
    onOpenList: (String) -> Unit = {},
    onOpenPlay: (String) -> Unit = {},
    onOpenClass: (String) -> Unit = {},
) {
    val container = LocalAppContainer.current
    val allProductions by container.plays.store.productions.collectAsState()
    // A TV records nothing (PLAYS-DESIGN §2), so it lists no ear dramas.
    val television = LocalIsTelevision.current
    val productions = if (television) emptyList() else allProductions
    val sharing = container.sharing
    val account by container.accounts.account.collectAsState()
    val signedIn = account != null
    val links by sharing.links.collectAsState()
    val remote by sharing.remote.collectAsState()
    // Shared productions and classes are the Worker's; a TV plays back only (PLAYS-DESIGN §11.7).
    LaunchedEffect(account?.userId, television) {
        if (television) return@LaunchedEffect
        if (account == null) {
            sharing.forget()
        } else {
            runCatching { sharing.loadRemote() }
            runCatching { sharing.loadClasses() }
        }
    }
    val dramaRows = remember(productions, links, remote, television) {
        if (television) emptyList() else PlaysShare.libraryRows(container.plays.store, remote)
    }
    val withClasses = signedIn && !television
    val lists by rememberCatalogQuery(watchUser = true) { db ->
        val progress = container.user.inProgress(limit = 100)
        val byId = progress.associateBy { it.episodeId }
        LibraryLists(
            queued = db.episodes(container.user.queue()).distinctBy { it.id },
            inProgress = db.episodes(progress.map { it.episodeId }).mapNotNull { row ->
                byId[row.id]?.let { row to it }
            }.distinctBy { it.first.id },
            finished = db.episodes(container.user.finished().map { it.episodeId }).distinctBy { it.id },
            // A followed series this catalog does not serve is kept for sync and not listed.
            following = resolveFollowing(container.user.followed()) { db.series(it) },
        )
    }
    val emptied = com.example.appname.navigation.LibraryDoor.empty
    val storedDownloads by container.downloads.records.collectAsState()
    val downloadRecords = if (emptied) emptyMap() else storedDownloads
    var unfollowing by remember { mutableStateOf<SeriesRow?>(null) }
    // Voices is a section of Library (Decision 086); a TV has none.
    val voices = if (LocalIsTelevision.current) null else rememberVoicesState()
    val listState = androidx.compose.foundation.lazy.rememberLazyListState()
    val scope = rememberCoroutineScope()
    unfollowing?.let { row ->
        AlertDialog(
            onDismissRequest = { unfollowing = null },
            title = { Text("Unfollow ${row.name}?") },
            confirmButton = {
                TextButton(onClick = {
                    scope.launch { container.user.setFollowing(row.key, false) }
                    unfollowing = null
                }) { Text("Unfollow") }
            },
            dismissButton = { TextButton(onClick = { unfollowing = null }) { Text("Cancel") } },
        )
    }
    val (storedSide, setSide) = rememberLibrarySide()
    // A TV has no Making side (owner 2026-11-23): its Library is Listening and the foot.
    val side = if (television) LibraryModel.LISTENING else storedSide
    val groups = remember(dramaRows, emptied) { if (emptied) emptyList() else LibraryModel.groups(dramaRows) }
    val classes by sharing.classes.collectAsState()
    val classRows = if (withClasses && !emptied) classes?.let { it.teaching + it.memberOf }.orEmpty() else emptyList()
    val waiting by produceState(emptyList<com.example.appname.plays.SharedPlays.OpenPart>(), account?.userId, television) {
        value = if (account == null || television || emptied) emptyList() else runCatching { sharing.openParts() }.getOrDefault(emptyList())
    }
    val storedMarks = if (television) 0 else rememberMarkedScripts()
    val marksIn = if (emptied) 0 else storedMarks
    var voicesOpen by rememberSaveable { mutableStateOf(false) }
    var aboutOpen by rememberSaveable { mutableStateOf(false) }
    val voicesAt = remember { intArrayOf(0) }
    LaunchedEffect(voicesRequest) {
        if (voicesRequest > 0) {
            voicesOpen = true
            listState.animateScrollToItem(voicesAt[0])
        }
    }
    val bar = TopAppBarDefaults.enterAlwaysScrollBehavior()
    Scaffold(modifier = Modifier.nestedScroll(bar.nestedScrollConnection), topBar = { TopAppBar(title = { Text("Library") }, scrollBehavior = bar) }) { padding ->
        LoadableContent(lists, Modifier.padding(padding)) { stored ->
            val library = if (emptied) LibraryLists(emptyList(), emptyList(), emptyList(), emptyList()) else stored
            val up = remember(library) { LibraryModel.upNext(library.inProgress, library.queued) }
            val listeningEmpty = up.isEmpty() && library.following.isEmpty() && library.finished.isEmpty() && downloadRecords.isEmpty()
            val makingEmpty = groups.isEmpty() && waiting.isEmpty() && marksIn == 0 && classRows.isEmpty()
            // On a TV the D-pad starts on the first row (§9.2), or on an empty Library's Browse (§7.1a).
            val firstRow = remember { FocusRequester() }
            val tv = LocalIsTelevision.current
            if (!listeningEmpty || side == LibraryModel.MAKING) ClaimTvFocus(firstRow, Unit)
            LazyColumn(Modifier.fillMaxSize().focusRequester(firstRow), state = listState, contentPadding = padding) {
                var n = 0
                if (!tv) {
                    item(key = "side") { LibrarySideSwitch(side, setSide) }
                    n++
                }
                if (side == LibraryModel.LISTENING) {
                    if (listeningEmpty) {
                        item(key = "empty") { EmptyMessage("Nothing played yet.", action = EmptyAction("Browse", onBrowse)) }
                        n++
                    }
                    n += upNextItems(up, onOpenEpisode, onAll = { onOpenList(LIST_UP) })
                    if (library.following.isNotEmpty()) {
                        item(key = "following-h") { SectionHeader("Shows you follow") }
                        item(key = "following") {
                            ShowShelf(library.following, onOpen = { onOpenSeries(it.key) }, onLongClick = { unfollowing = it })
                        }
                        n += 2
                    }
                    if (library.finished.isNotEmpty()) {
                        item(key = "history") { CountLine("History", library.finished.size.toString()) { onOpenList(LIST_HISTORY) } }
                        n++
                    }
                    if (downloadRecords.isNotEmpty()) {
                        downloadsSection(downloadRecords, container.downloads.totalBytes, onOpen = onOpenDownloads)
                        n++
                    }
                } else {
                    if (makingEmpty) {
                        item(key = "empty-making") { EmptyMessage("No ear dramas yet.", action = EmptyAction("Record a play", onRecord)) }
                        n++
                    }
                    n += makingItems(groups, waiting, marksIn, classRows, onOpenProduction, onOpenPlay, onOpenClass)
                }
                // The foot, under either side (owner 2026-11-23): Account, Voices, Listen together, Export, About.
                item(key = "foot-h") { SectionHeader("Account and preferences") }
                item(key = "account") { AccountRow() }
                n += 2
                if (voices != null) {
                    voicesAt[0] = n
                    item(key = VOICES_KEY) {
                        DisclosureRow("Voices", voicesState(voices.first), voicesOpen, Icons.Filled.GraphicEq) { voicesOpen = !voicesOpen }
                    }
                    n++
                    if (voicesOpen) voicesItems(voices.first, voices.second, header = false)
                }
                if (!tv) {
                    item(key = "together") { ListenTogetherRow(onListenTogether) }
                    item(key = "export") { ExportRow() }
                } else {
                    item(key = "show-reading") {
                        val showReading = com.example.appname.ui.screens.LocalReadNav.current.showReading
                        ListItem(
                            modifier = Modifier.fillMaxWidth().tvFocusMark().clickable(onClickLabel = "Show a reading", onClick = showReading),
                            leadingContent = { Icon(Icons.Filled.Tv, contentDescription = null) },
                            headlineContent = { Text("Show a reading") },
                        )
                    }
                }
                item(key = "about") { DisclosureRow("About Ear Drama", null, aboutOpen, Icons.Outlined.Info) { aboutOpen = !aboutOpen } }
                if (aboutOpen) siteLinksItem()
            }
        }
    }
}

private fun voicesState(ui: VoiceSettingsUi): String =
    (if (ui.kokoro is KokoroUi.Ready) "Kokoro" else "This device") + " · " + com.example.appname.plays.speedText(ui.defaults.rate)
