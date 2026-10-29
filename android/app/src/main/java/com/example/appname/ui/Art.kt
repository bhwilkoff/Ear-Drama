package com.example.appname.ui

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import com.example.appname.data.Artwork
import com.example.appname.data.Face
import com.example.appname.data.artInitial
import com.example.appname.ui.theme.OnAir
import com.example.appname.ui.theme.Spacing
import androidx.core.net.toUri

// Art (Decision 069, contract §3.3a): a served portrait, else a card drawn
// from data. No stock, placeholder, or uploader art. A small crop centers on
// the face the pipeline published (R11a), never one found on the device.

/**
 * A small square crop (a row tile, a cast face, R11a): the square [Artwork.cropRect] picks around
 * the published face, the image scaled so that square fills [side] and shifted onto it, at the
 * smallest Commons step covering it on this screen. A wide picture with no face draws nothing, so
 * what is behind it shows (the tile's letter, the empty slot), as it does while loading or on
 * failure; an unknown size keeps the plain top fill crop.
 */
@Composable
fun ArtImage(art: Artwork, side: Dp, modifier: Modifier = Modifier, description: String? = null) {
    val r = art.cropRect()
    if (r == null) {
        if (art.aspectRatio != null) return
        val pixels = with(LocalDensity.current) { side.roundToPx() }
        AsyncImage(
            model = art.url(pixels),
            contentDescription = description,
            contentScale = ContentScale.Crop,
            alignment = Alignment.TopCenter,
            modifier = modifier,
        )
        return
    }
    val w = side / r.w
    val h = side / r.h
    val pixels = with(LocalDensity.current) { w.roundToPx() }
    Box(modifier.clipToBounds()) {
        AsyncImage(
            model = art.url(pixels),
            contentDescription = description,
            contentScale = ContentScale.FillBounds,
            modifier = Modifier
                .wrapContentSize(Alignment.TopStart, unbounded = true)
                .offset(x = -w * r.x, y = -h * r.y)
                .requiredSize(w, h),
        )
    }
}

/**
 * A picture in a box of its own shape (ANDROID-DESIGN R11a, `artwork-presentation-design`):
 * an archival print's hairline and the control radius, the genre's edge under it, and nothing
 * behind it, no wash, no bars. While it loads the box is the surface at exactly the picture's
 * size; the caller sizes the box from [Artwork.aspect], so the image fills it, and an unknown
 * size (drawn upright at 4:5) crops top-anchored rather than leaving bars.
 */
@Composable
fun ShapedArt(art: Artwork, modifier: Modifier = Modifier, genre: String? = null, description: String? = null) {
    val edge = OnAir.genre(genre)
    val shape = RoundedCornerShape(8.dp)
    BoxWithConstraints(
        modifier
            .clip(shape)
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .border(1.dp, MaterialTheme.colorScheme.outlineVariant, shape)
            .drawWithContent {
                drawContent()
                if (edge != null) drawRect(edge, Offset(0f, size.height - 3.dp.toPx()), Size(size.width, 3.dp.toPx()))
            },
    ) {
        val pixels = with(LocalDensity.current) { maxWidth.roundToPx() }
        AsyncImage(
            model = art.url(pixels),
            contentDescription = description,
            contentScale = ContentScale.Crop,
            alignment = Alignment.TopCenter,
            modifier = Modifier.fillMaxSize(),
        )
    }
}

/** The box for [art] inside a bound: its own aspect, as large as the bound allows. */
fun fittedSize(art: Artwork, maxWidth: Dp, maxHeight: Dp): Pair<Dp, Dp> {
    val width = minOf(maxWidth, maxHeight * art.aspect)
    return width to width / art.aspect
}

/**
 * A page's face (R11a). Upright (a square included): the print, 168 dp tall (240 from 600 dp
 * wide) and at most 150 dp wide (276), beside its label: whose face (unless the heading already
 * says), the credit its license asks for (a required fact), and the page's [facts] when given.
 * Wide: the plate, the column's width at its own aspect, at most 320 dp tall, at the start,
 * with the label under it.
 */
@Composable
fun FaceHero(face: Face, genre: String?, modifier: Modifier = Modifier, showsName: Boolean = true, facts: String? = null) {
    val window = with(LocalDensity.current) { LocalWindowInfo.current.containerSize.width.toDp() }
    val regular = window >= 600.dp
    val picture = Modifier.testTag("face-hero").semantics { contentDescription = face.name }
    if (face.art.isWide) {
        Column(modifier, verticalArrangement = Arrangement.spacedBy(Spacing.S2.dp)) {
            ShapedArt(
                face.art,
                picture.widthIn(max = 320.dp * face.art.aspect).fillMaxWidth().aspectRatio(face.art.aspect),
                genre,
            )
            FaceLabel(face, showsName, facts)
        }
    } else {
        val (w, h) = if (regular) fittedSize(face.art, 276.dp, 240.dp) else fittedSize(face.art, 150.dp, 168.dp)
        Row(modifier, horizontalArrangement = Arrangement.spacedBy(Spacing.S3.dp), verticalAlignment = Alignment.Bottom) {
            ShapedArt(face.art, picture.width(w).height(h), genre)
            FaceLabel(face, showsName, facts, Modifier.weight(1f))
        }
    }
}

