package com.example.appname.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Explore
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Sensors
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import com.example.appname.ui.revealWhole
import com.example.appname.ui.HeadWindow
import com.example.appname.data.ItemLead
import androidx.compose.runtime.setValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.appname.data.LabelItem
import com.example.appname.data.LabelKind
import com.example.appname.data.SeriesRow
import com.example.appname.data.heroTitle
import com.example.appname.data.labelItem
import com.example.appname.radio.DialEntry
import com.example.appname.radio.HomeLive
import com.example.appname.ui.EventLine
import com.example.appname.ui.LabelArt
import com.example.appname.ui.formatAirDate
import com.example.appname.data.headNameStep
import com.example.appname.ui.nameStyle
import com.example.appname.ui.theme.OnAir
import com.example.appname.ui.theme.Spacing
import com.example.appname.ui.theme.boardColor
import com.example.appname.ui.theme.onBoardColor
import com.example.appname.ui.tvFocusMark
import java.time.Instant

// Home's first screen (WEB-DESIGN §4.2r rules 1-3, ANDROID-DESIGN §4.1, Decision 081): On the air as the hero on its
// show's board, the dial of genre stations under it, and the two quiet doors. "The goal is to have the home view
// feel more cohesive and inviting from the moment that you open the app."

/** Past a phone's column the window stands beside the words, 320 dp, as on the web. */
private val BesideFrom = 560.dp

/**
 * The hero: the board of the show on the air, its window (the show's picture, else its label with the evening's year
 * ticked) full width on a phone and 320 dp beside the words on a wider layout, the kicker, the show's name, the event
 * line, Listen live and All stations.
 */
@Composable
fun OnAirHero(
    on: HomeLive,
    now: Instant,
    series: SeriesRow?,
    tuned: Boolean,
    onTune: () -> Unit,
    onOpenStations: () -> Unit,
    onOpenEpisode: (String) -> Unit,
    liveFocus: FocusRequester,
    modifier: Modifier = Modifier,
) {
    val dark = OnAir.colors.dark
    val episode = on.slot.playableEpisode ?: return
    val genre = series?.genre
    val ground = boardColor(genre, dark)
    val ink = onBoardColor(genre, dark)
    val name = series?.name ?: episode.series
    val label = (series?.labelItem() ?: LabelItem(LabelKind.Series, episode.series, genre)).copy(tickYear = on.tickYear)
    val t = MaterialTheme.typography
    BoxWithConstraints(modifier.fillMaxWidth().padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp)) {
        // A picture keeps its own shape and fills its window (a wide one is a plate over the words); the label stands in for
        // none, a failed load or one under the size floor. Google TV Home drew a wide photo small inside a square window.
        var failed by remember(series?.windowArt) { mutableStateOf(false) }
        val shown = if (failed) null else ItemLead.shown(series?.windowArt)
        val frame = ItemLead.window(shown, maxWidth.value)
        val beside = maxWidth >= BesideFrom && !frame.plate
        val open = Modifier.clickable(onClickLabel = "Open episode") { onOpenEpisode(episode.id) }
        val window = @Composable {
            Box(open) { HeadWindow(shown, label, false, frame, null) { failed = true } }
        }
        val words = @Composable { m: Modifier ->
            Column(m, verticalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
                    Box(Modifier.size(8.dp).clip(CircleShape).background(ink))
                    Text(
                        "ON THE AIR · ${on.kicker.uppercase()}",
                        style = t.labelMedium.copy(letterSpacing = 1.sp),
                        color = ink,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.semantics { heading() },
                    )
                }
                Text(
                    name,
                    style = nameStyle(headNameStep(name), t, headL1 = true),
                    color = ink,
                    maxLines = 3,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.focusProperties { down = liveFocus }.tvFocusMark().then(open),
                )
                EventLine(
                    listOf(heroTitle(episode.title, episode.id) { formatAirDate(it) ?: it }, "${on.minutesIn(now)} min in"),
                    color = ink,
                )
                on.note?.let { Text(it, style = t.labelMedium, color = ink) }
                Row(
                    Modifier.padding(top = Spacing.S1.dp),
                    horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Button(
                        onClick = onTune,
                        colors = ButtonDefaults.buttonColors(containerColor = ink, contentColor = ground),
                        modifier = Modifier.focusRequester(liveFocus).tvFocusMark().semantics {
                            contentDescription = if (tuned) "Listening live to ${on.kicker}, stop" else "Listen live to ${on.kicker}"
                        },
                    ) {
                        Icon(Icons.Filled.Sensors, contentDescription = null)
                        Text(if (tuned) "Listening live" else "Listen live", Modifier.padding(start = Spacing.S2.dp), maxLines = 1)
                    }
                    OutlinedButton(
                        onClick = onOpenStations,
                        colors = ButtonDefaults.outlinedButtonColors(contentColor = ink),
                        border = androidx.compose.foundation.BorderStroke(1.dp, ink.copy(alpha = 0.5f)),
                        modifier = Modifier.tvFocusMark(),
                    ) { Text("All stations", maxLines = 1) }
                }
            }
        }
        val card = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(ground).revealWhole()
        if (beside) {
            Row(card, verticalAlignment = Alignment.CenterVertically) {
                window()
                words(Modifier.weight(1f).padding(Spacing.S6.dp))
            }
        } else {
            Column(card) {
                window()
                words(Modifier.fillMaxWidth().padding(Spacing.S4.dp))
            }
        }
    }
}

