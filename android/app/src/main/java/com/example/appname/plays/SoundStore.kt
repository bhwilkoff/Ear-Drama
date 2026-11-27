package com.example.appname.plays

import io.ktor.client.HttpClient
import io.ktor.client.request.get
import io.ktor.client.statement.bodyAsBytes
import io.ktor.http.isSuccess
import java.io.File
import java.io.IOException
import java.security.MessageDigest
import java.util.Base64
import java.util.UUID
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * The sounds a device holds for the Sound part (B32 §3.4, §5.2; ANDROID-DESIGN §4.17): the person's own sounds, which stay on
 * this device, and the pack cache. Mirrors js/sound-store.js. Tests: OwnSoundsTest.
 */

/** Own sounds (§3.4): under `filesDir/Sounds/mine/` beside `Plays/`, never synced, never uploaded, never published. */
class OwnSounds(private val dir: File) {
    @Serializable
    data class Sound(val id: String, val name: String, val createdMs: Long, val from: String, val seconds: Double, val bytes: Long)

    private val index = File(dir, "index.json")
    private val json = Json { ignoreUnknownKeys = true }

    fun list(): List<Sound> {
        if (!index.isFile) return emptyList()
        return runCatching { json.decodeFromString(ListSerializer(Sound.serializer()), index.readText()) }.getOrDefault(emptyList())
            .filter { file(it.id).isFile }
            .sortedByDescending { it.createdMs }
    }

    fun get(id: String): Sound? = list().firstOrNull { it.id == id }

    fun file(id: String) = File(dir, "$id.wav")

    fun has(id: String): Boolean = file(id).isFile && get(id) != null

    /** A sound recorded or decoded, kept as the take format (mono, 48 kHz WAV). A name is the person's; blank reads "Sound of {date}". */
    fun add(name: String, samples: FloatArray, from: String, nowMs: Long = System.currentTimeMillis()): Sound {
        require(samples.isNotEmpty()) { "nothing to keep" }
        dir.mkdirs()
        val id = UUID.randomUUID().toString().uppercase()
        val target = file(id)
        val sink = WavSink(target, TakeAudio.SAMPLE_RATE)
        sink.write(samples, samples.size)
        sink.finish()
        val label = name.trim().ifEmpty { "Sound of ${java.text.SimpleDateFormat("MMM d, h:mm a", java.util.Locale.US).format(java.util.Date(nowMs))}" }.take(60)
        val made = Sound(id, label, nowMs, from, samples.size.toDouble() / TakeAudio.SAMPLE_RATE, target.length())
        write(list() + made)
        return made
    }

    /**
     * A file the person brought (§3.2 item 6): audio up to 10 minutes and 50 MB, decoded and stored as the take format.
     * [source] is a copy the caller made (a content Uri read to a cache file); it is never kept.
     */
    fun bring(source: File, name: String): Sound {
        if (source.length() > SoundCore.OWN_FILE_MAX_BYTES) throw TooBig("That file is larger than 50 MB.")
        val samples = CueDecoder.decode(source) ?: throw IOException("That file has no audio this device can read.")
        if (samples.size > SoundCore.OWN_FILE_MAX_S * TakeAudio.SAMPLE_RATE) throw TooBig("That sound is longer than 10 minutes.")
        return add(name, samples, "file")
    }

    class TooBig(message: String) : IOException(message)

    fun remove(id: String) {
        file(id).delete()
        write(list().filter { it.id != id })
    }

    fun load(id: String): FloatArray? = if (has(id)) TakeAudio.read(file(id)).first else null

    private fun write(all: List<Sound>) {
        dir.mkdirs()
        val partial = File(dir, ".index.json.partial")
        partial.writeText(json.encodeToString(ListSerializer(Sound.serializer()), all))
        if (!partial.renameTo(index)) {
            index.delete()
            check(partial.renameTo(index)) { "could not save the sounds" }
        }
    }

    /** Export my data (docs/EXPORT.md `ownSounds[]`): each sound whole, so the export is a copy of the person's own work. */
    fun exportRows(): List<JsonObject> = list().map { s ->
        JsonObject(
            mapOf(
                "id" to JsonPrimitive(s.id), "name" to JsonPrimitive(s.name),
                "created" to JsonPrimitive(java.time.Instant.ofEpochMilli(s.createdMs).toString()),
                "from" to JsonPrimitive(s.from), "seconds" to JsonPrimitive(s.seconds), "bytes" to JsonPrimitive(s.bytes),
                "wav" to JsonPrimitive(Base64.getEncoder().encodeToString(file(s.id).readBytes())),
            ),
        )
    }
}

/** What the pack's hosting serves: bytes at a URL, null on a 404. Throws on any other failure. */
fun interface SoundFetch {
    suspend fun get(url: String): ByteArray?
}

class KtorSoundFetch(private val client: HttpClient) : SoundFetch {
    override suspend fun get(url: String): ByteArray? = withTimeout(60_000) {
        val response = client.get(url)
        when {
            response.status.value == 404 -> null
            response.status.isSuccess() -> response.bodyAsBytes()
            else -> throw IOException("HTTP ${response.status.value}")
        }
    }
}

/**
 * The cue pack (B32 §5.2): a source that may be absent. [manifestUrl] null (the owner has not ruled on its hosting) means the
 * library shows nothing; configured but unreachable with nothing cached is [State.Unreachable]. Files are kept by category under
 * `noBackupFilesDir/sounds/<pack>/`, each checked against its sha256 before use.
 */
