package com.example.appname.ui

import androidx.compose.ui.text.font.FontStyle
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonColors
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.State
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.appname.app.AppContainer
import com.example.appname.data.undatedBare
import com.example.appname.data.CatalogDatabase
import com.example.appname.data.EpisodeDetail
import com.example.appname.data.EpisodeRow
import com.example.appname.data.PersonRow
import com.example.appname.data.SeriesRow
import com.example.appname.ui.theme.OnAir
import com.example.appname.ui.theme.Spacing
import java.util.Locale
import kotlinx.coroutines.launch

val LocalAppContainer = compositionLocalOf<AppContainer> { error("AppContainer not provided") }

/** A query's state on screen: the four states of `universal-feature-states`. */
sealed interface Loadable<out T> {
    data object Loading : Loadable<Nothing>
    data class Ready<T>(val value: T) : Loadable<T>
    /** No catalog could be opened on this device. */
    data object NoCatalog : Loadable<Nothing>
    data object Failed : Loadable<Nothing>
}

/**
 * Runs [query] against the open catalog, re-running whenever the catalog
 * swaps (dbVersion), a [keys] value changes, or (with [watchUser]) the
 * listener's own records change.
 * The previous value stays on screen while a re-run is in flight.
 */
@Composable
fun <T> rememberCatalogQuery(
    vararg keys: Any?,
    watchUser: Boolean = false,
    query: suspend (CatalogDatabase) -> T,
): State<Loadable<T>> {
    val container = LocalAppContainer.current
    val dbVersion by container.catalog.dbVersion.collectAsState()
    val userChanges by container.user.changes.collectAsState()
    val userKey = if (watchUser) userChanges else 0
    return produceState<Loadable<T>>(Loadable.Loading, dbVersion, userKey, *keys) {
        val db = container.catalog.awaitDb()
        value = if (db == null) Loadable.NoCatalog else try {
            Loadable.Ready(query(db))
        } catch (_: Throwable) {
            Loadable.Failed
        }
    }
}

/** Renders loading, no-catalog and failed; calls [content] with a ready value. */
@Composable
fun <T> LoadableContent(state: Loadable<T>, modifier: Modifier = Modifier, content: @Composable (T) -> Unit) {
    when (state) {
        Loadable.Loading -> CenteredBox(modifier) {
            CircularProgressIndicator(Modifier.semantics { contentDescription = "Loading" })
        }
        Loadable.NoCatalog, Loadable.Failed -> RetryMessage(catalogProblem(state, LocalOnline.current)!!, modifier)
        is Loadable.Ready -> content(state.value)
    }
}

/**
 * The words a catalog screen shows instead of its rows. With no catalog and no
 * network the cause is the network: a neutral offline sentence (web §7.3).
 */
fun catalogProblem(state: Loadable<*>, online: Boolean): String? = when (state) {
    Loadable.NoCatalog -> if (online) "No catalog on this device yet." else OFFLINE_LINE
    Loadable.Failed -> "The catalog could not be read."
    else -> null
}

@Composable
private fun RetryMessage(text: String, modifier: Modifier) {
    val container = LocalAppContainer.current
    val scope = rememberCoroutineScope()
    CenteredBox(modifier) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(text, style = MaterialTheme.typography.bodyMedium, textAlign = TextAlign.Center)
            Spacer(Modifier.height(Spacing.S4.dp))
            Button(onClick = { scope.launch { container.catalog.refresh() } }) { Text("Try again") }
        }
    }
}

/** A filled button for the primary action (Play, Listen through, Listen live): On Air's ink (§6.1a). */
@Composable
fun playButtonColors(): ButtonColors =
    ButtonDefaults.buttonColors(containerColor = OnAir.colors.play, contentColor = OnAir.colors.onPlay)

/** The filled Start recording button: red, which means recording and nothing else (§6.1a). */
@Composable
fun recordButtonColors(): ButtonColors =
    ButtonDefaults.buttonColors(containerColor = OnAir.colors.record, contentColor = OnAir.colors.onRecord)

/** The one way on from an empty state: a verb and what it does. */
data class EmptyAction(val label: String, val onClick: () -> Unit)

/**
 * The one empty state (§7.1a): the fact and, when one exists, one productive
 * action. It sits beside the navigation the screen carries, never in its place.
 * On a TV the action takes the focus, unless the screen keeps it where the
 * listener just pressed ([claimTvFocus] false).
 */
