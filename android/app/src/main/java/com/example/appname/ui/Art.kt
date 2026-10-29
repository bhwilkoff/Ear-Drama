package com.example.appname.ui

import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
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

// Art (Decision 069, contract §3.3a): a served portrait, else a card drawn
// from data. No stock, placeholder, or uploader art. A portrait is the
// person's own Wikidata image, so a top-anchored crop keeps the face.

/** A portrait at the smallest Commons step covering [side] on this screen; a failed load shows what is behind it. */
@Composable
fun ArtImage(art: Artwork, side: Dp, modifier: Modifier = Modifier, description: String? = null) {
    val pixels = with(LocalDensity.current) { side.roundToPx() }
    AsyncImage(
        model = art.url(pixels),
        contentDescription = description,
        contentScale = ContentScale.Crop,
        alignment = Alignment.TopCenter,
        modifier = modifier,
    )
}

/**
 * The whole portrait at its own aspect over a wash of the same image, blurred and
 * dimmed (ANDROID-DESIGN R11a): never reshaped, and never an empty box while the
 * sharp copy loads, since the wash is the 120 step a row's tile has usually cached.
 * Below Android 12 there is no blur, so the wash is left out rather than shown sharp.
 */
@Composable
fun PortraitFrame(art: Artwork, modifier: Modifier = Modifier, description: String? = null) {
    val density = LocalDensity.current
    BoxWithConstraints(modifier.background(MaterialTheme.colorScheme.surfaceVariant), contentAlignment = Alignment.Center) {
        val aspect = art.aspect
        val drawn = minOf(maxWidth, maxHeight * aspect)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            AsyncImage(
                model = art.url(120),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier
                    .fillMaxSize()
                    .blur(20.dp)
                    .drawWithContent { drawContent(); drawRect(Color.Black.copy(alpha = 0.45f)) },
            )
        }
        AsyncImage(
            model = art.url(with(density) { drawn.roundToPx() }),
            contentDescription = description,
            contentScale = ContentScale.Fit,
            modifier = Modifier.fillMaxSize(),
        )
    }
}

/**
 * A page's face (R11a): a full-width band (240 dp, 320 dp on a wide screen) with the
 * genre's edge under it, then whose it is (unless the heading already says) and the
 * credit its license asks for, a required fact, so it is on screen with the picture.
 */
@Composable
fun FaceHero(face: Face, genre: String?, modifier: Modifier = Modifier, showsName: Boolean = true) {
    val tall = if (LocalConfiguration.current.screenWidthDp >= 600) 320.dp else 240.dp
    val edge = OnAir.genre(genre)
    Column(modifier, verticalArrangement = Arrangement.spacedBy(Spacing.S1.dp)) {
        PortraitFrame(
            face.art,
            Modifier
                .fillMaxWidth()
                .height(tall)
                .clip(RoundedCornerShape(12.dp))
                .drawWithContent {
                    drawContent()
                    if (edge != null) drawRect(edge, Offset(0f, size.height - 4.dp.toPx()), Size(size.width, 4.dp.toPx()))
                }
                .testTag("face-hero")
                .semantics { contentDescription = face.name },
        )
        if (showsName) {
            Text(face.name, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        face.art.credit?.let { ArtCredit(it, face.art.evidence) }
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

/** A face beside a heading: the portrait, whose it is, and the credit its license asks for (a required fact). */
@Composable
fun FaceFigure(face: Face, width: Dp = 76.dp) {
    Column(Modifier.width(width), verticalArrangement = Arrangement.spacedBy(Spacing.S1.dp)) {
        ArtImage(
            face.art, width,
            Modifier
                .width(width)
                .height(width * 1.25f)
                .clip(RoundedCornerShape(8.dp))
                .background(MaterialTheme.colorScheme.surfaceVariant),
            description = face.name,
        )
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
            runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(evidence))) }
        },
    )
}

/** A cast line's round portrait; with no portrait, an empty slot keeps names aligned. */
@Composable
fun CreditFace(art: Artwork?, size: Dp = 32.dp) {
    Box(Modifier.size(size).clip(CircleShape).clearAndSetSemantics {}) {
        if (art != null) {
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
 * Square and full width, no taller than [maxSide] (R11a: Play stays on the first screen); a
 * portrait sits whole in it over its wash.
 */
@Composable
fun NowPlayingArt(seriesName: String, genre: String?, line: String?, face: Face?, maxSide: Dp = 200.dp) {
    Box(Modifier.fillMaxWidth().heightIn(max = maxSide).aspectRatio(1f).clearAndSetSemantics {}) {
        if (face != null) {
            PortraitFrame(face.art, Modifier.fillMaxSize().clip(RoundedCornerShape(12.dp)))
        } else {
            TypeCard(seriesName, line, genre, Modifier.fillMaxSize())
        }
    }
}
