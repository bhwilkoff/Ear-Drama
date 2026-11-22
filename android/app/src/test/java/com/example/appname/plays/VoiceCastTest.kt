package com.example.appname.plays

import java.io.File
import java.util.Locale
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Casting the device voices (PLAYS-DESIGN §2.8, Decision 076 S2), the Kotlin mirror of js/voice-cast.test.js, run against
 * the shipped plays/VoiceCast.kt and plays/TableRead.kt with fake voices and a recording engine: nothing here speaks.
 *
 * The players themselves (SystemStandInVoice, CastSpeaker) are bound to android.speech.tts, so each reaches its engine through
 * [prepare], the one seam, over a [VoiceSetter]; the tests drive that seam as each player does, and a source scan holds the
 * players to it.
 *
 * Seen to fail, 2026-11-14, against a mutated VoiceCast.kt (restored after): autoCast over the reversed voice list (8 of 16 tests
 * failed, among them "the best voice to the largest part" and "one cast everywhere"); resolve() returning the stored voice without
 * checking the device has it (the fallback test); prepare() dropping the session's rate (the speed test). The shared-cast test
 * carries its own control: two players that assign by who spoke first, as the code before S2 did, still disagree.
 */
class VoiceCastTest {
    private fun raw(name: String, tag: String, quality: Int, network: Boolean = false, missing: Boolean = false, default: Boolean = false) =
        RawVoice(name, tag, quality, network, missing, default)

    private val device = listOf(
        raw("en-us-x-cloud", "en-US", 500, network = true),
        raw("en-gb-x-rjs-local", "en-GB", 300),
        raw("en-us-x-tpd-local", "en-US", 400),
        raw("en-us-x-sfg-local", "en-US", 300, default = true),
        raw("fr-fr-x-vlf-local", "fr-FR", 500),
        raw("en-au-x-aua-local", "en-AU", 400),
        raw("en-in-x-ahp-local", "en-IN", 500, missing = true),
    )

    private fun voices(list: List<RawVoice> = device) = VoiceCasting.castable(list, Locale.US)

    private fun script(vararg names: String): PlayScript {
        val base = fixtureScript()
        val map = mapOf("MOLLY" to names.getOrElse(0) { "MOLLY" }, "FIBBER" to names.getOrElse(1) { "FIBBER" }, "DOC" to names.getOrElse(2) { "DOC" })
        return base.copy(lines = base.lines.map { l -> l.copy(role = l.role?.let { map.getValue(it) }) })
    }

    private fun parts(s: PlayScript = script()) = s.castParts.map { it.id }

    private fun caster(
        key: String = "p:P1",
        s: PlayScript = script(),
        store: CastStore = MemoryCastStore(),
        source: () -> List<CastVoice> = { voices() },
        seed: String? = null,
    ) = VoiceCast(key, parts(s), source, store, seed)

    /** Records what a player sets on its engine, as the system engine would be set. */
    private class Engine : VoiceSetter {
        var voiceId: String? = null
        var pitchSet = 0f
        var rateSet = 0f
        override fun setVoice(id: String): Boolean { voiceId = id; return true }
        override fun setPitch(pitch: Float) { pitchSet = pitch }
        override fun setSpeechRate(rate: Float) { rateSet = rate }
    }

    private fun who(cast: VoiceCast, part: PartID, sessionRate: Float = 1f): Triple<String?, Float, Float>? {
        val e = Engine()
        return if (cast.prepare(part, e, sessionRate)) Triple(e.voiceId, e.pitchSet, e.rateSet) else null
    }

    @Test fun `the castable voices are local installed English only, best first, by id not language`() {
        val v = voices()
        assertEquals(listOf("en-us-x-tpd-local", "en-au-x-aua-local", "en-us-x-sfg-local", "en-gb-x-rjs-local"), v.map { it.id })
        assertEquals(
            listOf("English (United States) 1", "English (Australia)", "English (United States) 2", "English (United Kingdom)"),
            v.map { it.name },
        )
        assertEquals(listOf(null, null, null, null), v.map { it.gender })
        assertEquals(listOf("High quality", "High quality", null, null), v.map { it.qualityNote })
        assertTrue("no raw engine name is ever the label", v.none { it.name.contains("-x-") })
    }

    @Test fun `quality leads, then the person's locale, then the system default, then the name`() {
        val tie = listOf(
            raw("b-voice", "en-GB", 300), raw("a-voice", "en-AU", 300), raw("d-default", "en-CA", 300, default = true), raw("c-own", "en-US", 300),
        )
        assertEquals(listOf("c-own", "d-default", "a-voice", "b-voice"), VoiceCasting.castable(tie, Locale.US).map { it.id })
    }

