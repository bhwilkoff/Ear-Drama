package com.example.appname.ui.screens

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withLink
import androidx.compose.ui.unit.dp
import com.example.appname.data.EpisodeDetail
import com.example.appname.plays.OwnRow
import com.example.appname.plays.OwnScripts
import com.example.appname.plays.OwnWords
import com.example.appname.plays.PlayScript
import com.example.appname.ui.CastWindow
import com.example.appname.ui.GrammarRow
import com.example.appname.ui.LocalAppContainer
import com.example.appname.ui.LocalIsTelevision
import com.example.appname.ui.playButtonColors
import com.example.appname.ui.theme.OnAir
import com.example.appname.ui.theme.Spacing
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// Where own scripts are met (ANDROID-DESIGN §4.23): Your scripts' rows, the two doors, and what an own script's page adds to a play's.

/** Your scripts on this device, the last one changed first; none on a TV, and none while they are read. */
@Composable
fun rememberOwnRows(): List<OwnRow> {
    if (LocalIsTelevision.current) return emptyList()
    val own = LocalAppContainer.current.plays.own
    val rows by own.rows.collectAsState()
    LaunchedEffect(own) { if (own.rows.value == null) runCatching { own.refresh() } }
    return rows.orEmpty()
}

@Composable
fun OwnScriptRow(row: OwnRow, onOpen: () -> Unit) {
    // A row's window is too small for its "+N": the largest seven parts stand alone.
    val window = remember(row) { row.copy(cast = row.cast.take(7)) }
    GrammarRow(title = row.title, visual = { m -> CastWindow(window, m) }, onOpen = onOpen, sub = listOf(row.facts), openLabel = "Open script")
}

@Composable
fun AddScriptButton(onClick: () -> Unit) {
    TextButton(onClick = onClick) {
        Icon(Icons.Outlined.Add, contentDescription = null)
        Text("Add a script", Modifier.padding(start = Spacing.S1.dp))
    }
}

/** Whether Record this on an episode with no castable script is sure to open; false while it is asked, and nothing is said. */
@Composable
fun rememberCanCastByEar(d: EpisodeDetail, asks: Boolean): Boolean {
    val television = LocalIsTelevision.current
    val container = LocalAppContainer.current
    val can by produceState(false, d.episode.id, d.transcriptUrl, asks, television) { value = !television && asks && canCastByEar(container, d) }
    return can
}

/** Record this where the words are the episode's automatic transcript: the same verb, so nobody learns a second one. */
@Composable
fun CastByEarButton(onClick: () -> Unit) {
    Button(onClick = onClick, colors = playButtonColors()) {
        Icon(Icons.Filled.Mic, contentDescription = null)
        Text("Record this", Modifier.padding(start = Spacing.S2.dp))
    }
}

/** An own script's page, after its parts: where it came from, the refusal, and its own verbs (§4.23 item 3). */
@Composable
internal fun OwnFoot(script: PlayScript, onDeleted: () -> Unit, onOpenEpisode: (String) -> Unit, onEdit: (String) -> Unit, onCastByEar: (String) -> Unit) {
    val container = LocalAppContainer.current
    val plays = container.plays
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var failed by remember { mutableStateOf<String?>(null) }
    var asking by remember { mutableStateOf<String?>(null) }
    val muted = MaterialTheme.colorScheme.onSurfaceVariant
    val save = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("text/plain")) { uri ->
        if (uri != null) scope.launch {
            val ok = withContext(Dispatchers.IO) {
                runCatching { checkNotNull(context.contentResolver.openOutputStream(uri)).use { it.write(OwnScripts.asText(script).toByteArray()) } }.isSuccess
            }
            failed = if (ok) null else "The file could not be saved."
        }
    }
    val frozen by produceState(false, script.id) { value = withContext(Dispatchers.IO) { runCatching { plays.own.frozen(script.id) }.getOrDefault(false) } }
    val left by produceState<OwnRow?>(null, script.id) {
        value = withContext(Dispatchers.IO) { runCatching { plays.own.list().firstOrNull { it.id == script.id && it.ear != null && it.ear.cast < it.ear.lines } }.getOrNull() }
    }
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
        val episode = script.episode
        Text(
            buildAnnotatedString {
                if (episode != null) {
                    val link = TextLinkStyles(SpanStyle(color = OnAir.colors.link, textDecoration = TextDecoration.Underline))
                    withLink(LinkAnnotation.Clickable("episode", link) { onOpenEpisode(episode) }) { append(script.source.name) }
                } else {
                    append(script.source.name)
                }
                append(if (frozen) " \u00b7 Shared" else " \u00b7 Kept on this device")
            },
            style = MaterialTheme.typography.labelMedium, color = muted,
        )
        left?.ear?.let { Text(OwnWords.castLine(it.cast, it.lines), style = MaterialTheme.typography.bodySmall, color = muted) }
        Text("This script can\u2019t be published.", style = MaterialTheme.typography.labelMedium, color = muted)
        ChipFlow {
            if (left != null && episode != null && !frozen) OutlinedButton(onClick = { onCastByEar(episode) }) { Text("Cast by ear") }
            if (frozen) {
                OutlinedButton(onClick = {
                    scope.launch {
                        try {
                            val made = plays.own.copy(script)
                            val casting = made.ear != null && com.example.appname.plays.OwnScript.castCount(made.doc).let { (n, of) -> n < of }
                            if (casting && made.episode != null) onCastByEar(made.episode.id) else onEdit(made.id)
                        } catch (e: CancellationException) {
                            throw e
                        } catch (e: Exception) {
                            failed = OwnWords.notKept(e)
                        }
                    }
                }) { Text("Edit a copy") }
            } else {
                OutlinedButton(onClick = { onEdit(script.id) }) { Text("Edit") }
            }
            OutlinedButton(onClick = { runCatching { save.launch(OwnScripts.fileName(script.title)) }.onFailure { failed = "The file could not be saved." } }) { Text("Save as text") }
            TextButton(onClick = {
                scope.launch {
                    val made = withContext(Dispatchers.IO) { plays.own.productions(script.id) }
                    asking = "Delete ${script.title}?" + if (made.isEmpty()) "" else " Its productions keep their copy."
                }
            }) { Text("Delete", color = com.example.appname.ui.theme.AppSemantics.colors.error) }
        }
        failed?.let { Refusal(it) }
    }
    asking?.let { words ->
        AlertDialog(
            onDismissRequest = { asking = null },
            title = { Text(words) },
            confirmButton = {
                TextButton(onClick = {
                    asking = null
                    scope.launch {
                        try {
                            plays.deleteOwn(script.id)
                            onDeleted()
                        } catch (e: CancellationException) {
                            throw e
                        } catch (e: Exception) {
                            failed = "This device could not delete it."
                        }
                    }
                }) { Text("Delete", color = com.example.appname.ui.theme.AppSemantics.colors.error) }
            },
            dismissButton = { TextButton(onClick = { asking = null }) { Text("Cancel") } },
        )
    }
}
