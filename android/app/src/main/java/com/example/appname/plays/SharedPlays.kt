package com.example.appname.plays

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.withContext

/**
 * What the screens hold of phase 2: the Worker's record of each shared
 * production on this device, the invitation token held for this session, the
 * shared productions this person is in, and the classes. Each verb is one
 * [PlaysShare] call plus a refresh, so the cast sheet always shows the Worker's
 * answer (C7), never a guess. A refusal surfaces as [PlaysException]; the
 * screen shows [PlaysShare.line] of it.
 */
class SharedPlays(
    private val api: PlaysTransport,
    private val store: ShareStore,
    private val me: () -> String?,
    private val scripts: suspend () -> List<PlayScript>,
    private val io: CoroutineDispatcher = Dispatchers.IO,
    private val now: () -> Long = System::currentTimeMillis,
) {
    private val _records = MutableStateFlow<Map<String, SharedRecord>>(emptyMap())

    /** The Worker's record by this device's production id. */
    val records: StateFlow<Map<String, SharedRecord>> = _records

    private val _links = MutableStateFlow<Map<String, ShareLink>>(emptyMap())
    val links: StateFlow<Map<String, ShareLink>> = _links

    private val _invite = MutableStateFlow<String?>(null)

    /** The invitation token this session holds (never written to disk). */
    val invite: StateFlow<String?> = _invite

    private val _remote = MutableStateFlow<List<RemoteRow>>(emptyList())
    val remote: StateFlow<List<RemoteRow>> = _remote

    private val _classes = MutableStateFlow<ClassesAnswer?>(null)
    val classes: StateFlow<ClassesAnswer?> = _classes

    val userId: String? get() = me()

    fun hold(token: String?) {
        _invite.value = token
    }

    fun linkOf(id: String): ShareLink? = _links.value[id] ?: store.share(id)?.also { l -> _links.update { it + (id to l) } }

    private fun setLink(id: String, link: ShareLink) {
        store.setShare(id, link)
        _links.update { it + (id to link) }
    }

    /** Reads the Worker's record and makes the local one follow its parts. */
    suspend fun refresh(localId: String): SharedRecord {
        val link = linkOf(localId) ?: throw PlaysException("not_found")
        val rec = api.get(link.pid)
        withContext(io) { PlaysShare.follow(store, localId, rec, me()) }
        _records.update { it + (localId to rec) }
        return rec
    }

    suspend fun share(localId: String, script: PlayScript, name: String?): SharedRecord = withContext(io) {
        val local = store.production(localId) ?: throw PlaysException("not_found")
        val rec = PlaysShare.share(api, store, local, script, name)
        _links.update { it + (localId to ShareLink(rec.id)) }
        _records.update { it + (localId to rec) }
        rec
    }

    /** A new invite link for the director, and what its caption says. */
    suspend fun makeInvite(localId: String): Pair<String, String> {
        val pid = linkOf(localId)?.pid ?: throw PlaysException("not_found")
        val made = api.invite(pid)
        return PlaysShare.inviteLink(made.token) to PlaysShare.worksFor(made.expiresAt, now())
    }

    suspend fun claim(localId: String, part: String): SharedRecord = act(localId) { pid -> api.claim(pid, part) }

    suspend fun action(localId: String, part: String, action: String): SharedRecord =
        act(localId) { pid -> api.partAction(pid, part, action) }

    private suspend fun act(localId: String, call: suspend (String) -> SharedRecord): SharedRecord {
        val pid = linkOf(localId)?.pid ?: throw PlaysException("not_found")
        val rec = call(pid)
        withContext(io) { PlaysShare.follow(store, localId, rec, me()) }
        _records.update { it + (localId to rec) }
        return rec
    }

    suspend fun upload(localId: String, script: PlayScript): PlaysShare.UploadResult {
        val rec = _records.value[localId] ?: refresh(localId)
        val local = store.production(localId) ?: throw PlaysException("not_found")
        val result = withContext(io) { PlaysShare.upload(api, store, local, script, rec, me()) }
        refresh(localId)
        return result
    }

    /** Fetches the other members' chosen takes, then the record again; the number of takes that arrived. */
    suspend fun bringHome(localId: String, script: PlayScript): Int {
        val rec = refresh(localId)
        return withContext(io) { PlaysShare.bringHome(api, store, localId, rec, script, me()) }
    }

    /** The Worker's consent words and whether it can reach archive.org; null when it cannot be read. */
    suspend fun consent(): Consent? = try {
        api.consent()
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        null
    }

    /** A performer's own agreement at the version the Worker served; nothing is queued. */
    suspend fun agree(localId: String, consent: Consent) {
        if (!consent.publishes) throw PlaysException("publish_waits")
        val pid = linkOf(localId)?.pid ?: throw PlaysException("not_found")
        api.agree(pid, consent.version)
        setLink(localId, ShareLink(pid, consent.version))
        refresh(localId)
    }

    /** Publish after the consent screen (rule 6): agree at the version the Worker served, then queue the job. */
    suspend fun publish(localId: String, script: PlayScript, consent: Consent): PublishAnswer {
        if (!consent.publishes) throw PlaysException("publish_waits")
        val pid = linkOf(localId)?.pid ?: throw PlaysException("not_found")
        val rec = _records.value[localId] ?: refresh(localId)
        if (!PlaysShare.canPublish(rec, script, me())) throw PlaysException("consent_missing")
        api.agree(pid, consent.version)
        setLink(localId, ShareLink(pid, consent.version))
        val answer = api.publish(pid)
        refresh(localId)
        return answer
    }

    suspend fun reportTake(localId: String, takeId: String, reason: String, note: String?) {
        val pid = linkOf(localId)?.pid ?: throw PlaysException("not_found")
        api.report(pid, takeId, null, reason, note)
        refresh(localId)
    }

    suspend fun reportMember(localId: String, userId: String, reason: String, note: String?) {
        val pid = linkOf(localId)?.pid ?: throw PlaysException("not_found")
        api.report(pid, null, userId, reason, note)
        refresh(localId)
    }

    suspend fun block(localId: String, userId: String) {
        api.block(userId)
        refresh(localId)
    }

    /** Library's shared productions this person is in (`GET /productions`). */
    suspend fun loadRemote() {
        _remote.value = api.list()
    }

    suspend fun viewInvite(token: String): InviteView = api.viewInvite(token)

    /** Joins by the held invite, claiming [part]; the local production, ready to open. */
    suspend fun join(token: String, part: String, name: String?, scriptID: String, revision: String): Production {
        val script = PlaysShare.scriptFor(scripts(), scriptID, revision)
        val joined = withContext(io) { PlaysShare.join(api, store, token, part, name, script) }
        _links.update { it + (joined.local.id to (store.share(joined.local.id) ?: ShareLink(joined.rec.id))) }
        _records.update { it + (joined.local.id to joined.rec) }
        withContext(io) { PlaysShare.follow(store, joined.local.id, joined.rec, me()) }
        _invite.value = null
        return joined.local
    }

    /** Opens a shared production this device has not opened: makes it here from the bundle's script, as a join does. */
    suspend fun openRemote(pid: String): Production {
        val rec = api.get(pid)
        val script = PlaysShare.scriptFor(scripts(), rec.scriptID, rec.scriptRevision)
        val local = withContext(io) { PlaysShare.localFor(store, pid, script) }
        _links.update { it + (local.id to (store.share(local.id) ?: ShareLink(pid))) }
        _records.update { it + (local.id to rec) }
        withContext(io) { PlaysShare.follow(store, local.id, rec, me()) }
        return local
    }

    suspend fun loadClasses() {
        val answer = api.classes()
        val teaching = answer.teaching.map { row ->
            if (row.under13) runCatching { api.classDetail(row.id) }.getOrNull()?.let { row.copy(schoolConsent = it.schoolConsent) } ?: row else row
        }
        _classes.value = answer.copy(teaching = teaching)
    }

    suspend fun makeClass(name: String, under13: Boolean): ClassRow {
        val row = api.createClass(name.trim(), under13)
        loadClasses()
        return row
    }

    suspend fun joinClass(code: String): ClassRow {
        val row = api.joinClass(PlaysShare.classCodeNormalize(code), null)
        loadClasses()
        return row
    }

    /** Signed out: nothing of this person's stays in memory. */
    fun forget() {
        _records.value = emptyMap()
        _remote.value = emptyList()
        _classes.value = null
    }
}
