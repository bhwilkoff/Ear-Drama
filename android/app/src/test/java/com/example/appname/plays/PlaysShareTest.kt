package com.example.appname.plays

import java.io.File
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Shared plays, phase 2 (PLAYS-DESIGN §11.7), as js/plays-share.js proves them:
 * `PlaysShare` against a fake Worker, with no Android framework.
 *
 * Broken controls, 2026-10-24 (each guard removed in PlaysShare.kt or
 * PlayFiles.kt, all together in one run, and each named test seen to fail;
 * then restored):
 *  - `pending` keeping flagged takes (drop `!it.bleed`)          -> `pending leaves out a flagged take`
 *  - `candidates` ignoring takes on the Worker (drop `!in onServer`) -> `pending leaves out a take the Worker already has`
 *  - `upload` ignoring the record's `uploads` (drop `uploadsOpen`)  -> `uploads off in the record stops before the upload endpoint`
 *  - `upload` ignoring GET /consent's `uploads`                    -> `uploads off in the consent stops before the upload endpoint`
 *  - `mirror` treating anyone's claim as this person's             -> `another person's claim is open here`
 *  - `isToken` accepting any length                                -> `invite tokens`
 *  - DeepLink.parse without its `invite` branch                    -> DeepLinkTest `an invite link ...`
 *  - `libraryRows` listing a shared production twice               -> `library rows merge the device and the Worker`
 *  - a changed line in `line`                                      -> `refusals read as one line each`
 *  - `importTake` overwriting an existing file                     -> `an imported take is never overwritten`
 *
 * 2026-10-28 (Decision 072), each seen to fail once:
 *  - `publish` ignoring `Consent.publishes`                        -> `Publish waits while the Worker cannot reach archive`
 *  - `upload` calling `api.agree` before sending                   -> `uploading to the members asks no consent`
 *
 * 2026-10-29 (P15), each seen to fail once:
 *  - `archiveLine` never answering "published"                     -> `the archive job is told truthfully`
 *  - `mergedChosen` reading `myParts` instead of `ownParts`        -> `a replacement take on a finished part is pending ...`
 */
class PlaysShareTest {
    private val script = fixtureScript()
    private val molly = PartID.role("MOLLY")
    private val me = "user-me"

    // MARK: fakes

    private class MemoryShareStore : ShareStore {
        val list = mutableListOf<Production>()
        val links = mutableMapOf<String, ShareLink>()
        val files = mutableMapOf<String, ByteArray>()
        override fun all() = list.toList()
        override fun production(id: String) = list.firstOrNull { it.id == id }
        override fun save(production: Production) {
            val at = list.indexOfFirst { it.id == production.id }
            if (at >= 0) list[at] = production else list += production
        }
        override fun create(script: PlayScript) = Production.create(script).also(::save)
        override fun share(id: String) = links[id]
        override fun setShare(id: String, link: ShareLink) { links[id] = link }
        override fun findShared(pid: String) = list.firstOrNull { links[it.id]?.pid == pid }
        override fun readTake(id: String, file: String) = files[file] ?: ByteArray(0)
        override fun importTake(id: String, file: String, bytes: ByteArray) { files.putIfAbsent(file, bytes) }
    }

