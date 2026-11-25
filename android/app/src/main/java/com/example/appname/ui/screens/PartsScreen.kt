package com.example.appname.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.clickable
import androidx.compose.material3.Button
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.example.appname.plays.PartID
import com.example.appname.plays.PlayScript
import com.example.appname.plays.ReadCore
import com.example.appname.plays.ReadFailure
import com.example.appname.plays.RelayCore
import com.example.appname.plays.SeatHome
import com.example.appname.plays.SeatLink
import com.example.appname.plays.SeatTake
import com.example.appname.plays.ShareJson
import com.example.appname.ui.LocalAppContainer
import com.example.appname.ui.theme.Spacing
import com.example.appname.ui.SectionHeader
import java.io.File
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

// Your parts (PLAYS-DESIGN §12.11, ANDROID-DESIGN §4.21): a seat at home. Its parts from the class, each line with its
// take's state on this device ("On this device · sends when Ms. Ortiz is in Ear Drama", "Sending", "Sent") and the
// teacher's review. The takes are the studio's own, recorded in a production kept on this device; the sender is RelayHub.
// Every word is a label, a fact, a warning or a refusal.

/** The lines of a part with each take's state. A plain column (no lazy list), so it draws in a screen and to a PNG. */
@Composable
fun RelayLines(rows: List<RelayCore.Row>, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth()) {
        rows.forEach { row ->
            Column(Modifier.fillMaxWidth().padding(vertical = 8.dp)) {
                Text(row.text, style = MaterialTheme.typography.bodyMedium)
                row.state?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                row.review?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = if (row.again) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant) }
            }
            HorizontalDivider()
        }
    }
}

/** The classes this device holds a seat in (names only; the key is in the Keystore vault). */
class HomeSeats(private val file: File) {
    fun load(): List<SeatLink> = runCatching { ShareJson.decodeFromString<List<SeatLink>>(file.readText()) }.getOrDefault(emptyList())
    fun add(s: SeatLink) {
        file.parentFile?.mkdirs()
        file.writeText(ShareJson.encodeToString(load().filter { it.classId != s.classId } + s))
    }
}

private class Block(val seat: SeatLink, val className: String, val production: SeatHome.Production, val script: PlayScript, val key: String)

private fun say(e: Exception): String = if (e is ReadFailure) ReadCore.refusal(e.code) else ReadCore.refusal("error")

