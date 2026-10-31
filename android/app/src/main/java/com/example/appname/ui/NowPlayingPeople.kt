package com.example.appname.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.unit.dp
import androidx.compose.ui.Modifier
import com.example.appname.data.EpisodeRow
import com.example.appname.data.onAirOf
import com.example.appname.ui.theme.Spacing

/**
 * Now Playing's two sections under the controls (direction D, D3-9): "On the air", the episode's
 * credited performers as round faces, and "That night on the radio", the other surviving
 * broadcasts of the same air date (contract §3.3b, `CatalogDatabase.sameDay`). Each draws only
 * when it has something: no credits, or an undated episode, leaves nothing and no heading.
 */
@Composable
fun NowPlayingPeople(
    episode: EpisodeRow,
    onOpenPerson: (String) -> Unit,
    onOpenEpisode: (String) -> Unit,
    onPlay: (EpisodeRow) -> Unit,
    modifier: Modifier = Modifier,
) {
    val credits by rememberCatalogQuery(episode.id) { db -> db.episodeDetail(episode.id)?.credits.orEmpty() }
    val night by rememberCatalogQuery(episode.id, episode.airDate) { db -> db.sameDay(episode.airDate, episode.id) }
    val air = onAirOf((credits as? Loadable.Ready)?.value.orEmpty())
    val same = (night as? Loadable.Ready)?.value.orEmpty()
    if (air.isEmpty() && same.isEmpty()) return
    Column(modifier) {
        if (air.isNotEmpty()) {
            OnTheAir(air, episode.seriesGenre, onOpenPerson)
            PictureCredit(air.map { it.art }, 72.dp, Modifier.padding(horizontal = Spacing.S4.dp))
        }
        if (same.isNotEmpty()) {
            SectionHeader("That night on the radio", Modifier.padding(top = Spacing.S4.dp))
            same.forEach { row ->
                EpisodeListItem(
                    row, showSeries = true, showDate = false, supporting = row.network,
                    onOpen = { onOpenEpisode(row.id) }, onPlay = { onPlay(row) },
                )
            }
        }
    }
}
