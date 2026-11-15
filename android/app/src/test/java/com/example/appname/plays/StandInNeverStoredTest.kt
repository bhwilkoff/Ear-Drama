package com.example.appname.plays

import com.example.appname.kokoro.FakeRenderer
import com.example.appname.kokoro.Kokoro
import com.example.appname.kokoro.KokoroModelStore
import com.example.appname.kokoro.KokoroReader
import com.example.appname.kokoro.NO_NETWORK
import com.example.appname.kokoro.downloadedRoot
import com.example.appname.kokoro.phonemeFile
import java.io.File
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.sin
import kotlin.random.Random
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/**
 * A synthetic voice is a live stand-in only, never stored (PLAYS-DESIGN §5,
 * §8 rule 3; Decisions 055 and 059). A whole play is recorded through the real
 * RecordingSession with a fake microphone and a stand-in whose every line is a
 * chirp, then every file in the production folder is searched for those chirps.
 *
 * The scan carries its own negative control ([a leaky microphone is caught]):
 * when the microphone hears the stand-in, the scan must find it in the take and
 * the session's bleed check must flag it.
 *
 * Broken controls, 2026-10-23, each against a mutated copy of plays/:
 *   RecordingSession writing the cue's stand-in samples as the take: the clean
 *   test fails (the scan finds it in every take and in the mix).
 *   RecordingSession keeping the whole capture (no window): the take-length check fails.
 *   A `File(` added to StandIn.kt: the source scan fails.
 */
class StandInNeverStoredTest {
    private class SignatureVoice : StandInVoice {
        val rendered = ArrayList<StandInAudio>()
        override suspend fun render(text: String, part: PartID, rate: Float): StandInAudio {
            val f0 = 500.0 + abs(text.hashCode() % 300)
            val samples = FloatArray(24_000) { i ->
                val t = i / 48_000.0
                0.3f * sin(2 * PI * (f0 * t + 2_500 * t * t)).toFloat()
            }
            return StandInAudio(samples, 48_000.0).also { rendered += it }
        }
    }

    /** Plays nothing and records nothing: the "microphone" is a performer signal, or, when [leaky], the last stand-in played. */
    private class FakeLiveAudio(val leaky: Boolean) : LiveAudio {
        private var lastPlayed = FloatArray(0)
        private var captured = FloatArray(0)
        private var captures = 0
        private val random = Random(7)

        override fun outputRoute() = AudioRoute.Headphones
        override fun start(echoCancelled: Boolean) {}
        override fun stop() {}
        override suspend fun play(cue: CueAudio) {
            if (cue is CueAudio.StandIn) lastPlayed = cue.audio.samples
        }

        override fun beginCapture(onChunk: (FloatArray) -> Unit) {
            captures += 1
            val signal = if (captures == 1) {
                FloatArray(48_000) { random.nextFloat() * 0.001f - 0.0005f } // room tone
            } else {
                val voice = if (leaky && lastPlayed.isNotEmpty()) lastPlayed else tone(listOf(150.0, 175.0), 0.6)
                FloatArray(9_600) + voice + FloatArray(60_000)
            }
            captured = signal
            for (start in signal.indices step 960) onChunk(signal.copyOfRange(start, minOf(start + 960, signal.size)))
        }

        override fun endCapture(): MicrophoneCapture = MicrophoneCapture(captured, 48_000.0).also { captured = FloatArray(0) }
    }

    private class Run(val findings: List<String>, val signatures: Int, val takes: List<Take>)

