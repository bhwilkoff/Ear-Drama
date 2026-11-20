package com.example.appname.ui

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil3.compose.AsyncImage
import kotlinx.coroutines.launch
import com.example.appname.data.Artwork
import com.example.appname.data.ItemLead
import com.example.appname.data.LabelItem
import com.example.appname.data.gradeOf
import com.example.appname.data.headNameStep
import com.example.appname.ui.theme.OnAir
import com.example.appname.ui.theme.Spacing
import com.example.appname.ui.theme.boardColor
import com.example.appname.ui.theme.onBoardColor

// Item pages wear Home's hero (WEB-DESIGN §6.4g, ANDROID-DESIGN §4.3g, Decision 081, Round 3 V7; owner, 2026-11-19: "We need to
// continue making the app more visually appealing, both from the home screen perspective ... and the individual item
// perspective."). The series, episode, person, play and finished ear drama pages open on the same board as Home's On the air:
// the window at tier L across the board's top on a phone and a 320 dp column beside the words from 560 dp, the words in the
// same order, then the strip. A picture keeps its own shape.

/**
 * The page head's board. [art] is the picture that leads (null is the [label], at tier L); [customWindow] stands in for both
 * (a play's opening drawn as a page). [kicker] draws the line over the name in the board's ink.
 */
@Composable
fun ItemHeadBoard(
    name: String,
    genre: String?,
    label: LabelItem,
    modifier: Modifier = Modifier,
    art: Artwork? = null,
    round: Boolean = false,
    kicker: (@Composable (Color) -> Unit)? = null,
    facts: List<Any?> = emptyList(),
    credits: String? = null,
    first: String? = null,
    last: String? = null,
    years: List<Int>? = null,
    markYear: Int? = null,
    mark: (@Composable (Dp) -> Unit)? = null,
    customWindow: (@Composable (Modifier) -> Unit)? = null,
) {
    val dark = OnAir.colors.dark
    val ground = boardColor(genre, dark)
    val ink = onBoardColor(genre, dark)
    val t = MaterialTheme.typography
    var failed by remember(art) { mutableStateOf(false) }
    val shown = if (failed) null else ItemLead.shown(art)
    BoxWithConstraints(modifier.fillMaxWidth().padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp)) {
        val frame = ItemLead.window(if (customWindow != null) null else shown, maxWidth.value)
        val beside = maxWidth.value >= ItemLead.BESIDE_FROM
        val wide = maxWidth.value >= 600f
        val window = @Composable {
            HeadWindow(shown, label, round, frame, customWindow) { failed = true }
        }
        val words = @Composable { m: Modifier ->
            Column(m, verticalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
                kicker?.invoke(ink)
                Text(
                    name,
                    style = nameStyle(headNameStep(name), t, headL1 = true),
                    color = ink,
                    maxLines = 3,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.semantics { heading() },
                )
                if (credits != null) Text(credits, style = t.titleMedium, color = ink)
                EventLine(facts, color = ink)
            }
        }
        val strip = @Composable { h: Dp ->
            if (mark != null) mark(h)
            else if (first != null || last != null || !years.isNullOrEmpty()) RunStrip(first, last, ink, height = h, years = years, markYear = markYear)
        }
        val card = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(ground)
        if (beside && !frame.plate) {
            Row(card.heightIn(min = frame.height.dp)) {
                window()
                Column(
                    Modifier.weight(1f).heightIn(min = frame.height.dp).padding(Spacing.S6.dp),
                    verticalArrangement = Arrangement.SpaceBetween,
                ) {
                    words(Modifier.fillMaxWidth())
                    Spacer(Modifier.height(Spacing.S3.dp))
                    strip(56.dp)
                }
            }
        } else {
            Column(card) {
                window()
                Column(
                    Modifier.fillMaxWidth().padding(if (beside) Spacing.S6.dp else Spacing.S4.dp),
                    verticalArrangement = Arrangement.spacedBy(Spacing.S3.dp),
                ) {
                    words(Modifier.fillMaxWidth())
                    strip(if (wide) 56.dp else 40.dp)
                }
            }
        }
    }
}

