package com.example.appname.playback

import android.content.ComponentName
import android.content.Context
import android.net.Uri
import android.os.SystemClock
import androidx.annotation.OptIn
import androidx.media3.cast.CastPlayer
import androidx.media3.cast.RemoteCastPlayer
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.example.appname.data.ApiClient
import com.example.appname.data.CatalogRepository
import com.example.appname.data.DownloadStore
import com.example.appname.data.PlaybackSource
import com.example.appname.data.CatalogDatabase
import com.example.appname.data.EpisodeRow
import com.example.appname.data.Face
import com.example.appname.data.UserStore
import com.example.appname.radio.TransportEvent
import com.google.common.util.concurrent.ListenableFuture
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import androidx.core.net.toUri

/** What the player screens draw. */
data class NowPlaying(
    val episode: EpisodeRow? = null,
    val isPlaying: Boolean = false,
    val buffering: Boolean = false,
    val positionMs: Long = 0,
    val durationMs: Long = 0,
    val speed: Float = 1f,
    val sleep: SleepState = SleepState.Off,
    val sleepRemainingMs: Long? = null,
    val upNext: List<EpisodeRow> = emptyList(),
    /** On a story arc's last part: the series' next story, offered for the person to start (Decision 067). */
    val nextStory: EpisodeRow? = null,
    val failed: Boolean = false,
    /** The failure was the network, not the recording. */
    val offline: Boolean = false,
) {
    /** The one line a failure shows, or null. */
    val problem: String?
        get() = when {
            !failed -> null
            offline -> "No connection."
            else -> "Could not play this recording."
        }
}

/**
 * Owns the one ExoPlayer, the sleep timer, and resume positions. The
 * [PlaybackService] wraps this player in the MediaSession, so the
 * notification, lock screen, headset and Bluetooth controls drive the same
 * player the screens do. Every call is on the main thread.
 */
