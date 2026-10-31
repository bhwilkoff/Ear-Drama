package com.example.appname.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.appname.data.PersonRow
import com.example.appname.ui.theme.Spacing

// Voices (contract §3.3 `voices`): the most heard people as round faces, a person's portrait or
// their monogram, each opening the person's page. Browse's Voices scope and Home's "Most heard
// voices" shelf read the same published list; a catalog without it has none, and nothing draws.

private val VOICE_SIDE = 84.dp

/** A voice: the round face over the name and the episodes they are heard in. */
@Composable
fun VoiceFace(row: PersonRow, onOpen: () -> Unit, modifier: Modifier = Modifier) {
    val count = episodeCount(row.episodes)
    Column(
        modifier
            .tvFocusMark()
            .clip(MaterialTheme.shapes.medium)
            .clickable(onClickLabel = "Open ${row.person.name}", onClick = onOpen)
            .padding(vertical = Spacing.S1.dp)
            .clearAndSetSemantics { contentDescription = "${row.person.name}, $count" },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Spacing.S1.dp),
    ) {
        PictureWindow(row.person.art, row.person.name, null, Modifier.size(VOICE_SIDE).clip(CircleShape))
        Text(
            row.person.name,
            style = MaterialTheme.typography.labelMedium,
            textAlign = TextAlign.Center,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
        Text(
            count,
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
            maxLines = 1,
        )
    }
}

/** Home's "Most heard voices": a row of faces that scrolls sideways. */
@Composable
fun VoicesShelf(voices: List<PersonRow>, onOpenPerson: (String) -> Unit, modifier: Modifier = Modifier) {
    Column(modifier) {
        LazyRow(
            contentPadding = PaddingValues(horizontal = Spacing.S4.dp),
            horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp),
        ) {
            items(voices.size, key = { "voice:" + voices[it].person.id }) { i ->
                VoiceFace(voices[i], onOpen = { onOpenPerson(voices[i].person.id) }, modifier = Modifier.width(104.dp))
            }
        }
        PictureCredit(voices.map { it.person.art }, VOICE_SIDE, Modifier.padding(horizontal = Spacing.S4.dp))
    }
}

/** Browse's Voices scope: the count, then the faces, most heard first. */
@Composable
fun VoicesScope(onOpenPerson: (String) -> Unit, modifier: Modifier = Modifier) {
    val voices by rememberCatalogQuery { db -> db.voices() }
    LoadableContent(voices, modifier) { rows ->
        if (rows.isEmpty()) {
            EmptyMessage("No voices listed yet.")
            return@LoadableContent
        }
        LazyVerticalGrid(
            GridCells.Adaptive(104.dp),
            contentPadding = PaddingValues(Spacing.S4.dp),
            horizontalArrangement = Arrangement.spacedBy(Spacing.S2.dp),
            verticalArrangement = Arrangement.spacedBy(Spacing.S3.dp),
        ) {
            items(rows, key = { it.person.id }) { VoiceFace(it, onOpen = { onOpenPerson(it.person.id) }, modifier = Modifier.fillMaxWidth()) }
        }
    }
}
