package com.example.appname.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bookmarks
import androidx.compose.material.icons.filled.Explore
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.adaptive.currentWindowAdaptiveInfo
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffold
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffoldDefaults
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteType
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
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
import com.example.appname.ui.screens.CastingBoardScreen
import com.example.appname.ui.screens.ClassPageScreen
import com.example.appname.ui.screens.DramaScreen
import com.example.appname.ui.screens.ReadPairScreen
import com.example.appname.ui.screens.ReadRoomScreen
import com.example.appname.ui.screens.ReadScreenScreen
import com.example.appname.ui.screens.InvitationScreen
import com.example.appname.ui.screens.LibraryScreen
import com.example.appname.ui.screens.ListenScreen
import com.example.appname.ui.screens.MiniPlayer
import com.example.appname.ui.screens.PersonScreen
import com.example.appname.ui.screens.ProductionScreen
import com.example.appname.ui.screens.RadioScreen
import com.example.appname.ui.screens.ReaderScreen
import com.example.appname.ui.screens.RecordScreen
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
    Tab.Record -> Icons.Filled.Mic
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
    forceOffline: Boolean = false,
) {
    var selected by rememberSaveable { mutableStateOf(Tab.Home) }
    var playerOpen by rememberSaveable { mutableStateOf(false) }
    var incomingSearch by remember { mutableStateOf<String?>(null) }
    var browseGenre by remember { mutableStateOf<String?>(null) }
    var browseDramas by remember { mutableStateOf(false) }
    var browseVoices by remember { mutableStateOf(false) }
    var studioDoor by remember { mutableStateOf<InboxRequest.Read?>(null) }
    var roomSheet by rememberSaveable { mutableStateOf(false) }
    var roomCode by rememberSaveable { mutableStateOf("") }
    val haptics = rememberHaptics()
    val network by rememberOnline()
    val online = network && !forceOffline
    val stacks: Map<Tab, NavBackStack<NavKey>> = Tab.entries.associateWith { tab ->
        rememberNavBackStack(tab.root)
    }
    val stack = stacks.getValue(selected)

    LaunchedEffect(muted) { container.playback.muted = muted }
    // Before any screen's focus claim runs: a key pressed from here on belongs to the new screen.
    val top = stack.lastOrNull()
    LaunchedEffect(selected, top) { TvFocusClock.screenOpened() }

    LaunchedEffect(studioDoor) {
        val door = studioDoor ?: return@LaunchedEffect
        val part = door.studioPart ?: return@LaunchedEffect
        val resolved = runCatching {
            container.plays.script(door.id)?.let { script ->
                com.example.appname.plays.StudioOpen.resolve(container.plays, script, PartID(part))
            }
        }.getOrNull()
        stacks.getValue(Tab.Record).navigateTo(Route.Reader(door.id, door.line, resolved, resolved?.let { part }))
        studioDoor = null
    }

    // The ONE place the inbox is drained: deep links and test doors alike.
    LaunchedEffect(inbox.size) {
        while (inbox.isNotEmpty()) {
            when (val request = inbox.removeAt(0)) {
                is InboxRequest.Tab -> when {
                    // Stations and Surprise are Home's pushes, never tabs (ANDROID-DESIGN §3.1).
                    Tab.pushedFromHome(request.tab) != null -> {
                        selected = Tab.Home
                        stacks.getValue(Tab.Home).navigateTo(Tab.pushedFromHome(request.tab)!!)
                    }
                    // A TV records nothing: its Record door opens nothing.
                    else -> Tab.named(request.tab)?.takeUnless { it == Tab.Record && container.isTelevision }?.let { selected = it }
                }
                is InboxRequest.Item -> stacks.getValue(selected).navigateTo(if ('|' in request.id) Route.Episode(request.id) else Route.Series(request.id))
                is InboxRequest.ReadRoom -> stacks.getValue(selected).navigateTo(Route.ReadRoom(request.code, request.screen || container.isTelevision, request.seat))
                is InboxRequest.ReadPair -> stacks.getValue(selected).navigateTo(Route.ReadPair)
                is InboxRequest.Series -> stacks.getValue(selected).navigateTo(Route.Series(request.key))
                is InboxRequest.Person -> stacks.getValue(selected).navigateTo(Route.Person(request.id))
                is InboxRequest.Search -> {
                    selected = Tab.Search
                    incomingSearch = request.query
                }
                is InboxRequest.Room -> {
                    roomCode = request.code
                    roomSheet = true
                }
                is InboxRequest.Invite -> {
                    // A TV plays back only (PLAYS-DESIGN §11.7): it holds nothing and opens nothing.
                    if (!container.isTelevision) {
                        container.sharing.hold(request.token)
                        stacks.getValue(selected).navigateTo(Route.Invitation)
                    }
                }
                // A TV lists no ear dramas yet (PARITY), so a drama link opens nothing there.
                is InboxRequest.Drama -> if (!container.isTelevision) stacks.getValue(selected).navigateTo(Route.Drama(request.pid))
                is InboxRequest.Along -> {
                    com.example.appname.navigation.AlongDoor.autoplay = request.pid
                    stacks.getValue(selected).navigateTo(Route.Drama(request.pid))
                }
                is InboxRequest.Read -> if (!container.isTelevision) {
                    // The studio door presses the reader's Record for the part (PLAYS-DESIGN §2.9 rule 1), off this loop:
                    // a suspension here would be cancelled by the next inbox change.
                    if (request.studioPart != null) {
                        studioDoor = request
                    } else {
                        stacks.getValue(Tab.Record).navigateTo(Route.Reader(request.id, request.line))
                    }
                    selected = Tab.Record
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
    // A series page's genre link: Browse at its root, filtered to that genre.
    val openGenre: (String) -> Unit = { genre ->
        val browse = stacks.getValue(Tab.Browse)
        while (browse.size > 1) browse.removeAt(browse.lastIndex)
        browseGenre = genre
        selected = Tab.Browse
    }
    val openPerson: (String) -> Unit = { id -> stack.navigateTo(Route.Person(id)) }
    val openTranscript: (String) -> Unit = { id -> stack.navigateTo(Route.Transcript(id)) }
    val back: () -> Unit = { if (stack.size > 1) stack.removeAt(stack.lastIndex) }
    val openScript: (String) -> Unit = { id -> stack.navigateTo(Route.Script(id)) }
    val openDrama: (String) -> Unit = { id -> stack.navigateTo(Route.Drama(id)) }
    val openProduction: (String) -> Unit = { id -> stack.navigateTo(Route.Production(id)) }
    val openReader: (String) -> Unit = { id -> stack.navigateTo(Route.Reader(id)) }
    val openStudio: com.example.appname.ui.screens.OpenStudio = { id, line, production, part ->
        stack.navigateTo(Route.Reader(id, line, production, part))
    }
    val accountAsk by container.plays.accountAsk.collectAsState()
    // Reading is full screen (§4.17): the tab bar, the mini player and the offline line step aside.
    val last = stack.lastOrNull()
    val reading = last is Route.Reader || last is Route.ReadRoom || last is Route.ReadPair

    CompositionLocalProvider(
        LocalPlayerMuted provides muted,
        LocalAppContainer provides container,
        LocalOnline provides online,
        com.example.appname.ui.screens.LocalReadNav provides com.example.appname.ui.screens.ReadNav(
            openClass = { id -> stack.navigateTo(Route.ClassPage(id)) },
            openRoom = { code -> stack.navigateTo(Route.ReadRoom(code)) },
            showReading = { stack.navigateTo(Route.ReadPair) },
        ),
    ) {
        HapticEvents()
        // §9.2a: on a TV the whole app sits inside the safe area; the background still fills the screen.
        val safeArea = if (container.isTelevision) {
            Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)
                .padding(horizontal = TvSafeHorizontal, vertical = TvSafeVertical)
        } else Modifier
        NavigationSuiteScaffold(
            modifier = safeArea,
            layoutType = if (reading) NavigationSuiteType.None
            else NavigationSuiteScaffoldDefaults.calculateFromAdaptiveInfo(currentWindowAdaptiveInfo()),
            navigationSuiteItems = {
                Tab.entries.filter { !(container.isTelevision && it == Tab.Record) }.forEach { tab ->
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
                                ListenScreen(
                                    onOpenEpisode = openEpisode, onOpenSeries = openSeries,
                                    onSurprise = { stack.navigateTo(Route.Surprise) },
                                    onBrowse = { haptics(Haptic.Selection); selected = Tab.Browse },
                                    onOpenDrama = openDrama,
                                    onDramas = { haptics(Haptic.Selection); browseDramas = true; selected = Tab.Browse },
                                    onOpenPerson = openPerson,
                                    onVoices = { haptics(Haptic.Selection); browseVoices = true; selected = Tab.Browse },
                                    onOpenStations = { stack.navigateTo(Route.Radio) },
                                    onOpenRecord = { haptics(Haptic.Selection); selected = Tab.Record },
                                    onOpenScript = openScript,
                                    onOpenProduction = openProduction,
                                    onRead = openReader,
                                    onOpenStudio = openStudio,
                                )
                            }
                            entry<Route.SeriesBrowse> {
                                SeriesBrowseScreen(
                                    onOpenSeries = openSeries,
                                    genreRequest = browseGenre, onGenreRequestHandled = { browseGenre = null },
                                    dramasRequest = browseDramas, onDramasRequestHandled = { browseDramas = false },
                                    voicesRequest = browseVoices, onVoicesRequestHandled = { browseVoices = false },
                                    onOpenPerson = openPerson,
                                    onOpenDrama = openDrama,
                                )
                            }
                            entry<Route.Surprise> {
                                SurpriseScreen(
                                    onBack = back,
                                    onOpenEpisode = openEpisode,
                                    onOpenScript = openScript,
                                    onOpenProduction = openProduction,
                                )
                            }
                            entry<Route.Radio> { RadioScreen(onOpenEpisode = openEpisode, onBack = back) }
                            entry<Route.Record> {
                                RecordScreen(
                                    onOpenScript = openScript, onOpenProduction = openProduction, onOpenDrama = openDrama,
                                    onDramas = { haptics(Haptic.Selection); browseDramas = true; selected = Tab.Browse },
                                    onRead = openReader,
                                    onOpenStudio = openStudio,
                                )
                            }
                            entry<Route.Search> {
                                SearchScreen(
                                    onOpenSeries = openSeries,
                                    onOpenEpisode = openEpisode,
                                    onOpenScript = openScript,
                                    onOpenPerson = openPerson,
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
                                    onBrowse = { haptics(Haptic.Selection); selected = Tab.Browse },
                                )
                            }
                            entry<Route.Downloads> { DownloadsScreen(onBack = back, onOpenEpisode = openEpisode) }
                            entry<Route.Series> { route ->
                                SeriesScreen(route.key, onBack = back, onOpenEpisode = openEpisode, onOpenGenre = openGenre)
                            }
                            entry<Route.Episode> { route ->
                                EpisodeScreen(
                                    route.id,
                                    onBack = back,
                                    onOpenSeries = openSeries,
                                    onOpenTranscript = openTranscript,
                                    onOpenProduction = openProduction,
                                    onOpenPerson = openPerson,
                                )
                            }
                            entry<Route.Person> { route ->
                                PersonScreen(route.id, onBack = back, onOpenEpisode = openEpisode, onOpenSeries = openSeries)
                            }
                            entry<Route.Invitation> {
                                InvitationScreen(onBack = back, onOpenProduction = { id ->
                                    // Joining replaces the invitation with the cast sheet: depth stays two.
                                    if (stack.lastOrNull() == Route.Invitation) stack.removeAt(stack.lastIndex)
                                    stack.add(Route.Production(id))
                                })
                            }
                            entry<Route.Drama> { route ->
                                DramaScreen(route.id, onBack = back, onReadAlong = { play, _ -> stack.add(Route.Reader(play.scriptId, null, null, null, along = true, drama = play.id)) })
                            }
                            entry<Route.ReadRoom> { route ->
                if (route.screen) ReadScreenScreen(route.code, onBack = back)
                else ReadRoomScreen(route.code, onBack = back, onOpenScreen = { stack.add(Route.ReadRoom(it, screen = true)) }, seatDoor = route.seat)
            }
            entry<Route.ReadPair> { ReadPairScreen(onBack = back) }
            entry<Route.ClassPage> { route ->
                ClassPageScreen(route.id, onBack = back, onCasting = { c, p -> stack.add(Route.ClassCasting(c, p)) }, onOpenRoom = { stack.add(Route.ReadRoom(it)) })
            }
            entry<Route.ClassCasting> { route -> CastingBoardScreen(route.classId, route.productionId, onBack = back) }
            entry<Route.Transcript> { route -> TranscriptScreen(route.id, onBack = back) }
                            entry<Route.Script> { route ->
                                ScriptScreen(route.id, onBack = back, onRead = openReader, onOpenProduction = { id ->
                                    // Starting one replaces the play's page with its cast sheet: depth stays two (§1.4).
                                    if (stack.lastOrNull() == route) stack.removeAt(stack.lastIndex)
                                    stack.add(Route.Production(id))
                                })
                            }
                            entry<Route.Reader> { route ->
                                ReaderScreen(
                                    route.scriptId, route.lineId, route.productionId, route.part, route.along, route.drama, onBack = back,
                                    onOpenStudio = { production, part, line ->
                                        // Record in the reader replaces it with the reader holding the studio: depth stays the same.
                                        if (stack.lastOrNull() == route) stack.removeAt(stack.lastIndex)
                                        stack.add(Route.Reader(route.scriptId, line, production, part))
                                    },
                                )
                            }
                            entry<Route.Production> { route ->
                                // Take Part, Record and Open Part open the reader with the studio (PLAYS-DESIGN §2.9 rule 1).
                                val openStudio = { part: PartID, line: String? ->
                                    container.plays.store.production(route.id)?.let { stack.add(Route.Reader(it.scriptID, line, route.id, part.raw)) }
                                    Unit
                                }
                                val readAlong = {
                                    container.plays.store.production(route.id)?.let { stack.add(Route.Reader(it.scriptID, null, route.id, null, along = true)) }
                                    Unit
                                }
                                ProductionScreen(route.id, onBack = back, onRecord = { part -> openStudio(part, null) }, onReplace = { part, line -> openStudio(part, line) }, onReadAlong = readAlong)
                            }
                            entry<Route.Recording> { route ->
                                RecordingScreen(route.production, PartID(route.part), onBack = back, startLine = route.line)
                            }
                        },
                    )
                }
                // Below the screens, so it never sits under the status bar (edge to edge).
                if (!reading) {
                    offlineLine(online)?.let { OfflineLine(it) }
                    MiniPlayer(onExpand = { playerOpen = true })
                }
            }
        }
        if (playerOpen) {
            PlayerSheet(
                onDismiss = { playerOpen = false },
                onOpenEpisode = { id -> playerOpen = false; openEpisode(id) },
                onOpenSeries = { key -> playerOpen = false; openSeries(key) },
                onOpenTranscript = { id -> playerOpen = false; openTranscript(id) },
                onListenTogether = { playerOpen = false; roomSheet = true },
                onOpenPerson = { id -> playerOpen = false; openPerson(id) },
            )
        }
        if (roomSheet) {
            ListenTogetherSheet(initialCode = roomCode, onDismiss = { roomSheet = false; roomCode = "" })
        }
        // A production that could not begin without an account (Decision 079): the reason and the sign-in, in place of the studio.
        accountAsk?.let { why -> SignInSheet(why) { container.plays.accountAsk.value = null } }
    }
}
