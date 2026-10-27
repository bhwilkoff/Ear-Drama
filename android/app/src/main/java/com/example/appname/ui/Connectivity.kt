package com.example.appname.ui

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.State
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.example.appname.ui.theme.Spacing

/** True while the device reports a network. Provided once, in AppRoot. */
val LocalOnline = compositionLocalOf { true }

const val OFFLINE_LINE = "You are offline."

/** The status line while [online] is false, else nothing. */
fun offlineLine(online: Boolean): String? = if (online) null else OFFLINE_LINE

private fun Context.hasNetwork(): Boolean {
    val cm = getSystemService(ConnectivityManager::class.java) ?: return true
    val caps = cm.getNetworkCapabilities(cm.activeNetwork) ?: return false
    return caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
}

/** Follows the default network, so the offline line comes and goes as the device does. */
@Composable
fun rememberOnline(): State<Boolean> {
    val context = LocalContext.current
    val online = remember { mutableStateOf(context.hasNetwork()) }
    DisposableEffect(context) {
        val cm = context.getSystemService(ConnectivityManager::class.java)
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) { online.value = context.hasNetwork() }
            override fun onLost(network: Network) { online.value = context.hasNetwork() }
            override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) {
                online.value = caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            }
        }
        runCatching { cm?.registerDefaultNetworkCallback(callback) }
        onDispose { runCatching { cm?.unregisterNetworkCallback(callback) } }
    }
    return online
}

/**
 * The web's §7.3 status line, in the flow above the screens: offline is a
 * degraded mode, not a failure, so it is neutral, never the error color.
 */
@Composable
fun OfflineLine(text: String = OFFLINE_LINE) {
    Text(
        text,
        style = MaterialTheme.typography.labelMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = Spacing.S4.dp, vertical = Spacing.S1.dp)
            .semantics { liveRegion = LiveRegionMode.Polite },
    )
}