    private suspend fun recordWholePlay(leaky: Boolean, kokoro: Boolean = false): Run {
        val script = fixtureScript()
        val store = ProductionStore(temporaryRoot())
        try {
            var production = store.create(script)
            val system = SignatureVoice()
            val (voice, rendered) = if (kokoro) kokoroVoice(script, system) else system to system.rendered
            for (part in Relay.order(script).filter { it.isSpeaking }) {
                production = Relay.take(part, null, production, script)
                store.save(production)
                val session = RecordingSession(production, script, part, store, FakeLiveAudio(leaky), voice, wait = {}, announce = {})
                session.begin(echoCancelled = false)
                for (l in session.lines) session.record(l.id)
                session.end()
                if (leaky) {
                    try {
                        Relay.finish(part, store.production(production.id)!!, script)
                        fail("a part whose takes are flagged is not done")
                    } catch (_: Relay.Refusal.LinesMissing) {
                    }
                    production = store.production(production.id)!!
                    break
                }
                production = Relay.finish(part, store.production(production.id)!!, script)
                store.save(production)
            }
            if (leaky) {
                assertFalse("flagged takes leave the play unfinished", Relay.isComplete(production, script))
            } else {
                assertTrue(Relay.isComplete(production, script))
                store.renderMix(production.id) { WavSink(it, 48_000) }
                assertTrue(store.mixFile(production.id).isFile)
            }
            if (kokoro) assertTrue("every cue came from Kokoro, none from the system voice", system.rendered.isEmpty())
            return Run(standInFindings(store.folder(production.id), rendered), rendered.size, store.production(production.id)!!.takes)
        } finally {
            store.root.deleteRecursively()
        }
    }

    /**
     * Every speaking part cast to a downloaded voice, read by the real KokoroReader (published phonemes, tokenizer, guard,
     * marking) over a renderer that returns a chirp per line instead of running the model; the cue path is KokoroStandIn.
     */
    private fun kokoroVoice(script: PlayScript, system: SignatureVoice): Pair<StandInVoice, List<StandInAudio>> {
        val reader = KokoroReader(
            KokoroModelStore(downloadedRoot(File(temporaryRoot(), "kokoro")), NO_NETWORK),
            { phonemeFile(script) },
            { _, _ -> FakeRenderer() },
            kotlinx.coroutines.Dispatchers.Unconfined,
        )
        val cast = VoiceCast("p:kokoro", script.castParts.map { it.id }, { listOf(CastVoice("sys", "System", "en-US", 300)) }, MemoryCastStore(), downloaded = { Kokoro.castable(true) })
        script.castParts.filter { it.id.isSpeaking }.forEachIndexed { i, p ->
            val v = Kokoro.VOICES[i * 5 % Kokoro.VOICES.size]
            cast.set(p.id) { copy(engine = VoiceCastEntry.KOKORO, voice = v.id, name = v.name) }
        }
        val inner = KokoroStandIn(cast, system) { text, id, speed -> reader.render(script.id, text, id, speed) }
        val rendered = ArrayList<StandInAudio>()
        return object : StandInVoice {
            override suspend fun render(text: String, part: PartID, rate: Float): StandInAudio? = inner.render(text, part, rate)?.also { rendered += it }
        } to rendered
    }

    @Test fun `no file holds a Kokoro stand-in`() = runTest {
        val run = recordWholePlay(leaky = false, kokoro = true)
        assertTrue("the first parts were cued by a Kokoro voice", run.signatures > 0)
        assertEquals("no take, room tone, or mix holds a Kokoro line", emptyList<String>(), run.findings)
        assertTrue(run.takes.none { it.bleed })
        assertTrue(run.takes.any { Take.STAND_IN in it.heard.values })
    }

    @Test fun `a leaky microphone is caught with a Kokoro voice too`() = runTest {
        val run = recordWholePlay(leaky = true, kokoro = true)
        assertFalse("the scan must catch a Kokoro line in a file", run.findings.isEmpty())
        assertTrue("the bleed check flags the take", run.takes.any { it.bleed })
    }

