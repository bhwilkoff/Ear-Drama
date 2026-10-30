package com.example.appname.ui

import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.background
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.example.appname.data.EpisodeRow
import com.example.appname.ui.theme.Spacing
import kotlinx.coroutines.launch

/**
 * The queue verbs (the web's Detail button and Library rows): add to the end,
 * remove, reorder. They never change what plays next (Decision 067).
 */

/** A long-press menu on an episode row: add or remove, and in the queue's own list, one step up or down. */
@Composable
fun QueueMenu(episodeId: String, open: Boolean, onDismiss: () -> Unit, inQueueList: Boolean = false) {
    val container = LocalAppContainer.current
    val scope = rememberCoroutineScope()
    val queued by produceState(emptyList<String>(), open) { if (open) value = container.user.queue() }
    val index = queued.indexOf(episodeId)
    DropdownMenu(expanded = open, onDismissRequest = onDismiss) {
        if (index < 0) {
            DropdownMenuItem(
                text = { Text("Add to queue") },
                onClick = { onDismiss(); scope.launch { container.queue.add(episodeId) } },
            )
        } else {
            if (inQueueList) {
                DropdownMenuItem(
                    text = { Text("Move up") },
                    enabled = index > 0,
                    onClick = { onDismiss(); scope.launch { container.queue.move(episodeId, -1) } },
                )
                DropdownMenuItem(
                    text = { Text("Move down") },
                    enabled = index < queued.size - 1,
                    onClick = { onDismiss(); scope.launch { container.queue.move(episodeId, 1) } },
                )
            }
            DropdownMenuItem(
                text = { Text("Remove from queue") },
                onClick = { onDismiss(); scope.launch { container.queue.remove(episodeId) } },
            )
        }
    }
}

/** Detail's toggle, the web's "Add to queue" / "In queue" (`aria-pressed`). */
@Composable
fun QueueToggle(episodeId: String, folded: Boolean, modifier: Modifier = Modifier) {
    val container = LocalAppContainer.current
    val scope = rememberCoroutineScope()
    val changes by container.user.changes.collectAsState()
    val queued by produceState(false, changes) { value = episodeId in container.user.queue() }
    FoldButton(
        if (queued) Icons.Filled.Check else Icons.Filled.Add,
        if (queued) "In queue" else "Add to queue",
        folded,
        { scope.launch { if (queued) container.queue.remove(episodeId) else container.queue.add(episodeId) } },
        modifier,
    )
}

/** Library's Queue section: swipe a row away to remove it; long-press for Move up, Move down, Remove. */
@OptIn(ExperimentalMaterial3Api::class)
fun LazyListScope.queueSection(rows: List<EpisodeRow>, onOpen: (String) -> Unit, onPlay: (EpisodeRow) -> Unit) {
    if (rows.isEmpty()) return
    item(key = "queue-h") { SectionHeader("Queue") }
    items(rows.size, key = { "q:" + rows[it].id }) { i ->
        val row = rows[i]
        val container = LocalAppContainer.current
        val state = rememberSwipeToDismissBoxState()
        LaunchedEffect(state.currentValue) {
            if (state.currentValue == SwipeToDismissBoxValue.EndToStart) container.queue.remove(row.id)
        }
        SwipeToDismissBox(
            state = state,
            enableDismissFromStartToEnd = false,
            backgroundContent = {
                Box(
                    Modifier.fillMaxSize().background(MaterialTheme.colorScheme.errorContainer)
                        .padding(horizontal = Spacing.S4.dp),
                    contentAlignment = Alignment.CenterEnd,
                ) {
                    Icon(Icons.Filled.Delete, contentDescription = "Remove from queue")
                }
            },
        ) {
            EpisodeListItem(
                row,
                showSeries = true,
                onOpen = { onOpen(row.id) },
                onPlay = { onPlay(row) },
                inQueueList = true,
                modifier = Modifier.background(MaterialTheme.colorScheme.surface),
            )
        }
    }
}
