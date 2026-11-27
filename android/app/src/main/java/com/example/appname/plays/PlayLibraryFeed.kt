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
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer

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
        /** [facets] are the index's own counts and bins (contract §4.1, B31 C3); null in a library built before them or while only the bundle answers. */
        data class Ready(val rows: List<PlayRow>, val published: Boolean, val facets: PlayFacetsIndex? = null) : Rows
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
        var text: String? = null
        val fresh = try {
            transport.get("index.json")?.also { text = it }?.let(PlayIndex::decode)?.takeIf { it.plays.isNotEmpty() }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            null
        }
        if (fresh != null) {
            runCatching { cache("index.json")?.apply { parentFile?.mkdirs() }?.writeText(text!!) }
            return Rows.Ready(fresh.plays, published = true, facets = fresh.facets)
        }
        val kept = runCatching { cache("index.json")?.takeIf { it.exists() }?.readText()?.let(PlayIndex::decode) }.getOrNull()
        if (kept != null && kept.plays.isNotEmpty()) return Rows.Ready(kept.plays, published = true, facets = kept.facets)
        val bundled = runCatching { bundle() }.getOrDefault(emptyList())
        return if (bundled.isEmpty()) Rows.Unavailable else Rows.Ready(bundled.map(PlayRow::of), published = false)
    }

    private fun cache(name: String): File? = cacheDir?.let { File(it, name) }

    /**
     * One play's whole script: the library's file when the index lists it, else the bundle's. With a [revision], only
     * that revision (the library's file, this device's kept copy, else the bundle's, which may be the older one): null
     * when none is it though another is, which the caller says as "This play has changed". Null too when no one has the
     * play; throws the fetch's error when the library could not be reached and the bundle does not hold it.
     */
    suspend fun script(id: String, revision: String? = null): PlayScript? {
        loadRows()
        val row = (_rows.value as? Rows.Ready)?.rows?.firstOrNull { it.id == id }
        var failure: Exception? = null
        var found: PlayScript? = null
        var kept: PlayScript? = null
        if (row != null && row.path.isNotEmpty()) {
            val file = cache("scripts/$id.json")
            kept = runCatching { if (file != null && file.exists()) decode(file.readText(), id) else null }.getOrNull()
            if (kept != null && kept.revision == row.revision) {
                found = kept
            } else {
                try {
                    val text = transport.get(row.path)
                    found = text?.let { withContext(Dispatchers.Default) { decode(it, id) } }
                    if (found != null && file != null) runCatching { file.apply { parentFile?.mkdirs() }.writeText(text!!) }
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    failure = e
                }
            }
        }
        val floor = runCatching { bundle() }.getOrDefault(emptyList()).firstOrNull { it.id == id }
        val have = listOfNotNull(found, kept, floor)
        if (revision != null) {
            have.firstOrNull { it.revision == revision }?.let { return it }
            if (have.isNotEmpty()) return null
        } else {
            have.firstOrNull()?.let { return it }
        }
        if (failure == null && (_rows.value as? Rows.Ready)?.published != true) failure = IOException("The play library could not be read.")
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

    // ---- Finding a play (B31 §3): the library's own files, never an index built here ----

    private var collectionsRead: PlayCollections? = null
    private var charactersRead: PlayCharacters? = null
    private val shards = java.util.concurrent.ConcurrentHashMap<String, Map<String, List<Int>>>()

    /** The library's collections, read beside the index it was built with; null in an older library or while only the bundle answers. */
    suspend fun collections(): PlayCollections? {
        collectionsRead?.let { return it }
        if ((_rows.value as? Rows.Ready)?.published != true) return null
        val text = try { transport.get("collections.json") } catch (e: CancellationException) { throw e } catch (e: Exception) { null } ?: return null
        return runCatching { PlayCollections.decode(text) }.getOrNull()?.also { collectionsRead = it }
    }

    /** `characters.json`, read once; null in an older library or the bundle. Throws when the file could not be fetched. */
    suspend fun characterNames(): Map<String, List<List<Int>>>? {
        charactersRead?.let { return it.names }
        if ((_rows.value as? Rows.Ready)?.published != true) return null
        val text = transport.get("characters.json") ?: return null
        return PlayCharacters.decode(text).also { charactersRead = it }.names
    }

    /**
     * One shard of `search/lines/` or `search/said/`, kept while the search runs: null when the library has no such directory (a 404
     * for the shard), empty for a shard with no words. Throws when the file could not be fetched.
     */
    suspend fun shard(dir: String, file: String): Map<String, List<Int>>? {
        val key = "$dir/$file"
        shards[key]?.let { return it }
        if ((_rows.value as? Rows.Ready)?.published != true) return null
        val text = transport.get("search/$key.json") ?: return null
        val terms = withContext(Dispatchers.Default) { PlayIndex.json.decodeFromString(MapSerializer(String.serializer(), ListSerializer(Int.serializer())), text) }
        shards[key] = terms
        return terms
    }

    /** Forgets the shards a finished search kept. */
    fun forgetShards() = shards.clear()

    /** A library script read for a line search and not kept (a line search reads many and opens few), decoded off the main thread; null when the row names no file. */
    suspend fun scriptOnce(row: PlayRow): PlayScript? {
        if (row.path.isEmpty()) return null
        val text = transport.get(row.path) ?: return null
        return withContext(Dispatchers.Default) { decode(text, row.id) }
    }

    private fun decode(text: String, id: String): PlayScript? = PlayScriptFile.decode(text).scripts.firstOrNull { it.id == id }

}