/** The head window: a picture at its own shape, never cropped, graded as everywhere; else the label, round for a person. */
@Composable
fun HeadWindow(
    art: Artwork?,
    label: LabelItem,
    round: Boolean,
    frame: ItemLead.Window,
    custom: (@Composable (Modifier) -> Unit)?,
    onFail: () -> Unit,
) {
    val size = Modifier.size(frame.width.dp, frame.height.dp)
    when {
        custom != null -> custom(size)
        art != null -> {
            val filter = remember(art) { ColorFilter.colorMatrix(gradeMatrix(gradeOf(art))) }
            val pixels = with(LocalDensity.current) { frame.width.dp.roundToPx() }
            Box(size.clip(RoundedCornerShape(4.dp)).clearAndSetSemantics {}) {
                AsyncImage(
                    model = art.url(pixels),
                    contentDescription = null,
                    contentScale = ContentScale.Fit,
                    colorFilter = filter,
                    onError = { onFail() },
                    modifier = Modifier.fillMaxSize(),
                )
            }
        }
        round -> Box(size, contentAlignment = Alignment.Center) {
            LabelArt(label, Modifier.fillMaxSize().padding(Spacing.S4.dp).clip(CircleShape))
        }
        else -> LabelArt(label, size)
    }
}

/** The credit a license asks for under a head picture; nothing when the picture owes none. */
@Composable
fun HeadCredit(art: Artwork?, modifier: Modifier = Modifier) {
    val shown = ItemLead.shown(art) ?: return
    PictureCredit(listOf(shown), 1.dp, modifier)
}

/** The kicker's genre as a link, then the networks after it, in the board's ink. */
@Composable
fun GenreKicker(name: String, rest: String, ink: Color, onOpen: () -> Unit) {
    val t = MaterialTheme.typography
    Row {
        Text(
            name.uppercase(),
            style = t.labelMedium.copy(letterSpacing = 1.sp, textDecoration = TextDecoration.Underline),
            color = ink,
            modifier = Modifier.tvFocusMark().clickable(onClickLabel = "Browse $name", onClick = onOpen),
        )
        if (rest.isNotEmpty()) Text(" · " + rest.uppercase(), style = t.labelMedium.copy(letterSpacing = 1.sp), color = ink)
    }
}

/** An episode's kicker: its show, a link to the show's page. */
@Composable
fun ShowKicker(name: String, ink: Color, onOpen: () -> Unit) {
    Text(
        name.uppercase(),
        style = MaterialTheme.typography.labelMedium.copy(letterSpacing = 1.sp, textDecoration = TextDecoration.Underline),
        color = ink,
        modifier = Modifier.tvFocusMark().clickable(onClickLabel = "Open $name", onClick = onOpen),
    )
}

/** A plain kicker. */
@Composable
fun TextKicker(words: String, ink: Color) {
    Text(words.uppercase(), style = MaterialTheme.typography.labelMedium.copy(letterSpacing = 1.sp), color = ink)
}

/**
 * Asks the list to reveal the whole box when any child inside it takes focus, not only the child. A TV's D-pad moving to a
 * button at the foot of a tall hero otherwise scrolled the hero's top off screen (Google TV Home, 2026-11-19).
 */
@OptIn(ExperimentalFoundationApi::class)
fun Modifier.revealWhole(): Modifier = composed {
    val requester = remember { BringIntoViewRequester() }
    val scope = rememberCoroutineScope()
    bringIntoViewRequester(requester).onFocusChanged { if (it.hasFocus) scope.launch { requester.bringIntoView() } }
}

/**
 * A series' further pictures (`series.gallery`): one row of whole pictures at one height, shown ungraded, each captioned with
 * its credit (else the site its evidence is on) linked to that evidence. Drawn only from [ItemLead.gallery].
 */
@Composable
fun SeriesGallery(pictures: List<Artwork>, modifier: Modifier = Modifier) {
    val window = with(LocalDensity.current) { LocalWindowInfo.current.containerSize.width.toDp() }
    val height = if (window >= 600.dp) 200.dp else 160.dp
    LazyRow(
        modifier.fillMaxWidth(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = Spacing.S4.dp),
        horizontalArrangement = Arrangement.spacedBy(Spacing.S3.dp),
    ) {
        items(pictures, key = { it.url }) { art ->
            val w = height * art.aspect
            val pixels = with(LocalDensity.current) { w.roundToPx() }
            Column(Modifier.width(w), verticalArrangement = Arrangement.spacedBy(Spacing.S1.dp)) {
                AsyncImage(
                    model = art.url(pixels),
                    contentDescription = null,
                    contentScale = ContentScale.Fit,
                    modifier = Modifier.size(w, height).clip(RoundedCornerShape(4.dp)).clearAndSetSemantics {},
                )
                ArtCredit(galleryCaption(art), art.evidence)
            }
        }
    }
}

/** A gallery picture's caption: its credit, else the name of the site its evidence is on. */
fun galleryCaption(art: Artwork): String {
    art.credit?.takeIf { it.isNotBlank() }?.let { return it }
    val host = art.evidence?.let { runCatching { java.net.URI(it).host }.getOrNull() }.orEmpty()
    return host.removePrefix("www.")
}
