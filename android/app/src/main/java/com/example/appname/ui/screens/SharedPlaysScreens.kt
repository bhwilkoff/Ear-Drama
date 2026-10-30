package com.example.appname.ui.screens

import com.example.appname.ui.wayColors
import android.content.Context
import androidx.compose.foundation.clickable
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.selection.selectable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import com.example.appname.plays.ConsentBlock
import com.example.appname.plays.ConsentText
import androidx.compose.ui.unit.dp
import com.example.appname.plays.CastPart
import com.example.appname.plays.ClassRow
import com.example.appname.plays.InviteView
import com.example.appname.plays.PartID
import com.example.appname.plays.PlayScript
import com.example.appname.plays.PlaysLibrary
import com.example.appname.plays.PlaysShare
import com.example.appname.plays.SharedPart
import com.example.appname.plays.SharedPlays
import com.example.appname.plays.SharedRecord
import com.example.appname.ui.AccountRow
import com.example.appname.ui.Holder
import com.example.appname.ui.PartCard
import com.example.appname.ui.PartGrid
import com.example.appname.ui.LocalAppContainer
import com.example.appname.ui.SectionHeader
import com.example.appname.ui.playButtonColors
import com.example.appname.ui.shareLink
import com.example.appname.ui.theme.AppSemantics
import com.example.appname.ui.theme.Spacing
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

// Shared ear dramas, phase 2 (PLAYS-DESIGN §11.7, ANDROID-DESIGN §4.16): the
// cast sheet's shared verbs, the invitation, the people, and the classes, in
// Material's own components. None of it is drawn on a TV (it plays back only).

/** The reasons a report can give (docs/WORKER.md, Reports): the Worker's code, then the words on screen. */
private val REASONS = listOf(
    "offensive" to "Offensive",
    "harassment" to "Harassment",
    "personal_information" to "Personal information",
    "not_a_performance" to "Not a performance",
    "other" to "Other",
)

/**
 * One shared production's cast sheet in the open: what is busy, the one line
 * a refusal gives, and every verb. A verb asks the Worker and shows its
 * answer; nothing here decides a claim (C7).
 */
@Stable
class SharedSheet(
    val id: String,
    val script: PlayScript,
    private val sharing: SharedPlays,
    private val scope: CoroutineScope,
    private val context: Context,
    private val onRecord: (PartID) -> Unit,
) {
    var busy by mutableStateOf(false)
        private set
    var error by mutableStateOf<String?>(null)
    var caption by mutableStateOf<String?>(null)
        private set

    private fun run(block: suspend () -> Unit) {
        if (busy) return
        busy = true
        error = null
        scope.launch {
            try {
                block()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                error = PlaysShare.line(e)
            } finally {
                busy = false
            }
        }
    }

    fun take(part: String) = run {
        sharing.claim(id, part)
        onRecord(PartID(part))
    }

    fun leaveSilent(part: String) = run { sharing.action(id, part, "silent") }
    fun reopen(part: String) = run { sharing.action(id, part, "reopen") }
    fun release(part: String) = run { sharing.action(id, part, "release") }
    fun done(part: String) = run { sharing.action(id, part, "done") }

    fun invite() = run {
        val (link, works) = sharing.makeInvite(id)
        caption = works
        context.shareLink(script.title, link)
    }

    fun upload() = run {
        val result = sharing.upload(id, script)
        when {
            result.error != null -> error = PlaysShare.line(result.error)
            result.stopped == PlaysShare.Stop.UploadsOff -> error = PlaysShare.line(com.example.appname.plays.PlaysException("uploads_off"))
            result.flagged > 0 -> error = PlaysShare.line(com.example.appname.plays.PlaysException("bleed_flagged"))
        }
    }

    suspend fun consent(): com.example.appname.plays.Consent? = sharing.consent()

    fun publish(consent: com.example.appname.plays.Consent) = run { sharing.publish(id, script, consent) }

    fun agree(consent: com.example.appname.plays.Consent) = run { sharing.agree(id, consent) }

    fun block(userId: String) = run { sharing.block(id, userId) }

    fun publishAgain() = run { sharing.publishAgain(id, script) }

    fun removeLine(lineId: String, reason: String) = run { sharing.removeLine(id, lineId, reason) }

    val removed get() = sharing.removed

    fun report(userId: String?, takeId: String?, reason: String, note: String) = run {
        if (takeId != null) sharing.reportTake(id, takeId, reason, note) else sharing.reportMember(id, userId.orEmpty(), reason, note)
    }

    /** Fetches the other members' chosen takes before the phase 1 listen-through. */
    suspend fun prepareListen() {
        try {
            sharing.bringHome(id, script)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            error = PlaysShare.line(e)
        }
    }
}

