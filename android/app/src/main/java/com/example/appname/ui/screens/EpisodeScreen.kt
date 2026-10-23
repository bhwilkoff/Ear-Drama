package com.example.appname.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.FormatQuote
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.example.appname.data.DisplayVocabulary
import com.example.appname.data.Recording
import com.example.appname.data.Transcript
import com.example.appname.navigation.SiteLinks
import com.example.appname.ui.ClaimTvFocus
import com.example.appname.ui.DownloadControl
import com.example.appname.ui.EmptyMessage
import com.example.appname.ui.Loadable
import com.example.appname.ui.LoadableContent
import com.example.appname.ui.LocalAppContainer
import com.example.appname.ui.Meta
import com.example.appname.ui.SectionHeader
import com.example.appname.ui.ShareAction
import com.example.appname.ui.detailFacts
import com.example.appname.ui.episodeShareTitle
import com.example.appname.ui.episodeTitle
import com.example.appname.ui.formatAirDate
import com.example.appname.ui.formatClock
import com.example.appname.ui.formatLength
import com.example.appname.ui.rememberCatalogQuery
import com.example.appname.ui.liveButtonColors
import com.example.appname.ui.tvFocusMark
import com.example.appname.ui.theme.OnAir
import com.example.appname.ui.theme.Spacing

/** Episode Detail (§4.4): series, title, date, facts, Play, Share, credits, versions in rank order, the rights line. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EpisodeScreen(
    id: String,
    onBack: () -> Unit,
    onOpenSeries: (String) -> Unit,
    onOpenTranscript: (String) -> Unit,
) {
    val container = LocalAppContainer.current
    val detail by rememberCatalogQuery(id, watchUser = true) { db ->
        db.episodeDetail(id)?.let { it to container.user.progress(it.episode.id) }
    }
    val shown = (detail as? Loadable.Ready)?.value?.first?.episode
    Scaffold(
        topBar = {
            TopAppBar(
                title = {},
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    shown?.let { ShareAction(episodeShareTitle(it), SiteLinks.episode(it.id)) }
                },
            )
        },
    ) { padding ->
        LoadableContent(detail, Modifier.padding(padding)) { loaded ->
            if (loaded == null) {
                EmptyMessage("This episode is not in the catalog.", Modifier.padding(padding))
                return@LoadableContent
            }
            val (d, progress) = loaded
            val row = d.episode
            val pad = Modifier.padding(horizontal = Spacing.S4.dp)
            // On a TV the D-pad starts on Play (§9.2, tvOS-DESIGN §6.2).
            val play = remember { FocusRequester() }
            ClaimTvFocus(play, row.id)
            LazyColumn(Modifier.fillMaxSize(), contentPadding = padding) {
                // §4.4, the web's order: the series, the title, the date, then the facts.
                item(key = "head") {
                    Text(
                        row.seriesName,
                        style = MaterialTheme.typography.titleMedium,
                        color = OnAir.colors.link,
                        modifier = Modifier
                            .tvFocusMark()
                            .clickable(onClickLabel = "Open series") { onOpenSeries(row.seriesKey) }
                            .padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp),
                    )
                    Text(
                        episodeTitle(row),
                        style = MaterialTheme.typography.displaySmall,
                        modifier = pad.semantics { heading() },
                    )
                    formatAirDate(row.airDate)?.let {
                        Text(
                            it,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = pad,
                        )
                    }
                    detailFacts(d)?.let { Meta(it, pad) }
                }
                item(key = "play") {
                    val resume = progress?.takeIf { !it.finished && it.positionMs > 0 }
                    Button(
                        onClick = { container.playback.play(row) },
                        enabled = d.recordings.isNotEmpty(),
                        modifier = Modifier.padding(Spacing.S4.dp).focusRequester(play).tvFocusMark(),
                        colors = liveButtonColors(),
                        contentPadding = ButtonDefaults.ButtonWithIconContentPadding,
                    ) {
                        Icon(Icons.Filled.PlayArrow, contentDescription = null)
                        Text(if (resume != null) "Resume at ${formatClock(resume.positionMs)}" else "Play")
                    }
                }
                item(key = "download") { DownloadControl(d) }
                if (d.transcriptUrl != null) {
                    item(key = "transcript") {
                        OutlinedButton(
                            onClick = { onOpenTranscript(row.id) },
                            modifier = Modifier.padding(horizontal = Spacing.S4.dp).tvFocusMark(),
                            contentPadding = ButtonDefaults.ButtonWithIconContentPadding,
                        ) {
                            Icon(Icons.Filled.FormatQuote, contentDescription = null)
                            Text(Transcript.LABEL)
                        }
                    }
                }
                if (d.credits.isNotEmpty()) {
                    item(key = "credits-h") { SectionHeader("Cast and credits") }
                    // A person can hold two roles on one broadcast; the credit's position is its identity here.
                    itemsIndexed(d.credits, key = { i, _ -> "c$i" }) { _, c ->
                        ListItem(
                            headlineContent = { Text(c.name) },
                            supportingContent = listOfNotNull(c.character, c.role).joinToString(" · ")
                                .ifEmpty { null }?.let { { Text(it) } },
                        )
                    }
                }
                if (d.recordings.size > 1) {
                    item(key = "versions-h") { SectionHeader("Versions") }
                    items(d.recordings, key = { "r${it.rank}" }) { rec ->
                        VersionItem(rec, onPlay = { container.playback.play(row, url = rec.url) })
                    }
                } else {
                    d.recordings.firstOrNull()?.let { rec ->
                        val notes = recordingNotes(rec)
                        if (notes.isNotEmpty()) item(key = "only-copy") { Meta(notes.joinToString(" · "), pad) }
                    }
                }
                d.rightsLine?.let { line ->
                    item(key = "rights") {
                        Meta(line, Modifier.padding(Spacing.S4.dp))
                    }
                }
            }
        }
    }
}

private fun recordingNotes(rec: Recording): List<String> =
    listOfNotNull(DisplayVocabulary.variantLine(rec.variant), DisplayVocabulary.PARTIAL.takeIf { rec.partial })

@Composable
private fun VersionItem(rec: Recording, onPlay: () -> Unit) {
    val technical = listOfNotNull(rec.format, rec.kbps?.let { "$it kbps" }, formatLength(rec.lengthSeconds))
        .joinToString(" · ")
    val notes = recordingNotes(rec).joinToString(" · ")
    ListItem(
        headlineContent = { Text(rec.archiveId) },
        supportingContent = listOf(technical, notes).filter { it.isNotEmpty() }.joinToString("\n")
            .ifEmpty { null }?.let { { Text(it) } },
        trailingContent = {
            IconButton(onClick = onPlay, modifier = Modifier.tvFocusMark()) {
                Icon(Icons.Filled.PlayArrow, contentDescription = "Play the copy from ${rec.archiveId}")
            }
        },
    )
}
