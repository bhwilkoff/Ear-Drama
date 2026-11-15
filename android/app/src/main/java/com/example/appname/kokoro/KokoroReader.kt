package com.example.appname.kokoro

import com.example.appname.plays.SyntheticPCM
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/**
 * The downloaded voices reading a play's lines (PLAYS-DESIGN §2.8 engine `kokoro`, §5; Decision 078): a line's
 * published phonemes ([phonemes] reads `phonemes/<id>.json` through the library's one client) are tokenized and
 * rendered off the main thread into memory, and each render is marked synthetic so no writer in the app accepts it.
 * Nothing here writes a file or plays a sound: [KokoroLive] plays a render once and [com.example.appname.plays.KokoroStandIn]
 * hands one to the recorder's cue path. A null render means Kokoro cannot read the line (no model, no phonemes, a
 * non-finite or silent render), and the part's system voice reads it.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class KokoroReader(
    val store: KokoroModelStore,
    private val phonemes: suspend (playId: String) -> String?,
    private val loader: (KokoroModelStore.Paths, FloatArray) -> KokoroRenderer = KokoroEngines::load,
    private val worker: CoroutineDispatcher = Dispatchers.Default.limitedParallelism(1),
    /** Symbols per render: smaller pieces start sooner and peak lower (the S6a bench). */
    private val maxSymbols: Int = Kokoro.PIECE_SYMBOLS,
    /** Whether the engine is here (the on-demand `:kokoro` module); the model alone reads nothing. */
    private val engineReady: () -> Boolean = { true },
) {
    private class Loaded(val renderer: KokoroRenderer, val vocab: Map<String, Long>)

    private val lock = Mutex()
    @Volatile private var loaded: Loaded? = null
    private val plays = LinkedHashMap<String, Map<String, PhonemeLine>?>()

    /** Why the last refused render was refused (the bench and the logs say it; the person hears the system voice). */
    @Volatile var lastRefusal: String? = null
        private set

    fun ready(): Boolean = store.state.value is KokoroModelStore.State.Ready && engineReady()

    /** The castable Kokoro voices now: none until the model is downloaded. */
    fun voices() = Kokoro.castable(ready())

    /** Whether [playId] has published phonemes: null until [prepare] has asked. */
    fun hasPhonemes(playId: String): Boolean? = synchronized(plays) { if (playId in plays) plays[playId] != null else null }

    /** Fetches a play's phonemes once (the newest [KEEP_PLAYS] plays stay in memory). A play the catalog held has none. */
    suspend fun prepare(playId: String): Boolean {
        hasPhonemes(playId)?.let { return it }
        val map = try {
            phonemes(playId)?.let { text -> withContext(Dispatchers.Default) { PhonemeFile.decode(text).lines.associateBy { Kokoro.keyOf(it.t) } } }
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            return false
        }
        synchronized(plays) {
            plays[playId] = map
            while (plays.size > KEEP_PLAYS) plays.remove(plays.keys.first())
        }
        return map != null
    }

    private fun row(playId: String, text: String): PhonemeLine? = synchronized(plays) { plays[playId]?.get(Kokoro.keyOf(text)) }

    /** Whether Kokoro can read this line now (the model is here and the line has phonemes). */
    fun canRead(playId: String, text: String): Boolean = ready() && row(playId, text) != null

    private suspend fun engine(): Loaded? = lock.withLock {
        loaded?.let { return it }
        val paths = store.paths() ?: return null
        withContext(worker) {
            val vocab = Kokoro.parseVocab(paths.vocab.readText())
            val bytes = paths.voices.readBytes()
            val table = FloatArray(bytes.size / 4)
            ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN).asFloatBuffer().get(table)
            Loaded(loader(paths, table), vocab)
        }.also { loaded = it }
    }

    /** Loads the model now (the bench's load time; a first line otherwise loads it). */
    suspend fun warm(): Boolean = runCatching { engine() != null }.onFailure { lastRefusal = "load threw ${it::class.simpleName}: ${it.message}" }.getOrDefault(false)

    /**
     * The line's renders, one per piece of at most [maxSymbols] symbols, handed to [onPiece] as each is made.
     * False when Kokoro cannot read the line or the FIRST piece is refused (nothing was handed over, so the system
     * voice can read it); a later refused piece ends the line there.
     */
    suspend fun renderPieces(playId: String, text: String, voiceId: String, speed: Float, onPiece: suspend (FloatArray) -> Unit): Boolean {
        val voice = Kokoro.voice(voiceId) ?: return false
        if (!ready()) return false
        prepare(playId)
        val r = row(playId, text) ?: return false
        val e = runCatching { engine() }.getOrNull() ?: return false
        val pieces = Kokoro.chunks(Kokoro.phonemesFor(r, voice), maxSymbols).map { Kokoro.tokenize(it, e.vocab) }.filter { it.size > 2 }
        if (pieces.isEmpty()) return false
        for ((i, tokens) in pieces.withIndex()) {
            val samples = try {
                withContext(worker) { e.renderer.render(tokens, voice.index, speed) }
            } catch (c: CancellationException) {
                throw c
            } catch (x: Exception) {
                lastRefusal = "render threw ${x::class.simpleName}: ${x.message}"
                null
            }
            if (samples == null || !Kokoro.audible(samples)) {
                if (samples != null) lastRefusal = "refused ${samples.size} samples, ${samples.count { !it.isFinite() }} non-finite"
                return i > 0
            }
            SyntheticPCM.mark(samples)
            onPiece(samples)
        }
        return true
    }

    /** The whole line in one buffer (the recorder's cue), marked synthetic; null when Kokoro cannot read it. */
    suspend fun render(playId: String, text: String, voiceId: String, speed: Float): FloatArray? {
        val parts = ArrayList<FloatArray>()
        if (!renderPieces(playId, text, voiceId, speed) { parts += it }) return null
        val all = FloatArray(parts.sumOf { it.size })
        var at = 0
        for (p in parts) { p.copyInto(all, at); at += p.size }
        SyntheticPCM.mark(all)
        return all
    }

    /** Lets the model go (after Delete). */
    suspend fun unload() = lock.withLock {
        loaded?.renderer?.let { r -> withContext(worker) { r.close() } }
        loaded = null
    }

    companion object {
        const val KEEP_PLAYS = 2
    }
}
