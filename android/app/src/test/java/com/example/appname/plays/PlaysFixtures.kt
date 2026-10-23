package com.example.appname.plays

import java.io.File
import java.nio.file.Files
import kotlin.math.PI
import kotlin.math.sin

// Fixtures for the plays tests, the same play apple/Tests/PlaysTests.swift uses.

private fun line(id: String, role: String?, kind: ScriptLine.Kind = ScriptLine.Kind.Speech, text: String = "words") =
    if (kind == ScriptLine.Kind.Speech) {
        ScriptLine(id, kind, role = role, parts = listOf(LinePart.Say(text)))
    } else {
        ScriptLine(id, kind, source = text)
    }

/** MOLLY 5 lines, FIBBER 3, DOC 1, one sound cue, one direction. */
fun fixtureScript(): PlayScript {
    val lines = listOf(
        line("L0001", null, ScriptLine.Kind.Direction, "(A kitchen.)"),
        line("L0002", "FIBBER", text = "Well, Molly."),
        line("L0003", "MOLLY", text = "Yes, dearie?"),
        line("L0004", null, ScriptLine.Kind.Sound, "SOUND: DOOR OPENS"),
        line("L0005", "DOC", text = "Anybody home?"),
        line("L0006", "MOLLY", text = "Come in."),
        line("L0007", "MOLLY", text = "Sit down."),
        line("L0008", "FIBBER", text = "Doc!"),
        line("L0009", "MOLLY", text = "Tea?"),
        line("L0010", "FIBBER", text = "Not for me."),
        line("L0011", "MOLLY", text = "Good night."),
    )
    val roles = listOf("MOLLY", "FIBBER", "DOC").map { name -> PlayScript.Role(name, lines.count { it.role == name }, 2) }
    return PlayScript(
        id = "gut-0", revision = "r1", kind = "radio", title = "Good Grammar",
        source = PlayScript.Source("Fixture", "https://example.org"),
        rights = PlayScript.Rights("script_source_cleared"), roles = roles, lines = lines,
    )
}

fun temporaryRoot(): File = Files.createTempDirectory("plays-tests").toFile()

fun tone(hz: List<Double>, seconds: Double, amplitude: Float = 0.3f, rate: Double = 48_000.0): FloatArray =
    FloatArray((seconds * rate).toInt()) { i ->
        val t = i / rate
        amplitude * (hz.sumOf { sin(2 * PI * it * t) } / hz.size).toFloat()
    }

fun take(id: String, line: String, part: PartID, frames: Int, loudness: Double? = -16.0, peak: Float = 0.5f, bleed: Boolean = false) =
    Take(id, line, part, "$id.wav", 0.0, frames, 48_000.0, Take.Capture.Direct, emptyMap(), loudness, peak, bleed)

/** Every speaking line of the fixture given one take of [frames]. */
fun completeProduction(script: PlayScript, frames: Int = 4_800): Production {
    var p = Production.create(script)
    for (l in script.lines.filter { it.kind == ScriptLine.Kind.Speech }) p = p.add(take("t-${l.id}", l.id, l.part, frames))
    return p
}

/** Collects a render in memory. */
class MemorySink : MixSink {
    val samples = ArrayList<Float>()
    var finished = false
    override fun write(samples: FloatArray, count: Int) { for (i in 0 until count) this.samples += samples[i] }
    override fun finish() { finished = true }
    override fun abandon() {}
}
