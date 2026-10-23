package com.example.appname.playback

import android.content.ComponentName
import android.content.Context
import android.net.Uri
import android.os.SystemClock
import androidx.annotation.OptIn
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
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.example.appname.data.ApiClient
import com.example.appname.data.CatalogRepository
import com.example.appname.data.DownloadStore
import com.example.appname.data.EpisodeRow
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
    /** False for a room's copy, whose start is the host's, not this device's saved place. */
    private var resumeSaved = true
    /** Each queued item's loudness level (DECISIONS 061); the sleep fade scales from it. */
    private var levels: List<Float> = emptyList()
    private var lastFactor = 1f
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

    private var playerOrNull: ExoPlayer? = null

    val player: ExoPlayer
        get() = playerOrNull ?: buildPlayer().also { playerOrNull = it }

    private fun buildPlayer(): ExoPlayer {
        val dataSource = DefaultDataSource.Factory(context, OkHttpDataSource.Factory(api.okHttp))
        return ExoPlayer.Builder(context)
            .setMediaSourceFactory(DefaultMediaSourceFactory(context).setDataSourceFactory(dataSource))
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
            .also { it.addListener(listener) }
    }

    private val listener = object : Player.Listener {
        override fun onIsPlayingChanged(isPlaying: Boolean) {
            if (isPlaying) startTicker() else saveNow()
            publish()
        }

        override fun onPlaybackStateChanged(playbackState: Int) {
            if (playbackState == Player.STATE_ENDED) {
                saveNow()
                itemEnded(sleep.onItemEnded())
            }
            publish()
        }

        override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) {
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
            if (resumeSaved) mediaItem?.mediaId?.let { id -> resumeAt(id) }
            applyVolume(lastFactor)
            onRoomChange?.invoke()
            publish()
        }

        override fun onPlayerError(error: PlaybackException) {
            val offline = error.errorCode == PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED ||
                error.errorCode == PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT
            _state.value = _state.value.copy(failed = true, offline = offline, isPlaying = false)
        }
    }

    /**
     * Plays [episode] and queues the rest of its season of the same series,
     * oldest first (R3: never past it, never into another series). [url]
     * overrides the default copy with a version the listener picked.
     * [startMs] starts it there instead of the saved position (a Radio slot);
     * [queue] false queues nothing behind it.
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
        val following = if (queue) db.followingInSeason(detail.episode.id) else emptyList()
        val followingItems = following.mapNotNull { row ->
            val next = db.episodeDetail(row.id) ?: return@mapNotNull null
            next.recordings.firstOrNull()?.url?.let { Triple(row, it, LoudnessLevel.volume(next, it)) }
        }
        val items = listOf(Triple(detail.episode, startUrl, LoudnessLevel.volume(detail, startUrl))) + followingItems
        saveNow()
        episodes = items.map { it.first }
        urls = items.map { it.second }
        resumeSaved = true
        levels = items.map { it.third }
        lastFactor = 1f
        sleep.onUserPlay()
        syncPauseAtEnd()
        _state.value = _state.value.copy(failed = false, offline = false)
        // The phone's Play and the car's alike, so another episode ends listening live.
        onTransport(TransportEvent.Loaded(detail.episode.id))
        return Queue(items.map { (row, u, _) -> mediaItem(row, u) }, startMs ?: startPositionFor(detail.episode.id))
    }

    private suspend fun startPositionFor(id: String): Long {
        val saved = user.progress(id) ?: return 0
        return PlayerNumbers.fromSaved(saved.positionMs, saved.finished)
    }

    private fun resumeAt(id: String) {
        val p = playerOrNull ?: return
        if (p.currentPosition > 1_000) return
        scope.launch {
            val start = startPositionFor(id)
            if (start > 0 && p.currentMediaItem?.mediaId == id) p.seekTo(start)
        }
    }

    /** The downloaded copy of [url] when it is on this device, so it plays with no network. */
    private fun mediaItem(row: EpisodeRow, url: String): MediaItem = MediaItem.Builder()
        .setMediaId(row.id)
        .setUri(downloads.localFile(row.id, url)?.let { Uri.fromFile(it) } ?: Uri.parse(url))
        .setMediaMetadata(
            MediaMetadata.Builder()
                .setTitle(row.title ?: row.airDate ?: row.seriesName)
                .setArtist(row.seriesName)
                .setSubtitle(row.airDate)
                .setMediaType(MediaMetadata.MEDIA_TYPE_PODCAST_EPISODE)
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
        playerOrNull?.pauseAtEndOfMediaItems = sleep.pausesAtEndOfItem || !sleep.allowsAutoAdvance()
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

    /** [factor] is the sleep fade's, applied over the current item's loudness level. */
    private fun applyVolume(factor: Float) {
        lastFactor = factor
        val p = playerOrNull ?: return
        p.volume = if (muted) 0f else (levels.getOrNull(p.currentMediaItemIndex) ?: 1f) * factor
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
        val duration = p.duration.takeIf { it != C.TIME_UNSET } ?: 0
        if (position <= 0 && duration <= 0) return
        lastSaveAt = SystemClock.elapsedRealtime()
        scope.launch { user.save(id, position, duration) }
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
            durationMs = p.duration.takeIf { it != C.TIME_UNSET } ?: 0,
            speed = p.playbackParameters.speed,
            sleep = sleep.state,
            sleepRemainingMs = sleep.remainingMs(
                SystemClock.elapsedRealtime(), remainingMediaMs(p), p.playbackParameters.speed,
            ),
            upNext = if (sleep.allowsAutoAdvance()) episodes.drop(index + 1) else emptyList(),
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
    fun playRoomCopy(row: EpisodeRow, url: String, startMs: Long, playing: Boolean, speed: Float, level: Float) {
        ensureSession()
        saveNow()
        episodes = listOf(row)
        urls = listOf(url)
        resumeSaved = false
        levels = listOf(level)
        lastFactor = 1f
        _state.value = _state.value.copy(failed = false, offline = false)
        onTransport(TransportEvent.Loaded(row.id))
        val p = player
        p.setMediaItems(listOf(mediaItem(row, url)), 0, startMs.coerceAtLeast(0))
        applyVolume(1f)
        p.setPlaybackSpeed(speed)
        p.prepare()
        p.playWhenReady = playing
        syncPauseAtEnd()
        publish()
    }
}
