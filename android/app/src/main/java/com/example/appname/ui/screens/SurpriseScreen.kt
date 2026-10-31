package com.example.appname.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Shuffle
import androidx.compose.material.icons.filled.PlayArrow
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
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.example.appname.data.EpisodeDetail
import com.example.appname.data.EpisodeRow
import com.example.appname.data.SeriesRow
import com.example.appname.plays.PlayScript
import com.example.appname.radio.RadioClock
import com.example.appname.radio.TonightDay
import com.example.appname.ui.CenteredBox
import com.example.appname.ui.EmptyMessage
import com.example.appname.ui.HeadBoard
import com.example.appname.ui.PlayHeadBoard
import com.example.appname.ui.episodeTitle
import com.example.appname.ui.formatAirDate
import com.example.appname.ui.playButtonColors
import com.example.appname.ui.tvFocusMark
import com.example.appname.ui.LocalAppContainer
import com.example.appname.ui.SectionHeader
import com.example.appname.ui.theme.Spacing
import kotlin.coroutines.cancellation.CancellationException

/** One draw: each pick is absent when the data has none (ANDROID-DESIGN §4.14). */
private data class Picks(val episode: EpisodeRow?, val series: SeriesRow?, val evening: TonightDay?, val first: EpisodeDetail?)

/**
 * Surprise (Decision 068; Archive Watch's Home shuffle): an episode, an evening,
 * and a play, drawn when it opens and again on Shuffle, each one tap from
 * playing or starting. `kotlin.random.Random` and SQLite's random(): nothing
 * needs to match another device. No copy is written.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SurpriseScreen(onBack: () -> Unit, onOpenEpisode: (String) -> Unit, onOpenScript: (String) -> Unit, onOpenProduction: (String) -> Unit) {
    val container = LocalAppContainer.current
    val dbVersion by container.catalog.dbVersion.collectAsState()
    var draw by rememberSaveable { mutableIntStateOf(0) }
    val scripts = rememberCastablePlays()
    val script: PlayScript? = remember(draw, scripts) { scripts.randomOrNull() }
    val picks by produceState<Picks?>(null, draw, dbVersion) {
        value = null
        val db = container.catalog.awaitDb()
        val episode = db?.randomEpisode()
        val day = try {
            container.api.tonight()?.days?.values?.randomOrNull()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            println("[Surprise] tonight.json unreachable: ${e.message}")
            null
        }
        val first = day?.slots?.firstNotNullOfOrNull { slot ->
            slot.playableEpisode?.let { db?.episodeDetail(it.id) }?.takeIf { it.recordings.isNotEmpty() }
        }
        value = Picks(episode, episode?.let { db.series(it.seriesKey) }, day, first)
    }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Surprise") },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back") }
                },
                actions = {
                    IconButton(onClick = { draw += 1 }) { Icon(Icons.Filled.Shuffle, contentDescription = "Shuffle") }
                },
            )
        },
    ) { padding ->
        val p = picks
        if (p == null) {
            CenteredBox(Modifier.padding(padding)) {
                CircularProgressIndicator(Modifier.semantics { contentDescription = "Loading" })
            }
            return@Scaffold
        }
        if (p.episode == null && p.evening == null && script == null) {
            EmptyMessage("Nothing to pick from yet.", Modifier.padding(padding))
            return@Scaffold
        }
        LazyColumn(Modifier.fillMaxSize(), contentPadding = padding, verticalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
            p.episode?.let { row ->
                item(key = "episode-h") { SectionHeader("An episode") }
                item(key = "episode") {
                    HeadBoard(
                        name = row.seriesName, genre = row.seriesGenre, art = row.seriesWindowArt, kicker = null,
                        facts = listOf(episodeTitle(row), formatAirDate(row.airDate)),
                        first = p.series?.firstDate, last = p.series?.lastDate, years = p.series?.yearCounts,
                        onOpen = { onOpenEpisode(row.id) },
                    )
                }
                item(key = "episode-play") { PlayPick("Play") { container.playback.play(row) } }
            }
            p.evening?.let { day ->
                val lead = p.first?.episode
                item(key = "evening-h") { SectionHeader("An evening") }
                item(key = "evening") {
                    HeadBoard(
                        name = RadioClock.longDate(day.evening), genre = lead?.seriesGenre, art = lead?.seriesWindowArt, kicker = null,
                        facts = listOf(day.stationLine, lead?.seriesName), first = null, last = null,
                    )
                }
                p.first?.let { detail ->
                    item(key = "evening-play") {
                        // From its start, never live, and nothing queued behind it.
                        PlayPick("Play") {
                            container.live.stop()
                            container.playback.play(detail.episode, startMs = 0, queue = false)
                        }
                    }
                }
            }
            script?.let { s ->
                item(key = "play-h") { SectionHeader("A play") }
                item(key = "play") {
                    PlayHeadBoard(s, kicker = if (s.kind == "stage") "Stage play" else "Radio play",
                        modifier = Modifier.clickable(onClickLabel = "Open play") { onOpenScript(s.id) })
                }
                item(key = "play-start") {
                    Column(Modifier.padding(horizontal = Spacing.S4.dp)) { StartEarDramaButton(s, onOpenProduction) }
                }
            }
        }
    }
}

@Composable
private fun PlayPick(label: String, onClick: () -> Unit) {
    Column(Modifier.padding(horizontal = Spacing.S4.dp)) {
        Button(onClick = onClick, colors = playButtonColors(), modifier = Modifier.tvFocusMark()) {
            Icon(Icons.Filled.PlayArrow, contentDescription = null)
            Text(label, Modifier.padding(start = Spacing.S2.dp), maxLines = 1)
        }
    }
}
