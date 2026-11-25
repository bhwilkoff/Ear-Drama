package com.example.appname.data

import com.example.appname.plays.OwnCue
import com.example.appname.plays.OwnScript
import com.example.appname.radio.Station
import com.example.appname.radio.StationsFile
import com.example.appname.radio.TonightFile
import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.engine.okhttp.OkHttp
import io.ktor.client.plugins.HttpTimeout
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.request.get
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.http.ContentType
import io.ktor.http.contentType
import io.ktor.serialization.kotlinx.json.json
import java.io.IOException
import java.io.InputStream
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import okhttp3.Request

/**
 * Shared API client — ALL network calls go through this Hilt
 * singleton. Composables / ViewModels never use HttpClient or
 * OkHttpClient directly.
 *
 * Same architectural rule as iOS APIClient.shared and web js/api.js.
 *
 * The Worker (accounts and sync, docs/WORKER.md) rides [client] through
 * [com.example.appname.account.WorkerApi], which refreshes the session
 * before every call (the cross-platform "refresh-before-call" rule, AGENTS.md).
 */
@Singleton
class ApiClient @Inject constructor() {

    /**
     * The one OkHttp client: Ktor, the catalog refresh, and ExoPlayer's audio
     * all ride it, so the User-Agent archive.org expects is set in one place.
     */
    val okHttp: OkHttpClient = OkHttpClient.Builder()
        .addInterceptor { chain ->
            chain.proceed(chain.request().newBuilder().header("User-Agent", USER_AGENT).build())
        }
        .build()

    /** A conditional GET's result: [body] is null on 304 or a failed status. */
    class Conditional(val code: Int, val etag: String?, val body: InputStream?, private val onClose: () -> Unit) :
        AutoCloseable {
        override fun close() = onClose()
    }

    /** An ETag-conditional GET whose body the caller streams, then closes. Blocking. */
    fun conditionalGet(url: String, etag: String?): Conditional {
        val request = Request.Builder().url(url).apply {
            if (!etag.isNullOrEmpty()) header("If-None-Match", etag)
        }.build()
        val response = okHttp.newCall(request).execute()
        val ok = response.isSuccessful && response.code != 304
        return Conditional(response.code, response.header("ETag"), if (ok) response.body.byteStream() else null) {
            response.close()
        }
    }

    /**
     * A plain-text file from a host we do not run: archive.org's automatic
     * transcripts (§3.1). Throws on a failed status or no network.
     */
    suspend fun text(url: String): String = withContext(Dispatchers.IO) {
        okHttp.newCall(Request.Builder().url(url).header("Accept", "text/plain").build()).execute().use { response ->
            if (!response.isSuccessful) throw IOException("HTTP ${response.code} for $url")
            response.body.string()
        }
    }

    /** A shown transcript's times, as [transcriptCues] read them. */
    class CuesException(val missing: Boolean, message: String) : IOException(message)

    private val cueReads = object : LinkedHashMap<String, List<OwnCue>>(8, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, List<OwnCue>>) = size > 8
    }

    /**
     * A shown transcript's cues with their times ([url] is the Detail row's transcript), read once while the app runs. A
     * [CuesException] that is `missing`: no times, nothing to cast by ear. Any other failure may be asked again.
     */
    suspend fun transcriptCues(url: String?): List<OwnCue> {
        val at = cuesUrl(url) ?: throw CuesException(true, "no times for $url")
        synchronized(cueReads) { cueReads[at] }?.let { return it }
        val cues = withContext(Dispatchers.IO) {
            okHttp.newCall(Request.Builder().url(at).header("Accept", "text/vtt").build()).execute().use { response ->
                if (response.code == 404 || response.code == 403) throw CuesException(true, "HTTP ${response.code} for $at")
                if (!response.isSuccessful) throw CuesException(false, "HTTP ${response.code} for $at")
                OwnScript.parseCues(response.body.string()).filter { it.at != null }
            }
        }
        if (cues.isEmpty()) throw CuesException(true, "no times at $at")
        synchronized(cueReads) { cueReads[at] = cues }
        return cues
    }

    /**
     * Tonight in 19xx (contract §8) from the catalog's Release, or null when
     * none is published (404). Throws on any other failed status or no network.
     */
    suspend fun tonight(url: String = TONIGHT_URL): TonightFile? =
        if (url == TONIGHT_URL) tonightDay.get { fetchTonight(url) } else fetchTonight(url)

    private val tonightDay = DayCache<TonightFile>()
    private val stationsDay = DayCache<List<Station>>()

    private suspend fun fetchTonight(url: String): TonightFile? = withContext(Dispatchers.IO) {
        okHttp.newCall(Request.Builder().url(url).header("Accept", "application/json").build()).execute().use { response ->
            if (response.code == 404) return@use null
            if (!response.isSuccessful) throw IOException("HTTP ${response.code} for $url")
            TonightFile.decode(response.body.string())
        }
    }

    /**
     * The genre stations (contract §8) beside tonight.json, or an empty list
     * when none is published (404). Throws on any other failed status.
     */
    suspend fun stations(url: String = STATIONS_URL): List<Station> =
        (if (url == STATIONS_URL) stationsDay.get { fetchStations(url).ifEmpty { null } } else fetchStations(url))
            ?: emptyList()

    private suspend fun fetchStations(url: String): List<Station> = withContext(Dispatchers.IO) {
        okHttp.newCall(Request.Builder().url(url).header("Accept", "application/json").build()).execute().use { response ->
            if (response.code == 404) return@use emptyList()
            if (!response.isSuccessful) throw IOException("HTTP ${response.code} for $url")
            StationsFile.decode(response.body.string())
        }
    }

    companion object {
        private val TRANSCRIPT = Regex("https://archive\\.org/download/([^/]+/.+)\\.autogenerated\\.txt")

        /** Where a shown transcript's times are: the `.vtt` beside the `.txt`. Null for any other address. */
        fun cuesUrl(url: String?): String? =
            url?.let { TRANSCRIPT.matchEntire(it) }?.let { "https://archive.org/download/${it.groupValues[1]}.autogenerated.vtt" }

        const val STATIONS_URL = "https://github.com/bhwilkoff/Ear-Drama/releases/download/catalog-latest/stations.json"
        const val TONIGHT_URL = "https://github.com/bhwilkoff/Ear-Drama/releases/download/catalog-latest/tonight.json"
        const val USER_AGENT = "EarDrama-Android (https://eardrama.org)"
    }

    @PublishedApi internal val client = HttpClient(OkHttp) {
        engine { preconfigured = okHttp }
        // No defaults: only a request that asks (a read room's long poll) waits longer than OkHttp's own timeouts.
        install(HttpTimeout)
        install(ContentNegotiation) {
            json(
                Json {
                    ignoreUnknownKeys = true
                    encodeDefaults = false
                },
            )
        }
    }

    suspend inline fun <reified T> get(url: String): T = client.get(url).body()

    suspend inline fun <reified T, reified B : Any> post(url: String, body: B): T =
        client.post(url) {
            contentType(ContentType.Application.Json)
            setBody(body)
        }.body()
}
