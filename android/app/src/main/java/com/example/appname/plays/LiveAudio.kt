package com.example.appname.plays

import android.annotation.SuppressLint
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.os.Handler
import android.os.Looper
import java.io.File
import kotlin.concurrent.thread
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

/** Where the device's sound goes (PLAYS-DESIGN §4.1 route check). */
enum class AudioRoute {
    /** Wired, Bluetooth A2DP or LE, or USB headphones. */
    Headphones,
    Speaker,
    ;

    companion object {
        // A device type newer than the OS is simply never listed by it; the constant is an inlined int.
        @SuppressLint("InlinedApi")
        private val HEADPHONES = setOf(
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
            AudioDeviceInfo.TYPE_WIRED_HEADSET,
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
            AudioDeviceInfo.TYPE_USB_HEADSET,
            AudioDeviceInfo.TYPE_BLE_HEADSET,
        )

        /** The route for the output device types `AudioManager.getDevices(GET_DEVICES_OUTPUTS)` lists. */
        fun of(outputTypes: Collection<Int>): AudioRoute = if (outputTypes.any { it in HEADPHONES }) Headphones else Speaker
    }
}

/** What plays to the performer before their line. */
sealed interface CueAudio {
    class StandIn(val audio: StandInAudio) : CueAudio
    class TakeFile(val file: File) : CueAudio
}

/** The recording device seam: the app's is AudioRecord and AudioTrack; the tests' plays nothing aloud and records nothing. */
interface LiveAudio {
    fun outputRoute(): AudioRoute
    fun start(echoCancelled: Boolean)
    suspend fun play(cue: CueAudio)
    /** Microphone chunks, mono at the take rate, delivered on the main thread. */
    fun beginCapture(onChunk: (FloatArray) -> Unit)
    fun endCapture(): MicrophoneCapture
    fun stop()

    /** Ends the cue now playing (Run through's Pause). */
    fun stopPlayback() {}
}

/**
 * The microphone and the performer's ears (research 08a §4.3). Headphones on:
 * `VOICE_PERFORMANCE`, the source Android 10 made for capture with live
 * monitoring. Without headphones: `VOICE_COMMUNICATION` with the platform's
 * `AcousticEchoCanceler`, and the cue played as voice-call audio so the
 * canceller hears it as its reference. Only the microphone is ever written,
 * and only as a take. The built-in or wired microphone is preferred over a
 * Bluetooth one, whose hands-free link is narrowband (§4.3).
 */
class DeviceLiveAudio(context: Context) : LiveAudio {
    private val audioManager = context.getSystemService(AudioManager::class.java)
    private val main = Handler(Looper.getMainLooper())
    private var record: AudioRecord? = null
    private var echo: AcousticEchoCanceler? = null
    private var echoCancelled = false
    private var previousMode = AudioManager.MODE_NORMAL
    @Volatile private var running = false
    private var reader: Thread? = null
    @Volatile private var onChunk: ((FloatArray) -> Unit)? = null
    @Volatile private var playbackStopped = false
    private val lock = Any()
    private val captured = ArrayList<FloatArray>()

    override fun outputRoute(): AudioRoute =
        AudioRoute.of(audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).map { it.type })

    override fun start(echoCancelled: Boolean) {
        if (running) return
        this.echoCancelled = echoCancelled
        val rate = TakeAudio.SAMPLE_RATE
        val minimum = AudioRecord.getMinBufferSize(rate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_FLOAT)
        val source = if (echoCancelled) MediaRecorder.AudioSource.VOICE_COMMUNICATION else MediaRecorder.AudioSource.VOICE_PERFORMANCE
        val recorder = try {
            AudioRecord(source, rate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_FLOAT, maxOf(minimum, rate / 5 * 4))
        } catch (e: SecurityException) {
            throw IllegalStateException("The microphone is not allowed.", e)
        }
        check(recorder.state == AudioRecord.STATE_INITIALIZED) { "The microphone could not be opened." }
        audioManager.getDevices(AudioManager.GET_DEVICES_INPUTS)
            .firstOrNull { it.type == AudioDeviceInfo.TYPE_WIRED_HEADSET || it.type == AudioDeviceInfo.TYPE_USB_HEADSET }
            ?.let { recorder.setPreferredDevice(it) }
            ?: audioManager.getDevices(AudioManager.GET_DEVICES_INPUTS)
                .firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_MIC }?.let { recorder.setPreferredDevice(it) }
        if (echoCancelled) {
            previousMode = audioManager.mode
            audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
            if (AcousticEchoCanceler.isAvailable()) {
                echo = AcousticEchoCanceler.create(recorder.audioSessionId)?.also { it.enabled = true }
            }
        }
        recorder.startRecording()
        record = recorder
        running = true
        reader = thread(name = "plays-microphone", priority = Thread.MAX_PRIORITY) {
            val chunk = FloatArray(960)
            while (running) {
                val n = recorder.read(chunk, 0, chunk.size, AudioRecord.READ_BLOCKING)
                if (n <= 0) continue
                val listener = onChunk ?: continue
                val copy = chunk.copyOf(n)
                synchronized(lock) { captured += copy }
                main.post { listener(copy) }
            }
        }
    }

    override suspend fun play(cue: CueAudio) {
        if (!running) return
        val samples = when (cue) {
            is CueAudio.StandIn -> cue.audio.samples
            is CueAudio.TakeFile -> withContext(Dispatchers.IO) { runCatching { TakeAudio.read(cue.file).first }.getOrNull() }
        } ?: return
        if (samples.isEmpty()) return
        playbackStopped = false
        val usage = if (echoCancelled) AudioAttributes.USAGE_VOICE_COMMUNICATION else AudioAttributes.USAGE_MEDIA
        val track = AudioTrack.Builder()
            .setAudioAttributes(AudioAttributes.Builder().setUsage(usage).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
            .setAudioFormat(
                AudioFormat.Builder().setEncoding(AudioFormat.ENCODING_PCM_FLOAT).setSampleRate(TakeAudio.SAMPLE_RATE)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build(),
            )
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()
        try {
            track.play()
            withContext(Dispatchers.IO) { track.write(samples, 0, samples.size, AudioTrack.WRITE_BLOCKING) }
            // The written audio is still in the track's buffer; wait for it to be heard.
            val deadline = System.currentTimeMillis() + 2_000 + samples.size * 1000L / TakeAudio.SAMPLE_RATE
            while (!playbackStopped && track.playbackHeadPosition < samples.size && System.currentTimeMillis() < deadline) delay(20)
        } finally {
            track.stop()
            track.release()
        }
    }

    override fun stopPlayback() {
        playbackStopped = true
    }

    override fun beginCapture(onChunk: (FloatArray) -> Unit) {
        synchronized(lock) { captured.clear() }
        this.onChunk = onChunk
    }

    override fun endCapture(): MicrophoneCapture {
        onChunk = null
        val all = synchronized(lock) {
            val total = captured.sumOf { it.size }
            val out = FloatArray(total)
            var at = 0
            for (c in captured) { c.copyInto(out, at); at += c.size }
            captured.clear()
            out
        }
        return MicrophoneCapture(all, TakeAudio.SAMPLE_RATE.toDouble())
    }

    override fun stop() {
        if (!running) return
        running = false
        onChunk = null
        record?.let { runCatching { it.stop() } }
        reader?.join(1_000)
        reader = null
        record?.release()
        record = null
        echo?.release()
        echo = null
        if (echoCancelled) audioManager.mode = previousMode
    }
}
