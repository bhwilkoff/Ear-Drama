package com.example.appname.playback

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Typeface
import androidx.compose.ui.graphics.toArgb
import androidx.media3.common.MediaMetadata
import com.example.appname.data.EpisodeRow
import com.example.appname.data.Face
import com.example.appname.ui.theme.BrandBorderLight
import com.example.appname.ui.theme.BrandSurfaceAltLight
import com.example.appname.ui.theme.BrandTextLight
import com.example.appname.ui.theme.BrandTextMutedLight
import com.example.appname.ui.theme.genreColor
import java.io.ByteArrayOutputStream
import androidx.core.net.toUri
import androidx.core.graphics.createBitmap

/**
 * The media session's picture is the one Now Playing draws (Decision 069):
 * the face's portrait at Commons' 500 step, else the series' typographic card
 * painted to a PNG (the name and one line on the genre band, light palette).
 */
object SessionArtwork {
    fun apply(builder: MediaMetadata.Builder, row: EpisodeRow, face: Face?): MediaMetadata.Builder {
        if (face != null) return builder.setArtworkUri(face.art.url(500).toUri())
        return builder.setArtworkData(cardPng(row.seriesName, row.airDate?.take(4), row.seriesGenre),
            MediaMetadata.PICTURE_TYPE_FRONT_COVER)
    }

    fun cardPng(name: String, line: String?, genre: String?, side: Int = 512): ByteArray {
        val bitmap = createBitmap(side, side)
        val canvas = Canvas(bitmap)
        canvas.drawColor(BrandSurfaceAltLight.toArgb())
        val band = Paint().apply { color = (genreColor(genre, dark = false) ?: BrandBorderLight).toArgb() }
        canvas.drawRect(0f, 0f, side * 0.047f, side.toFloat(), band)
        val title = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = BrandTextLight.toArgb()
            textSize = side * 0.11f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        }
        val left = side * 0.11f
        val lines = wrap(name, title, side * 0.82f).take(5)
        val caption = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = BrandTextMutedLight.toArgb(); textSize = side * 0.066f }
        var y = side * 0.875f - (if (line != null) side * 0.1f else 0f) - (lines.size - 1) * title.textSize * 1.15f
        lines.forEach { canvas.drawText(it, left, y, title); y += title.textSize * 1.15f }
        if (line != null) canvas.drawText(line, left, y - title.textSize * 0.15f + caption.textSize * 0.4f, caption)
        return ByteArrayOutputStream().use { out ->
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
            bitmap.recycle()
            out.toByteArray()
        }
    }

    private fun wrap(text: String, paint: Paint, width: Float): List<String> {
        val out = mutableListOf<String>()
        var current = ""
        for (word in text.split(Regex("\\s+")).filter { it.isNotEmpty() }) {
            val next = if (current.isEmpty()) word else "$current $word"
            if (paint.measureText(next) > width && current.isNotEmpty()) { out += current; current = word } else current = next
        }
        if (current.isNotEmpty()) out += current
        return out
    }
}