@OptIn(UnstableApi::class)
class PlaybackEngine(
    private val context: Context,
    private val api: ApiClient,
    private val catalog: CatalogRepository,
    private val user: UserStore,
    private val downloads: DownloadStore,
) {
    companion object {
        const val SKIP_BACK_MS = 15_000L
        const val SKIP_FORWARD_MS = 30_000L
        val SPEEDS = PlayerNumbers.SPEEDS
        private const val SAVE_EVERY_MS = PlayerNumbers.SAVE_EVERY_MS
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val sleep = SleepTimer()
    private var episodes: List<EpisodeRow> = emptyList()
    /** Each queued item's copy as the catalog names it, never a local file: a room shares this (§4.13). */
    private var urls: List<String> = emptyList()
    /** The arc's last part's id and the next story it offers, for this queue (Decision 067). */
    private var offer: Pair<String, EpisodeRow>? = null
    /** False for a room's copy, whose start is the host's, not this device's saved place. */
    private var resumeSaved = true
    /** Whether the playlist's tail is the arc and the person's queue (a Radio slot and a room play nothing after). */
    private var playsQueue = false
    private var lastFactor = 1f
    /** Decision 067: volume leveled on the device as it plays (DynamicsProcessing on the player's session). */
    private val leveler = VolumeLeveler(context)
    val leveling: StateFlow<Boolean> get() = leveler.on
    fun setLeveling(on: Boolean) = leveler.set(on)

    /**
     * A Listen Together guest's own pause (true) and play (false), Decision 067:
     * whatever pressed it (the sheet, the notification, a headset), reported to
     * the room session, which holds them and catches them up on play.
     */
    var onGuestHold: ((Boolean) -> Unit)? = null
    /** True while the room itself drives this player, so its own play and pause are not the guest's. */
    private var roomApplying = false

    /** Runs a room correction; its play and pause are the room's, never a guest's hold. */
    fun <T> asRoom(block: () -> T): T {
        roomApplying = true
        try {
            return block()
        } finally {
            roomApplying = false
        }
    }
    private var ticker: Job? = null
    private var lastSaveAt = 0L
    private var interrupted = false
    private var controllerFuture: ListenableFuture<MediaController>? = null

    /** The test doors' mute: silent whatever the fade says. */
    var muted: Boolean = false
        set(value) {
            field = value
            if (playerOrNull != null) applyVolume(1f)
        }

    /** Every load, pause, end, sleep and stop, for listening live (radio/LiveRadio). */
    var onTransport: (TransportEvent) -> Unit = {}

    /** Every play, pause, seek, speed, and episode change, for a Listen Together room (together/ListenTogether). */
    var onRoomChange: (() -> Unit)? = null

    private val _state = MutableStateFlow(NowPlaying())
    val state: StateFlow<NowPlaying> = _state

    /** The session's player: Media3's CastPlayer over [exoOrNull] when Cast is offered (CastRoute), else that ExoPlayer. */
    private var playerOrNull: Player? = null
    private var exoOrNull: ExoPlayer? = null

    /** The catalog's length of each queued item by uri, for MP3s whose own header cannot say (see [Mp3Seeking]). */
    private val lengthsUs = java.util.concurrent.ConcurrentHashMap<String, Long>()

    val player: Player
        get() = playerOrNull ?: buildPlayer().also { playerOrNull = it }

    private fun buildPlayer(): Player {
        val exo = buildExoPlayer().also { exoOrNull = it }
        val outer: Player = if (CastRoute.offered) {
            runCatching {
                val remote = RemoteCastPlayer.Builder(context)
                    .setMediaItemConverter(CastRoute.Items)
                    .setSeekBackIncrementMs(SKIP_BACK_MS)
                    .setSeekForwardIncrementMs(SKIP_FORWARD_MS)
                    .build()
                CastPlayer.Builder(context).setLocalPlayer(exo).setRemotePlayer(remote).build()
            }.getOrElse { exo }
        } else {
            exo
        }
        outer.addListener(listener)
        return outer
    }

    private fun buildExoPlayer(): ExoPlayer {
        val dataSource = DefaultDataSource.Factory(context, OkHttpDataSource.Factory(api.okHttp))
        return ExoPlayer.Builder(context)
            .setMediaSourceFactory(
                DefaultMediaSourceFactory(context, Mp3Seeking.extractorsFactory { lengthsUs[it.toString()] })
                    .setDataSourceFactory(dataSource),
            )
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(C.USAGE_MEDIA)
                    .setContentType(C.AUDIO_CONTENT_TYPE_SPEECH)
                    .build(),
                true,
            )
            .setHandleAudioBecomingNoisy(true)
            .setWakeMode(C.WAKE_MODE_NETWORK)
            .setSeekBackIncrementMs(SKIP_BACK_MS)
            .setSeekForwardIncrementMs(SKIP_FORWARD_MS)
            .build()
            .also {
                it.addAnalyticsListener(analytics)
                leveler.attach(it.audioSessionId)
            }
    }

    private val analytics = object : AnalyticsListener {
        override fun onAudioSessionIdChanged(eventTime: AnalyticsListener.EventTime, audioSessionId: Int) {
            leveler.attach(audioSessionId)
        }
    }

    private val listener = object : Player.Listener {
        override fun onIsPlayingChanged(isPlaying: Boolean) {
            if (isPlaying) startTicker() else saveNow()
            publish()
        }

        override fun onPlaybackStateChanged(playbackState: Int) {
            if (playbackState == Player.STATE_READY) recovery?.second?.loaded()
            if (playbackState == Player.STATE_ENDED) {
                saveNow()
                itemEnded(sleep.onItemEnded())
            }
            publish()
        }

        override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) {
            if (reason == Player.PLAY_WHEN_READY_CHANGE_REASON_USER_REQUEST && !roomApplying) {
                onGuestHold?.invoke(!playWhenReady)
            }
            if (!playWhenReady && reason == Player.PLAY_WHEN_READY_CHANGE_REASON_END_OF_MEDIA_ITEM) {
                saveNow()
                itemEnded(sleep.onItemEnded())
            } else if (!playWhenReady) {
                // The person, the notification, a headset, or audio focus: any pause.
                onTransport(TransportEvent.Paused)
            }
            onRoomChange?.invoke()
            publish()
        }

        override fun onPositionDiscontinuity(
            oldPosition: Player.PositionInfo,
            newPosition: Player.PositionInfo,
            reason: Int,
        ) {
            if (reason == Player.DISCONTINUITY_REASON_SEEK) onRoomChange?.invoke()
        }

        override fun onPlaybackParametersChanged(playbackParameters: PlaybackParameters) {
            onRoomChange?.invoke()
        }

        // A call or another app's sound takes audio focus for a moment; when it
        // hands focus back, the last line is heard again (DECISIONS 062).
        override fun onPlaybackSuppressionReasonChanged(playbackSuppressionReason: Int) {
            val p = playerOrNull ?: return
            if (playbackSuppressionReason == Player.PLAYBACK_SUPPRESSION_REASON_TRANSIENT_AUDIO_FOCUS_LOSS) {
                interrupted = true
                saveNow()
            } else if (interrupted && playbackSuppressionReason == Player.PLAYBACK_SUPPRESSION_REASON_NONE) {
                interrupted = false
                p.seekTo(PlayerNumbers.rewound(p.currentPosition))
            }
            publish()
        }

        override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
            if (reason == Player.MEDIA_ITEM_TRANSITION_REASON_AUTO && !sleep.allowsAutoAdvance()) {
                player.pause()
            }
            // A queued episode that starts leaves the queue, as the web's does.
            if (reason == Player.MEDIA_ITEM_TRANSITION_REASON_AUTO) mediaItem?.mediaId?.let { dequeue(it) }
            if (resumeSaved) mediaItem?.mediaId?.let { id -> resumeAt(id) }
            applyVolume(lastFactor)
            onRoomChange?.invoke()
            publish()
        }

        override fun onPlayerError(error: PlaybackException) {
            val offline = error.errorCode == PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED ||
                error.errorCode == PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT
            scope.launch {
                if (!recover()) {
                    _state.value = _state.value.copy(failed = true, offline = offline, isPlaying = false)
                }
            }
        }
    }

    /** The failed item's recovery: the episode's id and the plan for its copies. */
    private var recovery: Pair<String, LoadRecovery>? = null

    /**
     * One retry of the same copy after a jittered wait, then the next copy in rank order, then
     * the error (resilient-media-streaming). False when nothing is left to try.
     */
    private suspend fun recover(): Boolean {
        val p = playerOrNull ?: return false
        val index = p.currentMediaItemIndex
        val row = episodes.getOrNull(index) ?: return false
        val url = urls.getOrNull(index) ?: return false
        var plan = recovery?.takeIf { it.first == row.id && it.second.current == url }?.second
        if (plan == null) {
            val ranked = catalog.awaitDb()?.episodeDetail(row.id)?.recordings?.map { it.url }.orEmpty()
            plan = LoadRecovery(url, ranked)
            recovery = row.id to plan
        }
        val at = p.currentPosition.coerceAtLeast(0)
        val next = when (val step = plan.failed(kotlin.random.Random.nextDouble(0.5, 1.5))) {
            LoadRecovery.Step.GiveUp -> return false
            is LoadRecovery.Step.Retry -> {
                delay((step.seconds * 1000).toLong())
                url
            }
            is LoadRecovery.Step.Fallback -> step.url
        }
        if (playerOrNull?.currentMediaItemIndex != index || episodes.getOrNull(index)?.id != row.id) return true
        urls = urls.toMutableList().also { it[index] = next }
        p.replaceMediaItem(index, mediaItem(row, next, card = index == 0))
        p.seekTo(index, at)
        p.prepare()
        p.play()
        return true
    }

    /**
     * Plays [episode], then the person's queue, whatever its series, then
     * stops (Decision 067: nothing they did not choose starts by itself). [url]
     * overrides the default copy with a version the listener picked.
     * [startMs] starts it there instead of the saved position (a Radio slot);
     * [queue] false plays nothing after it.
     */
    fun play(episode: EpisodeRow, url: String? = null, startMs: Long? = null, queue: Boolean = true) {
        ensureSession()
        scope.launch {
            val taken = takeQueue(episode.id, url, startMs, queue) ?: return@launch
            val p = player
            p.setMediaItems(taken.items, 0, taken.startPositionMs)
            applyVolume(1f)
            p.prepare()
            p.play()
            syncPauseAtEnd()
            publish()
        }
    }

    /** A queue for the player: its items, and where the first one starts. */
    class Queue(val items: List<MediaItem>, val startPositionMs: Long)

    /**
     * Builds [episodeId]'s queue and makes it the engine's own. [play] sets it
     * on the player; a car's play request hands it back to the media session,
     * which sets it there.
     */
    suspend fun takeQueue(
        episodeId: String,
        url: String? = null,
        startMs: Long? = null,
        queue: Boolean = true,
    ): Queue? {
        val db = catalog.awaitDb() ?: return null
        val detail = db.episodeDetail(episodeId) ?: return null
        val startUrl = url ?: detail.recordings.firstOrNull()?.url ?: return null
        val queued = user.queue()
        val arc = if (queue) db.arcAhead(detail.episode.id) else null
        val following = if (queue) PlaybackQueue.after(detail.episode.id, arc, queued) else emptyList()
        offer = PlaybackQueue.offeredBy(detail.episode.id, arc)?.let { by ->
            arc?.nextStory?.let { db.episodeDetail(it) }?.let { by to it.episode }
        }
        val followingItems = playable(db, following)
        val items = listOf(detail.episode to startUrl) + followingItems
        if (detail.episode.id in queued) user.setQueue(queued - detail.episode.id)
        saveNow()
        episodes = items.map { it.first }
        urls = items.map { it.second }
        recovery = null
        resumeSaved = true
        playsQueue = queue
        lastFactor = 1f
        sleep.onUserPlay()
        syncPauseAtEnd()
        _state.value = _state.value.copy(failed = false, offline = false)
        // The phone's Play and the car's alike, so another episode ends listening live.
        onTransport(TransportEvent.Loaded(detail.episode.id))
        // The first item wears the episode's own face (or its series' card); the rest their series' face.
        val media = items.mapIndexed { i, (row, u) ->
            if (i == 0) mediaItem(row, u, detail.face, card = true) else mediaItem(row, u)
        }
        return Queue(media, startMs ?: startPositionFor(detail.episode.id, detail.episode.lengthSeconds))
    }

    private suspend fun playable(db: CatalogDatabase, ids: List<String>): List<Pair<EpisodeRow, String>> = ids.mapNotNull { id ->
        val next = db.episodeDetail(id) ?: return@mapNotNull null
        next.recordings.firstOrNull()?.url?.let { next.episode to it }
    }

    /**
     * The person added, removed, or moved a queued episode: what follows the one
     * playing is rebuilt by the same rule (`PlaybackQueue.after`), so "Up next"
     * and the playlist match the queue. The playing item is untouched.
     */
    fun queueChanged() {
        scope.launch {
            val p = playerOrNull ?: return@launch
            val index = p.currentMediaItemIndex
            val current = episodes.getOrNull(index) ?: return@launch
            if (!playsQueue || p.mediaItemCount == 0) return@launch
            val db = catalog.awaitDb() ?: return@launch
            val following = PlaybackQueue.after(current.id, db.arcAhead(current.id), user.queue())
            val items = playable(db, following)
            if (p.currentMediaItem?.mediaId != current.id) return@launch
            p.removeMediaItems(index + 1, p.mediaItemCount)
            p.addMediaItems(items.map { (row, url) -> mediaItem(row, url) })
            episodes = episodes.take(index + 1) + items.map { it.first }
            urls = urls.take(index + 1) + items.map { it.second }
            publish()
        }
    }

    private fun dequeue(id: String) {
        scope.launch {
            val queued = user.queue()
            if (id in queued) user.setQueue(queued - id)
        }
    }

    private suspend fun startPositionFor(id: String, lengthSeconds: Double?): Long {
        val saved = user.progress(id) ?: return 0
        return PlayerNumbers.fromSaved(saved.positionMs, saved.finished, lengthSeconds?.let { (it * 1000).toLong() })
    }

    private fun resumeAt(id: String) {
        val p = playerOrNull ?: return
        if (p.currentPosition > 1_000) return
        scope.launch {
            val start = startPositionFor(id, episodes.firstOrNull { it.id == id }?.lengthSeconds)
            if (start > 0 && p.currentMediaItem?.mediaId == id) p.seekTo(start)
        }
    }

    /** The downloaded copy of [url] when it is on this device, so it plays with no network. */
    private fun mediaItem(
        row: EpisodeRow,
        url: String,
        face: Face? = row.seriesFace,
        card: Boolean = false,
    ): MediaItem {
        val source = downloads.playbackSource(row.id, url)
        return mediaItem(row, source, face, card, url)
    }

    /**
     * A downloaded file's lock-screen picture is the typographic card, drawn on
     * the device, so it shows with no network (a portrait is a URL to fetch).
     */
    private fun mediaItem(row: EpisodeRow, source: PlaybackSource, face: Face?, card: Boolean, copyUrl: String): MediaItem {
        val uri = if (source.isLocal) Uri.fromFile(java.io.File(source.location)) else source.location.toUri()
        row.lengthSeconds?.takeIf { it > 0 }?.let { lengthsUs[uri.toString()] = (it * 1_000_000).toLong() }
        return mediaItem(row, uri, source.isLocal, face, card, copyUrl)
    }

    private fun mediaItem(row: EpisodeRow, uri: Uri, isLocal: Boolean, face: Face?, card: Boolean, copyUrl: String): MediaItem = MediaItem.Builder()
        .setMediaId(row.id)
        .setUri(uri)
        // A Cast receiver plays the catalog copy even when this phone plays the downloaded file (CastRoute.Items).
        .setRequestMetadata(MediaItem.RequestMetadata.Builder().setMediaUri(copyUrl.toUri()).build())
        .setMediaMetadata(
            MediaMetadata.Builder()
                .setTitle(row.title ?: row.airDate ?: row.seriesName)
                .setArtist(row.seriesName)
                .setSubtitle(row.airDate)
                .setMediaType(MediaMetadata.MEDIA_TYPE_PODCAST_EPISODE)
                .let {
                    when {
                        isLocal -> SessionArtwork.apply(it, row, null)
                        face != null || card -> SessionArtwork.apply(it, row, face)
                        else -> it
                    }
                }
                .build(),
        )
        .build()

    fun togglePlay() {
        val p = playerOrNull ?: return
        if (p.isPlaying) {
            p.pause()
        } else {
            sleep.onUserPlay()
            syncPauseAtEnd()
            if (p.playbackState == Player.STATE_ENDED) p.seekToDefaultPosition()
            p.play()
        }
        publish()
    }

    fun skipBack() { playerOrNull?.seekBack(); publish() }
    fun skipForward() { playerOrNull?.seekForward(); publish() }
    fun seekTo(positionMs: Long) { playerOrNull?.seekTo(positionMs); publish() }

    fun setSpeed(speed: Float) {
        playerOrNull?.setPlaybackSpeed(speed)
        publish()
    }

    fun setSleep(mode: SleepMode?) {
        if (mode == null) sleep.cancel() else sleep.arm(mode, SystemClock.elapsedRealtime())
        applyVolume(1f)
        syncPauseAtEnd()
        publish()
    }

    val sleepOptions: List<SleepMode> get() = sleep.options

    private fun syncPauseAtEnd() {
        exoOrNull?.pauseAtEndOfMediaItems = sleep.pausesAtEndOfItem || !sleep.allowsAutoAdvance()
    }

    /** The recording reached its end: the sleep timer's, or a plain end. */
    private fun itemEnded(decision: SleepDecision) {
        onTransport(if (decision.pause) TransportEvent.SleepFired else TransportEvent.Ended)
        applySleep(decision)
    }

    private fun applySleep(decision: SleepDecision) {
        if (decision.pause) {
            playerOrNull?.pause()
            applyVolume(1f)
            syncPauseAtEnd()
        } else {
            applyVolume(decision.volume)
        }
    }

    /** [factor] is the sleep fade's; leveling is the session's effect, not the volume. */
    private fun applyVolume(factor: Float) {
        lastFactor = factor
        // The phone's own output only: on a Cast session the session's volume is the speaker's, which the person sets.
        val p = exoOrNull ?: return
        p.volume = if (muted) 0f else factor
    }

    private fun remainingMediaMs(p: Player): Long? =
        p.duration.takeIf { it != C.TIME_UNSET && it > 0 }?.let { (it - p.currentPosition).coerceAtLeast(0) }

    private fun startTicker() {
        if (ticker?.isActive == true) return
        ticker = scope.launch {
            while (isActive) {
                val p = playerOrNull ?: break
                if (p.isPlaying) {
                    val decision = sleep.tick(SystemClock.elapsedRealtime(), remainingMediaMs(p), p.playbackParameters.speed)
                    if (decision.pause) onTransport(TransportEvent.SleepFired)
                    applySleep(decision)
                    val now = SystemClock.elapsedRealtime()
                    if (now - lastSaveAt >= SAVE_EVERY_MS) saveNow()
                }
                publish()
                if (!p.isPlaying && sleep.state !is SleepState.Armed) break
                delay(500)
            }
        }
    }

    private fun saveNow() {
        val p = playerOrNull ?: return
        val id = p.currentMediaItem?.mediaId ?: return
        val position = p.currentPosition
        val duration = displayDurationMs(p, id)
        if (position <= 0 && duration <= 0) return
        lastSaveAt = SystemClock.elapsedRealtime()
        scope.launch { user.save(id, position, duration) }
    }

    private fun displayDurationMs(p: Player, id: String?): Long {
        val own = p.duration.takeIf { it != C.TIME_UNSET } ?: 0
        val catalog = episodes.firstOrNull { it.id == id }?.lengthSeconds?.let { (it * 1000).toLong() }
        return Mp3Seeking.displayMs(own, catalog)
    }

    private fun publish() {
        val p = playerOrNull ?: return
        val index = p.currentMediaItemIndex
        val current = episodes.getOrNull(index)
        _state.value = _state.value.copy(
            episode = current,
            isPlaying = p.isPlaying,
            buffering = p.playbackState == Player.STATE_BUFFERING,
            positionMs = p.currentPosition.coerceAtLeast(0),
            durationMs = displayDurationMs(p, current?.id),
            speed = p.playbackParameters.speed,
            sleep = sleep.state,
            sleepRemainingMs = sleep.remainingMs(
                SystemClock.elapsedRealtime(), remainingMediaMs(p), p.playbackParameters.speed,
            ),
            upNext = if (sleep.allowsAutoAdvance()) episodes.drop(index + 1) else emptyList(),
            nextStory = offer?.takeIf { it.first == current?.id }?.second,
        )
    }

    /** Binding a controller starts the session service, which posts the media notification. */
    private fun ensureSession() {
        if (controllerFuture != null) return
        val token = SessionToken(context, ComponentName(context, PlaybackService::class.java))
        controllerFuture = MediaController.Builder(context, token).buildAsync()
    }

    /** Stops playback for the test doors' end. */
    fun stop() {
        saveNow()
        playerOrNull?.stop()
        publish()
        onTransport(TransportEvent.Stopped)
    }

    /** Pauses, as the person's own pause does (Listening live's button). */
    fun pause() {
        playerOrNull?.pause()
        publish()
    }

    /** Plays on from here, for a room's correction. */
    fun resume() {
        playerOrNull?.play()
        publish()
    }

    /** What a Listen Together room reads from this player: the item playing, its catalog copy, and where it is. */
    data class RoomView(val episodeId: String, val copyUrl: String, val positionMs: Long, val playing: Boolean, val speed: Float)

    fun roomView(): RoomView? {
        val p = playerOrNull ?: return null
        val index = p.currentMediaItemIndex
        val id = episodes.getOrNull(index)?.id ?: return null
        val url = urls.getOrNull(index) ?: return null
        val playing = p.playWhenReady && p.playbackState != Player.STATE_ENDED && p.playbackState != Player.STATE_IDLE
        return RoomView(id, url, p.currentPosition.coerceAtLeast(0), playing, p.playbackParameters.speed)
    }

    /**
     * A guest plays the host's exact copy (Archive Watch Decision 143): this
     * one item, nothing queued, at the host's place and speed, never this
     * device's saved position.
     */
    fun playRoomCopy(row: EpisodeRow, url: String, startMs: Long, playing: Boolean, speed: Float) {
        ensureSession()
        saveNow()
        episodes = listOf(row)
        recovery = null
        offer = null
        urls = listOf(url)
        playsQueue = false
        resumeSaved = false
        lastFactor = 1f
        _state.value = _state.value.copy(failed = false, offline = false)
        onTransport(TransportEvent.Loaded(row.id))
        val p = player
        p.setMediaItems(listOf(mediaItem(row, url, card = true)), 0, startMs.coerceAtLeast(0))
        applyVolume(1f)
        p.setPlaybackSpeed(speed)
        p.prepare()
        p.playWhenReady = playing
        syncPauseAtEnd()
        publish()
    }
}
