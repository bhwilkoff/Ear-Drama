package com.example.appname

import android.content.Intent
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.lifecycle.lifecycleScope
import com.example.appname.app.AppNameApplication
import com.example.appname.navigation.DeepLink
import com.example.appname.navigation.InboxRequest
import com.example.appname.navigation.LaunchDoors
import com.example.appname.ui.AppRoot
import com.example.appname.navigation.OwnIntents
import com.example.appname.ui.LocalIsTelevision
import com.example.appname.ui.TvFocusClock
import com.example.appname.ui.isTelevision
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
    private var forceOffline by mutableStateOf(false)

    override fun onCreate(savedInstanceState: Bundle?) {
        // Splash Screen API — call BEFORE super.onCreate(). Android 12+
        // composites this over our themed window for the first frame.
        installSplashScreen()
        super.onCreate(savedInstanceState)

        // Mandatory at targetSdk >= 35; Android 16 ignores opt-out.
        // Scaffold + WindowInsets do the right thing from here.
        enableEdgeToEdge()

        // A recreated Activity keeps its back stacks; only a fresh launch routes the link.
        if (savedInstanceState == null) handleDeepLink(intent)
        if (savedInstanceState == null) handleText(intent)
        // A recreated Activity (rotation) must not re-open the launch doors.
        if (savedInstanceState == null) openDoors(intent)

        val television = isTelevision()
        setContent {
            AppTheme {
                CompositionLocalProvider(LocalIsTelevision provides television) {
                    // Every key down tells a pending focus claim the listener has started moving (§9.2).
                    androidx.compose.foundation.layout.Box(
                        androidx.compose.ui.Modifier.onPreviewKeyEvent {
                            if (it.type == androidx.compose.ui.input.key.KeyEventType.KeyDown) TvFocusClock.keyPressed()
                            false
                        },
                    ) {
                        AppRoot(container = container, inbox = inbox, muted = playerMuted, forceOffline = forceOffline)
                    }
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleDeepLink(intent)
        handleText(intent)
        openDoors(intent)
    }

    /**
     * Test doors (appname_start_tab / _start_item / _mute / _door_seconds / _force_offline, the
     * tools/app_config.py hooks). DEBUG builds only: a no-op in release.
     */
    private fun openDoors(intent: Intent?) {
        if (!BuildConfig.DEBUG) return
        val extras = intent?.extras ?: return
        @Suppress("DEPRECATION")
        val map = extras.keySet().associateWith { extras.get(it) }
        val doors = LaunchDoors.from(map, debug = BuildConfig.DEBUG)
        if (doors.mute) playerMuted = true
        if (doors.forceOffline) forceOffline = true
        if (doors.studioStub) com.example.appname.navigation.StudioDoor.stub = true
        doors.studioPhase?.let { com.example.appname.navigation.StudioDoor.phase = it }
        if (doors.emptyLibrary) com.example.appname.navigation.LibraryDoor.empty = true
        if (doors.skipOnboard) com.example.appname.navigation.VoicesStepDoor.skip = true
        if (doors.voicesStep) com.example.appname.navigation.VoicesStepDoor.force = true
        com.example.appname.navigation.ReadRoomDoor.part = doors.startReadPart
        com.example.appname.navigation.ReadRoomDoor.record = doors.startReadRecord
        inbox += doors.requests()
        doors.doorSeconds?.let { seconds ->
            lifecycleScope.launch {
                delay(seconds * 1000L)
                inbox += InboxRequest.EndDoor
            }
        }
    }

    /**
     * `eardrama://` and its `https://eardrama.org` twins (DEEP_LINKS.md) land in
     * the inbox; Sign in with Apple's return (`eardrama://oauth/apple`) goes to
     * the account instead and opens nothing.
     */
    private fun handleDeepLink(intent: Intent?) {
        if (intent?.action != Intent.ACTION_VIEW) return
        val url = intent.dataString ?: return
        if (container.accounts.handleCallback(url)) return
        DeepLink.parse(url)?.let { inbox += it }
    }

    /** A text shared to the app, or a text file opened in it, for Add a script: measured here, read by the page, never parsed unmeasured. */
    private fun handleText(intent: Intent?) {
        val found = OwnIntents.incoming(intent) ?: return
        inbox += InboxRequest.AddScript(found)
    }

    private val container get() = (application as AppNameApplication).container

    /** A signed-in app syncs when it comes forward and when it leaves (DECISIONS 063); signed out, nothing runs. */
    override fun onStart() {
        super.onStart()
        container.relay.setForeground(true)
        if (container.accounts.account.value != null) container.accounts.syncNow()
    }

    override fun onStop() {
        super.onStop()
        container.relay.setForeground(false)
        if (container.accounts.account.value != null) container.accounts.syncNow()
    }
}