    /** A Kokoro render, the whole line or a piece, is refused by every writer, as a system voice's is. */
    @Test fun `a Kokoro buffer is refused by every writer`() = runTest {
        val script = fixtureScript()
        val reader = KokoroReader(KokoroModelStore(downloadedRoot(File(temporaryRoot(), "kokoro")), NO_NETWORK), { phonemeFile(script) }, { _, _ -> FakeRenderer() }, kotlinx.coroutines.Dispatchers.Unconfined)
        val line = reader.render(script.id, "Come in.", "af_heart", 1f)!!
        val pieces = ArrayList<FloatArray>()
        reader.renderPieces(script.id, "Good night.", "bm_george", 1f) { pieces += it }
        val root = temporaryRoot()
        try {
            for ((label, samples) in listOf("line" to line, "piece" to pieces.single(), "resampled" to KokoroStandIn(
                VoiceCast("p:x", script.castParts.map { it.id }, { listOf(CastVoice("sys", "System", "en-US", 300)) }, MemoryCastStore(), downloaded = { Kokoro.castable(true) })
                    .also { c -> c.set(PartID.role("MOLLY")) { copy(engine = VoiceCastEntry.KOKORO, voice = "af_heart", name = "Heart") } },
                SignatureVoice(),
            ) { t, id, s -> reader.render(script.id, t, id, s) }.render("Come in.", PartID.role("MOLLY"), 1f)!!.samples)) {
                try {
                    TakeAudio.write(MicrophoneCapture(samples, 48_000.0), File(root, "$label.wav"))
                    fail("TakeAudio.write accepted a Kokoro $label")
                } catch (_: IllegalStateException) {
                }
                try {
                    val sink = WavSink(File(root, "$label-sink.wav"), 48_000)
                    try { sink.write(samples, samples.size) } finally { sink.abandon() }
                    fail("WavSink accepted a Kokoro $label")
                } catch (_: IllegalStateException) {
                }
            }
        } finally {
            root.deleteRecursively()
        }
    }

    /** Every file in a production folder that holds a stand-in that played, plus any file that is not a record or a WAV. */
    private fun standInFindings(folder: File, signatures: List<StandInAudio>): List<String> {
        val findings = ArrayList<String>()
        folder.walkTopDown().filter { it.isFile }.forEach { file ->
            if (file.extension == "json") return@forEach
            val head = file.inputStream().use { it.readNBytes(4) }
            if (String(head) != "RIFF") {
                findings += "unreadable file ${file.name}"
                return@forEach
            }
            val (samples, rate) = TakeAudio.read(file)
            if (signatures.any { BleedCheck.score(samples, it.samples, rate) >= BleedCheck.THRESHOLD }) findings += file.name
        }
        return findings
    }

    @Test fun `no file holds a stand-in`() = runTest {
        val run = recordWholePlay(leaky = false)
        assertTrue("the first parts were cued by the device voice", run.signatures > 0)
        assertEquals("no take, room tone, or mix holds a stand-in", emptyList<String>(), run.findings)
        assertTrue(run.takes.none { it.bleed })
        assertTrue("a take is the line window, not the whole capture", run.takes.all { it.frames < 60_000 })
        assertTrue(run.takes.any { Take.STAND_IN in it.heard.values })
        assertTrue("later parts heard the earlier performers' takes", run.takes.any { t -> t.heard.values.any { it != Take.STAND_IN } })
    }

    @Test fun `a leaky microphone is caught`() = runTest {
        val run = recordWholePlay(leaky = true)
        assertFalse("the scan must catch a stand-in in a file", run.findings.isEmpty())
        assertTrue("the bleed check flags the take", run.takes.any { it.bleed })
    }

