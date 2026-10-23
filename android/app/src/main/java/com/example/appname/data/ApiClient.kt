package com.example.appname.data

import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.engine.okhttp.OkHttp
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
 * When the project uses Supabase + Cloudflare Workers:
 *  - Add SupabaseAuthInterceptor to the OkHttpClient builder so
 *    every Worker call refreshes the JWT first (the cross-platform
 *    "refresh-before-call" rule — see AGENTS.md).
 *  - Share the OkHttpClient with Coil 3 via Application#sharedOkHttp.
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

    companion object {
        const val USER_AGENT = "EarDrama-Android (https://eardrama.org)"
    }

    @PublishedApi internal val client = HttpClient(OkHttp) {
        engine { preconfigured = okHttp }
        install(ContentNegotiation) {
            json(
                Json {
                    ignoreUnknownKeys = true
                    encodeDefaults = false
                },
            )
        }
        // FILL IN: defaultRequest { url(BASE_URL); header("Authorization", ...) }
    }

    suspend inline fun <reified T> get(url: String): T = client.get(url).body()

    suspend inline fun <reified T, reified B : Any> post(url: String, body: B): T =
        client.post(url) {
            contentType(ContentType.Application.Json)
            setBody(body)
        }.body()
}
