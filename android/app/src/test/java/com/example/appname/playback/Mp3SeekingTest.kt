package com.example.appname.playback

import androidx.media3.common.C
import androidx.media3.common.util.UnstableApi
import androidx.media3.extractor.ConstantBitrateSeekMap
import androidx.media3.extractor.DefaultExtractorsFactory
import androidx.media3.extractor.Extractor
import androidx.media3.extractor.ExtractorInput
import androidx.media3.extractor.ExtractorOutput
import androidx.media3.extractor.PositionHolder
import androidx.media3.extractor.SeekMap
import androidx.media3.extractor.TrackOutput
import androidx.media3.extractor.mp3.Mp3Extractor
import io.mockk.every
import io.mockk.mockk
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** A VBR MP3 with no seek header reads as a constant bitrate at its first frame's rate; the catalog's length corrects it. */
@UnstableApi
class Mp3SeekingTest {
    private val first32kbps = ConstantBitrateSeekMap(/* inputLength= */ 1_000_000, 0, 32_000, 104)

    @Test fun `the factory carries the index seeking flag`() {
        val factory = Mp3Seeking.extractorsFactory { null }
        val base = factory.javaClass.getDeclaredField("base").apply { isAccessible = true }.get(factory)
        val flags = DefaultExtractorsFactory::class.java.getDeclaredField("mp3Flags").apply { isAccessible = true }.getInt(base)
        assertEquals(Mp3Extractor.FLAG_ENABLE_INDEX_SEEKING, flags)
        assertEquals(Mp3Seeking.FLAGS, flags)
    }

    @Test fun `a known length wraps the Mp3 extractor and no other`() {
        val mp3 = Mp3Extractor(Mp3Seeking.FLAGS)
        val other = FakeMp3()
        val wrapped = CatalogLengthExtractorsFactory.wrapMp3(arrayOf(other, mp3), 94_000_000L)
        assertTrue(wrapped[0] === other)
        assertTrue(wrapped[1] is CatalogLengthMp3Extractor)
        assertTrue(wrapped[1].underlyingImplementation === mp3)
    }

    @Test fun `a first-frame duration that disagrees is replaced and seeks follow the catalog`() {
        assertEquals("1 MB at 32 kbps is 250 s", 250_000_000L, first32kbps.durationUs)
        val map = ProportionalSeekMap.replacing(first32kbps, catalogUs = 94_000_000)
        assertNotNull(map)
        assertEquals(94_000_000L, map!!.durationUs)
        val half = map.getSeekPoints(47_000_000).first
        assertEquals(47_000_000L, half.timeUs)
        assertEquals(500_000.0, half.position.toDouble(), 2_000.0)
        assertEquals(47_000_000.0, map.timeAt(half.position).toDouble(), 100_000.0)
    }

    @Test fun `a duration that agrees is left to the extractor`() {
        assertNull(ProportionalSeekMap.replacing(first32kbps, catalogUs = 245_000_000))
    }

    @Test fun `the shown duration is the catalog's when the player's is unknown or disagrees`() {
        assertEquals(1_421_000L, Mp3Seeking.displayMs(3_770_000, 1_421_000))
        assertEquals(1_421_000L, Mp3Seeking.displayMs(0, 1_421_000))
        assertEquals(1_430_000L, Mp3Seeking.displayMs(1_430_000, 1_421_000))
        assertEquals(1_430_000L, Mp3Seeking.displayMs(1_430_000, null))
    }

    private class FakeMp3 : Extractor {
        lateinit var out: ExtractorOutput
        lateinit var track: TrackOutput
        override fun sniff(input: ExtractorInput) = true
        override fun init(output: ExtractorOutput) {
            out = output
            track = output.track(0, C.TRACK_TYPE_AUDIO)
        }
        override fun read(input: ExtractorInput, seekPosition: PositionHolder) = Extractor.RESULT_END_OF_INPUT
        override fun seek(position: Long, timeUs: Long) {}
        override fun release() {}
    }

    @Test fun `after a seek the samples are stamped by the catalog map, not the first-frame one`() {
        val stamps = mutableListOf<Long>()
        lateinit var published: SeekMap
        val output = object : ExtractorOutput {
            override fun track(id: Int, type: Int) = mockk<TrackOutput>(relaxed = true).also {
                every { it.sampleMetadata(any(), any(), any(), any(), any()) } answers { stamps += firstArg<Long>() }
            }
            override fun endTracks() {}
            override fun seekMap(seekMap: SeekMap) { published = seekMap }
        }
        val fake = FakeMp3()
        val wrapped = CatalogLengthMp3Extractor(fake, catalogUs = 94_000_000)
        wrapped.init(output)
        fake.out.seekMap(first32kbps)
        assertEquals(94_000_000L, published.durationUs)
        fake.track.sampleMetadata(0, C.BUFFER_FLAG_KEY_FRAME, 104, 0, null)
        // Seeking to 47 s asks for the middle byte; the stock extractor stamps it with its own wrong clock (125 s).
        val middle = published.getSeekPoints(47_000_000).first.position
        wrapped.seek(middle, 47_000_000)
        fake.track.sampleMetadata(125_000_000, C.BUFFER_FLAG_KEY_FRAME, 104, 0, null)
        fake.track.sampleMetadata(125_026_000, C.BUFFER_FLAG_KEY_FRAME, 104, 0, null)
        assertEquals(0L, stamps[0])
        assertEquals(47_000_000.0, stamps[1].toDouble(), 100_000.0)
        assertEquals(stamps[1] + 26_000, stamps[2])
    }
}
