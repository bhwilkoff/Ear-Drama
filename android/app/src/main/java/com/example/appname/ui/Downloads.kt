package com.example.appname.ui

import android.text.format.Formatter
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Scaffold
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import com.example.appname.data.DownloadPlan
import com.example.appname.data.DownloadRequest
import kotlinx.coroutines.launch
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.appname.data.DownloadRecord
import com.example.appname.data.EpisodeDetail
import com.example.appname.ui.theme.AppSemantics
import com.example.appname.ui.theme.Spacing

// Downloads on phone and tablet. A downloaded file is played, never exported:
// there is no share or open-with action anywhere (research 04 §11).

@Composable
fun byteText(bytes: Long): String = Formatter.formatShortFileSize(LocalContext.current, bytes)

/**
 * Episode Detail's download button, one of the action row's: Download, progress with Cancel,
 * Downloaded with Remove, or failed with Try Again. Only the idle state keeps a label, and it folds
 * to its icon with the row.
 */
@Composable
fun DownloadButton(detail: EpisodeDetail, folded: Boolean, modifier: Modifier = Modifier) {
    val downloads = LocalAppContainer.current.downloads
    val records by downloads.records.collectAsState()
    val id = detail.episode.id
    val record = records[id]
    val start = { downloads.download(detail, episodeTitle(detail.episode)) }
    when (record?.state) {
        null -> FoldButton(
            Icons.Outlined.Download, "Download", folded, start,
            modifier, enabled = detail.recordings.isNotEmpty(),
        )
        DownloadRecord.State.Queued, DownloadRecord.State.Downloading -> {
            val fraction = record.fraction
            IconButton(onClick = { downloads.cancel(id) }, modifier = modifier.size(48.dp).tvFocusMark()) {
                if (fraction != null) {
                    CircularProgressIndicator(progress = { fraction }, modifier = Modifier.size(24.dp), strokeWidth = 2.dp)
                } else {
                    CircularProgressIndicator(modifier = Modifier.size(24.dp), strokeWidth = 2.dp)
                }
                Icon(
                    Icons.Outlined.Close,
                    contentDescription = "Cancel Download",
                    modifier = Modifier.size(12.dp),
                )
            }
        }
        DownloadRecord.State.Downloaded -> IconButton(
            onClick = { downloads.remove(id) },
            modifier = modifier.size(48.dp).tvFocusMark(),
        ) {
            Icon(Icons.Filled.CheckCircle, contentDescription = "Remove Download, ${byteText(record.receivedBytes)}")
        }
        DownloadRecord.State.Failed -> IconButton(onClick = start, modifier = modifier.size(48.dp).tvFocusMark()) {
            Icon(Icons.Outlined.Refresh, contentDescription = "Download failed. Try Again", tint = AppSemantics.colors.error)
        }
    }
}

@Composable
private fun DownloadProgress(record: DownloadRecord, modifier: Modifier = Modifier) {
    val fraction = record.fraction
    val label = Modifier.semantics {
        contentDescription = if (fraction != null) "Downloading, ${(fraction * 100).toInt()} percent" else "Downloading"
    }
    if (fraction != null) {
        LinearProgressIndicator(progress = { fraction }, modifier = modifier.then(label))
    } else {
        LinearProgressIndicator(modifier = modifier.then(label))
    }
}

/**
 * Library's Downloads row: the count and the storage held, opening the
 * Downloads place. A bulk download is hundreds of rows, which would bury the
 * rest of Library (§4.6).
 */
fun LazyListScope.downloadsSection(records: Map<String, DownloadRecord>, totalBytes: Long, onOpen: () -> Unit) {
    if (records.isEmpty()) return
    item(key = "downloads") {
        val count = if (records.size == 1) "1 episode" else "${records.size} episodes"
        ListItem(
            modifier = Modifier.clickable(onClickLabel = "Open downloads", onClick = onOpen).tvFocusMark(),
            leadingContent = { Icon(Icons.Outlined.Download, contentDescription = null) },
            headlineContent = { Text("Downloads") },
            trailingContent = { Text("$count · ${byteText(totalBytes)}", style = MaterialTheme.typography.labelMedium) },
        )
    }
}

