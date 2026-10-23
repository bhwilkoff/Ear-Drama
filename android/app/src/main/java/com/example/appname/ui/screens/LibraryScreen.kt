package com.example.appname.ui.screens

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import com.example.appname.ui.ClaimTvFocus
import androidx.compose.ui.Modifier
import com.example.appname.data.EpisodeRow
import com.example.appname.data.Progress
import com.example.appname.ui.AccountRow
import com.example.appname.ui.EmptyMessage
import com.example.appname.ui.EpisodeListItem
import com.example.appname.ui.LoadableContent
import com.example.appname.ui.LocalAppContainer
import com.example.appname.ui.SectionHeader
import com.example.appname.ui.downloadsSection
import com.example.appname.ui.formatClock
import com.example.appname.ui.rememberCatalogQuery

private data class LibraryLists(
    val inProgress: List<Pair<EpisodeRow, Progress>>,
    val finished: List<EpisodeRow>,
)

/** Library: what the listener started, downloaded, and played to the end on this device. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LibraryScreen(onOpenEpisode: (String) -> Unit) {
    val container = LocalAppContainer.current
    val lists by rememberCatalogQuery(watchUser = true) { db ->
        val progress = container.user.inProgress(limit = 100)
        val byId = progress.associateBy { it.episodeId }
        LibraryLists(
            inProgress = db.episodes(progress.map { it.episodeId }).mapNotNull { row ->
                byId[row.id]?.let { row to it }
            }.distinctBy { it.first.id },
            finished = db.episodes(container.user.finished().map { it.episodeId }).distinctBy { it.id },
        )
    }
    val downloadRecords by container.downloads.records.collectAsState()
    Scaffold(topBar = { TopAppBar(title = { Text("Library") }) }) { padding ->
        LoadableContent(lists, Modifier.padding(padding)) { library ->
            if (library.inProgress.isEmpty() && library.finished.isEmpty() && downloadRecords.isEmpty()) {
                Column(Modifier.padding(padding)) {
                    AccountRow()
                    EmptyMessage("Episodes you play appear here.")
                }
                return@LoadableContent
            }
            // On a TV the D-pad starts on the first row (§9.2).
            val firstRow = remember { FocusRequester() }
            ClaimTvFocus(firstRow, Unit)
            LazyColumn(Modifier.fillMaxSize().focusRequester(firstRow), contentPadding = padding) {
                // §4.11: the account is the first row, above what this device holds.
                item(key = "account") { AccountRow() }
                if (library.inProgress.isNotEmpty()) {
                    item(key = "progress-h") { SectionHeader("In progress") }
                    items(library.inProgress, key = { "p:" + it.first.id }) { (row, p) ->
                        EpisodeListItem(
                            row,
                            showSeries = true,
                            onOpen = { onOpenEpisode(row.id) },
                            onPlay = { container.playback.play(row) },
                            supporting = "${formatClock(p.positionMs)} of ${formatClock(p.durationMs)}",
                        )
                    }
                }
                downloadsSection(
                    records = downloadRecords.values.sortedByDescending { it.addedAtMs },
                    totalBytes = container.downloads.totalBytes,
                    onOpen = onOpenEpisode,
                    onRemove = container.downloads::remove,
                    onRemoveAll = container.downloads::removeAll,
                )
                if (library.finished.isNotEmpty()) {
                    item(key = "finished-h") { SectionHeader("Played") }
                    items(library.finished, key = { "f:" + it.id }) { row ->
                        EpisodeListItem(
                            row,
                            showSeries = true,
                            onOpen = { onOpenEpisode(row.id) },
                            onPlay = { container.playback.play(row) },
                        )
                    }
                }
            }
        }
    }
}
