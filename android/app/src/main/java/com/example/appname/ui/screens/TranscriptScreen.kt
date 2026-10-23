package com.example.appname.ui.screens

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.example.appname.data.Transcript
import com.example.appname.ui.CenteredBox
import com.example.appname.ui.EmptyMessage
import com.example.appname.ui.LoadableContent
import com.example.appname.ui.LocalAppContainer
import com.example.appname.ui.episodeTitle
import com.example.appname.ui.rememberCatalogQuery
import com.example.appname.ui.theme.Spacing

private sealed interface TranscriptLoad {
    data object Loading : TranscriptLoad
    data class Loaded(val text: String) : TranscriptLoad
    data class Failed(val offline: Boolean) : TranscriptLoad
}

/**
 * R16, text is a peer of sound: archive.org's automatic transcript, fetched
 * from its own URL when opened (never bundled), as plain selectable text at
 * the body size, so font scaling applies.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TranscriptScreen(id: String, onBack: () -> Unit) {
    val container = LocalAppContainer.current
    val detail by rememberCatalogQuery(id) { db -> db.episodeDetail(id) }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(Transcript.LABEL) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { padding ->
        LoadableContent(detail, Modifier.padding(padding)) { d ->
            val url = d?.transcriptUrl
            if (d == null || url == null) {
                EmptyMessage("This episode has no transcript.", Modifier.padding(padding))
                return@LoadableContent
            }
            val context = LocalContext.current
            var attempt by rememberSaveable { mutableIntStateOf(0) }
            val load by produceState<TranscriptLoad>(TranscriptLoad.Loading, url, attempt) {
                value = TranscriptLoad.Loading
                value = try {
                    TranscriptLoad.Loaded(container.api.text(url))
                } catch (e: kotlinx.coroutines.CancellationException) {
                    throw e
                } catch (_: Throwable) {
                    TranscriptLoad.Failed(offline = !isOnline(context))
                }
            }
            when (val state = load) {
                TranscriptLoad.Loading -> CenteredBox(Modifier.padding(padding)) {
                    CircularProgressIndicator(Modifier.semantics { contentDescription = "Loading" })
                }
                is TranscriptLoad.Failed -> CenteredBox(Modifier.padding(padding)) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(
                            if (state.offline) "You are offline." else "The transcript did not load.",
                            style = MaterialTheme.typography.bodyMedium,
                            textAlign = TextAlign.Center,
                        )
                        Spacer(Modifier.height(Spacing.S4.dp))
                        Button(onClick = { attempt++ }) { Text("Try again") }
                    }
                }
                is TranscriptLoad.Loaded -> Column(
                    Modifier
                        .fillMaxSize()
                        .padding(padding)
                        .verticalScroll(rememberScrollState())
                        .padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp),
                ) {
                    Text(
                        episodeTitle(d.episode),
                        style = MaterialTheme.typography.titleMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(Modifier.height(Spacing.S3.dp))
                    SelectionContainer {
                        Text(
                            Transcript.lines(state.text).joinToString("\n"),
                            style = MaterialTheme.typography.bodyMedium,
                            modifier = Modifier.widthIn(max = 680.dp),
                        )
                    }
                }
            }
        }
    }
}

private fun isOnline(context: Context): Boolean {
    val cm = context.getSystemService(ConnectivityManager::class.java) ?: return true
    val caps = cm.getNetworkCapabilities(cm.activeNetwork) ?: return false
    return caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
}
