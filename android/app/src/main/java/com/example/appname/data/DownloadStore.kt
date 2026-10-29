package com.example.appname.data

import java.io.File
import java.security.MessageDigest
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/** One downloaded (or downloading) episode, persisted in the downloads directory's index. */
@Serializable
data class DownloadRecord(
    val episodeId: String,
    val title: String,
    val seriesName: String,
    /** The recording the file came from (the catalog's rank 0 when it began). */
    val remoteUrl: String,
    val fileName: String,
    val state: State,
    val receivedBytes: Long = 0,
    val expectedBytes: Long = 0,
    val addedAtMs: Long,
    /**
     * Names the transfer. A late callback from a transfer cancelled before this
     * record was re-created carries a different token and is ignored.
     */
    val token: String,
) {
    @Serializable
    enum class State { Queued, Downloading, Downloaded, Failed }

    val isActive: Boolean get() = state == State.Queued || state == State.Downloading

    /** Episode ids carry the series key before their `|`, so a series' downloads are found from the index as it is. */
    val seriesKey: String get() = seriesKeyOf(episodeId)

    companion object {
        fun seriesKeyOf(episodeId: String): String = episodeId.substringBefore('|')
    }
    val fraction: Float?
        get() = if (expectedBytes > 0) (receivedBytes.toFloat() / expectedBytes).coerceAtMost(1f) else null
}

/** One episode's default recording, ready to download. */
data class DownloadRequest(
    val episodeId: String,
    val title: String,
    val seriesName: String,
    val url: String,
    /** Bitrate times length, when the catalog knows both. */
    val estimatedBytes: Long? = null,
) {
    companion object {
        fun from(detail: EpisodeDetail, title: String): DownloadRequest? {
            val recording = detail.recordings.firstOrNull() ?: return null
            val seconds = recording.lengthSeconds ?: detail.episode.lengthSeconds
            val kbps = recording.kbps
            val estimate = if (kbps != null && kbps > 0 && seconds != null && seconds > 0) {
                Math.round(kbps * 125.0 * seconds)
            } else {
                null
            }
            return DownloadRequest(detail.episode.id, title, detail.episode.seriesName, recording.url, estimate)
        }
    }
}

/**
 * What a bulk download would start: everything asked for that is not already
 * downloaded or on its way (a failed one starts over), and about how much space
 * it takes (Decision 071).
 */
class DownloadPlan(candidates: List<DownloadRequest>, records: Map<String, DownloadRecord>) {
    val requests: List<DownloadRequest> = candidates.distinctBy { it.episodeId }.filter { request ->
        val r = records[request.episodeId]
        r == null || r.state == DownloadRecord.State.Failed
    }
    /** The sum of the estimates the catalog could make; null when it could make none. */
    val estimatedBytes: Long? = requests.mapNotNull { it.estimatedBytes }.takeIf { it.isNotEmpty() }?.sum()
    val count: Int get() = requests.size
}

/** What the player opens: the finished file when there is one, else the network copy. */
data class PlaybackSource(val location: String, val isLocal: Boolean)

/** What moves the bytes. Production is WorkManager; the tests drive the store's callbacks themselves. */
interface DownloadTransport {
    fun begin(token: String, url: String)
    fun cancel(token: String)
    fun cancelAll()
    /** The transfers the system is still carrying, by token. */
    suspend fun liveTokens(): Set<String>
}

/**
 * Downloads an episode's default recording so it plays with no network: the
 * Android port of the Apple apps' DownloadStore, same states and same verbs.
 * The files live in filesDir/downloads, app-private (no media scanner, no
 * FileProvider, no share intent: the app must never export an MP3, research 04
 * §11) and excluded from backup and device transfer by the backup rules.
 *
 * Every create path has its inverse: [download] / [cancel], a finished file /
 * [remove], everything / [removeAll], and [reconnect] sweeps what a dead
 * process left behind. Calls arrive from the UI and from the worker's thread,
 * so every mutation holds one lock.
 */