    private inner class FakeApi(var consent: Consent = Consent("v1", "The owner's words.", true)) : PlaysTransport {
        val calls = mutableListOf<String>()
        val uploaded = mutableListOf<Triple<String, ByteArray, JsonObject>>()
        var fresh: SharedRecord? = null
        var created: JsonObject? = null
        private fun log(s: String) { calls += s }
        fun count(prefix: String) = calls.count { it.startsWith(prefix) }

        override suspend fun consent(): Consent { log("consent"); return consent }
        override suspend fun create(body: JsonObject): SharedRecord { log("create"); created = body; return record(id = "pid-new") }
        override suspend fun list() = emptyList<RemoteRow>()
        override suspend fun get(pid: String): SharedRecord { log("get"); return fresh ?: record(id = pid) }
        override suspend fun invite(pid: String) = error("not used")
        override suspend fun viewInvite(token: String) = error("not used")
        override suspend fun joinByInvite(token: String, part: String, displayName: String?) = record(id = "pid-joined")
        override suspend fun claim(pid: String, part: String) = error("not used")
        override suspend fun partAction(pid: String, part: String, action: String) = error("not used")
        override suspend fun agree(pid: String, version: String) { log("agree $version") }
        override suspend fun upload(pid: String, takeId: String, bytes: ByteArray, meta: JsonObject) {
            log("upload $takeId")
            uploaded += Triple(takeId, bytes, meta)
        }
        override suspend fun audio(pid: String, takeId: String): ByteArray { log("audio $takeId"); return byteArrayOf(1, 2, 3) }
        override suspend fun choose(pid: String, takeId: String): SharedRecord { log("choose $takeId"); return record() }
        override suspend fun publish(pid: String): PublishAnswer { log("publish"); return PublishAnswer("pending_owner_account") }
        override suspend fun removeLine(pid: String, lineId: String, reason: String) { log("remove $lineId $reason") }
        override suspend fun report(pid: String, takeId: String?, userId: String?, reason: String, note: String?) = error("not used")
        override suspend fun block(userId: String) = error("not used")
        override suspend fun classes() = error("not used")
        override suspend fun classDetail(id: String) = error("not used")
        override suspend fun createClass(name: String, under13: Boolean) = error("not used")
        override suspend fun joinClass(code: String, displayName: String?) = error("not used")
    }

    private fun record(
        id: String = "pid-1",
        parts: Map<String, SharedPart> = mapOf(molly.raw to SharedPart("recording", "Ann", userId = "user-me")),
        takes: List<SharedTake> = emptyList(),
        chosen: Map<String, String> = emptyMap(),
        uploads: Boolean = true,
    ) = SharedRecord(id, script.id, script.revision, script.title, parts = parts, takes = takes, chosen = chosen, director = "user-me", uploads = uploads)

    /** A device production linked to the Worker, with a chosen take on each of MOLLY's lines. */
    private fun linked(store: MemoryShareStore, consented: String? = null, flaggedLine: String? = null): Production {
        var p = Production.create(script)
        for (l in script.lines(molly)) {
            p = p.add(take("t-${l.id}", l.id, molly, 4_800, bleed = l.id == flaggedLine))
            store.files["t-${l.id}.wav"] = byteArrayOf(9, 9)
        }
        store.save(p)
        store.setShare(p.id, ShareLink("pid-1", consented))
        return p
    }

    // MARK: pending

    @Test fun `pending leaves out a flagged take`() {
        val store = MemoryShareStore()
        val p = linked(store, flaggedLine = "L0006")
        val rec = record()
        val pending = PlaysShare.pending(p, script, rec, me).map { it.lineID }
        assertEquals(listOf("L0003", "L0007", "L0009", "L0011"), pending)
        assertEquals(1, PlaysShare.flaggedPending(p, script, rec, me))
    }

    @Test fun `pending leaves out a take the Worker already has`() {
        val store = MemoryShareStore()
        val p = linked(store)
        val rec = record(takes = listOf(SharedTake("t-L0003", "L0003", molly.raw, "f.wav")))
        assertEquals(listOf("L0006", "L0007", "L0009", "L0011"), PlaysShare.pending(p, script, rec, me).map { it.lineID })
    }

    @Test fun `pending is only the parts this person holds`() {
        val store = MemoryShareStore()
        val p = linked(store)
        val rec = record(parts = mapOf(molly.raw to SharedPart("recording", "Bo", userId = "someone-else")))
        assertTrue(PlaysShare.pending(p, script, rec, me).isEmpty())
    }

    // MARK: upload

    @Test fun `uploads off in the record stops before the upload endpoint`() = runBlocking {
        val store = MemoryShareStore()
        val api = FakeApi()
        val p = linked(store)
        val result = PlaysShare.upload(api, store, p, script, record(uploads = false), me)
        assertEquals(PlaysShare.Stop.UploadsOff, result.stopped)
        assertEquals(0, result.sent)
        assertEquals("the upload endpoint is never called", 0, api.count("upload"))
        assertEquals("the person is not asked to consent to an upload that cannot happen", 0, api.count("consent"))
    }