    @Test fun `auto-cast is deterministic, distinct in cast order, the best voice to the largest part, sound and directions not read`() {
        val s = script()
        val v = voices()
        val a = VoiceCasting.autoCast(parts(s), v)
        assertEquals(a, VoiceCasting.autoCast(parts(s), v.toList()))
        assertEquals(listOf("role:MOLLY", "role:FIBBER", "role:DOC", "sound", "directions"), parts(s).map { it.raw })
        assertEquals(v[0].id, a.getValue(PartID.role("MOLLY")).voice)
        assertEquals(v.take(3).map { it.id }, listOf("MOLLY", "FIBBER", "DOC").map { a.getValue(PartID.role(it)).voice })
        assertEquals(listOf("none", "none"), listOf(a.getValue(PartID.SOUND).engine, a.getValue(PartID.DIRECTIONS).engine))
    }

    @Test fun `auto-cast never reads a part's name, so renaming every part changes nothing`() {
        val v = voices()
        val plain = VoiceCasting.autoCast(parts(script()), v).values.map { it.voice to it.pitch }
        val renamed = VoiceCasting.autoCast(parts(script("LADY MACBETH", "MRS. GIBBS", "FATHER BROWN")), v).values.map { it.voice to it.pitch }
        assertEquals(plain, renamed)
        val src = File("src/main/java/com/example/appname/plays/VoiceCast.kt").readText()
        val auto = src.substring(src.indexOf("fun autoCast"), src.indexOf("private fun clamp")).replace(Regex("\\b(v|voice)\\.name\\b"), "")
        assertFalse("autoCast reads no title, role, name or line", Regex("\\.(title|roleName|name)\\b|lines\\b|\\.raw\\b").containsMatchIn(auto))
    }

    @Test fun `auto-cast alternates a voice's own reported gender where the platform reports one`() {
        fun cv(id: String, gender: String?) = CastVoice(id, id, "en-US", 300, gender)
        val voices = listOf(cv("a", "female"), cv("b", "female"), cv("c", "male"), cv("d", null), cv("e", "male"))
        val four = (1..4).map { PartID.role("P$it") }
        val cast = VoiceCasting.autoCast(four, voices)
        assertEquals(listOf("a", "c", "b", "e"), four.map { cast.getValue(it).voice })
        // Android reports no gender: the same list without genders casts in plain order.
        val plain = voices.map { it.copy(gender = null) }
        assertEquals(listOf("a", "b", "c", "d"), four.map { VoiceCasting.autoCast(four, plain).getValue(it).voice })
    }

    @Test fun `fewer voices than parts starts the list again at the next pitch`() {
        val two = voices().take(2)
        val a = VoiceCasting.autoCast(parts(), two)
        val p = listOf("MOLLY", "FIBBER", "DOC").map { a.getValue(PartID.role(it)) }
        assertEquals(listOf(two[0].id, two[1].id, two[0].id), p.map { it.voice })
        assertEquals(listOf(1.0, 1.0, 0.86), p.map { it.pitch })
    }

    /** What the code before S2 did: every player kept its own map from part to the order it first spoke. */
    private class Loose(val voices: List<CastVoice>) {
        private val assigned = HashMap<PartID, Int>()
        fun voice(part: PartID): String {
            val index = assigned.getOrPut(part) { assigned.size }
            return voices[index % voices.size].id
        }
    }

    @Test fun `one cast everywhere - the recorder and the listen-through read each part in the same voice, and two loose players disagree`() {
        val store = MemoryCastStore()
        val molly = PartID.role("MOLLY")
        val doc = PartID.role("DOC")
        // Recording FIBBER: the recorder cues MOLLY's line, then DOC's. The listen-through then starts with FIBBER.
        val recorder = caster(store = store)
        val listen = caster(store = store)
        val fibber = PartID.role("FIBBER")
        val inRecorder = listOf(molly, doc).map { who(recorder, it)!!.first }
        val inListen = listOf(fibber, molly, doc).map { who(listen, it)!!.first }
        assertEquals(inRecorder[0], inListen[1])
        assertEquals(inRecorder[1], inListen[2])
        assertEquals("and it is the auto-cast voice: the largest part, the best voice", voices()[0].id, inListen[1])
        // Control: without one cast the same part changes voice.
        val a = Loose(voices())
        val b = Loose(voices())
        val loose = listOf(molly, doc).map { a.voice(it) } to listOf(fibber, molly, doc).map { b.voice(it) }
        assertTrue("control: without one cast MOLLY changes voice", loose.first[0] != loose.second[1])
    }

