package com.example.appname.ui

import android.content.Context
import android.content.Intent
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext

/**
 * Share (ANDROID-DESIGN §4.3, §4.4): the https twin (`SiteLinks`) through the
 * system share sheet, the page's title as the sheet's title. A TV has no share
 * sheet to another person, so the button is absent there (DEEP_LINKS.md: a TV
 * shares by QR code, not built yet).
 */
@Composable
fun ShareAction(title: String, url: String, modifier: Modifier = Modifier) {
    if (LocalIsTelevision.current) return
    val context = LocalContext.current
    IconButton(onClick = { context.shareLink(title, url) }, modifier = modifier) {
        Icon(Icons.Filled.Share, contentDescription = "Share $title")
    }
}

/** Share as one of a page's action row: its label folds to the icon with the row, kept as the accessible name. */
@Composable
fun ShareButton(title: String, url: String, folded: Boolean, modifier: Modifier = Modifier) {
    if (LocalIsTelevision.current) return
    val context = LocalContext.current
    FoldButton(
        Icons.Filled.Share, "Share", folded, { context.shareLink(title, url) }, modifier,
        description = "Share $title",
    )
}

fun Context.shareLink(title: String, url: String) {
    val send = Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_TEXT, url)
        putExtra(Intent.EXTRA_TITLE, title)
    }
    startActivity(Intent.createChooser(send, null))
}