    @Test fun `uploads off in the consent stops before the upload endpoint`() = runBlocking {
        val store = MemoryShareStore()
        val api = FakeApi(Consent("v1", "words", uploads = false))
        val p = linked(store)
        val result = PlaysShare.upload(api, store, p, script, record(uploads = true), me)
        assertEquals(PlaysShare.Stop.UploadsOff, result.stopped)
        assertEquals(0, api.count("upload"))
    }

    @Test fun `uploading to the members asks no consent`() = runBlocking {
        val store = MemoryShareStore()
        val api = FakeApi()
        val p = linked(store)
        val first = PlaysShare.upload(api, store, p, script, record(), me)
        assertEquals(5, first.sent)
        assertEquals("no consent is agreed to (Decision 072)", 0, api.calls.count { it.startsWith("agree") })
        assertNull(store.share(p.id)!!.consented)
    }

    @Test fun `Publish is the director's once complete`() {
        val parts = Relay.order(script).associate { it.raw to SharedPart("done", userId = me) }
        val chosen = script.speechLineIDs.associateWith { "t-$it" }
        val done = record(parts = parts, chosen = chosen)
        assertTrue("the fixture is complete", PlaysShare.complete(done, script))
        assertTrue(PlaysShare.canPublish(done, script, me))
        assertFalse("never a member", PlaysShare.canPublish(done, script, "someone-else"))
        assertFalse("never twice", PlaysShare.canPublish(done.copy(archive = SharedArchive("pending_owner_account")), script, me))
    }

    @Test fun `each performer agrees for their own recording and Publish waits on them`() {
        val parts = Relay.order(script).associate { it.raw to SharedPart("done", userId = me) }
        val chosen = script.speechLineIDs.associateWith { "t-$it" }
        val members = listOf(
            SharedMember(me, "Me", director = true, performer = true),
            SharedMember("bo", "Bo", performer = true),
            SharedMember("quiet", null),
        )
        val rec = record(parts = parts, chosen = chosen).copy(members = members)
        assertEquals(listOf(me, "bo"), PlaysShare.performers(rec).map { it.userId })
        assertTrue(PlaysShare.needsMyConsent(rec, script, "bo"))
        assertFalse("the director is asked by Publish", PlaysShare.needsMyConsent(rec, script, me))
        assertFalse(PlaysShare.needsMyConsent(rec, script, "quiet"))
        assertEquals(listOf("bo"), PlaysShare.waitingOn(rec).map { it.userId })
        val agreed = rec.copy(members = members.map { if (it.userId == "bo") it.copy(consented = true) else it })
        assertFalse(PlaysShare.needsMyConsent(agreed, script, "bo"))
        assertTrue(PlaysShare.waitingOn(agreed).isEmpty())
    }

    @Test fun `Publish waits while the Worker cannot reach archive`() = runBlocking {
        val store = MemoryShareStore()
        val api = FakeApi()
        val p = linked(store)
        val sharing = SharedPlays(api, store, { me }, { listOf(script) })
        val closed = Consent("cc0-x", "words", uploads = true, publishes = false)
        val refused = runCatching { sharing.publish(p.id, script, closed) }.exceptionOrNull()
        assertEquals("publish_waits", (refused as? PlaysException)?.code)
        assertEquals("nothing agreed or queued", 0, api.calls.count { it.startsWith("agree") || it == "publish" })
        assertEquals("Publishing opens when the Ear Drama archive account is connected.", PlaysShare.line(PlaysException("publish_waits")))
    }

