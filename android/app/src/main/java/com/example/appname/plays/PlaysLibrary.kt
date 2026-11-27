package com.example.appname.plays

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.withContext

/**
 * The Plays tab's state: the bundled castable scripts and the productions on
 * this device. It opens no audio and asks for nothing; the microphone is asked
 * for only when a performer starts recording (§2.3).
 */
class PlaysLibrary(private val context: Context, transport: LibraryTransport? = null, soundFetch: SoundFetch? = null) {
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

    /** The published library (contract §4.1) as the lists read it, the bundle its floor; `Caches/PlayLibrary/` keeps the last good copy. */
    val feed: PlayLibraryFeed = PlayLibraryFeed(
        transport ?: LibraryTransport { null },
        File(context.cacheDir, "PlayLibrary"),
    ) { load(); (_state.value as? State.Ready)?.scripts.orEmpty() }

    val rows: StateFlow<PlayLibraryFeed.Rows> get() = feed.rows

    suspend fun loadRows() = feed.loadRows()

    /** The person's own scripts (PLAYS-DESIGN §13), `filesDir/Scripts/`, beside the productions. */
    val own: OwnScripts by lazy {
        OwnScripts(File(context.filesDir, "Scripts"), { store }, onAdopted = { ids -> ids.forEach(cast::remove) })
    }

    /**
     * One play's whole script: the library's file, else the bundle's; null when neither has it, an error when it could not be
     * fetched. An own script is this device's and never asked of the network: the one seam every reader of a script goes through.
     */
    suspend fun script(id: String, revision: String? = null): PlayScript? =
        if (OwnScript.isOwnId(id)) withContext(Dispatchers.IO) { own.script(id) }?.takeIf { revision == null || it.revision == revision }
        else feed.script(id, revision)

    /** The same, as a screen's state: ready, or the words for why not. */
    suspend fun resolve(id: String, revision: String?): ScriptLoad = LibraryScripts.resolve(feed, id, revision)

    /** An own script's marks and voice choices go with it unless a production is left to read them in (§13 item 7). */
    suspend fun deleteOwn(id: String) {
        val made = own.productions(id)
        own.remove(id)
        if (made.isEmpty()) {
            VoiceCasting.forget(VoiceCasting.scriptKey(id), PrefsCastStore(context))
            MarksRepository(MarksDatabase.get(context).marks()).save(id, null, emptyList())
        }
    }

    /** A play's published phonemes for the downloaded voices; null for a held play or with no published index. */
    suspend fun phonemes(id: String): String? = feed.phonemes(id)

    private val cast = ConcurrentHashMap<String, PlayScript>()

    /** The script a production was cast from, as stored with it, read once off the main thread. */
    suspend fun castScript(productionId: String): PlayScript? = cast[productionId]
        ?: withContext(Dispatchers.IO) { store.production(productionId)?.let(::scopedScript) }?.also { cast[productionId] = it }

    private val _drifted = MutableStateFlow<Set<String>>(emptySet())

    /** Productions whose range a revision moved, dropped to the whole play: the cast sheet says so once (PLAYS-DESIGN §2.12 rule 4). */
    val drifted: StateFlow<Set<String>> = _drifted

    fun acknowledgeDrift(productionId: String) { _drifted.update { it - productionId } }

    /** The script of [production]: cut to its range; a range that no longer resolves is dropped and saved first. */
    private fun scopedScript(production: Production): PlayScript? {
        val whole = store.wholeScript(production) ?: return null
        if (!production.rangeDrifted(whole)) return production.scoped(whole)
        store.save(production.dropRange(whole))
        _drifted.update { it + production.id }
        return whole
    }

    fun cachedCastScript(productionId: String): PlayScript? = cast[productionId]

    /** Whether someone is signed in (the container sets it): a second production asks for an account (Decision 079). */
    var signedIn: () -> Boolean = { true }

    /** Why the sign-in sheet is up, set where a production could not begin without an account; the root shows it. */
    val accountAsk = MutableStateFlow<String?>(null)

    private val leaving = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    /**
     * Leaving the studio: once every take write for it has settled, a production with no take is removed, unless a
     * screen (its cast sheet) holds it again by then (PLAYS-DESIGN §2.3 rule 3a).
     */
    fun leftStudio(productionId: String) {
        leaving.launch {
            withContext(Dispatchers.IO) { store.dropWhenSettled(productionId) }
            if (store.production(productionId) == null) cast.remove(productionId)
        }
    }

