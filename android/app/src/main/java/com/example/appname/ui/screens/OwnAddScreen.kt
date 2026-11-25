package com.example.appname.ui.screens

import android.content.ClipboardManager
import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.input.TextFieldLineLimits
import androidx.compose.foundation.text.input.TextFieldState
import androidx.compose.foundation.text.input.maxLength
import androidx.compose.foundation.text.input.setTextAndPlaceCursorAtEnd
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.outlined.ContentPaste
import androidx.compose.material.icons.outlined.FileOpen
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import com.example.appname.plays.OwnDraft
import com.example.appname.plays.OwnScript
import com.example.appname.plays.OwnText
import com.example.appname.plays.OwnWords
import com.example.appname.ui.Haptic
import com.example.appname.ui.LocalAppContainer
import com.example.appname.ui.playButtonColors
import com.example.appname.ui.rememberHaptics
import com.example.appname.ui.theme.Spacing
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** What another app handed over, waiting in the app for the page that reads it (ANDROID-DESIGN §4.23 item 1). */
sealed interface OwnIncoming {
    data class Words(val read: OwnText) : OwnIncoming
    data class File(val uri: Uri) : OwnIncoming
}

/** A file's text, at most the cap of it read, with its name as a title to offer. */
internal suspend fun readText(context: Context, uri: Uri): OwnText = withContext(Dispatchers.IO) {
    try {
        val name = context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst() && !c.isNull(0)) c.getString(0) else null
        } ?: uri.lastPathSegment.orEmpty()
        val read = context.contentResolver.openInputStream(uri)?.use(OwnText::read) ?: OwnText.Refused("not_text")
        if (read is OwnText.Read) read.copy(title = name.substringAfterLast('/').replace(Regex("\\.[^.]*$"), "").take(OwnScript.MAX_TITLE)) else read
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        OwnText.Refused("not_text")
    }
}

