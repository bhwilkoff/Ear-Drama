package com.example.appname.plays

import java.io.BufferedOutputStream
import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.UUID
import kotlin.math.roundToInt
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.serialization.json.Json

/**
 * What the microphone captured: the only thing a take or room-tone file is
 * ever written from. A stand-in is a different type ([StandInAudio]) with no
 * path to a file (PLAYS-DESIGN §5 rule 1).
 */
class MicrophoneCapture(val samples: FloatArray, val sampleRate: Double) {
    fun slice(range: IntRange): MicrophoneCapture {
        val lower = range.first.coerceIn(0, samples.size)
        val upper = (range.last + 1).coerceIn(lower, samples.size)
        return MicrophoneCapture(samples.copyOfRange(lower, upper), sampleRate)
    }
}

/**
 * Marks the PCM a device voice produced. Every writer calls [refuse] on what
 * it is handed, so a synthetic buffer can never reach a take, a mix, an export
 * or an upload (PLAYS-DESIGN section 5 rule 1, section 8 rule 3). Identity, not content.
 */
object SyntheticPCM {
    private val marked: MutableSet<FloatArray> =
        java.util.Collections.newSetFromMap(java.util.Collections.synchronizedMap(java.util.WeakHashMap()))

    fun mark(samples: FloatArray) { marked += samples }

    fun refuse(samples: FloatArray) {
        check(samples !in marked) { "a device voice is never stored" }
    }
}

/** Where a rendered mix goes, a chunk at a time. The app's encodes AAC into `.m4a` (MixEncoder.kt). */
interface MixSink {
    fun write(samples: FloatArray, count: Int)
    fun finish()
    fun abandon()
}

/**
 * Takes on disk: mono, 48 kHz, 24-bit PCM WAV (§4.2, §6). WAV, not FLAC, on
 * Android: MediaMuxer has no FLAC container, so a FLAC take would mean writing
 * the stream header by hand around MediaCodec's frames, on a path no JVM test
 * can run or read back. WAV is lossless, exact at 24 bits, and readable
 * everywhere; it costs about twice FLAC's space.
 */
object TakeAudio {
    const val SAMPLE_RATE = 48_000
    const val FILE_EXTENSION = "wav"

    fun write(capture: MicrophoneCapture, file: File) {
        SyntheticPCM.refuse(capture.samples)
        val sink = WavSink(file, capture.sampleRate.roundToInt())
        sink.write(capture.samples, capture.samples.size)
        sink.finish()
    }

    /** A WAV file (16- or 24-bit PCM, or 32-bit float, mono) as float samples at its own rate. */
    fun read(file: File): Pair<FloatArray, Double> {
        val bytes = file.readBytes()
        val buf = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        require(bytes.size >= 12 && String(bytes, 0, 4) == "RIFF" && String(bytes, 8, 4) == "WAVE") { "not a WAV file" }
        var pos = 12
        var format = 1
        var channels = 1
        var rate = SAMPLE_RATE
        var bits = 24
        while (pos + 8 <= bytes.size) {
            val id = String(bytes, pos, 4)
            val size = buf.getInt(pos + 4)
            val body = pos + 8
            if (id == "fmt ") {
                format = buf.getShort(body).toInt()
                channels = buf.getShort(body + 2).toInt()
                rate = buf.getInt(body + 4)
                bits = buf.getShort(body + 14).toInt()
            } else if (id == "data") {
                val length = minOf(size, bytes.size - body)
                val width = bits / 8
                val frames = length / (width * channels)
                val out = FloatArray(frames) { i ->
                    val at = body + i * width * channels
                    when {
                        format == 3 -> buf.getFloat(at)
                        bits == 16 -> buf.getShort(at) / 32_768f
                        else -> {
                            val v = (bytes[at].toInt() and 0xFF) or ((bytes[at + 1].toInt() and 0xFF) shl 8) or
                                (bytes[at + 2].toInt() shl 16)
                            v / 8_388_608f
                        }
                    }
                }
                return out to rate.toDouble()
            }
            pos = body + size + (size and 1)
        }
        return FloatArray(0) to rate.toDouble()
    }
}

/** A 24-bit mono WAV written a chunk at a time; the header's sizes are filled in on [finish]. */
class WavSink(private val file: File, private val sampleRate: Int) : MixSink {
    private val out = BufferedOutputStream(FileOutputStream(file))
    private var dataBytes = 0L

    init {
        out.write(ByteArray(HEADER))
    }

    override fun write(samples: FloatArray, count: Int) {
        SyntheticPCM.refuse(samples)
        val bytes = ByteArray(count * 3)
        for (i in 0 until count) {
            val v = (samples[i].coerceIn(-1f, 1f) * 8_388_607f).roundToInt()
            bytes[3 * i] = v.toByte()
            bytes[3 * i + 1] = (v shr 8).toByte()
            bytes[3 * i + 2] = (v shr 16).toByte()
        }
        out.write(bytes)
        dataBytes += bytes.size
    }

    override fun finish() {
        out.close()
        val header = ByteBuffer.allocate(HEADER).order(ByteOrder.LITTLE_ENDIAN)
        header.put("RIFF".toByteArray()).putInt((36 + dataBytes).toInt()).put("WAVE".toByteArray())
        header.put("fmt ".toByteArray()).putInt(16).putShort(1).putShort(1).putInt(sampleRate)
            .putInt(sampleRate * 3).putShort(3).putShort(24)
        header.put("data".toByteArray()).putInt(dataBytes.toInt())
        RandomAccessFile(file, "rw").use { it.seek(0); it.write(header.array()) }
    }