/** The Downloads place: by series, each removable; a series' Remove and Remove All ask first; the storage at the foot. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DownloadsScreen(onBack: () -> Unit, onOpenEpisode: (String) -> Unit) {
    val downloads = LocalAppContainer.current.downloads
    val records by downloads.records.collectAsState()
    var confirmingAll by rememberSaveable { mutableStateOf(false) }
    var removingSeries by rememberSaveable { mutableStateOf<String?>(null) }
    val groups = remember(records) { downloads.seriesGroups }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Downloads") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { padding ->
        if (groups.isEmpty()) {
            EmptyMessage("No downloads", Modifier.padding(padding))
            return@Scaffold
        }
        LazyColumn(Modifier.fillMaxSize(), contentPadding = padding) {
            groups.forEach { (key, rows) ->
                item(key = "h:$key") {
                    Row(
                        Modifier.fillMaxWidth().padding(end = Spacing.S2.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        SectionHeader(rows.first().seriesName, Modifier.weight(1f))
                        TextButton(
                            onClick = { removingSeries = key },
                            modifier = Modifier.semantics { contentDescription = "Remove ${rows.first().seriesName} downloads" },
                        ) {
                            Text("Remove", color = MaterialTheme.colorScheme.error)
                        }
                    }
                }
                items(rows, key = { "d:" + it.episodeId }) { record ->
                    DownloadItem(
                        record,
                        showSeries = false,
                        onOpen = { onOpenEpisode(record.episodeId) },
                        onRemove = { downloads.remove(record.episodeId) },
                    )
                }
            }
            item(key = "foot") {
                Row(
                    Modifier.fillMaxWidth().padding(horizontal = Spacing.S4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Meta("${byteText(downloads.totalBytes)} on this device", Modifier.weight(1f))
                    TextButton(onClick = { confirmingAll = true }) {
                        Text("Remove All Downloads", color = MaterialTheme.colorScheme.error)
                    }
                }
            }
        }
    }
    if (confirmingAll) {
        ConfirmRemove("Remove all downloads?", "Remove All Downloads", onDismiss = { confirmingAll = false }) {
            downloads.removeAll()
        }
    }
    removingSeries?.let { key ->
        ConfirmRemove("Remove this series' downloads?", "Remove Downloads", onDismiss = { removingSeries = null }) {
            downloads.removeSeries(key)
        }
    }
}

@Composable
private fun ConfirmRemove(title: String, action: String, onDismiss: () -> Unit, onConfirm: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        confirmButton = {
            TextButton(onClick = { onDismiss(); onConfirm() }) {
                Text(action, color = MaterialTheme.colorScheme.error)
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

/** The words of a bulk download's question: the count, then about how much space (Decision 071). */
fun downloadPlanTitle(plan: DownloadPlan): String =
    if (plan.count == 1) "Download 1 episode?" else "Download ${plan.count} episodes?"

/**
 * A series page's Download action (§4.3): the whole run, the selected season,
 * or Remove downloads; a download asks first with the count and the space.
 */
@Composable
fun SeriesDownloadAction(seriesKey: String, allIds: List<String>, season: String?, seasonIds: List<String>?) {
    val container = LocalAppContainer.current
    val downloads = container.downloads
    val records by downloads.records.collectAsState()
    val scope = rememberCoroutineScope()
    var open by remember { mutableStateOf(false) }
    var plan by remember { mutableStateOf<DownloadPlan?>(null) }
    var confirmingRemove by remember { mutableStateOf(false) }
    val prepare: (List<String>) -> Unit = { ids ->
        open = false
        scope.launch {
            val db = container.catalog.awaitDb() ?: return@launch
            val requests = downloads.missing(ids).mapNotNull { id ->
                db.episodeDetail(id)?.let { DownloadRequest.from(it, episodeTitle(it.episode)) }
            }
            plan = DownloadPlan(requests, downloads.records.value).takeIf { it.count > 0 }
        }
    }
    Box {
        IconButton(onClick = { open = true }, modifier = Modifier.tvFocusMark()) {
            Icon(Icons.Outlined.Download, contentDescription = "Download")
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            DropdownMenuItem(
                text = { Text("Download all episodes") },
                enabled = remember(records, allIds) { downloads.missing(allIds).isNotEmpty() },
                onClick = { prepare(allIds) },
            )
            if (seasonIds != null) {
                DropdownMenuItem(
                    text = { Text("Download ${seasonLabel(season)}") },
                    enabled = remember(records, seasonIds) { downloads.missing(seasonIds).isNotEmpty() },
                    onClick = { prepare(seasonIds) },
                )
            }
            if (records.values.any { it.seriesKey == seriesKey }) {
                DropdownMenuItem(
                    text = { Text("Remove downloads", color = MaterialTheme.colorScheme.error) },
                    onClick = { open = false; confirmingRemove = true },
                )
            }
        }
    }
    plan?.let { p ->
        AlertDialog(
            onDismissRequest = { plan = null },
            title = { Text(downloadPlanTitle(p)) },
            text = p.estimatedBytes?.let { bytes -> { Text("About ${byteText(bytes)}.") } },
            confirmButton = { TextButton(onClick = { plan = null; downloads.download(p) }) { Text("Download") } },
            dismissButton = { TextButton(onClick = { plan = null }) { Text("Cancel") } },
        )
    }
    if (confirmingRemove) {
        ConfirmRemove("Remove this series' downloads?", "Remove Downloads", onDismiss = { confirmingRemove = false }) {
            downloads.removeSeries(seriesKey)
        }
    }
}

/** A download row: the record's own title and series, so it stays readable with no network and across catalog swaps. */
@Composable
private fun DownloadItem(record: DownloadRecord, showSeries: Boolean = true, onOpen: () -> Unit, onRemove: () -> Unit) {
    ListItem(
        modifier = Modifier.clickable(onClickLabel = "Open episode", onClick = onOpen),
        headlineContent = { Text(record.title, maxLines = 2, overflow = TextOverflow.Ellipsis) },
        supportingContent = {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
                if (showSeries) {
                    Text(record.seriesName, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                }
                when (record.state) {
                    DownloadRecord.State.Downloaded -> Text(byteText(record.receivedBytes))
                    DownloadRecord.State.Queued, DownloadRecord.State.Downloading ->
                        DownloadProgress(record, Modifier.width(80.dp))
                    DownloadRecord.State.Failed -> Text("Download failed", color = AppSemantics.colors.error)
                }
            }
        },
        trailingContent = {
            val active = record.isActive
            IconButton(onClick = onRemove) {
                Icon(
                    if (active) Icons.Outlined.Close else Icons.Outlined.Delete,
                    contentDescription = if (active) "Cancel Download" else "Remove Download",
                )
            }
        },
    )
}
