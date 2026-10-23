package com.example.appname.plays

import java.io.File
import kotlin.math.abs
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Takes are immutable and never overwritten (§8 rule 5), the kept window is the
 * line only (§4.2), and the files sit where Apple puts them (§6).
 *
 * Broken control, 2026-10-23: Production.add appending without moving
 * `chosen` fails the re-take test.
 */
class TakesTest {
    @Test fun `a re-take is chosen and the old take stays until discarded`() {
        val script = fixtureScript()
        val store = ProductionStore(temporaryRoot())
        try {
            var p = store.create(script)
            val capture = MicrophoneCapture(tone(listOf(200.0), 0.2), 48_000.0)
            val first = store.writeTake(capture, p, "L0003")
            val second = store.writeTake(capture, p, "L0003")
            assertNotEquals("a take file is never overwritten", first, second)

            val molly = PartID.role("MOLLY")
            val a = take("a", "L0003", molly, 9_600).copy(file = first, heard = mapOf("L0002" to Take.STAND_IN))
            val b = take("b", "L0003", molly, 9_600).copy(file = second)
            p = p.add(a).add(b)
            assertEquals("the re-take becomes the line's take", "b", p.chosen["L0003"])
            assertEquals("choosing never deletes the old take", listOf("a", "b"), p.takes("L0003").map { it.id })
            p = p.choose("a")
            assertEquals("a", p.chosenTake("L0003")?.id)
            store.save(p)

            store.discardUnusedTakes(p.id)
            val kept = store.production(p.id)!!
            assertEquals(listOf("a"), kept.takes.map { it.id })
            assertEquals("only the unused take's file is removed", listOf(first), store.takesFolder(p.id).list()!!.toList())

            val reloaded = ProductionStore(store.root)
            assertEquals("the record survives a reload", kept, reloaded.production(p.id))
            assertEquals("the script as cast is stored", script.lines.size, reloaded.script(kept)?.lines?.size)

            reloaded.delete(p.id)
            assertFalse("delete removes the folder", reloaded.folder(p.id).exists())
            assertTrue(reloaded.productions.value.isEmpty())
        } finally {
            store.root.deleteRecursively()
        }
    }

    @Test fun `the files have Apple's names and production json Apple's keys`() {
        val store = ProductionStore(temporaryRoot())
        try {
            val p = store.create(fixtureScript())
                .add(take("a", "L0003", PartID.role("MOLLY"), 10))
            store.save(p)
            val folder = store.folder(p.id)
            assertEquals(File(store.root, p.id), folder)
            assertEquals(setOf("script.json", "production.json", "takes", "roomtone"), folder.list()!!.toSet())
            assertEquals("mix.m4a", store.mixFile(p.id).name)
            val record = Json.parseToJsonElement(File(folder, "production.json").readText()).jsonObject
            for (key in listOf("id", "scriptID", "scriptRevision", "title", "created", "parts", "takes", "chosen", "roomTone", "listenedThrough")) {
                assertTrue("production.json has $key", key in record)
            }
            assertTrue("parts are keyed by the raw part id", "role:MOLLY" in record.getValue("parts").jsonObject)
            assertEquals("a", record.getValue("chosen").jsonObject.getValue("L0003").jsonPrimitive.content)
        } finally {
            store.root.deleteRecursively()
        }
    }

    @Test fun `a 24-bit take reads back as written`() {
        val root = temporaryRoot()
        try {
            val samples = tone(listOf(440.0), 0.1, amplitude = 0.8f)
            val file = File(root, "t.wav")
            TakeAudio.write(MicrophoneCapture(samples, 48_000.0), file)
            val (read, rate) = TakeAudio.read(file)
            assertEquals(48_000.0, rate, 0.0)
            assertEquals(samples.size, read.size)
            assertTrue(samples.indices.all { abs(samples[it] - read[it]) < 1e-6f })
        } finally {
            root.deleteRecursively()
        }
    }

    @Test fun `a take is the line window only`() {
        val rate = 48_000.0
        val capture = FloatArray(48_000) + tone(listOf(180.0), 0.5) + FloatArray(72_000)
        val detector = LineEndDetector(rate, 0.0005f)
        val events = ArrayList<LineEndDetector.Event>()
        for (start in capture.indices step 960) {
            detector.feed(capture.copyOfRange(start, minOf(start + 960, capture.size)))?.let { events += it }
        }
        assertEquals(2, events.size)
        val window = LineEndDetector.window(detector.onset, detector.end, capture.size, rate)
        assertTrue("onset less 250 ms", abs(window.first - 36_000) <= 960)
        assertTrue("end plus 250 ms", abs(window.last + 1 - 84_000) <= 960)
    }

    @Test fun `the route asks for headphones on the speaker`() {
        assertEquals(AudioRoute.Speaker, AudioRoute.of(listOf(android.media.AudioDeviceInfo.TYPE_BUILTIN_SPEAKER)))
        assertEquals(
            AudioRoute.Headphones,
            AudioRoute.of(listOf(android.media.AudioDeviceInfo.TYPE_BUILTIN_SPEAKER, android.media.AudioDeviceInfo.TYPE_WIRED_HEADPHONES)),
        )
        assertEquals(AudioRoute.Headphones, AudioRoute.of(listOf(android.media.AudioDeviceInfo.TYPE_BLUETOOTH_A2DP)))
        assertEquals("a hands-free link is not headphones", AudioRoute.Speaker, AudioRoute.of(listOf(android.media.AudioDeviceInfo.TYPE_BLUETOOTH_SCO)))
    }
}