// MARK: Share, on a production that is not shared yet

/** "Share" (rule 1): signed out, "Sharing needs an account." and the sign-in row. */
@Composable
fun ShareEntry(signedIn: Boolean, onShare: (String) -> Unit, error: String?) {
    var asking by remember { mutableStateOf(false) }
    Column(Modifier.padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp), verticalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
        if (!signedIn) {
            Text("Sharing needs an account.", style = MaterialTheme.typography.bodyMedium)
            AccountRow()
        } else {
            OutlinedButton(onClick = { asking = true }) {
                Icon(Icons.Filled.Share, contentDescription = null)
                Text("Share", Modifier.padding(start = Spacing.S2.dp))
            }
        }
        error?.let { ErrorLine(it) }
    }
    if (asking) {
        var name by remember { mutableStateOf("") }
        AlertDialog(
            onDismissRequest = { asking = false },
            title = { Text("Share") },
            text = { OutlinedTextField(value = name, onValueChange = { name = it }, label = { Text("Your name") }, singleLine = true) },
            confirmButton = { TextButton(onClick = { asking = false; onShare(name) }) { Text("Share") } },
            dismissButton = { TextButton(onClick = { asking = false }) { Text("Not now") } },
        )
    }
}

// MARK: The shared cast sheet

/** The parts with the Worker's state (rule 4), then upload, people, and publish. */
@OptIn(ExperimentalLayoutApi::class)
fun LazyListScope.sharedCastRows(
    sheet: SharedSheet,
    rec: SharedRecord?,
    me: String?,
    pendingByPart: Map<String, Int>,
    onRecord: (PartID) -> Unit,
    onReplace: (PartID, String) -> Unit,
) {
    if (rec == null) return
    val recordingNow = PlaysShare.recordingPart(rec)
    val director = PlaysShare.isDirector(rec, me)
    item(key = "shared-parts-h") { SectionHeader("Parts") }
    item(key = "shared-parts") {
        PartGrid(sheet.script.castParts) { part, modifier ->
        val state = rec.parts[part.id.raw] ?: SharedPart()
        SharedCastRow(
            modifier = modifier,
            script = sheet.script,
            part = part,
            state = state,
            mine = PlaysShare.isMine(rec, part.id.raw, me),
            performerIsMe = me != null && state.userId == me,
            director = director,
            recordingElsewhere = recordingNow != null,
            isNext = rec.next == part.id.raw,
            waiting = pendingByPart[part.id.raw] ?: 0,
            ready = !part.id.isSpeaking || sheet.script.lines(part.id).all { rec.chosen[it.id] != null },
            busy = sheet.busy,
            sheet = sheet,
            onRecord = { onRecord(part.id) },
        )
        }
    }
    sheet.error?.let { item(key = "shared-error") { Column(Modifier.padding(horizontal = Spacing.S4.dp)) { ErrorLine(it) } } }
    val total = pendingByPart.values.sum()
    if (!rec.uploads) {
        item(key = "uploads-off") {
            Text(
                PlaysShare.line(com.example.appname.plays.PlaysException("uploads_off")),
                Modifier.padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp),
                style = MaterialTheme.typography.bodyMedium,
                color = AppSemantics.colors.warning,
            )
        }
    } else if (total > 0) {
        item(key = "upload") {
            Button(
                onClick = sheet::upload,
                enabled = !sheet.busy,
                modifier = Modifier.padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp),
            ) { Text(if (total == 1) "Upload 1 take" else "Upload $total takes") }
        }
    }
    if (director) {
        item(key = "invite") {
            Column(Modifier.padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp), verticalArrangement = Arrangement.spacedBy(Spacing.S1.dp)) {
                OutlinedButton(onClick = sheet::invite, enabled = !sheet.busy) { Text("Invite") }
                sheet.caption?.let { Text(it, style = MaterialTheme.typography.labelMedium) }
            }
        }
    }
    item(key = "people-h") { SectionHeader("People") }
    items(rec.members, key = { "member:" + it.userId }) { member ->
        PersonRow(member.displayName, member.userId == me, member.director, sheet, member.userId)
    }
    if (PlaysShare.needsMyConsent(rec, sheet.script, me)) {
        item(key = "agree") {
            val consent by produceState<com.example.appname.plays.Consent?>(null) { value = sheet.consent() }
            var notNow by remember { mutableStateOf(false) }
            val words = consent
            if (words != null && words.publishes && !notNow) {
                Column(Modifier.padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp), verticalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
                    ConsentWords(words.text)
                    Button(onClick = { sheet.agree(words) }, enabled = !sheet.busy, colors = playButtonColors()) {
                        Text("I agree to publish my recording under CC0.")
                    }
                    TextButton(onClick = { notNow = true }) { Text("Not now") }
                }
            }
        }
    }
    if (PlaysShare.canPublish(rec, sheet.script, me)) {
        item(key = "publish") {
            val consent by produceState<com.example.appname.plays.Consent?>(null) { value = sheet.consent() }
            var asking by remember { mutableStateOf(false) }
            val words = consent
            if (words != null && words.publishes) {
                PlaysShare.performers(rec).forEach { m ->
                    ListItem(
                        headlineContent = { Text(m.displayName ?: "No name") },
                        trailingContent = {
                            Icon(
                                if (m.consented) Icons.Filled.CheckCircle else Icons.Outlined.Circle,
                                contentDescription = if (m.consented) "Agreed" else "Not yet",
                            )
                        },
                    )
                }
                Button(onClick = { asking = true }, enabled = !sheet.busy && PlaysShare.waitingOn(rec).isEmpty(), modifier = Modifier.padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp)) {
                    Text("Publish")
                }
                if (asking) {
                    AlertDialog(
                        onDismissRequest = { asking = false },
                        title = { Text("Publish") },
                        text = { ConsentWords(words.text, Modifier.verticalScroll(rememberScrollState())) },
                        confirmButton = { TextButton(onClick = { asking = false; sheet.publish(words) }) { Text("I agree to publish my recording under CC0.") } },
                        dismissButton = { TextButton(onClick = { asking = false }) { Text("Not now") } },
                    )
                }
            } else if (words != null) {
                Text(PlaysShare.PUBLISH_WAITS, Modifier.padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp), style = MaterialTheme.typography.bodyMedium)
            }
        }
    }
    PlaysShare.archiveLine(rec)?.let { line ->
        item(key = "archive") { ArchiveRow(line, PlaysShare.canPublishAgain(rec, me), sheet) }
    }
    val changes = PlaysShare.changeableLines(rec, sheet.script, me)
    if (changes.isNotEmpty()) {
        item(key = "change-h") { SectionHeader(if (director) "Lines" else "Your lines") }
        items(changes, key = { "change:" + it.line.id }) { change -> ChangeRow(rec.id, change, sheet, onReplace) }
    }
}

