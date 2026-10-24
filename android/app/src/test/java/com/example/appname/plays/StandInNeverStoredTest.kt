package com.example.appname.plays

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

    private suspend fun recordWholePlay(leaky: Boolean): Run {
        val script = fixtureScript()
        val store = ProductionStore(temporaryRoot())
        try {
            var production = store.create(script)
            val voice = SignatureVoice()
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
            return Run(standInFindings(store.folder(production.id), voice.rendered), voice.rendered.size, store.production(production.id)!!.takes)
        } finally {
            store.root.deleteRecursively()
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
        assertTrue("the live listen uses only local voices", live.contains("!it.isNetworkConnectionRequired"))
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
    }

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
        } || (name == "plays/StandIn.kt" && (standInForbidden.any { source.contains(it) } || Regex("""(?<![A-Za-z])File\(""").containsMatchIn(source)))
        return if (bad) listOf(name) else emptyList()
    }
}
