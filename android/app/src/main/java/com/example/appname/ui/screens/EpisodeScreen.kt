package com.example.appname.ui.screens

import androidx.compose.ui.Alignment
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
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
import com.example.appname.data.EpisodeDetail
import com.example.appname.data.Progress
import com.example.appname.data.Recording
import com.example.appname.data.SeriesRow
import com.example.appname.data.Transcript
import com.example.appname.data.episodeFacts
import com.example.appname.data.leadPicture
import com.example.appname.data.onAirOf
import com.example.appname.navigation.SiteLinks
import com.example.appname.ui.ActionRow
import com.example.appname.ui.CastAndCredits
import com.example.appname.ui.ClaimTvFocus
import com.example.appname.ui.DownloadButton
import com.example.appname.ui.EmptyMessage
import com.example.appname.ui.EventLine
import com.example.appname.ui.HeadBoard
import com.example.appname.ui.Loadable
import com.example.appname.ui.LoadableContent
import com.example.appname.ui.LocalAppContainer
import com.example.appname.ui.Meta
import com.example.appname.ui.OnTheAir
import com.example.appname.ui.PictureCredit
import com.example.appname.ui.QueueToggle
import com.example.appname.ui.SectionHeader
import com.example.appname.ui.ShareButton
import com.example.appname.ui.episodeCount
import com.example.appname.ui.episodeShareTitle
import com.example.appname.ui.episodeTitle
import com.example.appname.ui.formatAirDateLong
import com.example.appname.ui.formatClock
import com.example.appname.ui.formatLength
import com.example.appname.ui.headSlot
import com.example.appname.ui.playButtonColors
import com.example.appname.ui.rememberCatalogQuery
import com.example.appname.ui.seriesYears
import com.example.appname.ui.theme.Spacing
import com.example.appname.ui.tvFocusMark

/**
 * Episode Detail (§4.4, R11d): the head board of its show, the episode's title and event line, one
 * button row, the ear drama row where a script exists, On the air, Cast and credits folded, the
 * recordings in rank order, the rights line.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EpisodeScreen(
    id: String,
    onBack: () -> Unit,
    onOpenSeries: (String) -> Unit,
    onOpenTranscript: (String) -> Unit,
    onOpenProduction: (String) -> Unit,
    onOpenPerson: (String) -> Unit,
) {
    val container = LocalAppContainer.current
    val plays = rememberCastablePlays()
    val detail by rememberCatalogQuery(id, watchUser = true) { db ->
        db.episodeDetail(id)?.let { it to container.user.progress(it.episode.id) }
    }
    val shownSeries = (detail as? Loadable.Ready)?.value?.first?.episode?.seriesKey
    val seriesState by rememberCatalogQuery(shownSeries) { db -> shownSeries?.let { db.series(it) } }
    Scaffold(
        topBar = {
            TopAppBar(
                title = {},
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
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
            // On a TV the D-pad starts on Play (§9.2, tvOS-DESIGN §6.2).
            val play = remember { FocusRequester() }
            ClaimTvFocus(play, row.id)
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
                LazyColumn(Modifier.widthIn(max = 720.dp).fillMaxSize(), contentPadding = padding) {
                    episodeHead(
                        d = d,
                        series = (seriesState as? Loadable.Ready)?.value,
                        progress = progress,
                        playFocus = play,
                        onPlay = { container.playback.play(row) },
                        onOpenSeries = onOpenSeries,
                        onOpenPerson = onOpenPerson,
                        onOpenTranscript = onOpenTranscript,
                        queue = { folded -> QueueToggle(row.id, folded) },
                        share = { folded -> ShareButton(episodeShareTitle(row), SiteLinks.episode(row.id), folded) },
                        download = { folded -> DownloadButton(d, folded) },
                        earDrama = plays.firstOrNull { it.id == d.script }?.let { script ->
                            @Composable { StartEarDramaButton(script, onOpenProduction) }
                        },
                    )
                    if (d.recordings.size > 1) {
                        item(key = "versions-h") { SectionHeader("Versions") }
                        items(d.recordings, key = { "r${it.rank}" }) { rec ->
                            VersionItem(rec, onPlay = { container.playback.play(row, url = rec.url) })
                        }
                    } else {
                        d.recordings.firstOrNull()?.let { rec ->
                            val notes = recordingNotes(rec)
                            if (notes.isNotEmpty()) {
                                item(key = "only-copy") {
                                    Meta(notes.joinToString(" · "), Modifier.padding(horizontal = Spacing.S4.dp))
                                }
                            }
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
}

/**
 * The episode page down to its credits: every slot is drawn in the same order whether the episode
 * is rich or bare, and a section with nothing in it is not drawn.
 */
