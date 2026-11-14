package com.example.appname.data

import android.content.Context
import com.example.appname.BuildConfig
import java.io.File
import java.io.InputStream
import java.util.zip.Inflater
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/** What the catalog is serving right now. */
enum class CatalogSource { None, Seed, Full }

/**
 * The catalog's lifecycle (docs/CATALOG-CONTRACT.md §2), ported from Archive
 * Watch's CatalogRepository: the bundled seed for a first launch offline,
 * then the full projection from the rolling release, fetched with an
 * ETag-conditional GET, inflated as raw DEFLATE straight into a staging file,
 * validated (size floor, integrity_check, schema floor, a known row), and
 * swapped in by an atomic rename. Any failure keeps what is already served.
 * Screens key their queries on [dbVersion], which bumps on every swap.
 */
class CatalogRepository(
    private val context: Context,
    private val api: ApiClient,
) {
    companion object {
        /** The rolling release asset (§2). Until it is published a 404 leaves the seed in place. */
        const val CATALOG_URL =
            "https://github.com/bhwilkoff/Ear-Drama/releases/download/catalog-latest/ear-drama.sqlite.zz"
        const val SEED_ASSET = "ear-drama-seed.sqlite"
        /** The full projection measured 133 MB; anything this small is a broken download. */
        private const val MIN_FULL_BYTES = 20_000_000L
        private const val STALE_AFTER_MS = 6L * 60 * 60 * 1000
    }

    private val files = CatalogFiles(context.filesDir, MIN_FULL_BYTES, CatalogDatabase::validate)

    @Volatile var db: CatalogDatabase? = null
        private set

    private val _dbVersion = MutableStateFlow(0)
    val dbVersion: StateFlow<Int> = _dbVersion

    private val _source = MutableStateFlow(CatalogSource.None)
    val source: StateFlow<CatalogSource> = _source

    private val _ready = MutableStateFlow(false)
    /** True once [initialize] has run, whether or not a catalog opened. */
    val ready: StateFlow<Boolean> = _ready

    private val refreshMutex = Mutex()

    /** Suspends until [initialize] has finished; null when no catalog could be opened. */
    suspend fun awaitDb(): CatalogDatabase? {
        ready.first { it }
        return db
    }

    private val seedStamp get() = "seed:${BuildConfig.VERSION_CODE}"

    suspend fun initialize() = withContext(Dispatchers.IO) {
        val opened = files.openAtLaunch(seedStamp, ::copySeed, CatalogDatabase::open)
        swap(opened, if (opened == null) CatalogSource.None else sourceOf(files.readSource()))
        _ready.value = true
    }

    private fun sourceOf(stamp: String?) = if (stamp == "full") CatalogSource.Full else CatalogSource.Seed

    /** Copies the bundled seed; false when this build carries none. */
    private fun copySeed(): Boolean = try {
        context.assets.open(SEED_ASSET).use { input ->
            val staging = File(context.filesDir, "catalog.sqlite.seed")
            staging.outputStream().use { input.copyTo(it, 64 * 1024) }
            check(staging.renameTo(files.live))
        }
        files.source.writeText(seedStamp)
        true
    } catch (_: Throwable) {
        false
    }

    fun isStale(): Boolean = files.isStale(System.currentTimeMillis(), STALE_AFTER_MS)

    /** The foreground path: a no-op inside the stale window, unless nothing is served. */
    suspend fun refreshIfStale() {
        if (db == null || isStale()) refresh()
    }

    /** A second caller while one runs returns at once; its result is what that caller wanted. */
    suspend fun refresh() {
        if (refreshMutex.isLocked) return
        refreshMutex.withLock { withContext(Dispatchers.IO) { refreshInner() } }
    }

    /**
     * "Last checked" is stamped only once a check has finished (a 304, a 404
     * before the first publish, or a swap), so a download a kill interrupts
     * is retried at the next launch instead of waiting out the stale window.
     */
    private suspend fun refreshInner() {
        val etag = files.etag.takeIf { it.exists() && files.readSource() == "full" }?.readText()?.trim()
        try {
            api.conditionalGet(CATALOG_URL, etag).use { response ->
                val body = response.body
                if (body == null) {
                    if (response.code == 304 || response.code == 404) files.markChecked(System.currentTimeMillis())
                    return
                }
                inflateRawDeflate(body, files.staging)
                files.writeStagingEtag(response.etag)
                val old = db
                if (!files.promoteStaging()) return
                swap(CatalogDatabase.open(files.live.path), CatalogSource.Full)
                old?.closeWhenIdle()
                files.markChecked(System.currentTimeMillis())
            }
        } catch (_: Throwable) {
            // Offline, a 404 before the first publish, or a torn download: keep what is served.
        } finally {
            files.discardStaging()
        }
    }

    private fun swap(newDb: CatalogDatabase?, source: CatalogSource) {
        db = newDb
        _source.value = source
        _dbVersion.value += 1
    }

    /** Raw DEFLATE (RFC 1951): `Inflater(nowrap = true)`, 64 KB chunks, socket to file. */
    private fun inflateRawDeflate(src: InputStream, dst: File) {
        val inflater = Inflater(true)
        try {
            dst.outputStream().use { out ->
                val inBuf = ByteArray(64 * 1024)
                val outBuf = ByteArray(64 * 1024)
                while (!inflater.finished()) {
                    if (inflater.needsInput()) {
                        val n = src.read(inBuf)
                        if (n == -1) break
                        inflater.setInput(inBuf, 0, n)
                    }
                    while (true) {
                        val written = inflater.inflate(outBuf)
                        if (written > 0) out.write(outBuf, 0, written) else break
                    }
                }
            }
            check(inflater.finished()) { "truncated DEFLATE stream" }
        } finally {
            inflater.end()
        }
    }
}
