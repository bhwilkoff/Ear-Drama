package com.example.appname.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bookmarks
import androidx.compose.material.icons.filled.Explore
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Radio
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateList
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.navigation3.runtime.NavBackStack
import androidx.navigation3.runtime.NavKey
import androidx.navigation3.runtime.entryProvider
import androidx.navigation3.runtime.rememberNavBackStack
import androidx.navigation3.ui.NavDisplay
import com.example.appname.app.AppContainer
import com.example.appname.navigation.InboxRequest
import com.example.appname.navigation.LocalPlayerMuted
import com.example.appname.navigation.Route
import com.example.appname.navigation.Tab
import com.example.appname.navigation.navigateTo
import com.example.appname.plays.PartID
import com.example.appname.ui.screens.EpisodeScreen
import com.example.appname.ui.screens.LibraryScreen
import com.example.appname.ui.screens.ListenScreen
import com.example.appname.ui.screens.MiniPlayer
import com.example.appname.ui.screens.ProductionScreen
import com.example.appname.ui.screens.RadioScreen
import com.example.appname.ui.screens.RecordingScreen
import com.example.appname.ui.screens.ScriptScreen
import com.example.appname.ui.screens.PlayerSheet
import com.example.appname.ui.screens.SearchScreen
import com.example.appname.ui.screens.SeriesBrowseScreen
import com.example.appname.ui.screens.SeriesScreen
import com.example.appname.ui.screens.SurpriseScreen
import com.example.appname.ui.screens.TranscriptScreen

private fun Tab.icon(): ImageVector = when (this) {
    Tab.Home -> Icons.Filled.Home
    Tab.Browse -> Icons.Filled.Explore
    Tab.Stations -> Icons.Filled.Radio
    Tab.Search -> Icons.Filled.Search
    Tab.Library -> Icons.Filled.Bookmarks
}

/**
 * Root: the size-class-adaptive tab surface (bar, rail, or drawer) over one
 * Navigation 3 back stack per tab, so system back and predictive back pop
 * within a tab and a tab tap returns to its root. The mini player sits above
 * the tabs whenever an episode is loaded.
 */
