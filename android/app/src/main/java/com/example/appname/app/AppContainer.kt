package com.example.appname.app

import android.content.Context
import com.example.appname.data.ApiClient
import com.example.appname.data.CatalogRepository
import com.example.appname.data.DownloadStore
import com.example.appname.data.UserStore
import com.example.appname.data.WorkManagerDownloadTransport
import com.example.appname.playback.PlaybackEngine
import com.example.appname.plays.PlaysLibrary
import java.io.File

/** The app's singletons, built once in [AppNameApplication]. */
class AppContainer(context: Context) {
    val api = ApiClient()
    val catalog = CatalogRepository(context, api)
    val user: UserStore by lazy { UserStore.open(File(context.filesDir, "user.sqlite").path) }
    val downloads = DownloadStore(File(context.filesDir, "downloads"), WorkManagerDownloadTransport(context))
    val playback = PlaybackEngine(context, api, catalog, user, downloads)
    val plays = PlaysLibrary(context)
}
