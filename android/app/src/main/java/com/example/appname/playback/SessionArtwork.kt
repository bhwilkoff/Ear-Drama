package com.example.appname.playback

import android.content.Context
import android.graphics.Bitmap
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.core.net.toUri
import androidx.media3.common.MediaMetadata
import com.example.appname.data.EpisodeRow
import com.example.appname.data.Face
import com.example.appname.data.labelItem
import com.example.appname.ui.labelBitmap
import java.io.ByteArrayOutputStream

/**
 * The media session's picture is the one Now Playing draws (Decision 069, D3-4): the show's picture,
 * else the face's portrait, at Commons' 500 step, else the episode's own label (Decision 081) painted
 * to a 512 px PNG on the device, so each broadcast shows its own dated disc with no network.
 */
object SessionArtwork {
    fun apply(builder: MediaMetadata.Builder, context: Context, row: EpisodeRow, face: Face?): MediaMetadata.Builder {
        if (face != null) return builder.setArtworkUri((row.seriesWindowArt ?: face.art).url(500).toUri())
        return builder.setArtworkData(labelPng(context, row), MediaMetadata.PICTURE_TYPE_FRONT_COVER)
    }

    fun labelPng(context: Context, row: EpisodeRow, side: Int = 512): ByteArray = labelPng(context, row.labelItem(), side)

    fun labelPng(context: Context, item: com.example.appname.data.LabelItem, side: Int = 512): ByteArray {
        val bitmap = labelBitmap(context, item, side).asAndroidBitmap()
        return ByteArrayOutputStream().use { out ->
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
            out.toByteArray()
        }
    }
}
