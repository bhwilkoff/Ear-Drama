package com.example.appname.plays

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.withContext

/**
 * The Plays tab's state: the bundled castable scripts and the productions on
 * this device. It opens no audio and asks for nothing; the microphone is asked
 * for only when a performer starts recording (§2.3).
 */
class PlaysLibrary(private val context: Context) {
    sealed interface State {
        data object Loading : State
        data class Ready(val scripts: List<PlayScript>) : State
        data object Unavailable : State
    }

    private val _state = MutableStateFlow<State>(State.Loading)
    val state: StateFlow<State> = _state

    /** `filesDir/Plays/`, the folder name Apple uses. */
    val store: ProductionStore by lazy { ProductionStore(File(context.filesDir, "Plays")) }

    suspend fun load() {
        if (_state.value is State.Ready) return
        _state.value = withContext(Dispatchers.IO) {
            store.load()
            runCatching {
                val text = context.assets.open(CastableLibrary.ASSET).bufferedReader().use { it.readText() }
                State.Ready(CastableLibrary.decode(text).scripts)
            }.getOrDefault(State.Unavailable)
        }
    }

    fun script(id: String): PlayScript? = (_state.value as? State.Ready)?.scripts?.firstOrNull { it.id == id }

    private val cast = ConcurrentHashMap<String, PlayScript>()

    /** The script a production was cast from, as stored with it, read once off the main thread. */
    suspend fun castScript(productionId: String): PlayScript? = cast[productionId]
        ?: withContext(Dispatchers.IO) { store.production(productionId)?.let(store::script) }?.also { cast[productionId] = it }

    fun cachedCastScript(productionId: String): PlayScript? = cast[productionId]

    suspend fun create(script: PlayScript): Production = withContext(Dispatchers.IO) {
        store.create(script).also { cast[it.id] = script }
    }

    suspend fun delete(productionId: String) = withContext(Dispatchers.IO) {
        store.delete(productionId)
        cast.remove(productionId)
    }

    suspend fun renderMix(id: String): File = withContext(Dispatchers.Default) {
        store.renderMix(id) { AacMixSink(it) }
    }
}

/** Plays a rendered mix on this device; a seek forward means the listen was not all the way through. */
class MixPlayback {
    private var player: MediaPlayer? = null
    var skipped = false
        private set
    var onEnded: (() -> Unit)? = null

    val isPlaying: Boolean get() = player?.isPlaying == true
    val durationMs: Int get() = player?.duration ?: 0
    val positionMs: Int get() = player?.currentPosition ?: 0
    val isLoaded: Boolean get() = player != null

    fun load(file: File) {
        stop()
        skipped = false
        player = MediaPlayer().apply {
            setAudioAttributes(
                AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build(),
            )
            setDataSource(file.path)
            setOnCompletionListener { onEnded?.invoke() }
            prepare()
        }
    }

    fun toggle() {
        val p = player ?: return
        if (p.isPlaying) p.pause() else p.start()
    }

    fun seek(ms: Int) {
        val p = player ?: return
        if (ms > p.currentPosition + 1_000) skipped = true
        p.seekTo(ms.coerceIn(0, p.duration))
    }

    fun stop() {
        player?.release()
        player = null
    }
}