    @Test fun `Publish agrees at the served version, then queues`() = runBlocking {
        val store = MemoryShareStore()
        val api = FakeApi()
        val p = linked(store)
        val parts = Relay.order(script).associate { it.raw to SharedPart("done", userId = me) }
        api.fresh = record(parts = parts, chosen = script.speechLineIDs.associateWith { "t-$it" })
        val sharing = SharedPlays(api, store, { me }, { listOf(script) })
        sharing.publish(p.id, script, Consent("cc0-x", "words", uploads = true, publishes = true))
        assertEquals(listOf("agree cc0-x", "publish"), api.calls.filter { it.startsWith("agree") || it == "publish" })
        assertEquals("cc0-x", store.share(p.id)!!.consented)
    }

    @Test fun `an upload carries the take's fields and its audio`() = runBlocking {
        val store = MemoryShareStore()
        val api = FakeApi()
        val p = linked(store, consented = "v1")
        PlaysShare.upload(api, store, p, script, record(), me)
        val (id, bytes, meta) = api.uploaded.first { it.first == "t-L0003" }
        assertEquals("t-L0003", id)
        assertEquals(listOf<Byte>(9, 9), bytes.toList())
        assertEquals("L0003", meta.getValue("lineID").jsonPrimitive.content)
        assertEquals("role:MOLLY", meta.getValue("part").jsonPrimitive.content)
        assertEquals("direct", meta.getValue("capture").jsonPrimitive.content)
        assertEquals(false, meta.getValue("bleed").jsonPrimitive.booleanOrNull)
        assertEquals(4800, meta.getValue("frames").jsonPrimitive.content.toInt())
    }

    @Test fun `a flagged take is counted and never sent`() = runBlocking {
        val store = MemoryShareStore()
        val api = FakeApi()
        val p = linked(store, consented = "v1", flaggedLine = "L0009")
        val result = PlaysShare.upload(api, store, p, script, record(), me)
        assertEquals(4, result.sent)
        assertEquals(1, result.flagged)
        assertFalse(api.uploaded.any { it.first == "t-L0009" })
    }

    // MARK: following the Worker

    @Test fun `another person's claim is open here`() {
        val local = Production.create(script)
        val rec = record(
            parts = mapOf(
                molly.raw to SharedPart("recording", "Bo", userId = "someone-else"),
                "role:FIBBER" to SharedPart("recording", "Ann", userId = me),
                "role:DOC" to SharedPart("done", "Cy", userId = "third"),
                "sound" to SharedPart("silent"),
                "directions" to SharedPart("open"),
            ),
        )
        val mirrored = PlaysShare.mirror(local, rec, me)
        assertEquals(PartState(PartState.Status.Open), mirrored.state(molly))
        assertEquals(PartState(PartState.Status.Recording, "Ann"), mirrored.state(PartID.role("FIBBER")))
        assertEquals(PartState(PartState.Status.Done, "Cy"), mirrored.state(PartID.role("DOC")))
        assertEquals(PartState(PartState.Status.Silent), mirrored.state(PartID.SOUND))
    }

    @Test fun `bringing home fetches only chosen takes the device lacks and keeps its own picks`() = runBlocking {
        val store = MemoryShareStore()
        val api = FakeApi()
        val local = Production.create(script).add(take("mine", "L0006", molly, 4_800))
        store.save(local)
        store.setShare(local.id, ShareLink("pid-1"))
        val theirs = SharedTake("theirs", "L0002", "role:FIBBER", "x.wav", frames = 4_800, capture = "aec", userId = "other")
        val rec = record(
            parts = mapOf(molly.raw to SharedPart("recording", "Ann", userId = me), "role:FIBBER" to SharedPart("done", "Bo", userId = "other")),
            takes = listOf(theirs),
            chosen = mapOf("L0002" to "theirs"),
        )
        assertEquals(1, PlaysShare.bringHome(api, store, local.id, rec, script, me))
        val after = store.production(local.id)!!
        assertEquals("theirs", after.chosen["L0002"])
        assertEquals("my pick on a part I hold, not yet on the Worker, stays chosen", "mine", after.chosen["L0006"])
        assertEquals(Take.Capture.Aec, after.take("theirs")!!.capture)
        assertEquals("m-theirs.wav", after.take("theirs")!!.file)
        assertTrue(PlaysShare.inStep(after, script, rec, me))
        assertEquals(0, PlaysShare.bringHome(api, store, local.id, rec, script, me))
        assertEquals("audio is fetched once", 1, api.count("audio"))
    }