@Composable
fun EmptyMessage(
    text: String,
    modifier: Modifier = Modifier,
    action: EmptyAction? = null,
    claimTvFocus: Boolean = true,
) {
    val fill = if (action == null) Modifier.fillMaxSize() else Modifier.fillMaxWidth()
    Column(
        modifier = modifier.then(fill).padding(Spacing.S6.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Spacing.S3.dp, Alignment.CenterVertically),
    ) {
        Text(
            text,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
        if (action != null) {
            val focus = remember { FocusRequester() }
            if (claimTvFocus) ClaimTvFocus(focus, action.label)
            FilledTonalButton(onClick = action.onClick, modifier = Modifier.focusRequester(focus).tvFocusMark()) {
                Text(action.label)
            }
        }
    }
}

@Composable
fun CenteredBox(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Column(
        modifier = modifier.fillMaxSize().padding(Spacing.S6.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) { content() }
}

@Composable
fun SectionHeader(text: String, modifier: Modifier = Modifier) {
    Text(
        text,
        style = MaterialTheme.typography.headlineSmall,
        modifier = modifier
            .padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp)
            .semantics { heading() },
    )
}

/**
 * R1: the date is the identity, shown as the catalog stores it (`1943-02-24`),
 * as Apple and the web do, in the tabular style so a column of dates aligns.
 */
fun formatAirDate(date: String?): String? = date?.takeIf { it.isNotBlank() }

/**
 * The episode page's date, as the web writes it: a full day in the device's long date format
 * ("May 25, 1943"); a year-only or month-only date stays as precise as the catalog is (R1), so it is
 * shown as stored.
 */
fun formatAirDateLong(date: String?, locale: Locale = Locale.getDefault()): String? {
    val d = formatAirDate(date) ?: return null
    if (d.length != 10) return d
    return try {
        java.time.LocalDate.parse(d).format(java.time.format.DateTimeFormatter.ofLocalizedDate(java.time.format.FormatStyle.LONG).withLocale(locale))
    } catch (_: java.time.format.DateTimeParseException) {
        d
    }
}

/** "30 min", or null when the length is unknown (LibriVox chapters are stored as 0). */
fun formatLength(seconds: Double?): String? =
    seconds?.takeIf { it >= 60 }?.let { "${(it / 60).toInt()} min" }

fun formatClock(ms: Long): String {
    val total = (ms / 1000).coerceAtLeast(0)
    val h = total / 3600
    val m = (total % 3600) / 60
    val s = total % 60
    return if (h > 0) String.format(Locale.US, "%d:%02d:%02d", h, m, s)
    else String.format(Locale.US, "%d:%02d", m, s)
}

/** "1949–50" for a broadcast season, "Undated" for the null season. */
fun seasonLabel(season: String?): String = season?.replace('-', '–') ?: "Undated"

fun episodeTitle(row: EpisodeRow): String =
    row.title?.takeIf { it.isNotBlank() } ?: row.num?.let { "No. $it" } ?: formatAirDate(row.airDate) ?: row.seriesName

/**
 * Detail's one facts line (ANDROID-DESIGN §4.4, WEB-DESIGN §4.5): "Undated"
 * opens it when no date is known, then the network, the sponsor, and the
 * length; a part with no data is absent.
 */
fun detailFacts(d: EpisodeDetail): String? = listOfNotNull(
    "Undated".takeIf { formatAirDate(d.episode.airDate) == null },
    d.network,
    d.sponsor,
    formatLength(d.episode.lengthSeconds),
).joinToString(" · ").ifEmpty { null }

/** The share sheet's title for an episode, the web's: "Sorry, Wrong Number (1943-05-25)". */
fun episodeShareTitle(row: EpisodeRow): String = "${episodeTitle(row)} (${formatAirDate(row.airDate) ?: "undated"})"

fun seriesYears(row: SeriesRow): String? {
    val first = row.firstDate?.take(4) ?: return null
    val last = row.lastDate?.take(4)
    return if (last == null || last == first) first else "$first–$last"
}

/**
 * An episode row (R11b, the one grammar): the date block leads (R1) in a list of one series, the
 * series' window where the list mixes series; then the title, the sub line (the series and date
 * where series mix, then [supporting]), the length, and Play. Tapping opens Detail; long press
 * opens the queue menu.
 */
@Composable
fun EpisodeListItem(
    row: EpisodeRow,
    showSeries: Boolean,
    onOpen: () -> Unit,
    onPlay: () -> Unit,
    modifier: Modifier = Modifier,
    supporting: String? = null,
    inQueueList: Boolean = false,
    /** Search's transcript match: the line as said, verbatim from the automatic transcript. */
    quote: String? = null,
) {
    var menuOpen by remember { mutableStateOf(false) }
    val title = episodeTitle(row)
    val length = formatLength(row.lengthSeconds)
    val date = formatAirDate(row.airDate)
    Box {
        GrammarRow(
            title = title,
            visual = { m ->
                if (showSeries || undatedBare(row.airDate, row.num)) PictureWindow(row.seriesWindowArt, row.seriesName, row.seriesGenre, m)
                else DateBlock(row.airDate, row.num, row.seriesGenre, m)
            },
            onOpen = onOpen,
            modifier = modifier,
            sub = if (showSeries) listOf(row.seriesName, date ?: "Undated", supporting) else listOf(supporting),
            length = length,
            onPlay = onPlay,
            playDescription = "Play $title",
            description = listOfNotNull(title, row.seriesName.takeIf { showSeries }, date ?: "Undated", supporting, length)
                .joinToString(", "),
            onLongClick = { menuOpen = true },
            quote = quote,
        )
        QueueMenu(row.id, menuOpen, { menuOpen = false }, inQueueList)
    }
}

/** A person in Search: portrait or initial, the name, and how many episodes credit them. */
@Composable
fun PersonListItem(row: PersonRow, onOpen: () -> Unit) {
    ListItem(
        modifier = Modifier.fillMaxWidth().tvFocusMark().clickable(onClickLabel = "Open person", onClick = onOpen),
        leadingContent = { ArtTile(row.person.name, null, row.person.face) },
        headlineContent = {
            Column {
                Text(row.person.name, maxLines = 2, overflow = TextOverflow.Ellipsis)
                Text(
                    episodeCount(row.episodes),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        },
    )
}

fun episodeCount(n: Int): String = "%,d %s".format(n, if (n == 1) "episode" else "episodes")

/** A series row (R11b): its window, the name, and the years and count as an event line. */
@Composable
fun SeriesListItem(row: SeriesRow, onOpen: () -> Unit) {
    GrammarRow(
        title = row.name,
        visual = { m -> PictureWindow(row.windowArt, row.name, row.genre, m) },
        onOpen = onOpen,
        sub = listOf(seriesYears(row), episodeCount(row.episodes)),
        openLabel = "Open series",
    )
}

@Composable
fun Meta(text: String, modifier: Modifier = Modifier) {
    Row(modifier) {
        Text(text, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
