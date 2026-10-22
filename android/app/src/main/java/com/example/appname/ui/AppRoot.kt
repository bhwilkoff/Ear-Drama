package com.example.appname.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.adaptive.currentWindowAdaptiveInfo
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.snapshots.SnapshotStateList
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.example.appname.navigation.InboxRequest
import com.example.appname.navigation.LocalPlayerMuted

/**
 * Root scaffold. Hosts the size-class-adaptive nav surface
 * (NavigationBar on compact, NavigationRail on medium+, drawer on
 * expanded) via [NavigationSuiteScaffold]. One Composable hierarchy;
 * never fork per form factor.
 *
 * Per ANDROID-DESIGN §6.6, every screen MUST work on compact /
 * medium / expanded. Adaptive concerns belong here at the root, not
 * inside per-feature screens.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AppRoot(
    inbox: SnapshotStateList<InboxRequest> = remember { mutableStateListOf() },
    muted: Boolean = false,
) {
    // FILL IN: replace with your destination enum. Survives process death
    // via rememberSaveable; the actual ViewModel state survives via
    // SavedStateHandle (Hilt-injected).
    var selectedTab by rememberSaveable { mutableStateOf("home") }
    var openItem by rememberSaveable { mutableStateOf<String?>(null) }

    // The ONE place the inbox is drained: deep links and test doors alike.
    LaunchedEffect(inbox.size) {
        while (inbox.isNotEmpty()) {
            when (val request = inbox.removeAt(0)) {
                is InboxRequest.Tab -> { selectedTab = request.tab; openItem = null }
                is InboxRequest.Item -> openItem = request.id  // FILL IN: push the detail route
                InboxRequest.EndDoor -> openItem = null        // FILL IN: also stop playback
            }
        }
    }

    CompositionLocalProvider(LocalPlayerMuted provides muted) {
        NavigationSuiteScaffold(
            navigationSuiteItems = {
                // FILL IN: navigation destinations
                // item(
                //     selected = selectedTab == "home",
                //     onClick = { selectedTab = "home" },
                //     icon = { Icon(Icons.Default.Home, null) },
                //     label = { Text("Home") },
                // )
            },
        ) {
            Scaffold(
                topBar = {
                    CenterAlignedTopAppBar(
                        title = { Text("App Name") },
                        colors = TopAppBarDefaults.centerAlignedTopAppBarColors(),
                    )
                },
            ) { padding ->
                // FILL IN: route to per-destination Composable
                Column(
                    modifier = Modifier.fillMaxSize().padding(padding).padding(24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center,
                ) {
                    Text("Welcome — selected: $selectedTab")
                    openItem?.let { Text("Item: $it") }
                    Text(
                        "Size class: ${currentWindowAdaptiveInfo().windowSizeClass}",
                    )
                }
            }
        }
    }
}
