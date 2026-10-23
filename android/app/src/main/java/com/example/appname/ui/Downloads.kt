package com.example.appname.ui

import android.text.format.Formatter
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
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

/** Episode Detail's download row: Download, progress with Cancel, Downloaded with Remove, or failed with Try Again. */
@Composable
fun DownloadControl(detail: EpisodeDetail, modifier: Modifier = Modifier) {
    val downloads = LocalAppContainer.current.downloads
    val records by downloads.records.collectAsState()
    val id = detail.episode.id
    val record = records[id]
    val start = { downloads.download(detail, episodeTitle(detail.episode)) }
    Row(
        modifier.fillMaxWidth().padding(horizontal = Spacing.S4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Spacing.S3.dp),
    ) {
        when (record?.state) {
            null -> OutlinedButton(onClick = start, enabled = detail.recordings.isNotEmpty()) {
                Icon(Icons.Outlined.Download, contentDescription = null)
                Text("Download", Modifier.padding(start = Spacing.S2.dp))
            }
            DownloadRecord.State.Queued, DownloadRecord.State.Downloading -> {
                DownloadProgress(record, Modifier.weight(1f))
                IconButton(onClick = { downloads.cancel(id) }) {
                    Icon(Icons.Outlined.Close, contentDescription = "Cancel Download")
                }
            }
            DownloadRecord.State.Downloaded -> {
                Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(
                    "Downloaded · ${byteText(record.receivedBytes)}",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.weight(1f),
                )
                IconButton(onClick = { downloads.remove(id) }) {
                    Icon(Icons.Outlined.Delete, contentDescription = "Remove Download")
                }
            }
            DownloadRecord.State.Failed -> {
                Icon(Icons.Outlined.WarningAmber, contentDescription = null, tint = AppSemantics.colors.error)
                Text(
                    "Download failed",
                    style = MaterialTheme.typography.labelMedium,
                    color = AppSemantics.colors.error,
                    modifier = Modifier.weight(1f),
                )
                TextButton(onClick = start) {
                    Icon(Icons.Outlined.Refresh, contentDescription = null)
                    Text("Try Again", Modifier.padding(start = Spacing.S2.dp))
                }
            }
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
 * Library's Downloads section: every download, newest first, each removable,
 * one confirmed Remove All, and the storage they hold.
 */
fun LazyListScope.downloadsSection(
    records: List<DownloadRecord>,
    totalBytes: Long,
    onOpen: (String) -> Unit,
    onRemove: (String) -> Unit,
    onRemoveAll: () -> Unit,
) {
    if (records.isEmpty()) return
    item(key = "downloads-h") { SectionHeader("Downloads") }
    items(records, key = { "d:" + it.episodeId }) { record ->
        DownloadItem(record, onOpen = { onOpen(record.episodeId) }, onRemove = { onRemove(record.episodeId) })
    }
    item(key = "downloads-f") {
        var confirming by rememberSaveable { mutableStateOf(false) }
        Row(
            Modifier.fillMaxWidth().padding(horizontal = Spacing.S4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Meta("${byteText(totalBytes)} on this device", Modifier.weight(1f))
            TextButton(onClick = { confirming = true }) {
                Text("Remove All Downloads", color = MaterialTheme.colorScheme.error)
            }
        }
        if (confirming) {
            AlertDialog(
                onDismissRequest = { confirming = false },
                title = { Text("Remove all downloads?") },
                confirmButton = {
                    TextButton(onClick = { confirming = false; onRemoveAll() }) {
                        Text("Remove All Downloads", color = MaterialTheme.colorScheme.error)
                    }
                },
                dismissButton = { TextButton(onClick = { confirming = false }) { Text("Cancel") } },
            )
        }
    }
}

/** A download row: the record's own title and series, so it stays readable with no network and across catalog swaps. */
@Composable
private fun DownloadItem(record: DownloadRecord, onOpen: () -> Unit, onRemove: () -> Unit) {
    ListItem(
        modifier = Modifier.clickable(onClickLabel = "Open episode", onClick = onOpen),
        headlineContent = { Text(record.title, maxLines = 2, overflow = TextOverflow.Ellipsis) },
        supportingContent = {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
                Text(record.seriesName, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
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
