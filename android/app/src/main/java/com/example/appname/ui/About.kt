package com.example.appname.ui

import android.content.Context
import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.core.net.toUri
import com.example.appname.ui.theme.Spacing

fun openInCustomTab(context: Context, url: String) {
    runCatching { CustomTabsIntent.Builder().setShowTitle(true).build().launchUrl(context, url.toUri()) }
}

private const val ABOUT_COLLAPSED_LINES = 4

/**
 * A show's About (ANDROID-DESIGN §4.3): the catalog's paragraphs under the facts, four lines until
 * expanded, then "From [source]" opening the page it came from (Wikipedia text is CC BY-SA, so the
 * attribution is part of the text). A TV names the source without a link it cannot open.
 */
@Composable
fun AboutBlock(text: String, source: String?, url: String?, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val television = LocalIsTelevision.current
    var expanded by rememberSaveable(text) { mutableStateOf(false) }
    var overflows by remember(text) { mutableStateOf(false) }
    Column(modifier.fillMaxWidth().padding(horizontal = Spacing.S4.dp, vertical = Spacing.S2.dp)) {
        Text(
            text,
            style = MaterialTheme.typography.bodyMedium,
            maxLines = if (expanded) Int.MAX_VALUE else ABOUT_COLLAPSED_LINES,
            overflow = TextOverflow.Ellipsis,
            onTextLayout = { if (!expanded) overflows = it.hasVisualOverflow },
        )
        if (overflows || expanded) {
            TextLink(if (expanded) "Show less" else "Read more", onClick = { expanded = !expanded })
        }
        if (source != null) {
            val label = "From $source"
            if (url != null && !television) {
                TextLink(label, onClick = { openInCustomTab(context, url) })
            } else {
                Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}