    @Test fun `both players reach the engine only through the cast`() {
        for (file in listOf("StandIn.kt", "DeviceVoices.kt")) {
            val src = File("src/main/java/com/example/appname/plays/$file").readText()
            assertTrue("$file reads the cast through prepare", src.contains("cast.prepare("))
            assertFalse("$file keeps no map of voices by order spoken", src.contains("assigned"))
        }
        val live = File("src/main/java/com/example/appname/plays/LiveListen.kt").readText()
        assertTrue("the listen-through reads through the cast speaker", live.contains("speaker.speak("))
        assertFalse("and chooses no voice itself", live.contains("tts.voice") || live.contains("assigned"))
    }

    @Test fun `a choice is read by another player built later - its speed times the session's, its pitch - and Recast all restores auto-cast`() {
        val store = MemoryCastStore()
        val molly = PartID.role("MOLLY")
        val daniel = voices().first { it.id == "en-gb-x-rjs-local" }
        caster(store = store).set(molly) { copy(engine = "system", voice = daniel.id, name = daniel.name, rate = 1.3, pitch = 0.8) }
        val later = caster(store = store)
        val r = later.resolve(molly)
        assertEquals(listOf(daniel.id, 1.3, 0.8, null), listOf(r.voice?.id, r.rate, r.pitch, r.missing))
        val (id, pitch, rate) = who(later, molly, 1.5f)!!
        assertEquals(daniel.id, id)
        assertEquals(0.8f, pitch, 0.001f)
        assertEquals(1.95f, rate, 0.001f)
        later.recast()
        assertEquals(voices()[0].id, later.resolve(molly).voice?.id)
    }

    @Test fun `stage directions are not read until given a voice, then the listen plan reads them, and sound stays unread`() {
        val s = script()
        val cast = caster(s = s)
        assertFalse(cast.resolve(PartID.DIRECTIONS).read)
        val production = Production.create(s)
        fun plan() = Relay.listenPlan(production, s) { !it.isSpeaking && cast.resolve(it).read }
        assertTrue("no direction in the plan", plan().none { it.part == PartID.DIRECTIONS })
        val karen = voices()[1]
        cast.set(PartID.DIRECTIONS) { copy(engine = "system", voice = karen.id, name = karen.name) }
        val d = plan().firstOrNull { it.part == PartID.DIRECTIONS } as? Relay.ListenEntry.Voice
        assertNotNull("the direction is read once it has a voice", d)
        assertEquals("(A kitchen.)", d!!.text)
        assertEquals(karen.id, who(cast, PartID.DIRECTIONS)?.first)
        assertTrue("sound stays not read", plan().none { it.part == PartID.SOUND })
        assertEquals("the default plan is unchanged", Relay.listenPlan(production, s).map { it.lineID }, Relay.listenPlan(production, s, null).map { it.lineID })
        assertTrue("and holds no direction", Relay.listenPlan(production, s).none { it.part == PartID.DIRECTIONS })
    }

    @Test fun `a cast voice this device lacks falls back to the auto-cast voice, visibly, the choice is kept, and it returns with the voice`() {
        val store = MemoryCastStore()
        var device = this.device
        val cast = caster(store = store, source = { voices(device) })
        val fibber = PartID.role("FIBBER")
        cast.set(fibber) { copy(engine = "system", voice = "en-us-x-zoe-local", name = "English (United States) 3") }
        val r = cast.resolve(fibber)
        assertEquals(listOf(true, "English (United States) 3", voices()[1].id), listOf(r.read, r.missing, r.voice?.id))
        assertEquals("en-us-x-zoe-local", cast.entry(fibber)?.voice)
        device = this.device + raw("en-us-x-zoe-local", "en-US", 500)
        assertEquals("en-us-x-zoe-local", cast.resolve(fibber).voice?.id)
        assertNull(cast.resolve(fibber).missing)
        val k = caster(key = "p:P5", store = store, source = { voices(device) })
        k.set(PartID.role("DOC")) { copy(engine = "kokoro", voice = "af_heart", name = "Heart") }
        assertEquals("a Kokoro voice (none until S6) falls back the same way", "Heart", k.resolve(PartID.role("DOC")).missing)
    }

