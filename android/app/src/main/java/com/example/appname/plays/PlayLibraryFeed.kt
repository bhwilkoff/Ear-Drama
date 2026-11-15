package com.example.appname.plays

import io.ktor.client.HttpClient
import io.ktor.client.request.get
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpStatusCode
import io.ktor.http.isSuccess
import java.io.File
import java.io.IOException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout

/** Reads a file of the published play library by its path under `data/plays/library/`; null when the server has none (404). Throws on any other failure. */
fun interface LibraryTransport {
    suspend fun get(path: String): String?
}

/** The one Ktor client's read of the published library (contract §4.1): public data, no session to refresh. */
class KtorLibraryTransport(private val client: HttpClient, private val root: String = DEFAULT_ROOT) : LibraryTransport {
    override suspend fun get(path: String): String? = withTimeout(TIMEOUT_MS) {
        val response = client.get(root + path)
        when {
            response.status == HttpStatusCode.NotFound -> null
            response.status.isSuccess() -> response.bodyAsText()
            else -> throw IOException("HTTP ${response.status.value} for $path")
        }
    }

    companion object {
        const val DEFAULT_ROOT = "https://eardrama.org/data/plays/library/"
        private const val TIMEOUT_MS = 30_000L
    }
}

/**
 * The play library as the lists read it (Decision 075, contract §4.1): the published index's rows when it loads,
 * the last good copy of it on this device when it does not, the bundled plays when there is neither. A script opens
 * from `scripts/<id>.json`, else the bundle; a play that is in neither surfaces the error rather than reading as missing.
 * Mirrors js/api.js `playLibrary` and `playScript`.
 */
class PlayLibraryFeed(
    private val transport: LibraryTransport,
    private val cacheDir: File?,
    private val bundle: suspend () -> List<PlayScript>,
) {
    sealed interface Rows {
        data object Loading : Rows
        data class Ready(val rows: List<PlayRow>, val published: Boolean) : Rows
        data object Unavailable : Rows
    }

    private val _rows = MutableStateFlow<Rows>(Rows.Loading)
    val rows: StateFlow<Rows> = _rows
    private val lock = Mutex()

    suspend fun loadRows() = lock.withLock {
        val now = _rows.value
        if (now is Rows.Ready && now.published) return@withLock
        _rows.value = withContext(Dispatchers.IO) { read() }
    }

    /** Forgets an unavailable answer so the next [loadRows] asks again. */
    fun retry() {
        if (_rows.value is Rows.Unavailable) _rows.value = Rows.Loading
    }

    private suspend fun read(): Rows {
        val fresh = try {
            transport.get("index.json")?.let(PlayIndex::decode)?.plays?.takeIf { it.isNotEmpty() }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            null
        }
        if (fresh != null) {
            runCatching { cache("index.json")?.apply { parentFile?.mkdirs() }?.writeText(PlayIndex.json.encodeToString(PlayIndex.serializer(), PlayIndex(1, fresh.size, fresh))) }
            return Rows.Ready(fresh, published = true)
        }
        val kept = runCatching { cache("index.json")?.takeIf { it.exists() }?.readText()?.let(PlayIndex::decode)?.plays }.getOrNull()
        if (!kept.isNullOrEmpty()) return Rows.Ready(kept, published = true)
        val bundled = runCatching { bundle() }.getOrDefault(emptyList())
        return if (bundled.isEmpty()) Rows.Unavailable else Rows.Ready(bundled.map(PlayRow::of), published = false)
    }

    private fun cache(name: String): File? = cacheDir?.let { File(it, name) }

    /** One play's whole script: the library's file when the index lists it, else the bundle's; null when neither has it. */
    suspend fun script(id: String): PlayScript? {
        loadRows()
        val row = (_rows.value as? Rows.Ready)?.rows?.firstOrNull { it.id == id }
        var failure: Exception? = null
        if (row != null && row.path.isNotEmpty()) {
            val file = cache("scripts/$id.json")
            val kept = runCatching { if (file != null && file.exists()) decode(file.readText(), id) else null }.getOrNull()
            if (kept != null && kept.revision == row.revision) return kept
            try {
                val text = transport.get(row.path)
                val found = text?.let { withContext(Dispatchers.Default) { decode(it, id) } }
                if (found != null) {
                    if (file != null) runCatching { file.apply { parentFile?.mkdirs() }.writeText(text) }
                    return found
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                failure = e
            }
            if (kept != null) return kept
        }
        val bundled = runCatching { bundle() }.getOrDefault(emptyList()).firstOrNull { it.id == id }
        if (bundled != null) return bundled
        if (failure != null) throw failure
        return null
    }

    /**
     * A play's published phonemes (contract §4.1 `phonemes/<id>.json`, Decision 078) as text, for the downloaded voices;
     * null when the index names none (a held play, or no published index: the bundle carries no phonemes). Never cached on
     * disk. Throws when the file could not be fetched.
     */
    suspend fun phonemes(id: String): String? {
        loadRows()
        val now = _rows.value as? Rows.Ready ?: return null
        if (!now.published) return null
        val path = now.rows.firstOrNull { it.id == id }?.phonemes ?: return null
        return transport.get(path)
    }

    private fun decode(text: String, id: String): PlayScript? = PlayScriptFile.decode(text).scripts.firstOrNull { it.id == id }

}
