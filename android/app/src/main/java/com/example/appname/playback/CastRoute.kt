package com.example.appname.playback

import android.content.Context
import android.net.Uri
import androidx.annotation.OptIn
import androidx.core.content.ContextCompat
import androidx.media3.cast.Cast
import androidx.media3.cast.CastParams
import androidx.media3.cast.DefaultMediaItemConverter
import androidx.media3.cast.MediaItemConverter
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import com.example.appname.ui.isTelevision
import com.google.android.gms.cast.MediaQueueItem
import com.google.android.gms.cast.framework.CastContext
import com.google.android.gms.cast.framework.CastState
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * Play on another speaker or screen (the owner, 2026-10-28): Google Cast
 * through Media3's CastPlayer, which wraps the engine's ExoPlayer and moves
 * the queue and place to the receiver when a session starts and back when it
 * ends. The receiver is Google's Default Media Receiver, which fetches the
 * archive.org copy itself, never a file on this phone.
 *
 * Cast needs Google Play services, so a phone without them (and a Fire TV,
 * which has none) offers no button; a television is a Cast receiver, never a
 * sender. The system's own output switcher (Bluetooth, the phone's speaker)
 * comes from the media session on every device either way.
 */
object CastRoute {

    /** A phone or tablet with Play services sends; a TV or a phone without them does not. */
    fun offers(playServices: Boolean, television: Boolean): Boolean = playServices && !television

    /** The Cast button shows only while a receiver is on the network (Cast design checklist). */
    fun showsButton(offered: Boolean, castState: Int): Boolean =
        offered && castState != CastState.NO_DEVICES_AVAILABLE

    /** The receiver's copy: the catalog's url, so a downloaded episode still casts from archive.org. */
    fun receiverUrl(playing: String, catalog: String?): String =
        catalog?.takeIf { it.startsWith("https://") || it.startsWith("http://") } ?: playing

    /** The receiver needs a content type; archive.org's audio is named by its extension. */
    fun mimeTypeFor(url: String): String {
        val ext = url.substringBefore('?').substringAfterLast('/').substringAfterLast('.', "").lowercase()
        return when (ext) {
            "ogg", "oga" -> "audio/ogg"
            "m4a", "mp4", "aac" -> "audio/mp4"
            "flac" -> "audio/flac"
            "wav" -> "audio/wav"
            "opus" -> "audio/opus"
            else -> "audio/mpeg"
        }
    }

    @Volatile
    var offered: Boolean = false
        private set

    private val _available = MutableStateFlow(false)
    val available: StateFlow<Boolean> = _available

    /** Application.onCreate, on the main thread. Never throws: casting must not take the app down. */
    @OptIn(UnstableApi::class)
    fun initialize(context: Context) {
        val playServices = runCatching {
            GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(context) == ConnectionResult.SUCCESS
        }.getOrDefault(false)
        if (!offers(playServices, context.isTelevision())) return
        offered = runCatching {
            Cast.getSingletonInstance(context).initialize(
                CastParams.Builder().setShowSystemOutputSwitcherOnCastButtonClick(true).build(),
            )
            true
        }.onFailure { android.util.Log.w("CAST", "cast init failed: $it") }.getOrDefault(false)
        if (!offered) return
        CastContext.getSharedInstance(context, ContextCompat.getMainExecutor(context))
            .addOnSuccessListener { cast ->
                _available.value = showsButton(true, cast.castState)
                cast.addCastStateListener { _available.value = showsButton(offered, it) }
            }
            .addOnFailureListener {
                offered = false
                _available.value = false
            }
    }

    /** Swaps a local file for the catalog copy and names the content type, then Media3's own conversion. */
    @OptIn(UnstableApi::class)
    object Items : MediaItemConverter {
        private val base = DefaultMediaItemConverter()

        override fun toMediaQueueItem(mediaItem: MediaItem): MediaQueueItem {
            val playing = mediaItem.localConfiguration?.uri?.toString() ?: return base.toMediaQueueItem(mediaItem)
            val url = receiverUrl(playing, mediaItem.requestMetadata.mediaUri?.toString())
            return base.toMediaQueueItem(
                mediaItem.buildUpon().setUri(Uri.parse(url)).setMimeType(mimeTypeFor(url)).build(),
            )
        }

        override fun toMediaItem(mediaQueueItem: MediaQueueItem): MediaItem = base.toMediaItem(mediaQueueItem)
    }
}
