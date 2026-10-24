package com.example.appname.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Shuffle
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
import com.example.appname.plays.PlayScript
import com.example.appname.radio.RadioClock
import com.example.appname.radio.TonightDay
import com.example.appname.ui.CenteredBox
import com.example.appname.ui.EmptyMessage
import com.example.appname.ui.EpisodeListItem
import com.example.appname.ui.LocalAppContainer
import com.example.appname.ui.SectionHeader
import com.example.appname.ui.theme.Spacing
import kotlin.coroutines.cancellation.CancellationException

/** One draw: each pick is absent when the data has none (ANDROID-DESIGN §4.14). */
private data class Picks(val episode: EpisodeRow?, val evening: TonightDay?, val first: EpisodeDetail?)

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
        value = Picks(episode, day, first)
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
        LazyColumn(Modifier.fillMaxSize(), contentPadding = padding) {
            p.episode?.let { row ->
                item(key = "episode-h") { SectionHeader("An episode") }
                item(key = "episode") {
                    EpisodeListItem(row, showSeries = true, onOpen = { onOpenEpisode(row.id) },
                        onPlay = { container.playback.play(row) })
                }
            }
            p.evening?.let { day ->
                item(key = "evening-h") { SectionHeader("An evening") }
                item(key = "evening") {
                    Column(Modifier.padding(horizontal = Spacing.S4.dp), verticalArrangement = Arrangement.spacedBy(Spacing.S1.dp)) {
                        Text(RadioClock.longDate(day.evening), style = MaterialTheme.typography.titleMedium)
                        day.stationLine?.let { Text(it, style = MaterialTheme.typography.bodyMedium) }
                    }
                }
                p.first?.let { detail ->
                    item(key = "evening-first") {
                        // From its start, never live, and nothing queued behind it.
                        EpisodeListItem(detail.episode, showSeries = true, onOpen = { onOpenEpisode(detail.episode.id) },
                            onPlay = {
                                container.live.stop()
                                container.playback.play(detail.episode, startMs = 0, queue = false)
                            })
                    }
                }
            }
            script?.let { s ->
                item(key = "play-h") { SectionHeader("A play") }
                item(key = "play") { PlayListItem(s, onOpen = { onOpenScript(s.id) }) }
                item(key = "play-start") {
                    Column(Modifier.padding(horizontal = Spacing.S4.dp)) { StartEarDramaButton(s, onOpenProduction) }
                }
            }
        }
    }
}