    @Test fun `an imported take is never overwritten`() {
        val root = temporaryRoot()
        val store = ProductionStore(root)
        val p = store.create(script)
        store.importTake(p.id, "m-a.wav", byteArrayOf(1))
        store.importTake(p.id, "m-a.wav", byteArrayOf(2))
        assertEquals(listOf<Byte>(1), File(store.takesFolder(p.id), "m-a.wav").readBytes().toList())
    }

    @Test fun `share json sits beside the production and survives a reload`() {
        val root = temporaryRoot()
        val store = ProductionStore(root)
        val p = store.create(script)
        assertNull(store.share(p.id))
        store.setShare(p.id, ShareLink("pid-9", "v1"))
        assertTrue(File(store.folder(p.id), "share.json").isFile)
        val reopened = ProductionStore(root)
        assertEquals(ShareLink("pid-9", "v1"), reopened.share(p.id))
        assertEquals(p.id, reopened.findShared("pid-9")?.id)
    }

    @Test fun `sharing sends the cast sheet and keeps the Worker's id`() = runBlocking {
        val store = MemoryShareStore()
        val api = FakeApi()
        val p = store.create(script)
        val rec = PlaysShare.share(api, store, p, script, "  Ann ")
        assertEquals("pid-new", rec.id)
        assertEquals(ShareLink("pid-new"), store.share(p.id))
        val body = api.created!!
        assertEquals("Ann", body.getValue("display_name").jsonPrimitive.content)
        val cast = body.getValue("cast") as JsonArray
        assertEquals(script.lines.size, cast.size)
        assertEquals("role:FIBBER", (cast[1] as JsonObject).getValue("part").jsonPrimitive.content)
        assertEquals("L0002", (cast[1] as JsonObject).getValue("id").jsonPrimitive.content)
    }

    @Test fun `a revision the bundle lacks makes nothing`() {
        val store = MemoryShareStore()
        assertNull(PlaysShare.scriptFor(listOf(script), script.id, "older"))
        try {
            PlaysShare.localFor(store, "pid-x", null)
            throw AssertionError("should refuse")
        } catch (e: PlaysException) {
            assertEquals("revision_mismatch", e.code)
        }
        assertTrue(store.list.isEmpty())
        val made = PlaysShare.localFor(store, "pid-x", script)
        assertEquals("the second open finds it", made.id, PlaysShare.localFor(store, "pid-x", script).id)
        assertEquals(1, store.list.size)
    }

    // MARK: Library

    @Test fun `library rows merge the device and the Worker`() {
        val store = MemoryShareStore()
        val old = Production.create(script).copy(id = "old", created = 100.0)
        val recent = Production.create(script).copy(id = "recent", created = 5_000.0)
        store.save(old)
        store.save(recent)
        store.setShare("recent", ShareLink("pid-recent"))
        val remote = listOf(
            RemoteRow("pid-recent", "On this device already", updatedAt = 1),
            RemoteRow("pid-far", "Only on the Worker", updatedAt = (5_000L + 978_307_200L + 10) * 1000),
        )
        val rows = PlaysShare.libraryRows(store, remote)
        assertEquals(listOf("pid-far", "pid-recent", null), rows.map { it.pid })
        assertNull(rows[0].local)
        assertEquals("recent", rows[1].local!!.id)
        assertEquals("old", rows[2].local!!.id)
    }

    // MARK: invite links

    private val token = "A".repeat(43)

