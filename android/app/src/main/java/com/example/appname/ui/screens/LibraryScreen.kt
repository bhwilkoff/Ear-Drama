package com.example.appname.ui.screens

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.TextButton
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import kotlinx.coroutines.launch
import com.example.appname.ui.ShowShelf
import com.example.appname.ui.SectionCaption
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
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
    onBrowse: () -> Unit,
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
    val downloadRecords by container.downloads.records.collectAsState()
    var unfollowing by remember { mutableStateOf<SeriesRow?>(null) }
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
    Scaffold(topBar = { TopAppBar(title = { Text("Library") }) }) { padding ->
        LoadableContent(lists, Modifier.padding(padding)) { library ->
            val empty = library.queued.isEmpty() && library.inProgress.isEmpty() && library.finished.isEmpty() &&
                library.following.isEmpty() && downloadRecords.isEmpty() && dramaRows.isEmpty()
            // On a TV the D-pad starts on the first row (§9.2), or on an empty Library's Browse (§7.1a).
            val firstRow = remember { FocusRequester() }
            if (!empty) ClaimTvFocus(firstRow, Unit)
            LazyColumn(Modifier.fillMaxSize().focusRequester(firstRow), contentPadding = padding) {
                // §4.11: the account is the first row, above what this device holds.
                item(key = "account") { AccountRow() }
                item(key = "export") { ExportRow() }
                item(key = "together") { ListenTogetherRow(onListenTogether) }
                // §7.1a: the empty state heads what this device holds; the account and the site pages stay.
                if (empty) {
                    item(key = "empty") { EmptyMessage("Nothing played yet.", action = EmptyAction("Browse", onBrowse)) }
                }
                item(key = "progress-h") { SectionHeader("Continue") }
                if (library.inProgress.isEmpty()) {
                    item(key = "progress-empty") { SectionCaption("Episodes you stop partway through wait here.") }
                }
                items(library.inProgress, key = { "p:" + it.first.id }) { (row, p) ->
                    EpisodeListItem(
                        row,
                        showSeries = true,
                        onOpen = { onOpenEpisode(row.id) },
                        onPlay = { container.playback.play(row) },
                        supporting = "${formatClock(p.positionMs)} of ${formatClock(p.durationMs)}",
                    )
                }
                queueSection(
                    library.queued,
                    onOpen = onOpenEpisode,
                    onPlay = { container.playback.play(it) },
                )
                item(key = "following-h") { SectionHeader("Following") }
                if (library.following.isEmpty()) {
                    item(key = "following-empty") { SectionCaption("Series you follow appear here.") }
                } else {
                    item(key = "following") {
                        ShowShelf(library.following, onOpen = { onOpenSeries(it.key) }, onLongClick = { unfollowing = it })
                    }
                }
                item(key = "history-h") { SectionHeader("History") }
                if (library.finished.isEmpty()) {
                    item(key = "history-empty") { SectionCaption("Episodes you finish appear here, newest first.") }
                }
                items(library.finished, key = { "f:" + it.id }) { row ->
                    EpisodeListItem(
                        row,
                        showSeries = true,
                        onOpen = { onOpenEpisode(row.id) },
                        onPlay = { container.playback.play(row) },
                    )
                }
                downloadsSection(downloadRecords, container.downloads.totalBytes, onOpen = onOpenDownloads)
                earDramasSection(dramaRows, withClasses, onOpenProduction, recordsHere = !television)
                siteLinksItem()
            }
        }
    }
}
