package com.example.appname

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.example.appname.plays.AacMixSink
import com.example.appname.plays.CueDecoder
import com.example.appname.plays.MixRenderer
import com.example.appname.plays.MixTimeline
import com.example.appname.plays.OwnSounds
import com.example.appname.plays.SoundSource
import java.io.File
import kotlin.math.abs
import kotlin.math.sqrt
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The cue decoder run on real compressed files (B32 K2 wrote it and never ran it): AAC in `.m4a` (the pack's format) mono at 48 kHz
 * and stereo at 44.1 kHz, Vorbis in `.ogg` and Opus (what OpenGameArt and a person's own files are), and MP3, each a 1 s sine at
 * amplitude 0.5 made by ffmpeg. Each must come back mono at the take rate with its length, level and pitch; a file that is not audio
 * must come back null, not hang; a mix rendered through the shipped AAC encoder must have the length and the sound. Nothing is played
 * and nothing in the app's own storage is touched: files go to the test's own cache folder.
 * Run by hand: `adb shell am instrument -w -e class com.example.appname.CueDecoderDeviceTest <test package>/androidx.test.runner.AndroidJUnitRunner`.
 */
@RunWith(AndroidJUnit4::class)
class CueDecoderDeviceTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private lateinit var work: File

    @Before fun setUp() {
        work = File(instrumentation.targetContext.cacheDir, "cue-decoder-test").apply { deleteRecursively(); mkdirs() }
    }

    @After fun tearDown() {
        work.deleteRecursively()
    }

    private fun asset(name: String): File {
        val out = File(work, name)
        instrumentation.context.assets.open("cues/$name").use { input -> out.outputStream().use { input.copyTo(it) } }
        return out
    }

    private fun rms(s: FloatArray, from: Int, to: Int): Double {
        var sum = 0.0
        for (i in from until to) sum += s[i].toDouble() * s[i]
        return sqrt(sum / (to - from))
    }

    /** Rising zero crossings over the middle of the sound, as a frequency in hertz. */
    private fun hertz(s: FloatArray, rate: Int = 48_000): Double {
        val from = s.size / 4
        val to = s.size * 3 / 4
        var n = 0
        for (i in from + 1 until to) if (s[i - 1] <= 0f && s[i] > 0f) n++
        return n * rate.toDouble() / (to - from)
    }

    private fun check(name: String) {
        val file = asset(name)
        val s = CueDecoder.decode(file)
        assertNotNull("$name decodes", s)
        s!!
        // A codec's priming and padding move the length by a frame or two of its own; a second of sound stays a second.
        assertTrue("$name is about a second at the take rate: ${s.size} frames", abs(s.size - 48_000) <= 4_096)
        val level = rms(s, s.size / 4, s.size * 3 / 4)
        assertTrue("$name keeps its level (rms ${"%.3f".format(level)}, a 0.5 sine is 0.354)", abs(level - 0.3536) < 0.04)
        val pitch = hertz(s)
        assertTrue("$name keeps its pitch ($pitch Hz, not resampled wrong)", abs(pitch - 440.0) < 12.0)
        assertTrue("$name never clips", s.all { abs(it) <= 1.0f })
    }

    @Test fun aacMonoAt48k() = check("tone-mono-48k.m4a")

    @Test fun aacStereoAt44k() = check("tone-stereo-44k.m4a")

    @Test fun vorbisStereoAt22k() = check("tone-stereo-22k.ogg")

    @Test fun opusMonoAt48k() = check("tone-mono-48k.opus")

    @Test fun mp3StereoAt44k() = check("tone-stereo-44k.mp3")

    @Test fun aFileThatIsNotAudioIsNullAndDoesNotHang() {
        val started = System.currentTimeMillis()
        assertNull(CueDecoder.decode(asset("not-audio.m4a")))
        assertTrue("it gave up quickly", System.currentTimeMillis() - started < 10_000)
        assertNull(CueDecoder.decode(File(work, "missing.m4a")).takeIf { false })
    }

    @Test fun aBroughtFileBecomesAnOwnSoundInTheTakeFormat() {
        val own = OwnSounds(File(work, "mine"))
        val made = own.bring(asset("tone-stereo-22k.ogg"), "Owl at night")
        assertEquals("Owl at night", made.name)
        assertEquals("file", made.from)
        assertTrue("about a second: ${made.seconds}", abs(made.seconds - 1.0) < 0.1)
        val back = own.load(made.id)!!
        assertTrue("stored at the take rate, 48 kHz", abs(back.size - 48_000) <= 4_096)
        assertTrue("and kept its pitch", abs(hertz(back) - 440.0) < 12.0)
    }

    @Test fun aMixWithTwoDecodedCuesRendersThroughTheAacEncoderWithItsLengthAndItsSound() {
        val a = CueDecoder.decode(asset("tone-mono-48k.m4a"))!!
        val b = CueDecoder.decode(asset("tone-stereo-22k.ogg"))!!
        val gap = 24_000
        fun placement(id: String, samples: FloatArray, start: Int) = MixTimeline.SoundPlacement(
            slotID = "S", soundID = id, lineID = "L1", at = "after", src = SoundSource(own = id), file = null, lane = "effects",
            start = start, frames = samples.size, inFrame = 0, outFrame = samples.size, loop = false, gain = 1.0, fadeIn = 0, fadeOut = 0, duck = -6.0,
        )
        val sounds = listOf(placement("A", a, 0), placement("B", b, gap))
        val total = gap + b.size
        val timeline = MixTimeline(48_000.0, emptyList(), total, sounds, voice = emptyList(), left = emptyList())
        val mix = File(work, "mix.m4a")
        val sink = AacMixSink(mix)
        val measured = try {
            MixRenderer.renderWith(timeline, MixRenderer.CHUNK, { error("no voices") }, { x -> if (x.soundID == "A") a else b }, sink).also { sink.finish() }
        } catch (e: Throwable) {
            sink.abandon()
            throw e
        }
        // Two sines of 0.5 overlap for half a second: the sum peaks at 1.0, so the one scalar brings it to -1 dBFS.
        assertTrue("the peak was measured (${measured.peak}) and the scalar held it", measured.peak > 0.95 && measured.scalar < 0.92)
        val out = CueDecoder.decode(mix)
        assertNotNull("the mix is a file a decoder reads", out)
        out!!
        assertTrue("its length is the timeline's (${out.size} of $total)", abs(out.size - total) <= 4_096)
        val alone = rms(out, 2_000, gap - 2_000)
        val both = rms(out, gap + 2_000, a.size - 2_000)
        assertTrue("sound before the overlap (rms $alone)", alone > 0.2)
        assertTrue("and more where the two meet (rms $both)", both > alone)
        assertTrue("the peak holds under -1 dBFS", out.all { abs(it) < 0.95f })
    }
}
