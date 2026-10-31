package com.example.appname.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.FileDownload
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.example.appname.data.DataExport
import java.time.LocalDate
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Export (Human-Shaped principle 11), beside the account in Library: the person's own history,
 * follows, queue, and takes list as a JSON file, and the history as CSV, written where the
 * system's save sheet is pointed. Built on the device; nothing is uploaded, and it needs no
 * account. A TV has no save sheet, so the row is absent there.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ExportRow(modifier: Modifier = Modifier) {
    if (LocalIsTelevision.current) return
    val container = LocalAppContainer.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var open by rememberSaveable { mutableStateOf(false) }
    var failed by remember { mutableStateOf(false) }
    var pending by remember { mutableStateOf("") }

    fun write(uri: android.net.Uri?) {
        if (uri == null) return
        scope.launch {
            val ok = withContext(Dispatchers.IO) {
                runCatching { context.contentResolver.openOutputStream(uri)?.use { it.write(pending.toByteArray()) } }.isSuccess
            }
            failed = !ok
            if (ok) open = false
        }
    }

    val saveJson = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { write(it) }
    val saveCsv = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("text/csv")) { write(it) }

    suspend fun gather(): DataExport {
        val db = container.catalog.awaitDb()
        val changes = container.user.localChanges(all = true)
        val history = changes.history.filter { !it.deleted }.sortedByDescending { it.updatedAt }
        val queueIds = container.user.queue()
        val rows = db?.episodes((history.map { it.episodeId } + queueIds).distinct()).orEmpty().associateBy { it.id }
        val followed = changes.follows.filter { it.following }.sortedByDescending { it.updatedAt }
        return DataExport(
            exportedAtMs = System.currentTimeMillis(),
            history = history.map {
                val row = rows[it.episodeId]
                DataExport.History(it.episodeId, row?.let(::episodeTitle), row?.seriesName, row?.airDate, it.updatedAt, it.position, it.duration)
            },
            following = followed.map { DataExport.Follow(it.seriesId, db?.series(it.seriesId)?.name) },
            queue = queueIds.map {
                val row = rows[it]
                DataExport.Queued(it, row?.let(::episodeTitle), row?.seriesName, row?.airDate)
            },
            takes = container.plays.store.productions.value.map { p ->
                DataExport.Production(p.id, p.title, DataExport.fromReferenceDate(p.created), p.takes.map { t ->
                    DataExport.Take(t.id, t.lineID, t.part.raw, DataExport.fromReferenceDate(t.created), t.frames / t.sampleRate, p.chosen[t.lineID] == t.id)
                })
            },
        )
    }

    ListItem(
        modifier = modifier.tvFocusMark().clickable(onClickLabel = "Open export") { open = true },
        leadingContent = { Icon(Icons.Outlined.FileDownload, contentDescription = null) },
        headlineContent = { Text("Export my data") },
    )
    if (open) {
        ModalBottomSheet(onDismissRequest = { open = false; failed = false }) {
            Column(
                Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(bottom = 24.dp).navigationBarsPadding(),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text("Export my data", style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
                if (failed) Text("The file could not be saved.", color = MaterialTheme.colorScheme.error)
                val day = LocalDate.now()
                FilledTonalButton(
                    onClick = { scope.launch { pending = gather().json(); saveJson.launch("ear-drama-$day.json") } },
                    modifier = Modifier.fillMaxWidth(),
                ) { Text("Save everything (JSON)") }
                OutlinedButton(
                    onClick = { scope.launch { pending = gather().historyCsv(); saveCsv.launch("ear-drama-history-$day.csv") } },
                    modifier = Modifier.fillMaxWidth(),
                ) { Text("Save history (CSV)") }
            }
        }
    }
}