@Composable
fun PartsScreen(onBack: () -> Unit, onRecord: OpenStudio) {
    val container = LocalAppContainer.current
    val context = androidx.compose.ui.platform.LocalContext.current
    val scope = rememberCoroutineScope()
    val relay = container.relay
    val store = container.plays.store
    val homeSeats = remember { HomeSeats(File(context.filesDir, "home-seats.json")) }
    val wire = container.readClass
    val seatWire = remember { com.example.appname.plays.WorkerSeat(container.accounts.worker) }
    var blocks by remember { mutableStateOf<List<Block>>(emptyList()) }
    var loaded by remember { mutableStateOf(false) }
    var failure by remember { mutableStateOf<String?>(null) }
    var classCode by remember { mutableStateOf("") }
    var seatList by remember { mutableStateOf<com.example.appname.plays.ReadSeatList?>(null) }
    var receiverName by remember { mutableStateOf<Map<String, String>>(emptyMap()) }
    var attempt by remember { mutableStateOf(0) }
    @Suppress("UNUSED_VARIABLE") val revision by relay.revision.collectAsState()

    LaunchedEffect(attempt) {
        failure = null
        val out = ArrayList<Block>()
        for (seat in homeSeats.load()) {
            val key = relay.vault.key(seat.classId) ?: continue
            try {
                val home = seatWire.home(key)
                for (p in home.productions.filter { it.assignments.isNotEmpty() }) {
                    // A catalog play at the library's revision; an own script by this seat's key, drawn only once it is whole (§13 item 14).
                    val script = if (com.example.appname.plays.OwnShare.isOwn(p.scriptID)) {
                        try {
                            container.scripts.scriptOf(
                                p.scriptID, p.scriptRevision, com.example.appname.plays.ScriptWho(seat = key, pid = p.id),
                                com.example.appname.plays.OwnShare.Fits.seat(p.assignments.map { Triple(it.part, it.from, it.to) }),
                            )
                        } catch (e: CancellationException) {
                            throw e
                        } catch (e: Exception) {
                            failure = if (com.example.appname.plays.RelayCore.codeOf(e) == "no_script") "Your teacher has not sent this script yet." else com.example.appname.plays.OwnShare.scriptLine(e).ifEmpty { say(e) }
                            null
                        }
                    } else {
                        container.plays.script(p.scriptID)?.takeIf { it.revision == p.scriptRevision }
                    }
                    if (script == null) { if (failure == null) failure = ReadCore.refusal("revision_mismatch"); continue }
                    out += Block(seat, home.`class`.name, p, script, key)
                    runCatching { seatWire.receiver(key, p.id) }.getOrNull()?.name?.let { receiverName = receiverName + (p.id to it) }
                }
            } catch (e: CancellationException) { throw e } catch (e: Exception) { failure = say(e) }
        }
        blocks = out
        loaded = true
        out.forEach { b -> store.findShared(b.production.id)?.let { relay.kick(it.id) } }
    }

    Scaffold(topBar = { BackBar(onBack, "Your parts") }) { padding ->
        Column(Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(Spacing.S4.dp), verticalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
            if (homeSeats.load().isEmpty()) {
                OutlinedTextField(classCode, { classCode = it.uppercase() }, label = { Text("Class code") }, singleLine = true)
                Button(onClick = {
                    scope.launch {
                        failure = null
                        try { seatList = wire.seatList(classCode) } catch (e: CancellationException) { throw e } catch (e: Exception) { failure = say(e) }
                    }
                }, enabled = classCode.isNotBlank()) { Text("Show names") }
                seatList?.let { l ->
                    SectionHeader(l.`class`.name)
                    l.seats.forEach { s ->
                        ListItem(
                            headlineContent = { Text(s.label, style = MaterialTheme.typography.bodyMedium) },
                            modifier = Modifier.fillMaxWidth().clickable {
                                scope.launch {
                                    try {
                                        val r = wire.seatClaim(classCode, s.id, false)
                                        relay.vault.set(l.`class`.id, r.seatKey)
                                        homeSeats.add(SeatLink(l.`class`.id, s.label))
                                        attempt += 1
                                    } catch (e: CancellationException) { throw e } catch (e: Exception) { failure = say(e) }
                                }
                            },
                        )
                    }
                }
            } else if (loaded && blocks.isEmpty() && failure == null) {
                Text("No parts yet.", style = MaterialTheme.typography.bodySmall)
            }
            blocks.forEach { b ->
                SectionHeader("${b.seat.label} · ${b.className}")
                Text(b.production.title, style = MaterialTheme.typography.titleMedium)
                val cast = b.script.lines.map { it.id to it.part.raw }
                val mine = RelayCore.assignedLines(cast, b.production.assignments).toSet()
                b.production.assignments.map { it.part }.distinct().forEach { part ->
                    val lines = b.script.lines.filter { it.part.raw == part && it.id in mine }
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                        Text("${PartID(part).title} · ${lines.size} ${if (lines.size == 1) "line" else "lines"}", style = MaterialTheme.typography.titleMedium)
                        Button(onClick = {
                            val local = store.findShared(b.production.id) ?: store.create(b.script)
                            relay.linkSeat(local.id, b.production.id, b.seat.classId, b.seat.label, b.key, b.production.assignments)
                            scope.launch { relay.kick(local.id) }
                            onRecord(b.script.id, null, local.id, part)
                        }) { Text("Record") }
                    }
                    val local = store.findShared(b.production.id)
                    val link = local?.let { store.share(it.id) }
                    val st = local?.let { relay.stateOf(it.id) }
                    val remote: Map<String, SeatTake> = b.production.takes.associateBy { it.lineID }
                    RelayLines(RelayCore.rows(lines, local, remote, link?.sent.orEmpty().toSet(), link?.refused.orEmpty(), st?.sending, st?.name ?: receiverName[b.production.id]))
                    Spacer(Modifier.padding(4.dp))
                }
            }
            failure?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        }
    }
}
