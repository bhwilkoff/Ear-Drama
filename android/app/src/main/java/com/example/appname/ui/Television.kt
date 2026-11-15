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
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.unit.dp
import com.example.appname.BuildConfig
import com.example.appname.ui.theme.OnAir

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
 * The TV safe area (ANDROID-DESIGN §9.2a; Google's TV layout guidance): 5% of
 * the 960 x 540 dp screen, 48 dp at each side and 27 dp at the top and bottom,
 * applied once around the whole app so the rail, the top bars, the rows and
 * the mini player all sit inside it. The background still fills the screen.
 */
val TvSafeHorizontal = 48.dp
val TvSafeVertical = 27.dp

/** Rows at least this wide wear the ring without the scale (§9.2a). */
private val WIDE = 400.dp

/**
 * On a TV the focused card is marked by a ring and a scale, never color alone
 * (the focus contract). A wide row is not scaled: growing it about its centre
 * pushes its edges under the rail and into the overscan. Elsewhere it changes
 * nothing.
 */
@Composable
fun Modifier.tvFocusMark(): Modifier {
    if (!LocalIsTelevision.current) return this
    var focused by remember { mutableStateOf(false) }
    var wide by remember { mutableStateOf(false) }
    val widePx = with(LocalDensity.current) { WIDE.roundToPx() }
    val ring = OnAir.colors.link
    return this
        .onSizeChanged { wide = it.width >= widePx }
        .onFocusChanged { focused = it.isFocused }
        .scale(if (focused && !wide) 1.06f else 1f)
        .then(if (focused) Modifier.border(3.dp, ring, MaterialTheme.shapes.medium) else Modifier)
}

/**
 * When the listener last pressed a key, and when the screen on top last
 * changed (MainActivity and AppRoot write these). A screen's initial focus is
 * claimed only while no key has been pressed since it opened, so a claim that
 * waits on data never pulls focus back from where the listener has moved
 * (2026-11-14: Home's late claim took focus from the rail after Back).
 */
object TvFocusClock {
    @Volatile var lastKeyNanos: Long = 0L
        private set
    @Volatile var screenOpenedNanos: Long = 0L
        private set

    fun keyPressed() { lastKeyNanos = System.nanoTime() }
    fun screenOpened() {
        screenOpenedNanos = System.nanoTime()
        if (firstScreenNanos == 0L) firstScreenNanos = screenOpenedNanos
    }
    @Volatile private var firstScreenNanos: Long = 0L
    val listenerHasMoved: Boolean get() = lastKeyNanos > screenOpenedNanos

    /**
     * The process's first claim is still pending: a key pressed while the first screen was loading
     * moved focus into the rail (the only focusable thing), which is not a choice, so until that
     * screen's content claims focus only keys pressed after the content appeared count.
     */
    @Volatile var firstClaimPending: Boolean = true
        private set

    fun firstClaimDone() { firstClaimPending = false }
    fun movedSince(nanos: Long): Boolean = if (firstClaimPending && screenOpenedNanos == firstScreenNanos) lastKeyNanos > nanos else listenerHasMoved
}

/**
 * Claims initial focus on a TV. Call it where the target is drawn, once the
 * content it belongs to has loaded: it then tries every frame until the
 * target is attached and takes focus, and stops as soon as the listener
 * presses a key on this screen. Exactly one surface per screen calls this.
 */
@Composable
fun ClaimTvFocus(requester: FocusRequester, key: Any?) {
    if (!LocalIsTelevision.current) return
    LaunchedEffect(key) {
        var frames = 0
        val begun = System.nanoTime()
        while (!TvFocusClock.movedSince(begun) && frames < MAX_CLAIM_FRAMES) {
            if (runCatching { requester.requestFocus(FocusDirection.Enter) }.getOrDefault(false)) {
                TvFocusClock.firstClaimDone()
                if (BuildConfig.DEBUG) println("[Focus] claimed after $frames frames (key=$key)")
                return@LaunchedEffect
            }
            frames++
            withFrameNanos { }
        }
        if (BuildConfig.DEBUG) println("[Focus] claim stopped after $frames frames (moved=${TvFocusClock.movedSince(begun)}, key=$key)")
    }
}

/** A target that has not attached within about 10 s of frames is not coming. */
private const val MAX_CLAIM_FRAMES = 600
