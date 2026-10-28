package com.example.appname.playback

import android.net.Uri
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.DataReader
import androidx.media3.common.Format
import androidx.media3.common.util.ParsableByteArray
import androidx.media3.common.util.UnstableApi
import androidx.media3.extractor.ConstantBitrateSeekMap
import androidx.media3.extractor.DefaultExtractorsFactory
import androidx.media3.extractor.Extractor
import androidx.media3.extractor.ExtractorInput
import androidx.media3.extractor.ExtractorOutput
import androidx.media3.extractor.ExtractorsFactory
import androidx.media3.extractor.PositionHolder
import androidx.media3.extractor.SeekMap
import androidx.media3.extractor.SeekPoint
import androidx.media3.extractor.TrackOutput
import androidx.media3.extractor.mp3.Mp3Extractor
import kotlin.math.abs

/**
 * Many Internet Archive VBR MP3s carry no Xing/Info/VBRI header. Media3's
 * Mp3Extractor then builds a constant-bitrate seek map from the FIRST frame's
 * bitrate, so the duration is wrong (a 32 kbps first frame in an 85 kbps file
 * reads about 2.7 times too long) and a seek lands at the wrong byte. None of
 * the Mp3Extractor flags changes that over HTTP: the CBR map is seekable when
 * the length is known, so index seeking (which would scan the file) never
 * engages. The catalog knows the real length, so a seek map is built from it.
 */
object Mp3Seeking {
    /**
     * Index seeking is the fallback when the byte length is unknown (chunked
     * responses): a time-to-byte map built as the file is read, exact duration at
     * the end of the stream.
     */
    const val FLAGS: Int = Mp3Extractor.FLAG_ENABLE_INDEX_SEEKING

    /** The extractor's duration and the catalog's disagree by more than this share. */
    const val DISAGREE_SHARE = 0.05

    fun disagrees(extractorUs: Long, catalogUs: Long): Boolean =
        extractorUs <= 0 || extractorUs == C.TIME_UNSET ||
            abs(extractorUs - catalogUs) > catalogUs * DISAGREE_SHARE

    /** The duration the player shows: the catalog's while the extractor's is unknown or disagrees. */
    fun displayMs(extractorMs: Long, catalogMs: Long?): Long =
        if (catalogMs == null || catalogMs <= 0) extractorMs
        else if (disagrees(extractorMs * 1000, catalogMs * 1000)) catalogMs
        else extractorMs

    @OptIn(UnstableApi::class)
    fun extractorsFactory(lengthUs: (Uri) -> Long?): ExtractorsFactory =
        CatalogLengthExtractorsFactory(DefaultExtractorsFactory().setMp3ExtractorFlags(FLAGS), lengthUs)
}

/** A seek map that spreads the catalog's duration evenly over the audio bytes. */
@OptIn(UnstableApi::class)
internal class ProportionalSeekMap(
    private val durationUs: Long,
    val startPosition: Long,
    val endPosition: Long,
) : SeekMap {
    override fun isSeekable() = true
    override fun getDurationUs() = durationUs
    override fun getSeekPoints(timeUs: Long): SeekMap.SeekPoints {
        val t = timeUs.coerceIn(0, durationUs)
        return SeekMap.SeekPoints(SeekPoint(t, positionAt(t)))
    }

    fun positionAt(timeUs: Long): Long =
        (startPosition + (endPosition - startPosition).toDouble() * timeUs / durationUs).toLong()
            .coerceIn(startPosition, (endPosition - 1).coerceAtLeast(startPosition))

    fun timeAt(position: Long): Long =
        ((position - startPosition).coerceAtLeast(0).toDouble() / (endPosition - startPosition) * durationUs).toLong()
            .coerceIn(0, durationUs)

    companion object {
        /** The replacement for a first-frame CBR map that disagrees with the catalog, else null. */
        fun replacing(map: SeekMap, catalogUs: Long): ProportionalSeekMap? {
            if (map !is ConstantBitrateSeekMap || !map.isSeekable || catalogUs <= 0) return null
            if (!Mp3Seeking.disagrees(map.durationUs, catalogUs)) return null
            val start = map.getSeekPoints(0).first.position
            val end = map.getSeekPoints(map.durationUs.coerceAtLeast(0)).first.position
            if (end <= start) return null
            return ProportionalSeekMap(catalogUs, start, end)
        }
    }
}