@Composable
fun AppRoot(
    container: AppContainer,
    inbox: SnapshotStateList<InboxRequest> = remember { mutableStateListOf() },
    muted: Boolean = false,
) {
    var selected by rememberSaveable { mutableStateOf(Tab.Home) }
    var playerOpen by rememberSaveable { mutableStateOf(false) }
    var incomingSearch by remember { mutableStateOf<String?>(null) }
    var roomSheet by rememberSaveable { mutableStateOf(false) }
    var roomCode by rememberSaveable { mutableStateOf("") }
    val haptics = rememberHaptics()
    val online by rememberOnline()
    val stacks: Map<Tab, NavBackStack<NavKey>> = Tab.entries.associateWith { tab ->
        rememberNavBackStack(tab.root)
    }
    val stack = stacks.getValue(selected)

    LaunchedEffect(muted) { container.playback.muted = muted }

    // The ONE place the inbox is drained: deep links and test doors alike.
    LaunchedEffect(inbox.size) {
        while (inbox.isNotEmpty()) {
            when (val request = inbox.removeAt(0)) {
                is InboxRequest.Tab -> when {
                    // Surprise is Home's push, never a tab (ANDROID-DESIGN §3.1).
                    request.tab.equals("surprise", ignoreCase = true) -> {
                        selected = Tab.Home
                        stacks.getValue(Tab.Home).navigateTo(Route.Surprise)
                    }
                    else -> Tab.named(request.tab)?.let { selected = it }
                }
                is InboxRequest.Item -> stacks.getValue(selected).navigateTo(Route.Episode(request.id))
                is InboxRequest.Series -> stacks.getValue(selected).navigateTo(Route.Series(request.key))
                is InboxRequest.Search -> {
                    selected = Tab.Search
                    incomingSearch = request.query
                }
                is InboxRequest.Room -> {
                    roomCode = request.code
                    roomSheet = true
                }
                InboxRequest.EndDoor -> {
                    container.playback.stop()
                    playerOpen = false
                }
            }
        }
    }

    val openEpisode: (String) -> Unit = { id -> stack.navigateTo(Route.Episode(id)) }
    val openSeries: (String) -> Unit = { key -> stack.navigateTo(Route.Series(key)) }
    val openTranscript: (String) -> Unit = { id -> stack.navigateTo(Route.Transcript(id)) }
    val back: () -> Unit = { if (stack.size > 1) stack.removeAt(stack.lastIndex) }
    val openScript: (String) -> Unit = { id -> stack.navigateTo(Route.Script(id)) }
    val openProduction: (String) -> Unit = { id -> stack.navigateTo(Route.Production(id)) }

    CompositionLocalProvider(
        LocalPlayerMuted provides muted,
        LocalAppContainer provides container,
        LocalOnline provides online,
    ) {
        HapticEvents()
        NavigationSuiteScaffold(
            navigationSuiteItems = {
                Tab.entries.forEach { tab ->
                    item(
                        selected = tab == selected,
                        onClick = {
                            if (tab == selected) {
                                val s = stacks.getValue(tab)
                                while (s.size > 1) s.removeAt(s.lastIndex)
                            } else {
                                haptics(Haptic.Selection)
                            }
                            selected = tab
                        },
                        icon = { Icon(tab.icon(), contentDescription = null) },
                        label = { Text(tab.label) },
                    )
                }
            },
        ) {
            Column(Modifier.fillMaxSize()) {
                Box(Modifier.weight(1f)) {
                    NavDisplay(
                        backStack = stack,
                        onBack = back,
                        entryProvider = entryProvider {
                            entry<Route.Listen> {
                                ListenScreen(onOpenEpisode = openEpisode, onSurprise = { stack.navigateTo(Route.Surprise) })
                            }
                            entry<Route.SeriesBrowse> {
                                SeriesBrowseScreen(onOpenSeries = openSeries, onOpenScript = openScript)
                            }
                            entry<Route.Surprise> {
                                SurpriseScreen(
                                    onBack = back,
                                    onOpenEpisode = openEpisode,
                                    onOpenScript = openScript,
                                    onOpenProduction = openProduction,
                                )
                            }
                            entry<Route.Radio> { RadioScreen(onOpenEpisode = openEpisode) }
                            entry<Route.Search> {
                                SearchScreen(
                                    onOpenSeries = openSeries,
                                    onOpenEpisode = openEpisode,
                                    onOpenScript = openScript,
                                    incoming = incomingSearch,
                                    onIncomingTaken = { incomingSearch = null },
                                )
                            }
                            entry<Route.Library> {
                                LibraryScreen(
                                    onOpenEpisode = openEpisode,
                                    onOpenSeries = openSeries,
                                    onOpenProduction = openProduction,
                                    onListenTogether = { roomSheet = true },
                                    onOpenDownloads = { stack.navigateTo(Route.Downloads) },
                                )
                            }
                            entry<Route.Downloads> { DownloadsScreen(onBack = back, onOpenEpisode = openEpisode) }
                            entry<Route.Series> { route ->
                                SeriesScreen(route.key, onBack = back, onOpenEpisode = openEpisode)
                            }
                            entry<Route.Episode> { route ->
                                EpisodeScreen(
                                    route.id,
                                    onBack = back,
                                    onOpenSeries = openSeries,
                                    onOpenTranscript = openTranscript,
                                    onOpenProduction = openProduction,
                                )
                            }
                            entry<Route.Transcript> { route -> TranscriptScreen(route.id, onBack = back) }
                            entry<Route.Script> { route ->
                                ScriptScreen(route.id, onBack = back, onOpenProduction = { id ->
                                    // Starting one replaces the play's page with its cast sheet: depth stays two (§1.4).
                                    if (stack.lastOrNull() == route) stack.removeAt(stack.lastIndex)
                                    stack.add(Route.Production(id))
                                })
                            }
                            entry<Route.Production> { route ->
                                ProductionScreen(route.id, onBack = back, onRecord = { part ->
                                    stack.add(Route.Recording(route.id, part.raw))
                                })
                            }
                            entry<Route.Recording> { route ->
                                RecordingScreen(route.production, PartID(route.part), onBack = back)
                            }
                        },
                    )
                }
                // Below the screens, so it never sits under the status bar (edge to edge).
                if (!online) OfflineLine()
                MiniPlayer(onExpand = { playerOpen = true })
            }
        }
        if (playerOpen) {
            PlayerSheet(
                onDismiss = { playerOpen = false },
                onOpenEpisode = { id -> playerOpen = false; openEpisode(id) },
                onOpenTranscript = { id -> playerOpen = false; openTranscript(id) },
                onListenTogether = { playerOpen = false; roomSheet = true },
            )
        }
        if (roomSheet) {
            ListenTogetherSheet(initialCode = roomCode, onDismiss = { roomSheet = false; roomCode = "" })
        }
    }
}