@Composable
private fun FaceLabel(face: Face, showsName: Boolean, facts: String?, modifier: Modifier = Modifier) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(Spacing.S1.dp)) {
        if (showsName) {
            Text(face.name, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        face.art.credit?.let { ArtCredit(it, face.art.evidence) }
        facts?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
    }
}

/** A row's tile: the series' star, else its first letter in its genre hue on the surface; 56 dp so a face can be known (R11a). */
@Composable
fun ArtTile(name: String, genre: String?, face: Face?, size: Dp = 56.dp) {
    val hue = OnAir.genre(genre)
    val band = hue ?: MaterialTheme.colorScheme.outline
    val shape = RoundedCornerShape(8.dp)
    Box(
        Modifier
            .size(size)
            .clip(shape)
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .drawBehind { drawRect(band, Offset(0f, this.size.height - 3.dp.toPx()), Size(this.size.width, 3.dp.toPx())) }
            .clearAndSetSemantics {},
        contentAlignment = Alignment.Center,
    ) {
        Text(
            artInitial(name),
            style = MaterialTheme.typography.headlineSmall,
            color = hue ?: MaterialTheme.colorScheme.onSurfaceVariant,
        )
        if (face != null) ArtImage(face.art, size, Modifier.size(size))
    }
}

/** A face beside a heading: the print at its own aspect inside a [height] bound, whose it is, and the credit owed. */
@Composable
fun FaceFigure(face: Face, height: Dp = 96.dp) {
    val (w, h) = fittedSize(face.art, height * 1.5f, height)
    Column(Modifier.width(w), verticalArrangement = Arrangement.spacedBy(Spacing.S1.dp)) {
        ShapedArt(face.art, Modifier.width(w).height(h), description = face.name)
        Text(face.name, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        face.art.credit?.let { ArtCredit(it, face.art.evidence) }
    }
}

/** "Author, CC BY-SA 3.0", opening the Commons file page. */
@Composable
fun ArtCredit(credit: String, evidence: String?, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    Text(
        credit,
        style = MaterialTheme.typography.bodySmall,
        color = if (evidence != null) OnAir.colors.link else MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = if (evidence == null) modifier else modifier.clickable(onClickLabel = "Open the photo's page") {
            runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, evidence.toUri())) }
        },
    )
}

/** A cast line's round portrait; with no portrait, an empty slot keeps names aligned. */
@Composable
fun CreditFace(art: Artwork?, size: Dp = 32.dp) {
    Box(Modifier.size(size).clip(CircleShape).clearAndSetSemantics {}) {
        if (art != null && (art.cropRect() != null || art.aspectRatio == null)) {
            ArtImage(art, size, Modifier.size(size).background(MaterialTheme.colorScheme.surfaceVariant))
        }
    }
}

/** The typographic card (R11): the name and one meta line on the genre; a series or a stage play draws one. */
@Composable
fun TypeCard(name: String, line: String?, genre: String?, modifier: Modifier = Modifier) {
    val band = OnAir.genre(genre) ?: MaterialTheme.colorScheme.outline
    Column(
        modifier
            .aspectRatio(1f)
            .clip(RoundedCornerShape(12.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .drawBehind { drawRect(band, size = Size(8.dp.toPx(), size.height)) }
            .padding(start = (Spacing.S4 + 8).dp, end = Spacing.S4.dp, top = Spacing.S4.dp, bottom = Spacing.S4.dp),
        verticalArrangement = Arrangement.Bottom,
    ) {
        Spacer(Modifier.weight(1f))
        Text(name, style = MaterialTheme.typography.headlineSmall, maxLines = 4, overflow = TextOverflow.Ellipsis)
        line?.let {
            Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/**
 * Now Playing's picture: the episode's face, else the series', else the series' typographic card.
 * The bound is a square, full width and no taller than [maxSide] (R11a: Play stays on the first
 * screen); a portrait is drawn whole at its own aspect and its box shrinks to it, centered.
 */
@Composable
fun NowPlayingArt(seriesName: String, genre: String?, line: String?, face: Face?, maxSide: Dp = 200.dp) {
    BoxWithConstraints(
        Modifier.fillMaxWidth().heightIn(max = maxSide).aspectRatio(1f).clearAndSetSemantics {},
        contentAlignment = Alignment.Center,
    ) {
        if (face != null) {
            val (w, h) = fittedSize(face.art, maxWidth, maxHeight)
            ShapedArt(face.art, Modifier.width(w).height(h))
        } else {
            TypeCard(seriesName, line, genre, Modifier.fillMaxSize())
        }
    }
}