    override fun abandon() {
        runCatching { out.close() }
        file.delete()
    }

    private companion object {
        const val HEADER = 44
    }
}

/**
 * Productions on the device (§6): `filesDir/Plays/<production>/` holds
 * `script.json` (the script as cast), `production.json`, `takes/`,
 * `roomtone/`, and `mix.m4a`, the names Apple uses. Nothing is uploaded and
 * no account is needed (§8 rule 4).
 */
class ProductionStore(val root: File) {
    private val _productions = MutableStateFlow<List<Production>>(emptyList())
    val productions: StateFlow<List<Production>> = _productions

    init {
        load()
    }

    fun folder(id: String) = File(root, id)
    fun takesFolder(id: String) = File(folder(id), "takes")
    fun roomToneFolder(id: String) = File(folder(id), "roomtone")
    fun mixFile(id: String) = File(folder(id), "mix.m4a")
    fun takeFile(production: Production, take: Take) = File(takesFolder(production.id), take.file)

    fun production(id: String): Production? = _productions.value.firstOrNull { it.id == id }

    fun load() {
        _productions.value = (root.listFiles() ?: emptyArray()).mapNotNull { dir ->
            val record = File(dir, "production.json")
            if (!record.isFile) null else runCatching { json.decodeFromString(Production.serializer(), record.readText()) }.getOrNull()
        }.sortedByDescending { it.created }
    }

    fun create(script: PlayScript): Production {
        val production = Production.create(script)
        takesFolder(production.id).mkdirs()
        roomToneFolder(production.id).mkdirs()
        writeAtomically(File(folder(production.id), "script.json"), json.encodeToString(PlayScript.serializer(), script))
        save(production)
        return production
    }

    /** The script as cast, read back from the production's own folder, so a later catalog revision never changes a play halfway through. */
    fun script(production: Production): PlayScript? {
        val file = File(folder(production.id), "script.json")
        if (!file.isFile) return null
        return runCatching { json.decodeFromString(PlayScript.serializer(), file.readText()) }.getOrNull()
    }

    fun save(production: Production) {
        folder(production.id).mkdirs()
        writeAtomically(File(folder(production.id), "production.json"), json.encodeToString(Production.serializer(), production))
        val list = _productions.value
        _productions.value = if (list.any { it.id == production.id }) {
            list.map { if (it.id == production.id) production else it }
        } else {
            listOf(production) + list
        }
    }

    /** Deleting a production deletes its folder: takes, room tone, mix, record. */
    fun delete(id: String) {
        folder(id).deleteRecursively()
        _productions.value = _productions.value.filter { it.id != id }
    }

    fun discardUnusedTakes(id: String) {
        val production = production(id) ?: return
        val (kept, gone) = production.discardUnused()
        gone.forEach { takeFile(production, it).delete() }
        save(kept)
    }

    /** Writes a take file that never existed before (takes are never overwritten). */
    fun writeTake(capture: MicrophoneCapture, production: Production, lineID: String): String {
        val name = "$lineID-${shortId()}.${TakeAudio.FILE_EXTENSION}"
        val file = File(takesFolder(production.id), name)
        check(!file.exists()) { "a take is never overwritten" }
        takesFolder(production.id).mkdirs()
        TakeAudio.write(capture, file)
        return name
    }

    fun writeRoomTone(capture: MicrophoneCapture, production: Production): String {
        val name = "roomtone-${shortId()}.${TakeAudio.FILE_EXTENSION}"
        roomToneFolder(production.id).mkdirs()
        TakeAudio.write(capture, File(roomToneFolder(production.id), name))
        return name
    }

    /**
     * Renders `mix.m4a` from the chosen takes when every speaking line has one
     * (PLAYS-DESIGN §2.7), and records which takes it was made from. A partial
     * play throws [MixTimeline.Incomplete] and writes nothing. [sink] is handed
     * a partial file beside the mix; it replaces the mix only once finished.
     */
    fun renderMix(id: String, sink: (File) -> MixSink): File {
        val production = production(id) ?: error("no production $id")
        val script = script(production) ?: error("no script for $id")
        val mix = mixFile(id)
        if (production.mixedFrom == production.chosenFingerprint && mix.isFile) return mix
        val timeline = MixTimeline.build(script, production)
        val partial = File(folder(id), ".mix-${shortId()}.m4a")
        val out = sink(partial)
        try {
            MixRenderer.render(timeline, takesFolder(id), out)
            out.finish()
        } catch (e: Throwable) {
            out.abandon()
            throw e
        }
        mix.delete()
        check(partial.renameTo(mix)) { "the mix could not be saved" }
        production(id)?.let { save(it.copy(mixedFrom = production.chosenFingerprint)) }
        return mix
    }

    /** Someone listened from the top to the end: the play is finished (§2.7). */
    fun markListenedThrough(id: String, fingerprint: String) {
        val p = production(id) ?: return
        if (p.chosenFingerprint != fingerprint) return
        save(p.copy(listenedThrough = true))
    }

    private fun shortId() = UUID.randomUUID().toString().take(8).uppercase()

    private fun writeAtomically(file: File, text: String) {
        val partial = File(file.parentFile, ".${file.name}.partial")
        partial.writeText(text)
        if (!partial.renameTo(file)) {
            file.delete()
            check(partial.renameTo(file)) { "could not save ${file.name}" }
        }
    }

    companion object {
        val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
    }
}
