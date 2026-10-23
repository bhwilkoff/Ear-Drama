package com.example.appname.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.example.appname.navigation.SiteLinks
import com.example.appname.together.ListenTogether
import com.example.appname.together.RoomStatus
import com.example.appname.ui.theme.Spacing
import kotlinx.coroutines.launch

/** The https link a room's code travels as (DEEP_LINKS.md): the web opens it, and so does the app once its filters are on. */
fun roomLink(code: String): String = SiteLinks.ROOT + "?room=" + code

/** Library's entry to Listen together (§4.13), so a code can be typed with nothing playing. */
@Composable
fun ListenTogetherRow(onOpen: () -> Unit) {
    val status by LocalAppContainer.current.together.status.collectAsState()
    val inRoom = status as? RoomStatus.In
    ListItem(
        modifier = Modifier.fillMaxWidth().tvFocusMark().clickable(onClickLabel = "Open Listen together", onClick = onOpen),
        leadingContent = { Icon(Icons.Filled.Groups, contentDescription = null) },
        headlineContent = { Text("Listen together") },
        supportingContent = inRoom?.let { { Text("Room ${it.code}") } },
    )
}

/**
 * The Listen together sheet (ANDROID-DESIGN §4.13): start a room from the
 * episode playing, or join by code; in a room, the code, how many are
 * listening, Share, Leave, and End room for the host.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ListenTogetherSheet(initialCode: String, onDismiss: () -> Unit) {
    val container = LocalAppContainer.current
    val together = container.together
    val status by together.status.collectAsState()
    val now by container.playback.state.collectAsState()
    val scope = rememberCoroutineScope()
    val television = LocalIsTelevision.current
    val context = LocalContext.current
    var typed by remember(initialCode) { mutableStateOf(initialCode) }
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            Modifier.fillMaxWidth().padding(horizontal = Spacing.S6.dp).padding(bottom = Spacing.S6.dp).navigationBarsPadding(),
            verticalArrangement = Arrangement.spacedBy(Spacing.S3.dp),
        ) {
            Text("Listen together", style = MaterialTheme.typography.headlineSmall)
            when (val s = status) {
                RoomStatus.Unavailable -> Text(
                    ListenTogether.NOT_AVAILABLE,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                RoomStatus.Busy -> CircularProgressIndicator(Modifier.semantics { contentDescription = "Loading" })
                is RoomStatus.Out -> {
                    if (now.episode != null) {
                        Button(onClick = { scope.launch { together.create() } }, modifier = Modifier.tvFocusMark()) {
                            Text("Start a room")
                        }
                    }
                    val field = remember { FocusRequester() }
                    ClaimTvFocus(field, Unit)
                    val join = { scope.launch { together.join(typed) }; Unit }
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.S3.dp)) {
                        OutlinedTextField(
                            value = typed,
                            onValueChange = { typed = it.take(12) },
                            label = { Text("Room code") },
                            singleLine = true,
                            keyboardOptions = KeyboardOptions(
                                capitalization = KeyboardCapitalization.Characters,
                                autoCorrectEnabled = false,
                                keyboardType = KeyboardType.Ascii,
                                imeAction = ImeAction.Go,
                            ),
                            keyboardActions = KeyboardActions(onGo = { join() }),
                            modifier = Modifier.weight(1f).focusRequester(field).tvFocusMark(),
                        )
                        OutlinedButton(onClick = join, enabled = typed.isNotBlank(), modifier = Modifier.tvFocusMark()) {
                            Text("Join")
                        }
                    }
                    s.line?.let {
                        Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                is RoomStatus.In -> {
                    Text(
                        s.code,
                        style = MaterialTheme.typography.displaySmall,
                        modifier = Modifier.semantics { contentDescription = "Room code ${s.code.toList().joinToString(" ")}" },
                    )
                    Text(
                        if (s.members == 1) "1 listening" else "${s.members} listening",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(Spacing.S3.dp)) {
                        if (!television) {
                            Button(onClick = { context.shareLink("Listen together", roomLink(s.code)) }) { Text("Share") }
                        }
                        val leave = remember { FocusRequester() }
                        ClaimTvFocus(leave, s.code)
                        OutlinedButton(
                            onClick = { scope.launch { together.leave() } },
                            modifier = Modifier.focusRequester(leave).tvFocusMark(),
                        ) { Text("Leave") }
                        if (s.isHost) {
                            TextButton(onClick = { scope.launch { together.end() } }, modifier = Modifier.tvFocusMark()) {
                                Text("End room")
                            }
                        }
                    }
                }
            }
        }
    }
}
