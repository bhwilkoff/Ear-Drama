package com.example.appname

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.lifecycle.lifecycleScope
import com.example.appname.navigation.InboxRequest
import com.example.appname.navigation.LaunchDoors
import com.example.appname.ui.AppRoot
import com.example.appname.ui.theme.AppTheme
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Single Activity — Compose-only, no Fragments, no AppCompat.
 *
 * Hosts the NavHost via [AppRoot]; handles edge-to-edge, splash screen,
 * and deep-link dispatch. Per ANDROID-DESIGN §0, every interaction
 * exhausts native M3 components first.
 */
@AndroidEntryPoint
class MainActivity : ComponentActivity() {

    /** Deep links and test doors are posted here; AppRoot drains it. */
    private val inbox = mutableStateListOf<InboxRequest>()
    private var playerMuted by mutableStateOf(false)

    override fun onCreate(savedInstanceState: Bundle?) {
        // Splash Screen API — call BEFORE super.onCreate(). Android 12+
        // composites this over our themed window for the first frame.
        installSplashScreen()
        super.onCreate(savedInstanceState)

        // Mandatory at targetSdk >= 35; Android 16 ignores opt-out.
        // Scaffold + WindowInsets do the right thing from here.
        enableEdgeToEdge()

        // Deep link dispatch — supabase OAuth callbacks + app-internal
        // routes. Switch by scheme, never by URL shape (see iOS lesson:
        // .onOpenURL fires for both Universal Links and custom schemes,
        // and the equivalent confusion existed across deep-link surfaces).
        handleDeepLink(intent)
        // A recreated Activity (rotation) must not re-open the launch doors.
        if (savedInstanceState == null) openDoors(intent)

        setContent {
            AppTheme {
                AppRoot(inbox = inbox, muted = playerMuted)
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleDeepLink(intent)
        openDoors(intent)
    }

    /**
     * Test doors (appname_start_tab / _start_item / _mute / _door_seconds, the
     * tools/app_config.py hooks). DEBUG builds only: a no-op in release.
     */
    private fun openDoors(intent: Intent?) {
        if (!BuildConfig.DEBUG) return
        val extras = intent?.extras ?: return
        @Suppress("DEPRECATION")
        val map = extras.keySet().associateWith { extras.get(it) }
        val doors = LaunchDoors.from(map, debug = BuildConfig.DEBUG)
        if (doors.mute) playerMuted = true
        inbox += doors.requests()
        doors.doorSeconds?.let { seconds ->
            lifecycleScope.launch {
                delay(seconds * 1000L)
                inbox += InboxRequest.EndDoor
            }
        }
    }

    private fun handleDeepLink(intent: Intent?) {
        val uri = intent?.data ?: return
        // supabase.handleDeeplinks(intent) — wire when Supabase ships
        when (uri.scheme) {
            "https" -> routeUniversalLink(uri)
            "appname" -> routeCustomScheme(uri)
        }
    }

    private fun routeUniversalLink(uri: android.net.Uri) {
        // FILL IN: route by uri.pathSegments
    }

    private fun routeCustomScheme(uri: android.net.Uri) {
        // FILL IN: route by uri.host / uri.pathSegments
    }
}