    @Test fun `with no voice nothing is cast, stored or spoken, and when voices arrive the Default reads and is never kept`() {
        val store = MemoryCastStore()
        var list = emptyList<RawVoice>()
        val cast = caster(store = store, source = { voices(list) })
        val molly = PartID.role("MOLLY")
        val r = cast.resolve(molly)
        assertEquals(listOf(false, true), listOf(r.read, r.none))
        assertNull(VoiceCasting.load("p:P1", store))
        assertNull("nothing reaches the engine", who(cast, molly))
        list = device
        assertEquals(voices()[0].id, cast.resolve(molly).voice?.id)
        assertNull("a Default is never written into the cast (Decision 086)", store.text)
    }

    @Test fun `a production starts from its play's cast, changing it leaves the play's alone, 80 casts are kept, storage failures are survived, and sync never names the cast`() {
        val store = MemoryCastStore()
        val s = script()
        val play = caster(key = VoiceCasting.scriptKey("gut-0"), store = store)
        val doc = PartID.role("DOC")
        play.set(doc) { copy(engine = "system", voice = "en-gb-x-rjs-local", name = "English (United Kingdom)") }
        val prod = caster(key = VoiceCasting.productionKey("P7"), store = store, seed = VoiceCasting.scriptKey("gut-0"))
        assertEquals("en-gb-x-rjs-local", prod.resolve(doc).voice?.id)
        prod.set(doc) { copy(voice = "en-us-x-sfg-local", name = "English (United States) 2") }
        assertEquals("en-gb-x-rjs-local", play.resolve(doc).voice?.id)
        for (i in 0 until 100) VoiceCasting.save("p:x$i", emptyMap(), store, now = i.toLong() + 1)
        val kept = store.text!!.let { Regex("\"(p|s):[^\"]+\":\\{").findAll(it).count() }
        assertTrue("the newest 80 are kept, got $kept", kept <= 80)
        assertNotNull("and the newest is among them", VoiceCasting.load("p:x99", store))
        assertNull("the oldest is not", VoiceCasting.load("p:x0", store))
        val broken = object : CastStore {
            override fun read(): String = throw IllegalStateException("blocked")
            override fun write(text: String) = throw IllegalStateException("blocked")
        }
        assertEquals(voices()[0].id, caster(key = "p:P8", s = s, store = broken).resolve(PartID.role("MOLLY")).voice?.id)
        VoiceCasting.forget("p:P7", store)
        assertNull(VoiceCasting.load("p:P7", store))
        val sources = File("src/main/java/com/example/appname").walkTopDown().filter { it.extension == "kt" }
            .filter { it.path.contains("/account/") || it.path.contains("/together/") || it.name == "PlaysShare.kt" || it.name == "SharedPlays.kt" }
        assertTrue(sources.count() > 3)
        assertEquals(emptyList<String>(), sources.filter { Regex("ed\\.cast|VoiceCast").containsMatchIn(it.readText()) }.map { it.name }.toList())
    }

    @Test fun `normalizing reads an unknown engine or a voiceless system entry as no entry, and clamps speed and pitch`() {
        assertNull(VoiceCasting.normalize(VoiceCastEntry("elevenlabs", "x")))
        assertNull(VoiceCasting.normalize(VoiceCastEntry("system", null)))
        val e = VoiceCasting.normalize(VoiceCastEntry("system", "v", null, rate = 9.0, pitch = 0.123))!!
        assertEquals(listOf(2.0, 0.5, "v"), listOf(e.rate, e.pitch, e.name))
        assertEquals("1.0×", speedText(1.0))
        assertEquals("1.25×", speedText(1.25))
        assertEquals(listOf("0", "+1", "−1"), listOf(pitchText(1.0), pitchText(1.1), pitchText(0.9)))
    }

    private class Speaker(val reads: Set<PartID>) : LineSpeaker {
        val spoken = ArrayList<Pair<PartID, String>>()
        override fun reads(part: PartID) = part in reads
        override suspend fun speak(text: String, part: PartID): Boolean { spoken += part to text; return true }
        override fun cancel() {}
    }

