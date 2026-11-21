package com.example.appname.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.selection.selectable
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.SelectableDates
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import com.example.appname.plays.AgeGate
import com.example.appname.plays.ClassDates
import com.example.appname.plays.ReadCore
import com.example.appname.ui.SectionHeader
import com.example.appname.ui.theme.AppSemantics
import com.example.appname.ui.theme.Spacing
import java.time.LocalDate
import java.time.ZoneOffset

// Student privacy (PLAYS-DESIGN §12.12, Decision 084): the class page's Class section and School approval, the destructive
// confirmation, the date picker, and the age question. Stateless where a render can draw it; words are exactly the document's.

/** The Class section that closes the teacher's class page (§12.12 item 1). */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun ClassSection(endsOn: String?, busy: Boolean, onChangeDate: () -> Unit, onExport: () -> Unit, onDelete: () -> Unit) {
    SectionHeader("Class")
    endsOn?.let { Text("Ends ${ClassDates.text(it)}", style = MaterialTheme.typography.bodyMedium) }
    FlowRow(horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
        OutlinedButton(onClick = onChangeDate, enabled = !busy) { Text("Change date") }
        OutlinedButton(onClick = onExport, enabled = !busy) { Text("Export class") }
        TextButton(onClick = onDelete, enabled = !busy) { Text("Delete class", color = AppSemantics.colors.error) }
    }
}

/** An under-13 class without the school's approval: the teacher names who approved (§12.12 item 5). */
@Composable
internal fun SchoolApproval(busy: Boolean, error: String?, onRecord: (String) -> Unit, initialChecked: Boolean = false, initialReference: String = "") {
    var ok by remember { mutableStateOf(initialChecked) }
    var reference by remember { mutableStateOf(initialReference) }
    var line by remember { mutableStateOf<String?>(null) }
    SectionHeader("School approval")
    Row(
        Modifier.fillMaxWidth().selectable(ok, role = Role.Checkbox, onClick = { ok = !ok }),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Checkbox(ok, onCheckedChange = null)
        Text("My school or district approved Ear Drama for this class.", Modifier.padding(start = Spacing.S2.dp), style = MaterialTheme.typography.bodyMedium)
    }
    OutlinedTextField(
        reference, { reference = it.take(120) },
        label = { Text("Approved by") },
        placeholder = { Text("School or district, and the approval") },
        modifier = Modifier.fillMaxWidth(),
    )
    (line ?: error)?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.labelMedium) }
    Button(
        enabled = !busy,
        onClick = {
            line = when {
                !ok -> ReadCore.refusal("confirmations_required")
                reference.isBlank() -> ReadCore.refusal("reference_required")
                else -> null
            }
            if (line == null) onRecord(reference.trim())
        },
    ) { Text("Record") }
}

