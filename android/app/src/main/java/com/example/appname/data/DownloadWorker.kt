package com.example.appname.data

import android.content.Context
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import com.example.appname.app.AppNameApplication
import java.io.File
import java.io.IOException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request

/**
 * The store's transport on WorkManager: a persisted job per download, run when
 * any network is up (cellular too: episodes are 15 to 30 MB), carried across
 * process death and reboot by WorkManager itself.
 */
class WorkManagerDownloadTransport(private val context: Context) : DownloadTransport {
    companion object {
        const val TAG = "episode-download"
        const val KEY_TOKEN = "token"
        const val KEY_URL = "url"
        private const val TOKEN_TAG = "download-token:"
    }

    private val work get() = WorkManager.getInstance(context)

    override fun begin(token: String, url: String) {
        val request = OneTimeWorkRequestBuilder<DownloadWorker>()
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .setInputData(workDataOf(KEY_TOKEN to token, KEY_URL to url))
            .addTag(TAG)
            .addTag(TOKEN_TAG + token)
            .build()
        work.enqueueUniqueWork(TOKEN_TAG + token, ExistingWorkPolicy.KEEP, request)
    }

    override fun cancel(token: String) {
        work.cancelUniqueWork(TOKEN_TAG + token)
    }

    override fun cancelAll() {
        work.cancelAllWorkByTag(TAG)
    }

    override suspend fun liveTokens(): Set<String> =
        work.getWorkInfosByTagFlow(TAG).first()
            .filter { !it.state.isFinished }
            .flatMap { info -> info.tags.filter { it.startsWith(TOKEN_TAG) }.map { it.removePrefix(TOKEN_TAG) } }
            .toSet()
}

/**
 * Moves one recording's bytes into the store's transfer file, then hands the
 * file to the store, which names it or deletes it. However the run ends (done,
 * failed, cancelled, stopped by the system), the transfer file is deleted here,
 * so a partial never outlives its run. A system stop leaves the record active
 * and WorkManager runs the job again from the start.
 */
class DownloadWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        val container = (applicationContext as AppNameApplication).container
        val store = container.downloads
        val token = inputData.getString(WorkManagerDownloadTransport.KEY_TOKEN) ?: return Result.failure()
        val url = inputData.getString(WorkManagerDownloadTransport.KEY_URL) ?: return Result.failure()
        if (!store.isActive(token)) return Result.success()
        val temp = store.transferFile(token)
        try {
            val status = fetch(container.api.okHttp, url, temp) { received, expected ->
                store.transferProgressed(token, received, expected)
            }
            store.transferFinished(token, temp, status)
        } catch (e: IOException) {
            store.transferFailed(token, e.message)
        } finally {
            temp.delete()
        }
        return Result.success()
    }

    /** Writes the body to [into] when the status is 2xx; returns the status either way. */
    private suspend fun fetch(
        client: OkHttpClient,
        url: String,
        into: File,
        progress: (Long, Long) -> Unit,
    ): Int = withContext(Dispatchers.IO) {
        into.delete()
        client.newCall(Request.Builder().url(url).build()).execute().use { response ->
            if (!response.isSuccessful) return@use response.code
            val body = response.body
            val expected = body.contentLength()
            var received = 0L
            body.byteStream().use { input ->
                into.outputStream().use { output ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        currentCoroutineContext().ensureActive()
                        val n = input.read(buffer)
                        if (n < 0) break
                        output.write(buffer, 0, n)
                        received += n
                        progress(received, expected)
                    }
                }
            }
            response.code
        }
    }
}