    suspend fun create(script: PlayScript, range: ProductionRange? = null, heading: String? = null): Production = withContext(Dispatchers.IO) {
        store.create(script, range, heading).also { cast[it.id] = it.scoped(script.wholeScript) }
    }

    suspend fun delete(productionId: String) = withContext(Dispatchers.IO) {
        store.delete(productionId)
        cast.remove(productionId)
        VoiceCasting.forget(VoiceCasting.productionKey(productionId), PrefsCastStore(context))
    }

    /** The person's own sounds: `filesDir/Sounds/mine/`, this device only (B32 §3.4). */
    val ownSounds: OwnSounds by lazy { OwnSounds(File(context.filesDir, "Sounds/mine")) }

    /** The cue pack, a source that may be absent; re-downloadable, so it lives where a backup does not take it. */
    val soundPack: SoundPack by lazy { SoundPack(File(context.noBackupFilesDir, "sounds"), soundFetch) }

    /**
     * Renders `mix.m4a`. A production with sound resolves every cue it names first: one this device lacks refuses the mix
     * ([MixTimeline.MissingSounds], named by [missingNames]) unless [withoutMissing] (Export without them).
     */
    suspend fun renderMix(id: String, withoutMissing: Boolean = false): File = withContext(Dispatchers.Default) {
        val production = store.production(id)
        if (production == null || !MixSound.hasSound(production)) return@withContext store.renderMix(id) { AacMixSink(it) }
        val resolver = soundResolver()
        store.renderMix(id, resolver::info, resolver::samples, withoutMissing) { AacMixSink(it) }
    }

    /** The live cues for a listen plan (B32 4.4), or null when the production has no sound. A sound this device lacks plays nothing. */
    suspend fun listenCues(production: Production, script: PlayScript, plan: List<Relay.ListenEntry>, muted: Boolean = false): ListenCues? {
        if (!MixSound.hasSound(production)) return null
        val pack = withContext(Dispatchers.IO) { (soundPack.manifest() as? SoundPack.State.Ready)?.pack }
        return ListenCues(SoundCore.listenCues(script, production, plan), { src ->
            when {
                src.take != null -> production.take(src.take)?.let { store.takeFile(production, it) }
                src.own != null -> ownSounds.file(src.own).takeIf { it.isFile }
                src.pack != null && pack != null -> pack.cues.firstOrNull { it.id == src.cue }?.takeIf { soundPack.has(pack, it) }?.let { soundPack.file(pack, it) }
                else -> null
            }
        }, SystemCuePlayer(muted))
    }

    private suspend fun soundResolver(): SoundResolver {
        val pack = (soundPack.manifest() as? SoundPack.State.Ready)?.pack
        return SoundResolver(ownSounds, pack) { cue -> pack?.let { p -> soundPack.file(p, cue).takeIf { soundPack.has(p, cue) } } }
    }

    /** The sounds a production names that this device lacks, by the name a person gave them or the pack's title. */
    suspend fun missingNames(id: String, ids: List<String>): List<String> = withContext(Dispatchers.Default) {
        val production = store.production(id) ?: return@withContext ids
        val resolver = soundResolver()
        ids.map { resolver.nameOf(production, it) }
    }
}

/** Plays a rendered mix on this device; a seek forward means the listen was not all the way through. */
class MixPlayback {
    private var player: MediaPlayer? = null
    var skipped = false
        private set
    var onEnded: (() -> Unit)? = null

    /** The test door's mute (appname_mute): the file plays in time at zero volume. */
    var muted = false

    /** The read-along's speed (PLAYS-DESIGN 2.11 rule 7); the pitch is kept. Applied as playback starts. */
    var speed = 1f
        set(x) {
            field = x
            player?.let { p -> if (p.isPlaying) runCatching { p.playbackParams = p.playbackParams.setSpeed(x).setPitch(1f) } }
        }

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
            if (muted) setVolume(0f, 0f)
            setOnCompletionListener { onEnded?.invoke() }
            prepare()
        }
    }

    fun toggle() {
        val p = player ?: return
        if (p.isPlaying) {
            p.pause()
        } else {
            p.start()
            if (speed != 1f) runCatching { p.playbackParams = p.playbackParams.setSpeed(speed).setPitch(1f) }
        }
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
