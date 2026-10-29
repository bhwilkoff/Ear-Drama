package com.example.appname.playback

import com.example.appname.data.DownloadRecord
import android.app.PendingIntent
import android.content.Intent
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.session.CommandButton
import androidx.media3.session.LibraryResult
import androidx.media3.session.MediaLibraryService
import androidx.media3.session.MediaLibraryService.MediaLibrarySession
import androidx.media3.session.MediaSession
import androidx.media3.session.SessionError
import com.example.appname.MainActivity
import com.example.appname.app.AppNameApplication
import com.google.common.collect.ImmutableList
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.SettableFuture
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi

/**
 * The Media3 library service (foregroundServiceType mediaPlayback). It wraps
 * the engine's one player, so the notification and lock screen carry play and
 * pause, skip back 15 and forward 30, and the system's seek bar; it serves
 * [CarLibrary]'s browse tree to Android Auto.
 *
 * The session stays on on Android TV and Fire TV: TV-NP asks an audio app that
 * keeps playing behind the home screen for a Now Playing card, which this
 * session is. Archive Watch turns its session off on TV because it is a video
 * app; this inverts that by rule (research 04 §3.7).
 *
 * Nothing plays at start (Auto MA-1): the only path to the player is a play
 * request from the listener.
 */
class PlaybackService : MediaLibraryService() {

    private var session: MediaLibrarySession? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    @OptIn(UnstableApi::class)
    override fun onCreate() {
        super.onCreate()
        val container = (application as AppNameApplication).container
        val engine = container.playback
        val library = CarLibrary(
            inProgressIds = { container.user.inProgress().map { it.episodeId } },
            rows = { ids -> container.catalog.awaitDb()?.episodes(ids) ?: emptyList() },
            downloadedIds = {
                container.downloads.sortedRecords.filter { it.state == DownloadRecord.State.Downloaded }.map { it.episodeId }
            },
        )
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val back = CommandButton.Builder(CommandButton.ICON_SKIP_BACK_15)
            .setPlayerCommand(Player.COMMAND_SEEK_BACK)
            .setDisplayName("Back 15 seconds")
            .setSlots(CommandButton.SLOT_BACK)
            .build()
        val forward = CommandButton.Builder(CommandButton.ICON_SKIP_FORWARD_30)
            .setPlayerCommand(Player.COMMAND_SEEK_FORWARD)
            .setDisplayName("Forward 30 seconds")
            .setSlots(CommandButton.SLOT_FORWARD)
            .build()
        session = MediaLibrarySession.Builder(this, engine.player, LibraryCallback(library, engine))
            .setSessionActivity(open)
            .setMediaButtonPreferences(listOf(back, forward))
            .build()
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaLibrarySession? = session

    override fun onTaskRemoved(rootIntent: Intent?) {
        val player = session?.player
        if (player == null || !player.playWhenReady || player.mediaItemCount == 0) stopSelf()
    }

    override fun onDestroy() {
        scope.cancel()
        session?.release()
        session = null
        super.onDestroy()
    }

    private fun <T : Any> future(block: suspend () -> T): ListenableFuture<T> {
        val out = SettableFuture.create<T>()
        scope.launch {
            try {
                out.set(block())
            } catch (e: Exception) {
                out.setException(e)
            }
        }
        return out
    }

    private inner class LibraryCallback(
        private val library: CarLibrary,
        private val engine: PlaybackEngine,
    ) : MediaLibrarySession.Callback {

        override fun onGetLibraryRoot(
            session: MediaLibrarySession,
            browser: MediaSession.ControllerInfo,
            params: LibraryParams?,
        ): ListenableFuture<LibraryResult<MediaItem>> =
            Futures.immediateFuture(LibraryResult.ofItem(library.root.toMediaItem(), params))

        override fun onGetChildren(
            session: MediaLibrarySession,
            browser: MediaSession.ControllerInfo,
            parentId: String,
            page: Int,
            pageSize: Int,
            params: LibraryParams?,
        ): ListenableFuture<LibraryResult<ImmutableList<MediaItem>>> = future {
            val children = library.children(parentId, page, pageSize)
            if (children == null) {
                LibraryResult.ofError(SessionError.ERROR_BAD_VALUE)
            } else {
                LibraryResult.ofItemList(children.map { it.toMediaItem() }, params)
            }
        }

        override fun onGetItem(
            session: MediaLibrarySession,
            browser: MediaSession.ControllerInfo,
            mediaId: String,
        ): ListenableFuture<LibraryResult<MediaItem>> = future {
            library.item(mediaId)?.let { LibraryResult.ofItem(it.toMediaItem(), null) }
                ?: LibraryResult.ofError(SessionError.ERROR_BAD_VALUE)
        }

        /** The car's play request: the same queue the phone's Play button builds (R3), resumed where it stopped. */
        @OptIn(UnstableApi::class)
        override fun onSetMediaItems(
            mediaSession: MediaSession,
            controller: MediaSession.ControllerInfo,
            mediaItems: List<MediaItem>,
            startIndex: Int,
            startPositionMs: Long,
        ): ListenableFuture<MediaSession.MediaItemsWithStartPosition> = future {
            val id = mediaItems.getOrNull(startIndex.coerceAtLeast(0))?.mediaId
                ?: throw UnsupportedOperationException("No episode to play")
            val queue = engine.takeQueue(id) ?: throw UnsupportedOperationException("Not in the catalog: $id")
            MediaSession.MediaItemsWithStartPosition(queue.items, 0, queue.startPositionMs)
        }
    }
}