fun LazyListScope.episodeHead(
    d: EpisodeDetail,
    series: SeriesRow?,
    progress: Progress?,
    playFocus: FocusRequester,
    onPlay: () -> Unit,
    onOpenSeries: (String) -> Unit,
    onOpenPerson: (String) -> Unit,
    onOpenTranscript: (String) -> Unit,
    queue: @Composable RowScope.(Boolean) -> Unit,
    share: @Composable RowScope.(Boolean) -> Unit,
    download: @Composable RowScope.(Boolean) -> Unit,
    earDrama: (@Composable () -> Unit)?,
) {
    val row = d.episode
    val genre = series?.genre ?: row.seriesGenre
    val lead = leadPicture(series, d.credits, d.star)
    item(key = "head") {
        HeadBoard(
            name = row.seriesName,
            genre = genre,
            art = lead,
            kicker = genre?.let { DisplayVocabulary.genreName(it) } ?: "Show",
            facts = listOf(series?.let { seriesYears(it) } ?: "Undated", series?.let { episodeCount(it.episodes) }),
            first = series?.firstDate,
            last = series?.lastDate,
            years = series?.yearCounts,
            onOpen = { onOpenSeries(row.seriesKey) },
        )
    }
    item(key = "title") {
        Text(
            episodeTitle(row),
            style = MaterialTheme.typography.displaySmall,
            modifier = Modifier.padding(start = Spacing.S4.dp, end = Spacing.S4.dp, top = Spacing.S3.dp).semantics { heading() },
        )
        EventLine(
            episodeFacts(d.network, d.sponsor, row.season, row.title, row.num, formatAirDateLong(row.airDate), formatLength(row.lengthSeconds)),
            Modifier.padding(horizontal = Spacing.S4.dp, vertical = Spacing.S1.dp),
        )
    }
    item(key = "actions") {
        val resume = progress?.takeIf { !it.finished && it.positionMs > 0 }
        ActionRow(Modifier.padding(horizontal = Spacing.S4.dp, vertical = Spacing.S3.dp), foldBelow = 600.dp) { fit ->
            Button(
                onClick = onPlay,
                enabled = d.recordings.isNotEmpty(),
                modifier = Modifier.weight(1f).focusRequester(playFocus).tvFocusMark(),
                colors = playButtonColors(),
                contentPadding = ButtonDefaults.ButtonWithIconContentPadding,
            ) {
                Icon(Icons.Filled.PlayArrow, contentDescription = null)
                Text(
                    if (resume == null) "Play" else if (fit.tight) "Resume" else "Resume at ${formatClock(resume.positionMs)}",
                    maxLines = 1,
                )
            }
            queue(fit.folded)
            share(fit.folded)
            download(fit.folded)
        }
    }
    // Decision 068: an episode linked to a castable script this bundle holds; none on a TV.
    if (earDrama != null) {
        item(key = "ear-drama") {
            Box(Modifier.padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp)) { earDrama() }
        }
    }
    item(key = "credit") {
        PictureCredit(listOf(lead), headSlot(), Modifier.padding(horizontal = Spacing.S4.dp))
    }
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
    val air = onAirOf(d.credits)
    if (air.isNotEmpty()) {
        item(key = "air") { OnTheAir(air, genre, onOpenPerson) }
        item(key = "air-credit") {
            PictureCredit(air.map { it.art }.filter { it?.evidence != lead?.evidence || it?.evidence == null }, 72.dp, Modifier.padding(horizontal = Spacing.S4.dp))
        }
    }
    if (d.credits.isNotEmpty()) {
        item(key = "credits") { CastAndCredits(d.credits, onOpenPerson) }
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