/** The destructive confirmation: the whole sentence, the destructive button in the error role, and Cancel. */
@Composable
internal fun DestructiveConfirm(message: String, action: String, onConfirm: () -> Unit, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        text = { Text(message) },
        confirmButton = { TextButton(onClick = onConfirm) { Text(action, color = AppSemantics.colors.error) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

/** Today to 400 days ahead, by calendar day: the picker's UTC midnights are days, never shifted by a time zone. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ClassDateDialog(endsOn: String?, today: LocalDate = LocalDate.now(), onPick: (String) -> Unit, onDismiss: () -> Unit) {
    val last = today.plusDays(ClassDates.MAX_DAYS)
    val bounds = remember(today) {
        object : SelectableDates {
            override fun isSelectableDate(utcTimeMillis: Long): Boolean {
                val day = java.time.Instant.ofEpochMilli(utcTimeMillis).atZone(ZoneOffset.UTC).toLocalDate()
                return !day.isBefore(today) && !day.isAfter(last)
            }
            override fun isSelectableYear(year: Int) = year in today.year..last.year
        }
    }
    val start = endsOn?.let(ClassDates::parse)?.takeIf { !it.isBefore(today) && !it.isAfter(last) }
    val state = rememberDatePickerState(
        initialSelectedDateMillis = start?.atStartOfDay(ZoneOffset.UTC)?.toInstant()?.toEpochMilli(),
        selectableDates = bounds,
    )
    DatePickerDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton(
                enabled = state.selectedDateMillis != null,
                onClick = {
                    state.selectedDateMillis?.let { onPick(java.time.Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate().toString()) }
                },
            ) { Text("Change date") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    ) { DatePicker(state) }
}

/** The file name Export class saves as: the class's name without characters a file name cannot hold (as the web does). */
internal fun exportFileName(className: String): String {
    val clean = className.replace(Regex("[\\\\/:*?\"<>|]+"), "").trim().ifEmpty { "Class" }
    return "$clean export.json"
}

// ---- The age question ----

/** The age question's state for one screen; the answer's only kept form is `ed.over13` (§12.12 item 8). */
@Stable
class AgeAsk(private val store: AgeGate.Store, private val thisYear: () -> Int) {
    var stage by mutableStateOf(Stage.None)
        private set
    private var pending: (() -> Unit)? = null

    enum class Stage { None, Asking, Refused }

    /** Runs [go] when sharing may go on; asks once per device. */
    fun ask(go: () -> Unit) {
        when (store.known()) {
            true -> go()
            false -> stage = Stage.Refused
            null -> { pending = go; stage = Stage.Asking }
        }
    }

    fun year() = thisYear()

    fun answer(birthYear: Int) {
        val over = !AgeGate.isUnder13(birthYear, year())
        store.keep(over)
        val go = pending
        pending = null
        stage = if (over) Stage.None else Stage.Refused
        if (over) go?.invoke()
    }

    fun cancel() { pending = null; stage = Stage.None }
}

@Composable
fun rememberAgeAsk(): AgeAsk {
    val context = LocalContext.current
    return remember(context) { AgeAsk(AgeGate.Store(context.applicationContext.getSharedPreferences("ed.age", android.content.Context.MODE_PRIVATE))) { LocalDate.now().year } }
}

/** Draws the age question or its refusal when the state asks; put it anywhere in the screen that calls [AgeAsk.ask]. */
@Composable
fun AgeAskDialogs(ask: AgeAsk) {
    when (ask.stage) {
        AgeAsk.Stage.Asking -> AgeQuestionDialog(AgeGate.years(ask.year()), onContinue = ask::answer, onCancel = ask::cancel)
        AgeAsk.Stage.Refused -> AgeRefusalDialog(onDismiss = ask::cancel)
        AgeAsk.Stage.None -> Unit
    }
}

/** "What year were you born?": a year picker with no default, Continue and Cancel. */
@Composable
internal fun AgeQuestionDialog(years: List<Int>, onContinue: (Int) -> Unit, onCancel: () -> Unit, initial: Int? = null) {
    var picked by remember { mutableStateOf(initial) }
    AlertDialog(
        onDismissRequest = onCancel,
        title = { Text("What year were you born?") },
        text = {
            LazyColumn(Modifier.height(280.dp)) {
                items(years, key = { it }) { y ->
                    Row(
                        Modifier.fillMaxWidth().selectable(picked == y, role = Role.RadioButton, onClick = { picked = y }),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        RadioButton(picked == y, onClick = null)
                        Text(y.toString(), Modifier.padding(start = Spacing.S3.dp, top = Spacing.S2.dp, bottom = Spacing.S2.dp))
                    }
                }
            }
        },
        confirmButton = { TextButton(enabled = picked != null, onClick = { picked?.let(onContinue) }) { Text("Continue") } },
        dismissButton = { TextButton(onClick = onCancel) { Text("Cancel") } },
    )
}

@Composable
internal fun AgeRefusalDialog(onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        text = { Text("Sharing is for 13 and over. Your teacher can add you to a class.") },
        confirmButton = { TextButton(onClick = onDismiss) { Text("OK") } },
    )
}
