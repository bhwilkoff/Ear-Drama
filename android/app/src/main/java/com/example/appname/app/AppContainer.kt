package com.example.appname.app

import android.content.Context
import com.example.appname.BuildConfig
import com.example.appname.account.Accounts
import com.example.appname.account.KeystoreSessionStore
import com.example.appname.account.SyncEngine
import com.example.appname.account.WorkerApi
import com.example.appname.account.WorkerConfig
import com.example.appname.data.ApiClient
import com.example.appname.data.CatalogRepository
import com.example.appname.data.DownloadStore
import com.example.appname.data.UserStore
import com.example.appname.data.WorkManagerDownloadTransport
import com.example.appname.kokoro.KokoroModelStore
import com.example.appname.kokoro.KokoroModule
import com.example.appname.kokoro.KokoroReader
import com.example.appname.kokoro.KtorRangeFetch
import com.example.appname.playback.PlaybackEngine
import com.example.appname.plays.FinishedList
import com.example.appname.plays.KtorLibraryTransport
import com.example.appname.plays.OpenPlaysApi
import com.example.appname.plays.PlaysApi
import com.example.appname.plays.PlaysLibrary
import com.example.appname.plays.SharedPlays
import com.example.appname.radio.LiveRadio
import com.example.appname.together.EngineRoomPlayer
import com.example.appname.together.ListenTogether
import com.example.appname.together.RoomsApi
import com.example.appname.ui.isTelevision
import io.ktor.client.request.get
import io.ktor.client.statement.bodyAsText
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/** The app's singletons, built once in [AppNameApplication]. */
class AppContainer(context: Context, scope: CoroutineScope) {
    val api = ApiClient()
    val catalog = CatalogRepository(context, api)
    val user: UserStore by lazy { UserStore.open(File(context.filesDir, "user.sqlite").path) }
    val downloads = DownloadStore(File(context.filesDir, "downloads"), WorkManagerDownloadTransport(context))
    val playback = PlaybackEngine(context, api, catalog, user, downloads)
    val queue by lazy { QueueVerbs(user, playback) }
    val plays = PlaysLibrary(context, KtorLibraryTransport(api.client)).also { p -> p.signedIn = { accounts.account.value != null } }
    val isTelevision = context.isTelevision()

    /**
     * The downloaded voices (Decision 078, S6d): the model under `filesDir/kokoro/v2`, fetched on the one Ktor client only
     * when the person asks, the play's phonemes through the library's client. The download runs in the app's scope so
     * leaving the picker does not stop it.
     */
    val kokoro: KokoroReader by lazy {
        KokoroReader(
            KokoroModelStore(File(context.filesDir, "kokoro/v2"), KtorRangeFetch(api.client)),
            phonemes = { id -> plays.phonemes(id) },
            engineReady = { kokoroModule.state.value is KokoroModule.State.Installed },
        )
    }

    /** The engine, an on-demand Play module installed with the voices (owner 2026-11-15). */
    val kokoroModule: KokoroModule by lazy { KokoroModule(context) }
    private val appScope = scope
    private var voiceDownload: Job? = null

    /** "Download voices": the engine module from Play, then the model; one at a time; a partial file resumes. */
    fun downloadVoices() {
        if (voiceDownload?.isActive == true) return
        kokoro.store.clearFailure()
        kokoroModule.clearFailure()
        voiceDownload = appScope.launch { if (kokoroModule.install()) kokoro.store.download() }
    }

    fun cancelVoiceDownload() {
        voiceDownload?.cancel()
        voiceDownload = null
    }

    /** "Delete downloaded voices": the model goes; parts cast to a Kokoro voice fall back visibly (§2.8 rule 8). */
    fun deleteVoices() {
        cancelVoiceDownload()
        appScope.launch {
            kokoro.unload()
            kokoro.store.delete()
            kokoroModule.uninstall()
        }
    }
    val live = LiveRadio(
        play = { detail, startMs -> playback.play(detail.episode, startMs = startMs, queue = false) },
        pause = { playback.pause() },
    ).also { live -> playback.onTransport = live::handle }

    /** Listen Together rooms on the Worker (DECISIONS 065): no account, the one Ktor client, the one engine. */
    val together: ListenTogether by lazy {
        ListenTogether(
            RoomsApi(api.client, BuildConfig.WORKER_BASE_URL),
            EngineRoomPlayer(playback, catalog),
            CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate),
        )
    }

    /** Shared ear dramas, phase 2 (PLAYS-DESIGN §11.7): the Worker's calls on the one client, never on a TV. */
    val sharing: SharedPlays by lazy {
        SharedPlays(
            PlaysApi(accounts.worker),
            plays.store,
            { accounts.account.value?.userId },
            { plays.load(); (plays.state.value as? PlaysLibrary.State.Ready)?.scripts.orEmpty() },
            libraryScript = { id, revision -> plays.script(id)?.takeIf { it.revision == revision } },
        )
    }

    /** Relay across time (PLAYS-DESIGN §12.11): the one sender for the takes on this device waiting for a receiver. */
    val relay: com.example.appname.plays.RelayHub by lazy {
        com.example.appname.plays.RelayHub(
            plays.store, scope,
            com.example.appname.plays.WorkerSeat(accounts.worker), PlaysApi(accounts.worker), com.example.appname.plays.WorkerMemberReceiver(accounts.worker),
            com.example.appname.plays.KeystoreSeatVault(File(context.noBackupFilesDir, "seats")),
            { accounts.account.value?.userId },
        )
    }

    /** Plays that need no account: an invite read and the finished ear dramas (owner, 2026-10-29). */
    val openPlays: OpenPlaysApi by lazy { OpenPlaysApi(accounts.worker) }

    /** Reading together (Decision 082): the read room's routes and the class's, both on the one Worker client. */
    val readWire: com.example.appname.plays.ReadWire by lazy { com.example.appname.plays.WorkerReadWire(accounts.worker) }
    val readClass: com.example.appname.plays.ReadClassWire by lazy { com.example.appname.plays.WorkerReadClass(accounts.worker) }
    val finished: FinishedList by lazy {
        FinishedList(openPlays) { item -> api.client.get("https://archive.org/metadata/$item").bodyAsText() }
    }

    /** Optional sign-in and sync (DECISIONS 057, 063), on the one Ktor client. */
    val accounts: Accounts by lazy {
        val device = if (context.isTelevision()) "android-tv" else "android"
        val worker = WorkerApi(
            api.client,
            WorkerConfig(
                baseUrl = com.example.appname.navigation.LaunchDoors.workerUrl ?: BuildConfig.WORKER_BASE_URL,
                googleWebClientId = BuildConfig.GOOGLE_WEB_CLIENT_ID,
                appleServicesId = BuildConfig.APPLE_SERVICES_ID,
                appleReturnUrl = BuildConfig.APPLE_RETURN_URL,
            ),
            KeystoreSessionStore(File(context.noBackupFilesDir, "account.bin")),
        )
        Accounts(worker, SyncEngine(worker, user, device, forwarding = { catalog.db?.forwarding() }), device, scope)
    }

    /** Contract §3.5: every store that keeps episode ids rewrites the ones the open catalog moved. */
    suspend fun forwardStored() {
        val forwarding = catalog.db?.forwarding() ?: return
        user.forward(forwarding)
        downloads.forward(forwarding)
    }
}