    @Test fun `the table read goes from a line to the end, each part in its voice, following each line`() = runTest {
        val s = script()
        val speaker = Speaker(parts(s).filter { it.isSpeaking }.toSet())
        val followed = ArrayList<String?>()
        TableRead(s, speaker) { followed += it?.id }.play(4)
        assertEquals(listOf("L0005", "L0006", "L0007", "L0008", "L0009", "L0010", "L0011", null), followed)
        assertEquals(PartID.role("DOC"), speaker.spoken.first().first)
        // A direction is read once its part has a voice.
        val withDirections = Speaker(speaker.reads + PartID.DIRECTIONS)
        TableRead(s, withDirections).play(0)
        assertEquals("(A kitchen.)", withDirections.spoken.first().second)
        assertTrue(withDirections.spoken.none { it.first == PartID.SOUND })
        val src = File("src/main/java/com/example/appname/plays/TableRead.kt").readText()
        assertFalse("the table read holds no store and calls no network", Regex("\\bstore\\b|ProductionStore|Api\\b|http").containsMatchIn(src))
    }

    @Test fun `stopping the table read stops it on the line it is on`() = runTest {
        val s = script()
        val stopper = object : LineSpeaker {
            val spoken = ArrayList<String>()
            override fun reads(part: PartID) = true
            override suspend fun speak(text: String, part: PartID): Boolean {
                spoken += text
                if (spoken.size == 2) throw CancellationException("stopped")
                return true
            }
            override fun cancel() {}
        }
        val followed = ArrayList<String?>()
        try { TableRead(s, stopper) { followed += it?.id }.play(0) } catch (_: CancellationException) { }
        assertEquals(2, stopper.spoken.size)
        assertNull("the follower is told it ended", followed.last())
    }

    @Test fun `a chip names a voice by its distinguishing part - a region in initials, the number kept`() {
        assertEquals("English (US) 3", chipVoiceName("English (United States) 3"))
        assertEquals("English (UK)", chipVoiceName("English (United Kingdom)"))
        assertEquals("English (Australia) 2", chipVoiceName("English (Australia) 2"))
        assertEquals("No Voice", chipVoiceName("No Voice"))
        assertEquals(
            "two voices of one locale stay apart",
            2,
            setOf(chipVoiceName("English (United States) 1"), chipVoiceName("English (United States) 2")).size,
        )
    }

    // The device's voice defaults (Decision 086), the mirror of js/voice-cast.test.js "The device's voice defaults".
    // Seen to fail, 2026-11-22, against a mutated VoiceCast.kt: ordered() without the engine rank (Kokoro not first);
    // pool() without the unticked filter; the Default written back as a choice; load() ignoring `v`.

    private fun kv(id: String, name: String, grade: String, off: Boolean = false) =
        CastVoice(id, "$name (Kokoro)", "en-US", 0, null, false, VoiceCastEntry.KOKORO, grade, off)

    private val heart = kv("af_heart", "Heart", "A")
    private val bella = kv("af_bella", "Bella", "A-")
    private val jessica = kv("af_jessica", "Jessica", "D", off = true)
    private val kokoro = listOf(heart, bella, jessica)

    private fun defaulted(
        key: String = "p:D1",
        store: CastStore = MemoryCastStore(),
        kokoroNow: () -> List<CastVoice> = { emptyList() },
        d: VoiceDefaults = VoiceDefaults(),
    ) = VoiceCast(key, parts(), { voices() }, store, downloaded = kokoroNow, defaults = { d })

    @Test fun `Kokoro leads the pool, then the person's order, unticked voices leave it, and all unticked means all`() {
        val all = kokoro + voices()
        assertEquals(kokoro.map { it.id } + voices().map { it.id }, VoiceCasting.ordered(all, VoiceDefaults()).map { it.id })
        assertFalse("a grade under C- starts unticked", VoiceCasting.pool(all, VoiceDefaults()).any { it.id == "af_jessica" })
        val sys = voices()
        val d = VoiceDefaults(order = listOf(sys[2].key, bella.key))
        assertEquals(listOf("af_bella", "af_heart", "af_jessica", sys[2].id), VoiceCasting.ordered(all, d).map { it.id }.take(4))
        val ticks = d.copy(off = mapOf(heart.key to true, jessica.key to false))
        assertEquals(listOf("af_bella", "af_jessica"), VoiceCasting.pool(all, ticks).map { it.id }.take(2))
        val none = VoiceDefaults(off = all.associate { it.key to true })
        assertEquals(all.size, VoiceCasting.pool(all, none).size)
    }