/**
 * The dial (WEB-DESIGN §4.2r rule 2): every genre station as a small label, its genre's name and the show it has on
 * now; a press tunes in. It does what the Listen door did.
 */
@Composable
fun HomeDial(entries: List<DialEntry>, liveStation: String?, onTune: (DialEntry) -> Unit, modifier: Modifier = Modifier) {
    LazyRow(
        modifier.fillMaxWidth(),
        contentPadding = PaddingValues(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp),
        horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp),
    ) {
        items(entries, key = { it.station.genre }) { e ->
            val listening = liveStation == e.station.genre
            val name = e.station.name
            val say = e.show?.let { "${if (listening) "Listening live to" else "Listen live to"} $name: $it" } ?: "$name: nothing on"
            Column(
                Modifier.width(96.dp)
                    .then(if (e.on != null) Modifier.clickable(onClickLabel = if (listening) "Stop" else "Tune in") { onTune(e) } else Modifier)
                    .tvFocusMark()
                    .semantics(mergeDescendants = true) { contentDescription = say; selected = listening },
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                StationMark(e, 56.dp)
                Spacer4()
                Text(
                    name,
                    style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.SemiBold),
                    color = if (listening) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    textAlign = TextAlign.Center,
                )
                Text(
                    e.show.orEmpty(),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    textAlign = TextAlign.Center,
                )
            }
        }
    }
}

@Composable
private fun Spacer4() = androidx.compose.foundation.layout.Spacer(Modifier.size(Spacing.S1.dp))

/**
 * A station's label on the dial: its genre's board with the year ticked. Given the station's name the label draws the
 * name's monogram in its center (LabelSpec), where the web's dial, passing no name, drew a blank disc.
 */
@Composable
fun StationMark(e: DialEntry, side: androidx.compose.ui.unit.Dp, modifier: Modifier = Modifier) {
    LabelArt(
        LabelItem(LabelKind.Station, e.station.name, e.station.genre, tickYear = e.year?.toString()),
        modifier.size(side).clip(RoundedCornerShape(4.dp)),
    )
}

/** The doors (§4.2r rule 3): two quiet buttons in one row. A TV draws none: focus does the work and Find a show is a tab. */
@Composable
fun HomeDoors(onFind: () -> Unit, onRecord: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp),
        horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp),
    ) {
        OutlinedButton(onClick = onFind, modifier = Modifier.tvFocusMark()) {
            Icon(Icons.Filled.Explore, contentDescription = null)
            Text("Find a show", Modifier.padding(start = Spacing.S2.dp), maxLines = 1)
        }
        OutlinedButton(onClick = onRecord, modifier = Modifier.tvFocusMark()) {
            Icon(Icons.Filled.Mic, contentDescription = null)
            Text("Record a play", Modifier.padding(start = Spacing.S2.dp), maxLines = 1)
        }
    }
}
