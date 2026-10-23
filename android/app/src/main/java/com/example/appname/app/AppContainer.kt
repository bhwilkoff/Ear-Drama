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
import com.example.appname.playback.PlaybackEngine
import com.example.appname.plays.PlaysLibrary
import com.example.appname.radio.LiveRadio
import com.example.appname.ui.isTelevision
import java.io.File
import kotlinx.coroutines.CoroutineScope

/** The app's singletons, built once in [AppNameApplication]. */
class AppContainer(context: Context, scope: CoroutineScope) {
    val api = ApiClient()
    val catalog = CatalogRepository(context, api)
    val user: UserStore by lazy { UserStore.open(File(context.filesDir, "user.sqlite").path) }
    val downloads = DownloadStore(File(context.filesDir, "downloads"), WorkManagerDownloadTransport(context))
    val playback = PlaybackEngine(context, api, catalog, user, downloads)
    val plays = PlaysLibrary(context)
    val live = LiveRadio(
        play = { detail, startMs -> playback.play(detail.episode, startMs = startMs, queue = false) },
        pause = { playback.pause() },
    ).also { live -> playback.onTransport = live::handle }

    /** Optional sign-in and sync (DECISIONS 057, 063), on the one Ktor client. */
    val accounts: Accounts by lazy {
        val device = if (context.isTelevision()) "android-tv" else "android"
        val worker = WorkerApi(
            api.client,
            WorkerConfig(
                baseUrl = BuildConfig.WORKER_BASE_URL,
                googleWebClientId = BuildConfig.GOOGLE_WEB_CLIENT_ID,
                appleServicesId = BuildConfig.APPLE_SERVICES_ID,
                appleReturnUrl = BuildConfig.APPLE_RETURN_URL,
            ),
            KeystoreSessionStore(File(context.noBackupFilesDir, "account.bin")),
        )
        Accounts(worker, SyncEngine(worker, user, device), device, scope)
    }
}
