package com.example.appname.kokoro

import io.ktor.client.HttpClient
import io.ktor.client.request.header
import io.ktor.client.request.prepareGet
import io.ktor.client.statement.bodyAsChannel
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.utils.io.readAvailable
import java.io.File
import java.io.IOException
import java.io.RandomAccessFile
import java.security.MessageDigest
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/**
 * One GET from [from] bytes on (an HTTP Range when above zero). [onBytes] receives the status (206 when the server
 * honored the range, 200 when it sent the whole file) with the body as it arrives. Returns the status.
 */
fun interface RangeFetch {
    suspend fun get(url: String, from: Long, onBytes: suspend (status: Int, bytes: ByteArray, count: Int) -> Unit): Int
}

/** The one Ktor client's read of a Release asset, resumable with `Range: bytes=N-`. Public files, no session. */
class KtorRangeFetch(private val client: HttpClient) : RangeFetch {
    override suspend fun get(url: String, from: Long, onBytes: suspend (Int, ByteArray, Int) -> Unit): Int =
        client.prepareGet(url) { if (from > 0) header(HttpHeaders.Range, "bytes=$from-") }.execute { response ->
            val status = response.status.value
            if (status != HttpStatusCode.OK.value && status != HttpStatusCode.PartialContent.value) return@execute status
            val channel = response.bodyAsChannel()
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val n = channel.readAvailable(buffer, 0, buffer.size)
                if (n < 0) break
                if (n > 0) onBytes(status, buffer, n)
            }
            status
        }
}

/**
 * The downloaded Kokoro model on this device (Decision 078): the native manifest's three files from the GitHub Release
 * `kokoro-model`, under filesDir, fetched only when the person asks ("Download voices"), resumed with HTTP Range, each
 * checked against the manifest's SHA-256 before it counts, and removed by Delete. The manifest is written last: its
 * presence beside the files is what "downloaded" means. Model bytes only; no audio is ever written here.
 */