    /** Batch 0b: a device voice's PCM can never reach a take, room-tone, mix or export writer. */
    @Test fun `a synthetic buffer is refused by every writer`() {
        val voice = StandInAudio(FloatArray(4_800) { 0.2f }, 48_000.0)
        val root = temporaryRoot()
        try {
            fun refused(label: String, block: () -> Unit) {
                try {
                    block()
                    fail("$label accepted a device voice")
                } catch (_: IllegalStateException) {
                }
            }
            refused("TakeAudio.write") { TakeAudio.write(MicrophoneCapture(voice.samples, 48_000.0), File(root, "a.wav")) }
            refused("WavSink") {
                val sink = WavSink(File(root, "b.wav"), 48_000)
                try { sink.write(voice.samples, voice.samples.size) } finally { sink.abandon() }
            }
            val store = ProductionStore(root)
            val production = store.create(fixtureScript())
            refused("writeTake") { store.writeTake(MicrophoneCapture(voice.samples, 48_000.0), production, "L0002") }
            refused("writeRoomTone") { store.writeRoomTone(MicrophoneCapture(voice.samples, 48_000.0), production) }
            assertTrue("nothing was left on disk", store.takesFolder(production.id).listFiles().orEmpty().isEmpty())
            val human = MicrophoneCapture(tone(listOf(150.0), 0.1), 48_000.0)
            TakeAudio.write(human, File(root, "human.wav"))
            assertTrue(File(root, "human.wav").isFile)
            val sources = File("src/main/java/com/example/appname/plays")
            assertTrue("the AAC mix writer checks too", File(sources, "MixEncoder.kt").readText().contains("SyntheticPCM.refuse(samples)"))
        } finally {
            root.deleteRecursively()
        }
    }

    @Test fun `a listen plan holds text, never audio`() {
        val script = fixtureScript()
        val plan = Relay.listenPlan(Production.create(script), script)
        assertTrue(plan.isNotEmpty())
        assertTrue(plan.all { it is Relay.ListenEntry.Voice })
        for (entry in plan) {
            val fields = entry::class.java.declaredFields
            assertTrue("${entry::class.simpleName} holds audio", fields.none { it.type.isArray || it.type == StandInAudio::class.java })
        }
        val live = File("src/main/java/com/example/appname/plays/LiveListen.kt").readText()
        assertFalse("the live listen never synthesizes to a file", live.contains("synthesizeToFile"))
        val voices = File("src/main/java/com/example/appname/plays/VoiceCast.kt").readText()
        assertTrue("the voices cast are local ones only", voices.contains("!it.networkRequired") && File("src/main/java/com/example/appname/plays/DeviceVoices.kt").readText().contains("isNetworkConnectionRequired"))
        assertFalse("the cast speaker never synthesizes to a file", File("src/main/java/com/example/appname/plays/DeviceVoices.kt").readText().contains("synthesizeToFile"))
    }

    /** Only the take and mix writers write audio, and the stand-in source touches no file at all. */
    @Test fun `only the take and mix writers write audio`() {
        val sources = File("src/main/java").walkTopDown().filter { it.extension == "kt" }.toList()
        assertTrue("no sources found from ${File(".").absolutePath}", sources.size > 10)
        val offenders = sources.flatMap { writeViolations(it.path, withoutComments(it.readText())) }
        assertEquals(emptyList<String>(), offenders)
        // The guard's controls: a file writer in the stand-in source, and an audio writer anywhere else, are caught.
        assertEquals(listOf("plays/StandIn.kt"), writeViolations("x/plays/StandIn.kt", "val f = File(cacheDir, \"line.wav\")"))
        assertEquals(listOf("plays/StandIn.kt"), writeViolations("x/plays/StandIn.kt", "TakeAudio.write(capture, file)"))
        assertEquals(listOf("screens/Other.kt"), writeViolations("x/ui/screens/Other.kt", "WavSink(file, 48_000)"))
        assertEquals(listOf("ui/Other.kt"), writeViolations("x/ui/Other.kt", "tts.synthesizeToFile(text, params, file, id)"))
        // Kokoro (S6d): the sources that hold rendered audio touch no file writer, and the model store holds no audio.
        assertTrue("the Kokoro sources are where the guard looks", kokoroAudio.all { File("src/main/java/com/example/appname/$it").isFile })
        assertEquals(listOf("kokoro/KokoroEngine.kt"), writeViolations("x/kokoro/KokoroEngine.kt", "val f = File(dir, \"line.pcm\")"))
        assertEquals(listOf("kokoro/KokoroReader.kt"), writeViolations("x/kokoro/KokoroReader.kt", "paths.voices.writeBytes(samples)"))
        assertEquals(listOf("kokoro/KokoroLive.kt"), writeViolations("x/kokoro/KokoroLive.kt", "FileOutputStream(f).use { }"))
        assertEquals(listOf("plays/KokoroStandIn.kt"), writeViolations("x/plays/KokoroStandIn.kt", "RandomAccessFile(f, \"rw\")"))
        assertEquals(listOf("kokoro/KokoroModelStore.kt"), writeViolations("x/kokoro/KokoroModelStore.kt", "fun keep(samples: FloatArray) {}"))
        assertEquals(emptyList<String>(), writeViolations("x/kokoro/KokoroModelStore.kt", "RandomAccessFile(part, \"rw\")"))
    }

