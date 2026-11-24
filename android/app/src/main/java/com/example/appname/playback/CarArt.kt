package com.example.appname.playback

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import com.example.appname.app.AppNameApplication
import com.example.appname.data.ApiClient
import com.example.appname.data.labelItem
import java.io.File
import java.io.FileNotFoundException
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeoutOrNull

/**
 * The car's pictures as files: a served picture is fetched once (500 px wide, at most [MAX_BYTES]) and
 * kept; when it cannot be fetched (offline, refused, too large) the item's own label, drawn on the
 * device, takes its place, so a download shows its art with no signal. The directory is trimmed to
 * [MAX_FILES] files.
 */
class CarArtStore(
    private val dir: File,
    private val download: (String) -> ByteArray?,
) {
    companion object {
        const val MAX_BYTES = 1_500_000
        const val MAX_FILES = 200

        fun fetch(url: String): ByteArray? = try {
            val c = URL(url).openConnection() as HttpURLConnection
            c.connectTimeout = 4_000
            c.readTimeout = 4_000
            c.setRequestProperty("User-Agent", ApiClient.USER_AGENT)
            try {
                if (c.responseCode != 200 || c.contentLengthLong > MAX_BYTES) null
                else c.inputStream.use { it.readBounded(MAX_BYTES + 1) }.takeIf { it.isNotEmpty() && it.size <= MAX_BYTES }
            } finally {
                c.disconnect()
            }
        } catch (e: java.io.IOException) {
            null
        }

        private fun java.io.InputStream.readBounded(limit: Int): ByteArray {
            val out = java.io.ByteArrayOutputStream()
            val buffer = ByteArray(8_192)
            while (out.size() < limit) {
                val n = read(buffer, 0, minOf(buffer.size, limit - out.size()))
                if (n < 0) break
                out.write(buffer, 0, n)
            }
            return out.toByteArray()
        }

        private fun name(s: String): String =
            MessageDigest.getInstance("SHA-256").digest(s.toByteArray()).joinToString("") { "%02x".format(it) }.take(32)
    }

    /** The picture for [key]: the served one at [servedUrl] when it can be had, else the label [label] draws. */
    fun file(key: String, servedUrl: String?, label: () -> ByteArray): File {
        dir.mkdirs()
        if (servedUrl != null) {
            val served = File(dir, name(servedUrl) + ".img")
            if (served.exists()) return touch(served)
            val bytes = download(servedUrl)
            if (bytes != null) return write(served, bytes)
        }
        val drawn = File(dir, "l-" + name(key) + ".png")
        if (drawn.exists()) return touch(drawn)
        return write(drawn, label())
    }

    private fun touch(f: File) = f.also { it.setLastModified(System.currentTimeMillis()) }

    private fun write(target: File, bytes: ByteArray): File {
        val part = File(dir, target.name + ".part")
        part.writeBytes(bytes)
        part.renameTo(target)
        trim()
        return target
    }

    private fun trim() {
        val files = dir.listFiles { f -> !f.name.endsWith(".part") } ?: return
        files.sortedBy { it.lastModified() }.take((files.size - MAX_FILES).coerceAtLeast(0)).forEach { it.delete() }
    }
}

/**
 * `content://<package>.carart/e/<episode id>` and `/s/<series key>`: what Android Auto reads an
 * item's picture from (it takes no web address). Read-only; any other path is refused.
 */
class CarArtProvider : ContentProvider() {
    override fun onCreate() = true

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        val parts = uri.pathSegments
        if (mode != "r" || parts.size != 2 || parts[0] !in setOf("e", "s")) throw FileNotFoundException(uri.toString())
        val context = context ?: throw FileNotFoundException(uri.toString())
        val container = (context.applicationContext as AppNameApplication).container
        val kind = parts[0]
        val id = parts[1]
        val store = CarArtStore(File(context.cacheDir, "carart"), CarArtStore::fetch)
        val file = runBlocking {
            val db = withTimeoutOrNull(5_000) { container.catalog.awaitDb() } ?: return@runBlocking null
            if (kind == "e") {
                val row = db.episodes(listOf(id)).firstOrNull() ?: return@runBlocking null
                store.file("e:${row.id}", row.seriesWindowArt?.url(500)) { SessionArtwork.labelPng(context, row, 384) }
            } else {
                val series = db.series(id) ?: return@runBlocking null
                store.file("s:${series.key}", series.windowArt?.url(500)) { SessionArtwork.labelPng(context, series.labelItem(), 384) }
            }
        } ?: throw FileNotFoundException(uri.toString())
        return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
    }

    override fun query(uri: Uri, projection: Array<out String>?, selection: String?, selectionArgs: Array<out String>?, sortOrder: String?): Cursor? = null
    override fun getType(uri: Uri): String? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?) = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?) = 0
}
