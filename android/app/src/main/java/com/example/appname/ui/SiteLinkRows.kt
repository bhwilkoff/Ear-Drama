package com.example.appname.ui

import android.net.Uri
import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.foundation.clickable
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.material3.ListItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.example.appname.navigation.SiteLinks
import androidx.core.net.toUri

/** ANDROID-DESIGN §4.11a: the site pages, names only; a Custom Tab opens each, a TV shows the address. */
@Composable
fun SiteLinkRows() {
    val context = LocalContext.current
    val television = LocalIsTelevision.current
    SiteLinks.PAGES.forEach { (name, url) ->
        ListItem(
            modifier = if (television) Modifier else Modifier.clickable(onClickLabel = "Open $name") {
                runCatching { CustomTabsIntent.Builder().setShowTitle(true).build().launchUrl(context, url.toUri()) }
            },
            headlineContent = { Text(name) },
            supportingContent = if (television) ({ Text(url.removePrefix("https://").trimEnd('/')) }) else null,
        )
    }
}

fun LazyListScope.siteLinksItem() {
    item(key = "site-links") { SiteLinkRows() }
}