class SoundPack(private val root: File, private val fetch: SoundFetch?, private val manifestUrl: String? = MANIFEST_URL) {
    sealed interface State {
        data object Absent : State
        data object Unreachable : State
        data class Ready(val pack: SoundCore.Pack) : State
    }

    private val json = Json { ignoreUnknownKeys = true }

    suspend fun manifest(): State {
        val url = manifestUrl ?: return State.Absent
        val cache = File(root, "sounds.json")
        val text = try {
            fetch?.get(url)?.toString(Charsets.UTF_8)?.also { root.mkdirs(); cache.writeText(it) }
        } catch (e: IOException) {
            null
        } ?: cache.takeIf { it.isFile }?.readText()
        ?: return State.Unreachable
        return try {
            State.Ready(SoundCore.readManifest(json.parseToJsonElement(text)))
        } catch (e: Exception) {
            State.Unreachable
        }
    }

    private fun folder(pack: SoundCore.Pack) = File(root, pack.pack)

    fun file(pack: SoundCore.Pack, cue: SoundCore.PackCue) = File(folder(pack), cue.file)

    private fun sha(file: File): String =
        MessageDigest.getInstance("SHA-256").digest(file.readBytes()).joinToString("") { "%02x".format(it) }

    /** Whether the cue's file is here and is the file the manifest names. */
    fun has(pack: SoundCore.Pack, cue: SoundCore.PackCue): Boolean {
        val f = file(pack, cue)
        return f.isFile && sha(f) == cue.sha256
    }

    fun categoryHere(pack: SoundCore.Pack, category: String): Boolean = pack.cues.filter { it.category == category }.all { has(pack, it) }

    /**
     * Downloads every cue of a category not here, each checked against its sha256; a file that fails is deleted and fetched
     * once more, then the error (§7).
     */
    suspend fun download(pack: SoundCore.Pack, category: String) {
        val base = manifestUrl?.substringBeforeLast('/', "") ?: throw IOException("The sounds could not be reached.")
        val get = fetch ?: throw IOException("The sounds could not be reached.")
        for (cue in pack.cues.filter { it.category == category }) {
            if (has(pack, cue)) continue
            var ok = false
            repeat(2) {
                if (ok) return@repeat
                val bytes = get.get("$base/${cue.file}") ?: throw IOException("The sounds could not be reached.")
                val target = file(pack, cue)
                target.parentFile?.mkdirs()
                target.writeBytes(bytes)
                if (sha(target) == cue.sha256) ok = true else target.delete()
            }
            if (!ok) throw IOException("A sound did not arrive whole.")
        }
    }

    companion object {
        /** Null until the owner rules on the pack's hosting (BACKLOG-LOOP round 3); the web's `CONFIG.sounds.manifest`. */
        val MANIFEST_URL: String? = null
    }
}

/**
 * What a render needs from this device's sounds, resolved before it starts: every cue the production names, decoded once to
 * take-format samples, or named as not here. [info] and [samples] are the seams `MixTimeline.build` and `MixRenderer.render` take.
 */
class SoundResolver(private val own: OwnSounds, private val pack: SoundCore.Pack?, private val packFile: (SoundCore.PackCue) -> File?) {
    private class Held(val samples: FloatArray, val kind: String, val loudness: Double?, val peak: Float)

    private val held = HashMap<String, Held?>()
    private val titles = HashMap<String, String>()

    private fun key(src: SoundSource) = when {
        src.own != null -> "o:${src.own}"
        src.pack != null -> "p:${src.pack}/${src.cue}"
        else -> null
    }

    private fun hold(src: SoundSource): Held? {
        val k = key(src) ?: return null
        return held.getOrPut(k) {
            if (src.own != null) {
                val s = own.load(src.own) ?: return@getOrPut null
                own.get(src.own)?.let { titles[k] = it.name }
                Held(s, "effect", BS1770.integratedLoudness(s, TakeAudio.SAMPLE_RATE.toDouble()), BS1770.samplePeak(s))
            } else {
                val cue = pack?.takeIf { it.pack == src.pack }?.cues?.firstOrNull { it.id == src.cue } ?: return@getOrPut null
                titles[k] = cue.title
                val file = packFile(cue) ?: return@getOrPut null
                val s = runCatching { CueDecoder.decode(file) }.getOrNull() ?: return@getOrPut null
                Held(s, cue.kind, cue.lufs ?: BS1770.integratedLoudness(s, TakeAudio.SAMPLE_RATE.toDouble()), (cue.peak?.toFloat()) ?: BS1770.samplePeak(s))
            }
        }
    }

    fun info(src: SoundSource, @Suppress("UNUSED_PARAMETER") cue: SoundCue): MixTimeline.SoundInfo? =
        hold(src)?.let { MixTimeline.SoundInfo(it.samples.size, it.kind, it.loudness, it.peak) }

    fun samples(x: MixTimeline.SoundPlacement): FloatArray? = hold(x.src)?.samples

    /** The name a person gave a sound, or a pack title, for a sound this device lacks (the mix names a cue by its id otherwise). */
    fun nameOf(production: Production, soundID: String): String {
        val x = production.sound?.slots.orEmpty().flatMap { it.sounds }.firstOrNull { it.id == soundID } ?: return soundID
        val k = key(x.src) ?: return soundID
        hold(x.src)
        return titles[k] ?: x.src.cue.orEmpty()
    }
}
