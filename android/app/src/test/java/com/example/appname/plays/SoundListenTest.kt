package com.example.appname.plays

import java.io.File
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The Sound part in a live listen and Hear it in place (B32 section 4.4; the case-for-case mirror of the live-listen tests in
 * js/sound.test.js and SoundListenTests in SoundBoardTests.swift). Fakes stand for the speaker, the take player and the cue player.
 *
 * Broken controls, 2026-11-26, each seen to fail one test: a bed's stop placed at its own entry (the first test); the range
 * ignored (the in-place test).
 */
class SoundListenTest {
    private fun say(id: String, role: String, vararg parts: LinePart) = ScriptLine(id, ScriptLine.Kind.Speech, role, parts.toList())
    private fun s(text: String) = LinePart.Say(text)

    private fun radio() = PlayScript(
        id = "fixture-radio", revision = "1", kind = "radio", title = "A ride in the rain",
        source = PlayScript.Source("x", "https://example.org"), rights = PlayScript.Rights("castable"),
        roles = listOf(PlayScript.Role("URIAH", 3, 20), PlayScript.Role("RODNEY", 3, 20)),
        lines = listOf(
            say("L0001", "URIAH", s("We got to make it, rain or no rain.")),
            say("L0002", "RODNEY", s("It's sprinkling.")),
            say("L0003", "URIAH", s("I felt it."), LinePart.Sound("another peal of thunder closer")),
            say("L0004", "RODNEY", LinePart.Direction("Sound of rain and wind"), s("I guess it is on us.")),
            say("L0005", "URIAH", s("Here, draw up your horse!")),
            ScriptLine("L0006", ScriptLine.Kind.Direction, source = "They ride off."),
            say("L0007", "RODNEY", s("Giddap!")),
        ),
    )

    private fun take(lineID: String, role: String) = Take(
        id = "t-$lineID", lineID = lineID, part = PartID.role(role), file = "t-$lineID.wav", created = 1.0, frames = 24000, sampleRate = 48000.0,
        capture = Take.Capture.Direct, heard = emptyMap(), peak = 0.5f, bleed = false,
    )

    private fun pack(cue: String) = SoundSource(pack = "x", cue = cue)

    /** Every speech line taken; thunder After line 3; rain as a bed from line 4 until line 5. */
    private fun production(): Pair<Production, String> {
        val script = radio()
        var p = Production.create(script, "P1")
        for (l in script.lines.filter { it.kind == ScriptLine.Kind.Speech }) {
            p = p.copy(takes = p.takes + take(l.id, l.role!!), chosen = p.chosen + (l.id to "t-${l.id}"))
        }
        val slots = SoundCore.slotsOf(script, p)
        val (p1, id3) = SoundCore.ensure(p, slots[0])
        val p2 = SoundCore.addSound(p1, script, id3, pack("thunder")).first
        val (p3, id4) = SoundCore.ensure(p2, slots[1])
        val (p4, bed) = SoundCore.addSound(p3, script, id4, pack("rain"), kind = "ambience")
        return SoundCore.updateSound(p4, id4, bed!!, SoundCore.Patch(until = "L0005")) to bed
    }

    @Test fun `cues play at their lines, a bed stops at its Until, and Hear it in place is the line before to the line after`() {
        val script = radio()
        val (p, bed) = production()
        val plan = Relay.listenPlan(p, script)
        assertEquals(listOf("L0001", "L0002", "L0003", "L0004", "L0005", "L0007"), plan.map { it.lineID })
        val cues = SoundCore.listenCues(script, p, plan)
        assertEquals("the After thunder follows line 3", listOf(pack("thunder")), cues[2].after.map { it.sound.src })
        assertEquals("the bed starts with line 4", listOf(pack("rain")), cues[3].under.map { it.sound.src })
        assertEquals("and stops after line 5, its Until", listOf(bed), cues[4].stop)
        assertTrue("no other entry plays a sound", listOf(0, 1, 5).all { i -> cues[i].before.isEmpty() && cues[i].under.isEmpty() && cues[i].after.isEmpty() && cues[i].stop.isEmpty() })
        val range = SoundCore.inPlace(script, plan, "L0003")!!
        assertEquals(listOf("L0002", "L0004"), listOf(plan[range.first].lineID, plan[range.last].lineID))
        val gap = SoundCore.addSlot(p, "L0006")
        val q = SoundCore.addSound(gap.first, script, gap.second, pack("hooves")).first
        assertEquals("a slot on a line the plan skips plays with the next entry", listOf(pack("hooves")), SoundCore.listenCues(script, q, plan)[5].before.map { it.sound.src })
    }

    private class Fakes {
        val log = ArrayList<String>()

        val speaker = object : LineSpeaker {
            override fun reads(part: PartID) = true
            override suspend fun speak(text: String, part: PartID): Boolean { log += "voice"; return true }
            override fun cancel() {}
        }

        val cues = object : ListenCuePlayer {
            override fun start(cue: SoundCore.LiveCue, file: File?): LiveCueHandle? {
                val name = cue.sound.src.cue!!
                log += "start $name"
                val end = CompletableDeferred<Unit>()
                if (!cue.sound.loop && cue.sound.at != "bed") end.complete(Unit)
                return object : LiveCueHandle {
                    override val soundID = cue.sound.id
                    override val isBed = cue.sound.at == "bed"
                    override fun duck(on: Boolean) { log += "duck ${if (on) "on" else "off"} $name" }
                    override fun stop() { log += "stop $name"; end.complete(Unit) }
                    override suspend fun done() = end.await()
                }
            }

            override fun stopAll() { log += "stopAll" }
        }

        fun listen() = LiveListen(File("takes"), speaker, takePlayer = { log += "take" })
    }

    @Test fun `a listen with cues starts each at its entry, ducks a bed under the line, and stops it at its Until`() = runBlocking {
        val script = radio()
        val (p, _) = production()
        val plan = Relay.listenPlan(p, script)
        val f = Fakes()
        f.listen().run(plan, ListenCues(SoundCore.listenCues(script, p, plan), { File("cue.wav") }, f.cues))
        val at = f.log::indexOf
        assertTrue("the After thunder starts once line 3 has played", at("start thunder") > 0 && f.log[at("start thunder") - 1] == "take")
        assertEquals("the bed starts with line 4 and ducks under it", "duck on rain", f.log[at("start rain") + 1])
        assertTrue("and stops after line 5, its Until", at("stop rain") > at("start rain") && "take" in f.log.subList(at("stop rain") - 3, at("stop rain")))
        assertEquals("every take played", 6, f.log.count { it == "take" })
        assertEquals("a listen ends by stopping every cue", "stopAll", f.log.last())
    }

    @Test fun `Hear it in place plays only its range of entries, with the cues that fall in it`() = runBlocking {
        val script = radio()
        val (p, _) = production()
        val plan = Relay.listenPlan(p, script)
        val f = Fakes()
        val range = SoundCore.inPlace(script, plan, "L0003")!!
        f.listen().run(plan, ListenCues(SoundCore.listenCues(script, p, plan), { File("cue.wav") }, f.cues), range)
        assertEquals("lines 2, 3 and 4", 3, f.log.count { it == "take" })
        assertTrue("the thunder after line 3 is heard", "start thunder" in f.log)
        assertTrue("the bed that starts at line 4 starts", "start rain" in f.log)
    }

    @Test fun `a listen without cues plays the plan as before`() = runBlocking {
        val script = radio()
        val (p, _) = production()
        val plan = Relay.listenPlan(p, script)
        val f = Fakes()
        f.listen().run(plan)
        assertEquals(List(6) { "take" }, f.log)
    }
}
