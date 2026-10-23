package com.example.appname.playback

import android.content.ComponentName
import android.content.Context
import android.os.SystemClock
import androidx.annotation.OptIn
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackException
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
import com.example.appname.data.EpisodeRow
import com.example.appname.data.UserStore
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
) {
    companion object {
        const val SKIP_BACK_MS = 15_000L
        const val SKIP_FORWARD_MS = 30_000L
        val SPEEDS = listOf(0.75f, 1f, 1.25f, 1.5f, 2f)
        /** Resuming starts a little before where the listener stopped. */
        private const val RESUME_REWIND_MS = 5_000L
        private const val SAVE_EVERY_MS = 5_000L
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val sleep = SleepTimer()
    private var episodes: List<EpisodeRow> = emptyList()
    private var ticker: Job? = null
    private var lastSaveAt = 0L
    private var controllerFuture: ListenableFuture<MediaController>? = null

    /** The test doors' mute: silent whatever the fade says. */
    var muted: Boolean = false
        set(value) {
            field = value
            if (playerOrNull != null) applyVolume(1f)
        }

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
                applySleep(sleep.onItemEnded())
            }
            publish()
        }

        override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) {
            if (!playWhenReady && reason == Player.PLAY_WHEN_READY_CHANGE_REASON_END_OF_MEDIA_ITEM) {
                saveNow()
                applySleep(sleep.onItemEnded())
            }
            publish()
        }

        override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
            if (reason == Player.MEDIA_ITEM_TRANSITION_REASON_AUTO && !sleep.allowsAutoAdvance()) {
                player.pause()
            }
            mediaItem?.mediaId?.let { id -> resumeAt(id) }
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
     */
    fun play(episode: EpisodeRow, url: String? = null) {
        ensureSession()
        scope.launch {
            val db = catalog.awaitDb() ?: return@launch
            val detail = db.episodeDetail(episode.id) ?: return@launch
            val startUrl = url ?: detail.recordings.firstOrNull()?.url ?: return@launch
            val following = db.followingInSeason(detail.episode.id)
            val followingUrls = following.mapNotNull { row ->
                db.episodeDetail(row.id)?.recordings?.firstOrNull()?.url?.let { row to it }
            }
            val queue = listOf(detail.episode to startUrl) + followingUrls
            episodes = queue.map { it.first }
            saveNow()
            sleep.onUserPlay()
            val p = player
            p.setMediaItems(queue.map { (row, u) -> mediaItem(row, u) }, 0, startPositionFor(detail.episode.id))
            p.prepare()
            p.play()
            syncPauseAtEnd()
            _state.value = _state.value.copy(failed = false, offline = false)
            publish()
        }
    }

    private suspend fun startPositionFor(id: String): Long {
        val saved = user.progress(id) ?: return 0
        if (saved.finished) return 0
        return (saved.positionMs - RESUME_REWIND_MS).coerceAtLeast(0)
    }

    private fun resumeAt(id: String) {
        val p = playerOrNull ?: return
        if (p.currentPosition > 1_000) return
        scope.launch {
            val start = startPositionFor(id)
            if (start > 0 && p.currentMediaItem?.mediaId == id) p.seekTo(start)
        }
    }

    private fun mediaItem(row: EpisodeRow, url: String): MediaItem = MediaItem.Builder()
        .setMediaId(row.id)
        .setUri(url)
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

    private fun applySleep(decision: SleepDecision) {
        if (decision.pause) {
            playerOrNull?.pause()
            applyVolume(1f)
            syncPauseAtEnd()
        } else {
            applyVolume(decision.volume)
        }
    }

    private fun applyVolume(volume: Float) {
        playerOrNull?.volume = if (muted) 0f else volume
    }

    private fun remainingMediaMs(p: Player): Long? =
        p.duration.takeIf { it != C.TIME_UNSET && it > 0 }?.let { (it - p.currentPosition).coerceAtLeast(0) }

    private fun startTicker() {
        if (ticker?.isActive == true) return
        ticker = scope.launch {
            while (isActive) {
                val p = playerOrNull ?: break
                if (p.isPlaying) {
                    applySleep(sleep.tick(SystemClock.elapsedRealtime(), remainingMediaMs(p), p.playbackParameters.speed))
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
    }
}
