package com.example.appname.plays

/**
 * The recorder's cue in a downloaded voice (PLAYS-DESIGN §2.8 engine `kokoro`, §5): a part cast to a Kokoro voice is
 * rendered by [render] (kokoro/KokoroReader.kt, from the play's published phonemes) into a [StandInAudio], in memory,
 * marked synthetic, played by the cue path and released like any stand-in. A line Kokoro cannot read, and every part on
 * a system voice, goes to [system] (which reads a Kokoro part in its auto-cast system voice). No file is touched here.
 */
class KokoroStandIn(
    private val cast: VoiceCast,
    private val system: StandInVoice,
    private val render: suspend (text: String, voiceId: String, speed: Float) -> FloatArray?,
) : StandInVoice {
    override suspend fun render(text: String, part: PartID, rate: Float): StandInAudio? {
        val r = cast.resolve(part)
        val v = r.voice
        if (r.read && v != null && v.engine == VoiceCastEntry.KOKORO) {
            val tempo = r.rate * rate
            val samples = render(text, v.id, (tempo / r.pitch).coerceIn(0.5, 2.0).toFloat())
            if (samples != null && samples.isNotEmpty()) {
                return StandInAudio(Resample.toTakeRate(samples, KOKORO_RATE * r.pitch), TakeAudio.SAMPLE_RATE.toDouble())
            }
        }
        return system.render(text, part, rate)
    }

    private companion object {
        const val KOKORO_RATE = 24_000.0
    }
}
