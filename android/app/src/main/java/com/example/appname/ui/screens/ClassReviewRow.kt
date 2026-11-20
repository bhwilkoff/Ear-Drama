package com.example.appname.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.appname.plays.ClassReview
import com.example.appname.plays.ClassReviewItem
import com.example.appname.ui.theme.Spacing

/**
 * One take waiting for the teacher on the class page (PLAYS-DESIGN §12.4 Review, §12.11): the seat, the part, the play, the
 * line's words, then Play (when the take passed through to this device), Approve and Again. The note is optional and goes with
 * Again only. Stateless but for the note, so a render can draw it.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ClassReviewRow(
    item: ClassReviewItem,
    seatLabel: String,
    partTitle: String,
    words: String,
    canPlay: Boolean,
    onPlay: () -> Unit = {},
    onDecide: (String, String?) -> Unit = { _, _ -> },
) {
    var note by remember(item.id) { mutableStateOf("") }
    Column(Modifier.fillMaxWidth().padding(vertical = Spacing.S1.dp), verticalArrangement = Arrangement.spacedBy(Spacing.S1.dp)) {
        Text("$seatLabel \u00B7 $partTitle \u00B7 ${item.playTitle}", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(words, style = MaterialTheme.typography.bodyMedium, maxLines = 3, overflow = TextOverflow.Ellipsis)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(Spacing.S1.dp)) {
            if (canPlay) TextButton(onClick = onPlay) { Text("Play") }
            else Text("On another device", Modifier.padding(horizontal = Spacing.S2.dp, vertical = Spacing.S2.dp), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            TextButton(onClick = { onDecide("approved", null) }) { Text("Approve") }
            TextButton(onClick = { onDecide("again", ClassReview.note(note)) }) { Text("Again") }
        }
        OutlinedTextField(note, { note = it.take(500) }, label = { Text("Note to $seatLabel") }, modifier = Modifier.fillMaxWidth(), minLines = 1, maxLines = 3)
    }
}