    @Test fun `invite tokens`() {
        assertEquals("https://eardrama.org/invite#$token", PlaysShare.inviteLink(token))
        assertEquals(token, PlaysShare.inviteToken("/invite", token))
        assertEquals(token, PlaysShare.inviteToken("/invite/", "#$token"))
        assertEquals(token, PlaysShare.inviteToken("/", "invite=$token"))
        assertEquals("the 404 forwarder's shape", token, PlaysShare.inviteToken("", "#invite=$token"))
        assertNull(PlaysShare.inviteToken("/invite", "A".repeat(42)))
        assertNull(PlaysShare.inviteToken("/invite", "A".repeat(44)))
        assertNull(PlaysShare.inviteToken("/invite", "A".repeat(42) + "!"))
        assertNull(PlaysShare.inviteToken("/invite", ""))
        assertNull("a token on another path is not an invite", PlaysShare.inviteToken("/series/x", token))
        assertNull(PlaysShare.inviteToken("/", "invite=short"))
    }

    @Test fun `works for N days counts up and class codes read in two groups`() {
        val day = PlaysShare.DAY_MS
        assertEquals("Works for 7 days.", PlaysShare.worksFor(1_000 + 7 * day, 1_000))
        assertEquals("Works for 1 day.", PlaysShare.worksFor(1_000 + day / 2, 1_000))
        assertEquals("ABCD EFGH", PlaysShare.classCodeDisplay("abcdefgh"))
        assertEquals("ABCDEFGH", PlaysShare.classCodeNormalize("abcd-efgh "))
    }

    // MARK: refusals

    private fun said(code: String, kind: PlaysException.Kind = PlaysException.Kind.Refused, detail: JsonElement? = null) =
        PlaysShare.line(PlaysException(code, kind, detail))

    @Test fun `refusals read as one line each`() {
        assertEquals("Uploads are off.", said("storage_not_configured"))
        assertEquals("Uploads are off.", said("uploads_off"))
        assertEquals("This part is taken.", said("not_open"))
        assertEquals("This invite does not work.", said("invite_not_found"))
        assertEquals("This production is not shared with you.", said("not_found"))
        assertEquals("The consent changed. Read it again.", said("consent_version_mismatch"))
        assertEquals("This play has changed since it was cast.", said("revision_mismatch"))
        assertEquals("A take holds the device voice. Re-take it with headphones.", said("bleed_flagged"))
        assertEquals("Only the director can do that.", said("director_only"))
        assertEquals("Too many tries. Try again in a minute.", said("", PlaysException.Kind.RateLimited))
        assertEquals("You are offline.", said("", PlaysException.Kind.Offline))
        assertEquals("Not available yet.", said("", PlaysException.Kind.NotConfigured))
        assertEquals("Sign in again.", said("", PlaysException.Kind.Unauthorized))
        assertEquals("Ear Drama could not be reached.", said("something_new"))
        assertEquals("Ear Drama could not be reached.", PlaysShare.line(IllegalStateException()))
        assertEquals("", PlaysShare.line(null))
        assertEquals("MOLLY is still recording.", said("another_part_is_recording", detail = JsonPrimitive("role:MOLLY")))
        assertEquals("Sound effects is still recording.", said("another_part_is_recording", detail = JsonPrimitive("sound")))
        assertEquals("1 line still needs a take.", said("lines_missing", detail = JsonArray(listOf(JsonPrimitive("L1")))))
        assertEquals("3 lines still need a take.", said("lines_missing", detail = JsonArray(List(3) { JsonPrimitive("L$it") })))
    }

    @Test fun `the archive job is told truthfully`() {
        fun with(a: SharedArchive?) = record().copy(archive = a)
        assertNull(PlaysShare.archiveLine(with(null)))
        assertEquals(PlaysShare.ArchiveLine.Waiting("Queued for archive.org"), PlaysShare.archiveLine(with(SharedArchive("queued"))))
        assertEquals(PlaysShare.ArchiveLine.Waiting("Uploading to archive.org"), PlaysShare.archiveLine(with(SharedArchive("uploading"))))
        assertEquals(PlaysShare.ArchiveLine.Published("https://archive.org/details/x"), PlaysShare.archiveLine(with(SharedArchive("published", url = "https://archive.org/details/x"))))
        val failed = with(SharedArchive("failed", reason = "archive.org refused the file (403)"))
        assertEquals(PlaysShare.ArchiveLine.Failed("archive.org refused the file (403)"), PlaysShare.archiveLine(failed))
        assertTrue(PlaysShare.canPublishAgain(failed, me))
        assertFalse(PlaysShare.canPublishAgain(failed, "user-bo"))
        assertFalse(PlaysShare.canPublishAgain(with(SharedArchive("published")), me))
    }

