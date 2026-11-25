package com.example.appname.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.example.appname.app.AppContainer
import com.example.appname.plays.OwnShare
import com.example.appname.plays.OwnState
import com.example.appname.plays.PlayScript
import com.example.appname.plays.PlaysException
import com.example.appname.plays.PlaysShare
import com.example.appname.plays.SharedRecord
import com.example.appname.ui.theme.Spacing
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// What a shared own script's cast sheet adds after its Parts (PLAYS-DESIGN §13 items 11, 12, 13, 15, 16; ANDROID-DESIGN §4.23):
// who can read it, or the state's refusal, the reason it has no Publish, then Read together, Edit a copy, Report script.

@Composable
internal fun OwnScriptBox(
    rec: SharedRecord,
    own: OwnState,
    director: Boolean,
    me: String?,
    sheet: SharedSheet,
    notSent: Throwable?,
    readTogether: (@Composable () -> Unit)?,
    onEditCopy: (() -> Unit)?,
) {
    var reporting by remember { mutableStateOf(false) }
    Column(Modifier.padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp), verticalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
        when (own.state) {
            "owed" -> {
                ErrorLine(if (director) OwnShare.NOT_SENT else PlaysShare.line(PlaysException("no_script")))
                if (director) {
                    notSent?.let { ErrorLine(PlaysShare.line(it)) }
                    OutlinedButton(onClick = sheet::sendAgain, enabled = !sheet.busy) { Text("Try again") }
                }
            }
            "removed" -> ErrorLine(PlaysShare.line(PlaysException("script_removed")))
            else -> Text(OwnShare.readers(rec, me), style = MaterialTheme.typography.labelMedium)
        }
        Text(OwnShare.CANT_PUBLISH, style = MaterialTheme.typography.labelMedium)
        ChipFlow {
            if (own.state == "kept" && director && rec.classId == null) readTogether?.invoke()
            if (own.mine) {
                onEditCopy?.let { OutlinedButton(onClick = it) { Text("Edit a copy") } }
            } else if (own.state == "kept") {
                OutlinedButton(onClick = { reporting = true }, enabled = !sheet.busy) { Text("Report script") }
            }
        }
    }
    if (reporting) {
        ReportDialog(onDismiss = { reporting = false }, reasons = OwnShare.SCRIPT_REASONS, title = "Report script") { reason, note ->
            reporting = false
            sheet.reportScript(reason, note)
        }
    }
}

/** Delete, in the sheet the title opens, for a script not yet Done (PLAYS-DESIGN §13 item 11): [delete] runs before the page goes. */
@Composable
internal fun DeleteNotDone(title: String, delete: suspend () -> Unit, onGone: () -> Unit) {
    var asking by remember { mutableStateOf(false) }
    var failed by remember { mutableStateOf<String?>(null) }
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    TextButton(onClick = { asking = true }) { Text("Delete", color = com.example.appname.ui.theme.AppSemantics.colors.error) }
    failed?.let { Refusal(it) }
    if (asking) {
        DestructiveConfirm(
            message = "Delete $title?", action = "Delete",
            onConfirm = {
                asking = false
                scope.launch {
                    try {
                        delete()
                        onGone()
                    } catch (e: kotlinx.coroutines.CancellationException) {
                        throw e
                    } catch (e: Exception) {
                        failed = "This device could not delete it."
                    }
                }
            },
            onDismiss = { asking = false },
        )
    }
}

/**
 * The production of [script] a reading of it carries (item 13): the one this person already shared, else null. A text that is
 * owed is sent first. A production gone from the Worker is passed over.
 */
internal suspend fun alreadySharedProduction(container: AppContainer, script: PlayScript): String? {
    val me = container.accounts.account.value?.userId ?: return null
    val store = container.plays.store
    for (p in withContext(Dispatchers.IO) { store.all() }) {
        val link = store.share(p.id) ?: continue
        if (p.scriptID != script.id || link.seat != null) continue
        val rec = try {
            container.sharing.refresh(p.id)
        } catch (e: PlaysException) {
            if (e.code == "not_found") continue else throw e
        }
        val own = OwnShare.ownState(rec, me) ?: continue
        if (rec.director != me || rec.scriptRevision != script.revision || own.state == "removed" || rec.classId != null) continue
        if (own.state == "owed") OwnShare.sendScript(container.scriptWire, link.pid, withContext(Dispatchers.IO) { store.script(p) } ?: script)
        return link.pid
    }
    return null
}

/** Shares a production of [script] for a reading; the Worker's id of it. A refusal is thrown, and a production nothing was shared of is dropped. */
internal suspend fun shareForReading(container: AppContainer, script: PlayScript): String {
    val local = container.plays.create(script)
    try {
        val rec = container.sharing.share(local.id, script, null)
        container.sharing.notSent.value[local.id]?.let { throw it }
        return rec.id
    } catch (e: Exception) {
        withContext(Dispatchers.IO) { container.plays.store.dropIfEmpty(local.id) }
        throw e
    }
}