/**
 * Add a script (ANDROID-DESIGN §4.23 item 1, PLAYS-DESIGN §13 item 2): a title and the text, pasted, opened from a plain text
 * file, or shared from another app. The count is read as it is typed; Next proposes the parts and opens the page that corrects them.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun OwnAddScreen(onClose: () -> Unit, onNext: (String) -> Unit) {
    val container = LocalAppContainer.current
    val own = container.plays.own
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val haptics = rememberHaptics()
    // Not saved state: 400 KB does not fit the system's bundle, and the draft on disk is what comes back.
    val title = remember { TextFieldState() }
    val text = remember { TextFieldState() }
    val titleFocus = remember { FocusRequester() }
    var ready by remember { mutableStateOf(false) }
    var refusal by remember { mutableStateOf<String?>(null) }
    var tally by remember { mutableStateOf("") }
    var valid by remember { mutableStateOf(false) }
    var kept by remember { mutableStateOf(false) }
    var adding by remember { mutableStateOf(false) }
    var replacing by remember { mutableStateOf<OwnText.Read?>(null) }

    fun refuse(words: String) {
        refusal = words
        haptics(Haptic.Error)
    }

    fun put(read: OwnText.Read) {
        text.edit {
            replace(0, length, read.text)
            selection = TextRange(0)
        }
        if (title.text.isBlank() && read.title.isNotBlank()) title.setTextAndPlaceCursorAtEnd(read.title)
    }

    fun take(read: OwnText) {
        when (read) {
            is OwnText.Refused -> refuse(OwnWords.file(read.why))
            is OwnText.Read -> {
                refusal = null
                if (text.text.isNotBlank()) replacing = read else put(read)
            }
        }
    }

    val open = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) scope.launch { take(readText(context, uri)) }
    }

    LaunchedEffect(Unit) {
        try {
            own.draft()?.let {
                title.setTextAndPlaceCursorAtEnd(it.title)
                text.edit { replace(0, length, it.text); selection = TextRange(0) }
                kept = it.text.isNotEmpty()
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            refuse(OwnWords.notKept(e))
        }
        ready = true
    }
    // Collected, not keyed: taking it clears it, and a keyed effect would cancel its own read.
    LaunchedEffect(ready) {
        if (ready) container.ownIncoming.collect { got ->
            if (got == null) return@collect
            container.ownIncoming.value = null
            take(when (got) {
                is OwnIncoming.Words -> got.read
                is OwnIncoming.File -> readText(context, got.uri)
            })
        }
    }
    // The count: read off the main thread a moment after the last key.
    LaunchedEffect(Unit) {
        snapshotFlow { text.text.toString() }.collectLatest { t ->
            valid = false
            if (t.isNotEmpty()) delay(180)
            // Done would refuse what the text builds to, so Next does too: the built canonical size, not only the raw text's (R4-2c).
            val (why, read) = withContext(Dispatchers.Default) { com.example.appname.plays.OwnScripts.judge(t) }
            val long = why == "too_long" || why == "too_many_lines"
            if (long) refuse(OwnWords.say("too_long")) else if (refusal == OwnWords.say("too_long")) refusal = null
            tally = if (read != null && !long) OwnWords.partsAndLines(read.parts.size, read.lines.size) else ""
            valid = read != null && !long
        }
    }

    suspend fun keepDraft() {
        withContext(NonCancellable) {
            try {
                own.setDraft(OwnDraft(title.text.toString(), text.text.toString()))
                kept = text.text.isNotEmpty()
            } catch (e: Exception) {
                kept = false
                refuse(OwnWords.notKept(e))
            }
        }
    }
    LaunchedEffect(ready) {
        if (!ready) return@LaunchedEffect
        snapshotFlow { title.text.toString() to text.text.toString() }.distinctUntilChanged().drop(1).collectLatest {
            kept = false
            delay(400)
            if (!adding) keepDraft()
        }
    }
    LaunchedEffect(Unit) { snapshotFlow { title.text.toString() }.map { it.isBlank() }.distinctUntilChanged().collect { if (!it && refusal == OwnWords.say("no_title")) refusal = null } }
    fun flush() { if (ready && !adding && !kept) container.appScope.launch { keepDraft() } }
    LifecycleEventEffect(Lifecycle.Event.ON_STOP) { flush() }
    DisposableEffect(Unit) { onDispose { flush() } }

    fun next() {
        if (title.text.isBlank()) {
            refuse(OwnWords.say("no_title"))
            runCatching { titleFocus.requestFocus() }
            return
        }
        adding = true
        scope.launch {
            try {
                val rec = own.create(title.text.toString(), text.text.toString())
                runCatching { own.setDraft(null) }
                onNext(rec.id)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                adding = false
                refuse(OwnWords.notKept(e))
            }
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Add a script", maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = { IconButton(onClick = onClose) { Icon(Icons.Filled.Close, contentDescription = "Close") } },
                actions = {
                    Button(onClick = ::next, enabled = valid && !adding, colors = playButtonColors(), modifier = Modifier.padding(end = Spacing.S3.dp)) { Text("Next") }
                },
            )
        },
        bottomBar = {
            Surface(color = MaterialTheme.colorScheme.surfaceContainer) {
                Column(Modifier.fillMaxWidth().navigationBarsPadding().imePadding().padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp)) {
                    refusal?.let { Refusal(it) }
                    val facts = listOfNotNull(tally.ifEmpty { null }, if (kept) "Kept on this device" else null)
                    Text(facts.joinToString("  ").ifEmpty { " " }, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        },
    ) { padding ->
        BoxWithConstraints(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.TopCenter) {
            // With a keyboard up in landscape there is no room for a field that takes what is left: the page scrolls.
            val short = maxHeight < 420.dp
            Column(
                Modifier.widthIn(max = 720.dp).fillMaxSize().then(if (short) Modifier.verticalScroll(rememberScrollState()) else Modifier).padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp),
                verticalArrangement = Arrangement.spacedBy(Spacing.S2.dp),
            ) {
                OutlinedTextField(
                    title, Modifier.fillMaxWidth().focusRequester(titleFocus), label = { Text("Title") }, lineLimits = TextFieldLineLimits.SingleLine,
                    inputTransformation = androidx.compose.foundation.text.input.InputTransformation.maxLength(OwnScript.MAX_TITLE),
                    isError = refusal == OwnWords.say("no_title"),
                )
                FlowRow(horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
                    OutlinedButton(onClick = {
                        scope.launch {
                            when (val got = fromClipboard(context)) {
                                null -> Unit
                                is OwnText.Refused -> refuse(OwnWords.say(got.why))
                                is OwnText.Read -> {
                                    refusal = null
                                    text.edit {
                                        val at = selection
                                        replace(at.min, at.max, got.text)
                                    }
                                }
                            }
                        }
                    }) {
                        Icon(Icons.Outlined.ContentPaste, contentDescription = null)
                        Text("Paste", Modifier.padding(start = Spacing.S2.dp))
                    }
                    OutlinedButton(onClick = { runCatching { open.launch(arrayOf("text/*")) }.onFailure { refuse(OwnWords.say("")) } }) {
                        Icon(Icons.Outlined.FileOpen, contentDescription = null)
                        Text("Open a file", Modifier.padding(start = Spacing.S2.dp))
                    }
                }
                OutlinedTextField(
                    text, Modifier.fillMaxWidth().then(if (short) Modifier.height(220.dp) else Modifier.weight(1f)), label = { Text("Script") },
                    lineLimits = TextFieldLineLimits.MultiLine(), labelPosition = androidx.compose.material3.TextFieldLabelPosition.Attached(alwaysMinimize = true),
                )
            }
        }
    }
    replacing?.let { read ->
        AlertDialog(
            onDismissRequest = { replacing = null },
            title = { Text("Replace the text?") },
            confirmButton = { TextButton(onClick = { replacing = null; put(read) }) { Text("Replace") } },
            dismissButton = { TextButton(onClick = { replacing = null }) { Text("Cancel") } },
        )
    }
}

/** The clipboard's words, or the text of the file on it; null when it holds neither. Nothing past the cap is read. */
private suspend fun fromClipboard(context: Context): OwnText? {
    val item = context.getSystemService(ClipboardManager::class.java)?.primaryClip?.takeIf { it.itemCount > 0 }?.getItemAt(0) ?: return null
    item.text?.let { return OwnText.shared(it) }
    return item.uri?.let { readText(context, it) }
}
