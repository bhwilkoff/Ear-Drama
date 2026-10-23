package com.example.appname.ui

import android.app.UiModeManager
import android.content.Context
import android.content.res.Configuration
import androidx.compose.foundation.border
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay

/**
 * Android TV and Fire TV are a runtime branch of the one app, never a fork or
 * a flavor (androidtv-compose-focus). Fire OS reports a normal UI mode on some
 * devices, so the launcher's own feature flags are the fallback.
 */
fun Context.isTelevision(): Boolean {
    val ui = getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
    if (ui?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION) return true
    return packageManager.hasSystemFeature("android.software.leanback") ||
        packageManager.hasSystemFeature("android.hardware.type.television")
}

/** Resolved once in MainActivity. */
val LocalIsTelevision = staticCompositionLocalOf { false }

/**
 * On a TV the focused card is marked by a ring and a scale, never color alone
 * (the focus contract). Elsewhere it changes nothing.
 */
@Composable
fun Modifier.tvFocusMark(): Modifier {
    if (!LocalIsTelevision.current) return this
    var focused by remember { mutableStateOf(false) }
    val ring = MaterialTheme.colorScheme.primary
    return this
        .onFocusChanged { focused = it.isFocused }
        .scale(if (focused) 1.06f else 1f)
        .then(if (focused) Modifier.border(3.dp, ring, MaterialTheme.shapes.medium) else Modifier)
}

/**
 * Claims initial focus on a TV, retrying while the target's lazy row has not
 * composed yet. Exactly one surface per screen calls this.
 */
@Composable
fun ClaimTvFocus(requester: FocusRequester, key: Any?) {
    if (!LocalIsTelevision.current) return
    LaunchedEffect(key) {
        repeat(20) {
            if (runCatching { requester.requestFocus(FocusDirection.Enter) }.getOrDefault(false)) return@LaunchedEffect
            delay(50)
        }
    }
}