open class DownloadStore(
    val directory: File,
    private val transport: DownloadTransport,
    private val clock: () -> Long = System::currentTimeMillis,
) {
    companion object {
        const val INDEX_NAME = "index.json"
        const val PARTIAL_EXTENSION = "partial"
        private const val PUBLISH_EVERY_MS = 250L
        private val json = Json { ignoreUnknownKeys = true }

        /**
         * Episode ids carry `|` and come from an open upload system: never a path
         * component as they are. Same digest as the Apple store.
         */
        fun fileStem(episodeId: String): String =
            MessageDigest.getInstance("SHA-256").digest(episodeId.toByteArray())
                .take(16).joinToString("") { "%02x".format(it) }
    }

    private val lock = Any()
    private val lastPublish = mutableMapOf<String, Long>()
    private val _records = MutableStateFlow<Map<String, DownloadRecord>>(emptyMap())
    val records: StateFlow<Map<String, DownloadRecord>> = _records

    init {
        directory.mkdirs()
        _records.value = loadIndex()
    }

    // --- Reads

    fun record(episodeId: String): DownloadRecord? = _records.value[episodeId]

    /** Newest first: what the Library lists. */
    val sortedRecords: List<DownloadRecord>
        get() = _records.value.values.sortedByDescending { it.addedAtMs }

    /** The Downloads place: by series name, each series in the order it was asked for. */
    val seriesGroups: List<Pair<String, List<DownloadRecord>>>
        get() = _records.value.values.groupBy { it.seriesKey }.values
            .map { rows -> rows.sortedWith(compareBy({ it.addedAtMs }, { it.episodeId })) }
            .sortedBy { it.first().seriesName.lowercase() }
            .map { it.first().seriesKey to it }

    /** True when any of this series is downloaded or on its way. */
    fun hasDownloads(seriesKey: String): Boolean = _records.value.values.any { it.seriesKey == seriesKey }

    /** The episodes among [ids] that still need a download (none, or a failed one). */
    fun missing(ids: List<String>): List<String> {
        val records = _records.value
        return ids.filter { records[it]?.state?.let { s -> s == DownloadRecord.State.Failed } ?: true }
    }

    /** Bytes the finished downloads hold on this device. */
    val totalBytes: Long
        get() = _records.value.values.filter { it.state == DownloadRecord.State.Downloaded }.sumOf { it.receivedBytes }

    /** The local file to play instead of [recording], when this episode's download of it is finished and on disk. */
    fun localFile(episodeId: String, recording: String): File? {
        val r = _records.value[episodeId] ?: return null
        if (r.state != DownloadRecord.State.Downloaded || r.remoteUrl != recording) return null
        return file(r.fileName).takeIf { it.isFile }
    }

    fun playbackSource(episodeId: String, url: String): PlaybackSource =
        localFile(episodeId, url)?.let { PlaybackSource(it.path, true) } ?: PlaybackSource(url, false)

    /** The file a running transfer writes; the worker deletes it however the transfer ends. */
    fun transferFile(token: String): File = file("$token.$PARTIAL_EXTENSION")

    fun isActive(token: String): Boolean = byToken(token)?.isActive == true

    // --- Commands

    /** Downloads the episode's default recording. A queued, running, or finished one is left alone; a failed one starts over. */
    fun download(detail: EpisodeDetail, title: String) {
        val recording = detail.recordings.firstOrNull() ?: return
        download(detail.episode.id, title, detail.episode.seriesName, recording.url)
    }

    fun download(
        episodeId: String,
        title: String,
        seriesName: String,
        url: String,
        addedAtMs: Long = clock(),
    ) = synchronized(lock) {
        val existing = _records.value[episodeId]
        if (existing != null && existing.state != DownloadRecord.State.Failed) return@synchronized
        existing?.let { deleteFiles(it) }
        val ext = url.substringAfterLast('/').substringAfterLast('.', "").lowercase()
            .takeIf { it.isNotEmpty() && it.length <= 5 && it.all(Char::isLetterOrDigit) } ?: "mp3"
        val record = DownloadRecord(
            episodeId = episodeId, title = title, seriesName = seriesName, remoteUrl = url,
            fileName = "${fileStem(episodeId)}.$ext", state = DownloadRecord.State.Queued,
            addedAtMs = addedAtMs, token = UUID.randomUUID().toString(),
        )
        put(record)
        saveIndex()
        transport.begin(record.token, url)
    }

    /** Starts every request of a plan, in order; each is added a millisecond after the last so the place keeps that order. */
    fun download(plan: DownloadPlan) {
        val start = clock()
        plan.requests.forEachIndexed { i, r -> download(r.episodeId, r.title, r.seriesName, r.url, addedAtMs = start + i) }
    }

    /** Every download of one series, gone: transfers, files, records. */
    fun removeSeries(seriesKey: String) {
        _records.value.values.filter { it.seriesKey == seriesKey }.map { it.episodeId }.forEach(::remove)
    }

    /** Stops a queued or running download and forgets it. */
    fun cancel(episodeId: String) {
        if (record(episodeId)?.isActive == true) remove(episodeId)
    }

    /** Removes a download in any state: the transfer, the file, the record. */
    fun remove(episodeId: String) = synchronized(lock) {
        val r = _records.value[episodeId] ?: return@synchronized
        _records.value = _records.value - episodeId
        if (r.isActive) transport.cancel(r.token)
        deleteFiles(r)
        lastPublish.remove(r.token)
        saveIndex()
    }

    /**
     * Contract §3.5: a download kept under an id the catalog moved is re-keyed to the id it
     * now is; its file keeps its name. When the new id already has its own download, the
     * moved one is a second copy and goes. A tombstoned id's download stays: the file plays.
     */
    fun forward(forwarding: IdForwarding) = synchronized(lock) {
        var changed = false
        for (old in _records.value.keys.sorted()) {
            val new = forwarding.resolve(old)
            val r = _records.value[old] ?: continue
            if (new == old) continue
            if (_records.value.containsKey(new)) {
                remove(old)
            } else {
                _records.value = _records.value - old + (new to r.copy(episodeId = new))
                changed = true
            }
        }
        if (changed) saveIndex()
    }

    /** Every download, gone. The files go first and unconditionally: they are what the listener asked to reclaim. */
    fun removeAll() = synchronized(lock) {
        transport.cancelAll()
        directory.listFiles()?.forEach { it.deleteRecursively() }
        _records.value = emptyMap()
        lastPublish.clear()
        saveIndex()
    }

    // --- Relaunch

    /**
     * Rebuilds the truth after a process death: a record whose transfer the
     * system no longer carries failed (the listener can try again), a finished
     * record whose file is gone is dropped, and a file no record claims is
     * deleted, because it is the one kind of leak nobody can find and clear.
     * A record created while the system was being asked is left alone.
     */
    suspend fun reconnect(): Unit = withContext(Dispatchers.IO) {
        val asked = synchronized(lock) { _records.value.values.map { it.token }.toSet() }
        val live = transport.liveTokens()
        synchronized(lock) {
            val claimed = mutableSetOf(INDEX_NAME)
            val next = _records.value.toMutableMap()
            for ((id, r) in _records.value) {
                when (r.state) {
                    DownloadRecord.State.Downloaded ->
                        if (file(r.fileName).isFile) claimed += r.fileName else next.remove(id)
                    DownloadRecord.State.Queued, DownloadRecord.State.Downloading ->
                        if (r.token in asked && r.token !in live) {
                            next[id] = r.copy(state = DownloadRecord.State.Failed)
                        } else {
                            claimed += transferFile(r.token).name
                        }
                    DownloadRecord.State.Failed -> Unit
                }
            }
            _records.value = next
            val tokens = next.values.filter { it.isActive }.map { it.token }.toSet()
            for (token in live) if (token !in tokens) transport.cancel(token)
            directory.listFiles()?.forEach { if (it.name !in claimed) it.deleteRecursively() }
            saveIndex()
        }
    }

    // --- Transport callbacks

    fun transferProgressed(token: String, received: Long, expected: Long) = synchronized(lock) {
        val r = byToken(token)?.takeIf { it.isActive } ?: return@synchronized
        val now = clock()
        // Callbacks arrive per chunk; the screens redraw at most 4 times a second.
        val last = lastPublish[token]
        if (r.state == DownloadRecord.State.Downloading && last != null && now - last < PUBLISH_EVERY_MS) return@synchronized
        lastPublish[token] = now
        val firstBytes = r.state == DownloadRecord.State.Queued
        put(
            r.copy(
                state = DownloadRecord.State.Downloading,
                receivedBytes = received,
                expectedBytes = if (expected > 0) expected else r.expectedBytes,
            ),
        )
        if (firstBytes) saveIndex()
    }

    /**
     * The transfer's file lands as a partial and takes its real name only once
     * it is known good; a failure deletes the partial, so a half file can never
     * reach the player or the disk total.
     */
    fun transferFinished(token: String, location: File, httpStatus: Int?) = synchronized(lock) {
        val r = byToken(token)?.takeIf { it.isActive } ?: return@synchronized
        lastPublish.remove(token)
        val final = file(r.fileName)
        val partial = File(directory, "${r.fileName}.$PARTIAL_EXTENSION")
        partial.delete()
        val saved = try {
            if (!location.renameTo(partial)) error("could not move the transfer")
            val size = partial.length()
            if ((httpStatus ?: 200) !in 200..299 || size <= 0) error("status $httpStatus, $size bytes")
            final.delete()
            if (!partial.renameTo(final)) error("could not name the file")
            r.copy(state = DownloadRecord.State.Downloaded, receivedBytes = size, expectedBytes = size)
        } catch (e: IllegalStateException) {
            println("[DownloadStore] ${r.episodeId} did not save: ${e.message}")
            deleteFiles(r)
            r.copy(state = DownloadRecord.State.Failed)
        }
        put(saved)
        saveIndex()
    }

    /** A transfer ended with an error. A deliberate cancel already removed its record, so this only marks a live download failed. */
    fun transferFailed(token: String, message: String?) = synchronized(lock) {
        val r = byToken(token)?.takeIf { it.isActive } ?: return@synchronized
        println("[DownloadStore] ${r.episodeId} failed: ${message ?: "unknown"}")
        lastPublish.remove(token)
        deleteFiles(r)
        put(r.copy(state = DownloadRecord.State.Failed))
        saveIndex()
    }

    // --- Files

    fun file(name: String): File = File(directory, name)

    /** Deletes everything a record can leave on disk: the file, its partial, and the transfer's own file. */
    protected open fun deleteFiles(record: DownloadRecord) {
        file(record.fileName).delete()
        file("${record.fileName}.$PARTIAL_EXTENSION").delete()
        transferFile(record.token).delete()
    }

    private fun byToken(token: String): DownloadRecord? = _records.value.values.firstOrNull { it.token == token }

    private fun put(record: DownloadRecord) {
        _records.value = _records.value + (record.episodeId to record)
    }

    private fun saveIndex() {
        try {
            val tmp = file("$INDEX_NAME.tmp")
            tmp.writeText(json.encodeToString(_records.value))
            if (!tmp.renameTo(file(INDEX_NAME))) tmp.delete()
        } catch (e: Exception) {
            println("[DownloadStore] index not saved: ${e.message}")
        }
    }

    private fun loadIndex(): Map<String, DownloadRecord> = try {
        file(INDEX_NAME).takeIf { it.isFile }?.readText()?.let { json.decodeFromString<Map<String, DownloadRecord>>(it) }
            ?: emptyMap()
    } catch (_: Exception) {
        emptyMap()
    }
}