    @Test fun `a performer changes their own lines and the director removes any`() {
        val done = mapOf(
            molly.raw to SharedPart("done", "Ann", userId = me),
            "role:FIBBER" to SharedPart("done", "Bo", userId = "user-bo"),
        )
        val chosen = script.speechLineIDs.associateWith { "t-$it" }
        val pub = record(parts = done, chosen = chosen).copy(director = "user-bo", archive = SharedArchive("published", url = "u"))
        val mine = PlaysShare.changeableLines(pub, script, me)
        assertEquals(script.lines(molly).map { it.id }, mine.map { it.line.id })
        assertTrue(mine.all { it.replace && !it.needsReason })
        val director = PlaysShare.changeableLines(pub, script, "user-bo")
        assertEquals(script.speechLineIDs.size, director.size)
        assertTrue(director.filter { it.replace }.all { it.line.part.raw == "role:FIBBER" })
        assertTrue(director.filter { !it.replace }.all { it.needsReason })
        assertTrue(PlaysShare.changeableLines(pub.copy(archive = SharedArchive("queued")), script, me).isEmpty())
        assertEquals(listOf(molly.raw), PlaysShare.ownParts(pub, me))
        assertTrue(PlaysShare.ownParts(pub.copy(archive = null), me).isEmpty())
    }

    @Test fun `a replacement take on a finished part is pending once the play is published`() {
        val store = MemoryShareStore()
        val p = linked(store)
        val onServer = script.lines(molly).map { SharedTake("t-${it.id}", it.id, molly.raw, "t-${it.id}.wav", userId = me) }
        val done = record(parts = mapOf(molly.raw to SharedPart("done", "Ann", userId = me)), takes = onServer)
        assertTrue(PlaysShare.pending(p, script, done, me).isEmpty())
        val first = script.lines(molly).first().id
        val replaced = p.add(take("t-new", first, molly, 4_800))
        assertTrue(PlaysShare.pending(replaced, script, done, me).isEmpty())
        val pub = done.copy(archive = SharedArchive("published"))
        assertEquals(listOf("t-new"), PlaysShare.pending(replaced, script, pub, me).map { it.id })
        assertEquals("t-new", PlaysShare.mergedChosen(replaced, script, pub, me)[first])
    }

    @Test fun `removing a line asks the Worker with the reason`() = runBlocking {
        val api = FakeApi()
        api.removeLine("pid-1", "L0003", "withdrawn")
        assertEquals(listOf("remove L0003 withdrawn"), api.calls)
        assertEquals("The director removed this line.", PlaysShare.line(PlaysException("removed_by_director")))
    }

    @Test fun `the relay helpers read the Worker's record`() {
        val rec = record(
            parts = mapOf(
                molly.raw to SharedPart("recording", "Ann", userId = me),
                "role:DOC" to SharedPart("done", "Cy", userId = "c"),
                "role:FIBBER" to SharedPart("open"),
            ),
        )
        assertEquals(molly.raw, PlaysShare.recordingPart(rec))
        assertEquals(listOf(molly.raw), PlaysShare.myParts(rec, me))
        assertTrue(PlaysShare.isMine(rec, molly.raw, me))
        assertFalse(PlaysShare.isMine(rec, molly.raw, null))
        assertFalse("nothing is claimed while a part records", PlaysShare.canClaim(rec, "role:FIBBER"))
        val idle = rec.copy(parts = rec.parts + (molly.raw to SharedPart("done", "Ann", userId = me)))
        assertTrue(PlaysShare.canClaim(idle, "role:FIBBER"))
        assertFalse(PlaysShare.canClaim(idle, "role:DOC"))
        assertTrue(PlaysShare.uploadsOpen(rec))
        assertFalse(PlaysShare.uploadsOpen(rec.copy(uploads = false)))
    }
}