class KokoroModelStore(
    val root: File,
    private val fetch: RangeFetch,
    private val base: String = RELEASE,
    private val manifestName: String = MANIFEST,
) {
    sealed interface State {
        data object Absent : State
        data class Downloading(val done: Long, val total: Long) : State
        data object Ready : State
        data class Failed(val message: String) : State
    }

    /** Where each file the engine reads lives. */
    class Paths(val model: File, val voices: File, val vocab: File, val manifest: KokoroManifest)

    private val _state = MutableStateFlow<State>(State.Absent)
    val state: StateFlow<State> = _state
    private val lock = Mutex()

    private val kept get() = File(root, "manifest.json")

    init {
        _state.value = if (paths() != null) State.Ready else State.Absent
    }

    /** The downloaded files, when every one the kept manifest names is here at its size. */
    fun paths(): Paths? {
        val m = runCatching { KokoroManifest.accept(kept.readText()) }.getOrNull() ?: return null
        if (m.files.any { File(root, it.path).length() != it.bytes }) return null
        return Paths(File(root, m.file("model")!!.path), File(root, m.file("voices")!!.path), File(root, m.file("vocab")!!.path), m)
    }

    /** The bytes a download moves, as the picker says it before the manifest is read. */
    fun downloadBytes(): Long = paths()?.manifest?.totalBytes ?: KNOWN_BYTES

    /** On disk now, finished or not (Delete frees this). */
    fun bytesOnDisk(): Long = root.listFiles().orEmpty().sumOf { it.length() }

    /**
     * Downloads the manifest, then each file it names that is not already here and whole, resuming a partial file
     * from its length. A file whose SHA-256 differs is deleted and the download fails; nothing half-checked is used.
     */
    suspend fun download() = lock.withLock {
        if (paths() != null) { _state.value = State.Ready; return@withLock }
        try {
            withContext(Dispatchers.IO) { run() }
            _state.value = State.Ready
        } catch (e: CancellationException) {
            _state.value = if (paths() != null) State.Ready else State.Absent
            throw e
        } catch (e: Exception) {
            _state.value = State.Failed(e.message ?: "download failed")
        }
    }

    private suspend fun run() {
        root.mkdirs()
        val text = ByteArrayOutput().also { out -> status(fetch.get(base + manifestName, 0) { _, b, n -> out.write(b, n) }, manifestName) }.text()
        val m = KokoroManifest.accept(text)
        val total = m.totalBytes
        var before = 0L
        for (f in m.files) {
            val done = File(root, f.path)
            if (done.length() == f.bytes && sha256(done) == f.sha256) { before += f.bytes; continue }
            done.delete()
            val part = File(root, f.path + ".part")
            if (part.length() > f.bytes) part.delete()
            var at = part.length()
            if (at < f.bytes) {
                RandomAccessFile(part, "rw").use { out ->
                    var first = true
                    val code = fetch.get(base + f.path, at) { code, b, n ->
                        currentCoroutineContext().ensureActive()
                        if (first) {
                            first = false
                            // The server ignored the range and sends the whole file from byte 0: start the file again.
                            if (code == 200 && at > 0) { at = 0; out.setLength(0) }
                        }
                        out.seek(at)
                        out.write(b, 0, n)
                        at += n
                        _state.value = State.Downloading(before + at, total)
                    }
                    status(code, f.path)
                    out.setLength(at)
                }
            }
            // A body that ended early is kept for the next try to resume from.
            if (part.length() != f.bytes) throw IOException("${f.path}: ${part.length()} of ${f.bytes} bytes")
            if (sha256(part) != f.sha256) { part.delete(); throw IOException("${f.path}: SHA-256 differs from the manifest") }
            if (!part.renameTo(done)) throw IOException("${f.path}: could not be kept")
            before += f.bytes
            _state.value = State.Downloading(before, total)
        }
        val tmp = File(root, "manifest.json.part")
        tmp.writeText(text)
        if (!tmp.renameTo(kept)) throw IOException("manifest could not be kept")
    }

    private fun status(code: Int, what: String) {
        if (code != 200 && code != 206) throw IOException("HTTP $code for $what")
    }

    /** Removes every downloaded file; the picker's Kokoro voices go, and parts cast to them fall back visibly. */
    suspend fun delete() = lock.withLock {
        withContext(Dispatchers.IO) { root.deleteRecursively() }
        _state.value = State.Absent
    }

    /** A failed download's message is cleared when the person tries again. */
    fun clearFailure() {
        if (_state.value is State.Failed) _state.value = State.Absent
    }

    private class ByteArrayOutput {
        private val out = java.io.ByteArrayOutputStream()
        fun write(b: ByteArray, n: Int) {
            if (out.size() + n > MAX_MANIFEST) throw IOException("manifest too large")
            out.write(b, 0, n)
        }
        fun text() = out.toString(Charsets.UTF_8.name())
    }

    companion object {
        const val RELEASE = "https://github.com/bhwilkoff/Ear-Drama/releases/download/kokoro-model/"
        const val MANIFEST = "kokoro-v1-manifest.json"

        /** kokoro-v1-manifest.json's three files: 86,033,585 + 14,622,720 + 3,497 bytes. */
        const val KNOWN_BYTES = 100_659_802L
        private const val MAX_MANIFEST = 1 shl 20

        fun sha256(file: File): String {
            val md = MessageDigest.getInstance("SHA-256")
            file.inputStream().use { input ->
                val buf = ByteArray(1 shl 16)
                while (true) {
                    val n = input.read(buf)
                    if (n < 0) break
                    md.update(buf, 0, n)
                }
            }
            return md.digest().joinToString("") { "%02x".format(it) }
        }

        /** "101 MB": decimal megabytes, as the stores and the Files app count. */
        fun megabytes(bytes: Long): String = "${Math.round(bytes / 1_000_000.0)} MB"
    }
}