    /** Kokoro's audio path: rendered in memory, played once, handed to the cue; never near a file writer (Decision 078). */
    private val kokoroAudio = listOf("kokoro/KokoroEngine.kt", "kokoro/KokoroReader.kt", "kokoro/KokoroLive.kt", "plays/KokoroStandIn.kt")
    private val kokoroForbidden = listOf(
        "FileOutputStream", "RandomAccessFile", "outputStream(", "writeBytes", "writeText", "appendBytes", "filesDir", "cacheDir",
        "WavSink", "TakeAudio.write", "MediaMuxer", "AacMixSink", "synthesizeToFile",
    )

    /** The model store downloads model bytes only: no audio type may appear in it. */
    private val modelStoreForbidden = listOf("FloatArray", "AudioTrack", "StandInAudio", "SyntheticPCM", "KokoroRenderer")

    private val audioWriters = mapOf(
        "FileOutputStream" to setOf("plays/PlayFiles.kt"),
        "RandomAccessFile" to setOf("plays/PlayFiles.kt"),
        "WavSink(" to setOf("plays/PlayFiles.kt"),
        "TakeAudio.write(" to setOf("plays/PlayFiles.kt"),
        "MediaMuxer" to setOf("plays/MixEncoder.kt"),
        "AacMixSink(" to setOf("plays/MixEncoder.kt", "plays/PlaysLibrary.kt"),
        "synthesizeToFile(" to setOf("plays/StandIn.kt"),
    )

    /** Tokens the stand-in source may never hold: it reaches the engine through a pipe and memory only. */
    private val standInForbidden = listOf("java.io.", "FileOutputStream", "filesDir", "cacheDir", "writeBytes", "writeText", "WavSink", "TakeAudio.write", "MediaMuxer")

    /** Code only: a comment may name a writer it explains. */
    private fun withoutComments(source: String): String =
        source.replace(Regex("""/\*[\s\S]*?\*/"""), "").replace(Regex("""(?m)^\s*//.*$"""), "")

    private fun writeViolations(path: String, source: String): List<String> {
        val name = path.replace('\\', '/').split('/').takeLast(2).joinToString("/")
        val inPlays = path.contains("/plays/") || name.startsWith("plays/")
        val bad = audioWriters.any { (token, allowed) ->
            val scoped = token == "FileOutputStream" || token == "RandomAccessFile"
            (inPlays || !scoped) && source.contains(token) && name !in allowed
        } || (name == "plays/StandIn.kt" && (standInForbidden.any { source.contains(it) } || Regex("""(?<![A-Za-z])File\(""").containsMatchIn(source))) ||
            (name in kokoroAudio && (kokoroForbidden.any { source.contains(it) } || Regex("""(?<![A-Za-z])File\(""").containsMatchIn(source))) ||
            (name == "kokoro/KokoroModelStore.kt" && modelStoreForbidden.any { source.contains(it) })
        return if (bad) listOf(name) else emptyList()
    }
}