@OptIn(UnstableApi::class)
internal class CatalogLengthExtractorsFactory(
    private val base: ExtractorsFactory,
    private val lengthUs: (Uri) -> Long?,
) : ExtractorsFactory {
    override fun createExtractors(): Array<Extractor> = base.createExtractors()

    override fun createExtractors(uri: Uri, responseHeaders: Map<String, List<String>>): Array<Extractor> {
        val extractors = base.createExtractors(uri, responseHeaders)
        val length = lengthUs(uri) ?: return extractors
        return wrapMp3(extractors, length)
    }

    companion object {
        fun wrapMp3(extractors: Array<Extractor>, lengthUs: Long): Array<Extractor> = Array(extractors.size) { i ->
            val e = extractors[i]
            if (e is Mp3Extractor) CatalogLengthMp3Extractor(e, lengthUs) else e
        }
    }
}

/**
 * Wraps the Mp3Extractor: when it settles on a first-frame CBR map that
 * disagrees with the catalog length, it publishes a proportional map instead,
 * and after each seek shifts sample timestamps so they follow that map (the
 * extractor stamps a seek's first frame from its own, wrong, byte-to-time map).
 */
@OptIn(UnstableApi::class)
internal class CatalogLengthMp3Extractor(
    private val inner: Extractor,
    private val catalogUs: Long,
) : Extractor {
    private var map: ProportionalSeekMap? = null
    private var rebasePending = false
    private var rebaseToUs = 0L
    private var offsetUs = 0L

    override fun sniff(input: ExtractorInput) = inner.sniff(input)

    override fun init(output: ExtractorOutput) {
        inner.init(object : ExtractorOutput {
            override fun track(id: Int, type: Int): TrackOutput = Rebasing(output.track(id, type))
            override fun endTracks() = output.endTracks()
            override fun seekMap(seekMap: SeekMap) {
                val replacement = ProportionalSeekMap.replacing(seekMap, catalogUs)
                map = replacement
                output.seekMap(replacement ?: seekMap)
            }
        })
    }

    override fun read(input: ExtractorInput, seekPosition: PositionHolder) = inner.read(input, seekPosition)

    override fun seek(position: Long, timeUs: Long) {
        inner.seek(position, timeUs)
        map?.let {
            rebasePending = true
            rebaseToUs = it.timeAt(position)
        }
    }

    override fun release() = inner.release()

    override fun getUnderlyingImplementation(): Extractor = inner.underlyingImplementation

    private inner class Rebasing(private val out: TrackOutput) : TrackOutput {
        override fun durationUs(durationUs: Long) = out.durationUs(map?.durationUs ?: durationUs)
        override fun format(format: Format) = out.format(format)
        override fun sampleData(input: DataReader, length: Int, allowEndOfInput: Boolean, sampleDataPart: Int) =
            out.sampleData(input, length, allowEndOfInput, sampleDataPart)

        override fun sampleData(data: ParsableByteArray, length: Int, sampleDataPart: Int) =
            out.sampleData(data, length, sampleDataPart)

        override fun sampleMetadata(
            timeUs: Long,
            flags: Int,
            size: Int,
            offset: Int,
            cryptoData: TrackOutput.CryptoData?,
        ) {
            if (map != null && rebasePending) {
                offsetUs = rebaseToUs - timeUs
                rebasePending = false
            }
            out.sampleMetadata(if (map == null) timeUs else timeUs + offsetUs, flags, size, offset, cryptoData)
        }
    }
}