    @Test fun `moving a voice swaps it within its own engine only`() {
        val all = kokoro + voices()
        val sys = voices()
        val d = VoiceCasting.move(all, VoiceDefaults(), sys[1], -1)
        assertEquals(listOf(sys[1].id, sys[0].id), VoiceCasting.ordered(all, d).filter { it.engine == "system" }.map { it.id }.take(2))
        assertTrue("Kokoro stays first", VoiceCasting.ordered(all, d).take(3).all { it.engine == "kokoro" })
        assertEquals("the first cannot move up", VoiceDefaults(), VoiceCasting.move(all, VoiceDefaults(), sys[0], -1))
    }

    @Test fun `untouched parts read the Default at the Default speed, a download reaches them, a chosen part keeps its voice, reset and Recast all return to Default`() {
        val store = MemoryCastStore()
        val d = VoiceDefaults(rate = 1.2)
        val molly = PartID.role("MOLLY")
        val fibber = PartID.role("FIBBER")
        val before = defaulted(store = store, d = d)
        assertEquals(listOf(voices()[0].id, 1.2, true), before.resolve(molly).let { listOf(it.voice?.id, it.rate, it.isDefault) })
        before.set(fibber) { copy(engine = "system", voice = "en-gb-x-rjs-local", name = "English (United Kingdom)") }
        val after = defaulted(store = store, kokoroNow = { kokoro }, d = d)
        assertEquals("a download reaches every untouched part", "af_heart", after.resolve(molly).voice?.id)
        val r = after.resolve(fibber)
        assertEquals(listOf("en-gb-x-rjs-local", false), listOf(r.voice?.id, r.isDefault))
        after.reset(fibber)
        assertEquals("af_bella", after.resolve(fibber).voice?.id)
        after.set(molly) { copy(rate = 0.8) }
        assertEquals(listOf("af_heart", 0.8), after.choice(molly).let { listOf(it?.voice, it?.rate) })
        after.recast()
        assertTrue(after.choice(molly) == null && after.resolve(molly).isDefault)
    }

    @Test fun `a Default is never written into the cast`() {
        val store = MemoryCastStore()
        val cast = defaulted(store = store, kokoroNow = { kokoro })
        for (p in parts()) { cast.resolve(p); cast.entry(p) }
        assertNull("reading writes nothing", store.text)
        cast.reset(PartID.role("MOLLY"))
        assertNull("resetting a Default writes nothing", store.text)
    }

    @Test fun `an old unversioned row is no choice, and a row written now is`() {
        val molly = PartID.role("MOLLY")
        val store = MemoryCastStore("""{"p:D3":{"parts":{"role:MOLLY":{"engine":"system","voice":"en-gb-x-rjs-local","name":"x"}},"at":1}}""")
        val cast = defaulted(key = "p:D3", store = store)
        assertNull(cast.choice(molly))
        assertEquals(voices()[0].id, cast.resolve(molly).voice?.id)
        cast.set(molly) { copy(voice = "en-gb-x-rjs-local") }
        assertEquals("en-gb-x-rjs-local", defaulted(key = "p:D3", store = store).choice(molly)?.voice)
    }

    @Test fun `the fallback for a Kokoro line is the Default among the device's own voices`() {
        val cast = defaulted(kokoroNow = { kokoro })
        val molly = PartID.role("MOLLY")
        assertEquals(VoiceCastEntry.KOKORO, cast.resolve(molly).voice?.engine)
        assertEquals(voices()[0].id, cast.systemFallback(molly)?.voice?.id)
    }

    @Test fun `defaults persist, are clamped, and a broken row reads as the defaults`() {
        val store = MemoryCastStore()
        assertEquals(VoiceDefaults(), VoiceDefaultsStore.load(store))
        VoiceDefaultsStore.save(store, VoiceDefaults(order = listOf("kokoro:af_heart"), off = mapOf("system:x" to true), rate = 9.0))
        val back = VoiceDefaultsStore.load(store)
        assertEquals(listOf(listOf("kokoro:af_heart"), mapOf("system:x" to true), 2.0), listOf(back.order, back.off, back.rate))
        store.write("not json")
        assertEquals(VoiceDefaults(), VoiceDefaultsStore.load(store))
    }

    @Test fun `Kokoro grades under C minus start unticked and the best grade leads`() {
        val off = com.example.appname.kokoro.Kokoro.castable(true).filter { it.offByDefault }.map { it.name }.toSet()
        assertEquals(setOf("Jessica", "River", "Echo", "Eric", "Liam", "Onyx", "Santa", "Adam", "Alice", "Lily", "Daniel", "Lewis").map { "$it (Kokoro)" }.toSet(), off)
        assertEquals("af_heart", com.example.appname.kokoro.Kokoro.castable(true).first().id)
    }
}