/** The archive.org job in essential words (rule 9): quiet while it waits, the item's link (the system opens it), or the Worker's reason with Publish again. */
@Composable
private fun ArchiveRow(line: PlaysShare.ArchiveLine, again: Boolean, sheet: SharedSheet) {
    val pad = Modifier.padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp)
    when (line) {
        is PlaysShare.ArchiveLine.Waiting -> Text(line.text, pad, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        is PlaysShare.ArchiveLine.Published -> {
            val uri = LocalUriHandler.current
            val url = line.url
            if (url != null) {
                TextButton(onClick = { runCatching { uri.openUri(url) } }, modifier = pad) { Text("On archive.org") }
            } else {
                Text("On archive.org", pad, style = MaterialTheme.typography.bodyMedium)
            }
        }
        is PlaysShare.ArchiveLine.Failed -> Column(pad, verticalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
            ErrorLine(line.reason)
            if (again) OutlinedButton(onClick = sheet::publishAgain, enabled = !sheet.busy) { Text("Publish again") }
        }
    }
}

/**
 * One line of a published play (P12, rule 13): Replace opens the recorder on it; Remove asks
 * first, in the error color and never red, and the director picks the reason.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ChangeRow(pid: String, change: PlaysShare.Change, sheet: SharedSheet, onReplace: (PartID, String) -> Unit) {
    val removedSet by sheet.removed.collectAsState()
    val line = change.line
    var reasons by remember { mutableStateOf(false) }
    var confirming by remember { mutableStateOf<String?>(null) }
    val gone = removedSet.any { it.endsWith(" " + line.id) }
    ListItem(
        overlineContent = if (line.role != null) ({ Text(line.role.orEmpty(), style = MaterialTheme.typography.labelMedium) }) else null,
        headlineContent = { Text(line.spokenText, style = MaterialTheme.typography.bodyMedium) },
        supportingContent = {
            if (gone) {
                Text("Removed", style = MaterialTheme.typography.labelMedium)
            } else {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
                    if (change.replace) OutlinedButton(onClick = { onReplace(line.part, line.id) }, enabled = !sheet.busy) { Text("Replace") }
                    TextButton(
                        onClick = { if (change.needsReason) reasons = true else confirming = "withdrawn" },
                        enabled = !sheet.busy,
                    ) { Text("Remove", color = AppSemantics.colors.error) }
                    DropdownMenu(expanded = reasons, onDismissRequest = { reasons = false }) {
                        REASONS.forEach { (code, label) ->
                            DropdownMenuItem(text = { Text(label) }, onClick = { reasons = false; confirming = code })
                        }
                    }
                }
            }
        },
    )
    confirming?.let { reason ->
        AlertDialog(
            onDismissRequest = { confirming = null },
            title = { Text("Remove this line from archive.org?") },
            confirmButton = {
                TextButton(onClick = { confirming = null; sheet.removeLine(line.id, reason) }) {
                    Text("Remove", color = AppSemantics.colors.error)
                }
            },
            dismissButton = { TextButton(onClick = { confirming = null }) { Text("Cancel") } },
        )
    }
}

/** The served consent words as a lead and a bulleted list, none changed. */
@Composable
private fun ConsentWords(text: String, modifier: Modifier = Modifier) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
        ConsentText.blocks(text).forEach { block ->
            when (block.kind) {
                ConsentBlock.Kind.Lead -> Text(block.text, style = MaterialTheme.typography.titleMedium)
                ConsentBlock.Kind.Paragraph -> Text(block.text, style = MaterialTheme.typography.bodyMedium)
                ConsentBlock.Kind.Item -> Row(horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
                    Text("•", Modifier.clearAndSetSemantics { }, style = MaterialTheme.typography.bodyMedium)
                    Text(block.text, Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
                }
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun SharedCastRow(
    modifier: Modifier,
    script: PlayScript,
    part: CastPart,
    state: SharedPart,
    mine: Boolean,
    performerIsMe: Boolean,
    director: Boolean,
    recordingElsewhere: Boolean,
    isNext: Boolean,
    waiting: Int,
    ready: Boolean,
    busy: Boolean,
    sheet: SharedSheet,
    onRecord: () -> Unit,
) {
    val raw = part.id.raw
    val name = state.performer?.let { " · $it" }.orEmpty()
    val status = when (state.status) {
        "recording" -> "Recording$name"
        "done" -> "Recorded$name"
        "silent" -> "Left silent"
        else -> "Open"
    }
    val full = Modifier.fillMaxWidth()
    PartCard(
        script = script,
        part = part,
        holder = if (state.status == "recording" || state.status == "done") Holder.Person(state.performer) else Holder.DeviceVoice,
        recorded = state.status == "done",
        modifier = modifier,
        who = status,
        highlight = state.status == "recording" && mine,
    ) {
        when (state.status) {
            "recording" -> if (mine) {
                Button(onClick = onRecord, enabled = !busy, modifier = full, colors = playButtonColors()) { Text("Record") }
                OutlinedButton(onClick = { sheet.done(raw) }, enabled = !busy && waiting == 0 && ready, modifier = full) { Text("Done with this part") }
                TextButton(onClick = { sheet.release(raw) }, enabled = !busy, modifier = full) { Text("Release") }
            }
            "done", "silent" -> if (!recordingElsewhere && (performerIsMe || director)) {
                OutlinedButton(onClick = { sheet.reopen(raw) }, enabled = !busy, modifier = full, colors = wayColors()) { Text("Open part") }
            }
            else -> if (!recordingElsewhere) {
                if (isNext) {
                    Button(onClick = { sheet.take(raw) }, enabled = !busy, modifier = full, colors = playButtonColors()) { Text("Take part") }
                } else {
                    OutlinedButton(onClick = { sheet.take(raw) }, enabled = !busy, modifier = full, colors = wayColors()) { Text("Take part") }
                }
                if (!part.id.isSpeaking) OutlinedButton(onClick = { sheet.leaveSilent(raw) }, enabled = !busy, modifier = full, colors = wayColors()) { Text("Leave silent") }
            }
        }
    }
}

@Composable
private fun PersonRow(displayName: String?, isMe: Boolean, isDirector: Boolean, sheet: SharedSheet, userId: String) {
    var menu by remember { mutableStateOf(false) }
    var reporting by remember { mutableStateOf(false) }
    var blocking by remember { mutableStateOf(false) }
    val shown = displayName?.takeIf { it.isNotBlank() } ?: "Member"
    val tags = listOfNotNull("You".takeIf { isMe }, "Director".takeIf { isDirector }).joinToString(" · ")
    ListItem(
        headlineContent = { Text(shown) },
        supportingContent = if (tags.isNotEmpty()) ({ Text(tags, style = MaterialTheme.typography.labelMedium) }) else null,
        trailingContent = if (!isMe) ({
            IconButton(onClick = { menu = true }) { Icon(Icons.Filled.MoreVert, contentDescription = "More for $shown") }
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                DropdownMenuItem(text = { Text("Report") }, onClick = { menu = false; reporting = true })
                DropdownMenuItem(text = { Text("Block") }, onClick = { menu = false; blocking = true })
            }
        }) else null,
    )
    if (reporting) ReportDialog(onDismiss = { reporting = false }, onReport = { reason, note -> reporting = false; sheet.report(userId, null, reason, note) })
    if (blocking) {
        AlertDialog(
            onDismissRequest = { blocking = false },
            title = { Text("Block $shown?") },
            text = { Text("You will no longer hear their takes.") },
            confirmButton = {
                TextButton(onClick = { blocking = false; sheet.block(userId) }) { Text("Block", color = AppSemantics.colors.error) }
            },
            dismissButton = { TextButton(onClick = { blocking = false }) { Text("Cancel") } },
        )
    }
}

/** Report (guideline 1.2): a reason and an optional note. */
@Composable
fun ReportDialog(onDismiss: () -> Unit, onReport: (reason: String, note: String) -> Unit) {
    var reason by remember { mutableStateOf<String?>(null) }
    var note by remember { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Report") },
        text = {
            Column {
                REASONS.forEach { (code, label) ->
                    Row(
                        Modifier.fillMaxWidth().selectable(selected = reason == code, role = Role.RadioButton, onClick = { reason = code }),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        RadioButton(selected = reason == code, onClick = null)
                        Text(label, Modifier.padding(start = Spacing.S2.dp))
                    }
                }
                OutlinedTextField(
                    value = note,
                    onValueChange = { note = it.take(500) },
                    label = { Text("Note") },
                    modifier = Modifier.fillMaxWidth().padding(top = Spacing.S2.dp),
                )
            }
        },
        confirmButton = { TextButton(onClick = { reason?.let { onReport(it, note) } }, enabled = reason != null) { Text("Report") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

// MARK: Library's Ear dramas: the invitation, the shared productions, the classes

/** The invitation held for this session (rule 3). */
@Composable
fun InvitationItem(token: String, onOpenProduction: (String) -> Unit) {
    val container = LocalAppContainer.current
    val sharing = container.sharing
    val account by container.accounts.account.collectAsState()
    val plays = container.plays
    LaunchedEffect(Unit) { plays.load() }
    val library by plays.state.collectAsState()
    val signedIn = account != null
    var view by remember(token) { mutableStateOf<InviteView?>(null) }
    var error by remember(token) { mutableStateOf<String?>(null) }
    var name by remember(token) { mutableStateOf("") }
    var busy by remember(token) { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    LaunchedEffect(token, signedIn) {
        if (!signedIn) return@LaunchedEffect
        try {
            view = sharing.viewInvite(token)
            error = null
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            error = PlaysShare.line(e)
        }
    }

    fun join(part: String, v: InviteView) {
        if (busy) return
        busy = true
        error = null
        scope.launch {
            try {
                onOpenProduction(sharing.join(token, part, name, v.scriptID, v.scriptRevision).id)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                error = PlaysShare.line(e)
            } finally {
                busy = false
            }
        }
    }

    SectionHeader("Invitation")
    Column(Modifier.padding(horizontal = Spacing.S4.dp), verticalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
        val v = view
        val ready = library is PlaysLibrary.State.Ready
        val script = if (v != null && ready) {
            PlaysShare.scriptFor((library as PlaysLibrary.State.Ready).scripts, v.scriptID, v.scriptRevision)
        } else {
            null
        }
        when {
            !signedIn -> {
                Text("Sign in to join", style = MaterialTheme.typography.titleMedium)
                AccountRow()
            }
            v == null -> error?.let { ErrorLine(it) }
            ready && script == null -> {
                Text(v.title, style = MaterialTheme.typography.titleMedium)
                ErrorLine(PlaysShare.line(com.example.appname.plays.PlaysException("revision_mismatch")))
            }
            else -> {
                Text(v.title, style = MaterialTheme.typography.titleMedium)
                val anyRecording = v.parts.any { it.status == "recording" }
                if (v.member) {
                    Button(onClick = {
                        if (busy) return@Button
                        busy = true
                        scope.launch {
                            try {
                                onOpenProduction(sharing.openRemote(v.id).id)
                            } catch (e: CancellationException) {
                                throw e
                            } catch (e: Exception) {
                                error = PlaysShare.line(e)
                            } finally {
                                busy = false
                            }
                        }
                    }, enabled = !busy) { Text("Open") }
                } else {
                    if (!anyRecording) {
                        OutlinedTextField(
                            value = name,
                            onValueChange = { name = it },
                            label = { Text("Your name") },
                            singleLine = true,
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                    v.parts.forEach { part ->
                        val id = PartID(part.id)
                        ListItem(
                            headlineContent = { Text(id.title) },
                            supportingContent = { Text(inviteStatus(part.status, part.lineCount), style = MaterialTheme.typography.labelMedium) },
                            trailingContent = if (part.status == "open" && !anyRecording) ({
                                if (v.next == part.id) {
                                    Button(onClick = { join(part.id, v) }, enabled = !busy) { Text("Take part") }
                                } else {
                                    OutlinedButton(onClick = { join(part.id, v) }, enabled = !busy) { Text("Take part") }
                                }
                            }) else null,
                        )
                    }
                }
                error?.let { ErrorLine(it) }
            }
        }
        TextButton(onClick = { sharing.hold(null) }) { Text("Not now") }
    }
}

private fun inviteStatus(status: String, lineCount: Int): String = when (status) {
    "recording" -> "Recording"
    "done" -> "Recorded"
    "silent" -> "Left silent"
    else -> if (lineCount == 1) "1 line" else "$lineCount lines"
}

/** A shared production this person is in that this device has not opened (rule 11). */
@Composable
fun RemoteProductionRow(row: com.example.appname.plays.RemoteRow, onOpenProduction: (String) -> Unit) {
    val sharing = LocalAppContainer.current.sharing
    val scope = rememberCoroutineScope()
    var error by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    Column {
        ListItem(
            headlineContent = { Text(row.title, style = MaterialTheme.typography.titleMedium) },
            modifier = Modifier.clickable(enabled = !busy, onClickLabel = "Open production") {
                busy = true
                error = null
                scope.launch {
                    try {
                        onOpenProduction(sharing.openRemote(row.id).id)
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: Exception) {
                        error = PlaysShare.line(e)
                    } finally {
                        busy = false
                    }
                }
            },
        )
        error?.let { Column(Modifier.padding(horizontal = Spacing.S4.dp)) { ErrorLine(it) } }
    }
}

/** Classes (rule 10): a roster only. Each with its code for its teacher, Make a class, Join a class. */
@Composable
fun ClassesBlock() {
    val sharing = LocalAppContainer.current.sharing
    val classes by sharing.classes.collectAsState()
    val scope = rememberCoroutineScope()
    var making by remember { mutableStateOf(false) }
    var joining by remember { mutableStateOf(false) }
    SectionHeader("Classes")
    classes?.let { answer ->
        (answer.teaching + answer.memberOf).forEach { row -> ClassItem(row) }
    }
    Row(Modifier.padding(horizontal = Spacing.S4.dp), horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
        OutlinedButton(onClick = { making = true }) { Text("Make a class") }
        OutlinedButton(onClick = { joining = true }) { Text("Join a class") }
    }
    if (making) {
        ClassDialog(
            title = "Make a class",
            confirm = "Make",
            withUnder13 = true,
            onDismiss = { making = false },
            onConfirm = { text, under13 -> sharing.makeClass(text, under13) },
            scope = scope,
        )
    }
    if (joining) {
        ClassDialog(
            title = "Join a class",
            confirm = "Join",
            withUnder13 = false,
            onDismiss = { joining = false },
            onConfirm = { text, _ -> sharing.joinClass(text) },
            scope = scope,
        )
    }
}

@Composable
private fun ClassItem(row: ClassRow) {
    val lines = listOfNotNull(
        row.code?.let { PlaysShare.classCodeDisplay(it) },
        "Waits for the school's consent".takeIf { row.under13 && row.code != null && !row.schoolConsent },
    )
    ListItem(
        headlineContent = { Text(row.name, style = MaterialTheme.typography.titleMedium) },
        supportingContent = if (lines.isNotEmpty()) ({ Text(lines.joinToString(" · "), style = MaterialTheme.typography.labelMedium) }) else null,
    )
}

@Composable
private fun ClassDialog(
    title: String,
    confirm: String,
    withUnder13: Boolean,
    onDismiss: () -> Unit,
    onConfirm: suspend (String, Boolean) -> Unit,
    scope: CoroutineScope,
) {
    var text by remember { mutableStateOf("") }
    var under13 by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
                OutlinedTextField(
                    value = text,
                    onValueChange = { text = it },
                    label = { Text(if (withUnder13) "Class name" else "Code") },
                    singleLine = true,
                )
                if (withUnder13) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.S3.dp)) {
                        Switch(checked = under13, onCheckedChange = { under13 = it })
                        Text("Under 13")
                    }
                }
                error?.let { ErrorLine(it) }
            }
        },
        confirmButton = {
            TextButton(
                enabled = text.isNotBlank() && !busy,
                onClick = {
                    busy = true
                    error = null
                    scope.launch {
                        try {
                            onConfirm(text, under13)
                            onDismiss()
                        } catch (e: CancellationException) {
                            throw e
                        } catch (e: Exception) {
                            error = PlaysShare.line(e)
                        } finally {
                            busy = false
                        }
                    }
                },
            ) { Text(confirm) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}
