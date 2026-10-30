package com.example.appname.plays

import com.example.appname.account.WorkerApi
import com.example.appname.account.WorkerException
import java.io.IOException
import java.net.URLEncoder
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.SerialName
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.Serializable

// Plays that need no account (owner, 2026-10-29; docs/WORKER.md "Open reads"): an invite link
// shows everything signed out, and finished ear dramas are listed and credited. Reads only.
// Claiming, recording, uploading, reporting and blocking stay in [PlaysApi], behind an account.

@Serializable
data class OpenPart(
    val id: String,
    val lineCount: Int = 0,
    val status: String = "open",
    /** The performer's chosen name; absent while the part is open. */
    val performer: String? = null,
)

@Serializable
data class OpenMember(val name: String = "", val director: Boolean = false)

/** A chosen take the viewer may hear; [audio] is a path for [OpenPlaysApi.audio]. */
@Serializable
data class OpenTake(
    val id: String,
    val lineID: String,
    val part: String,
    val frames: Long = 0,
    val sampleRate: Double = 0.0,
    val audio: String = "",
)

@Serializable
data class OpenArchive(val status: String = "", val url: String? = null)

/** `GET /plays/open/invite`: the play an invite opens, for someone not signed in. */
@Serializable
data class OpenInvite(
    val id: String,
    val scriptID: String,
    val scriptRevision: String,
    val title: String,
    val source: String? = null,
    val parts: List<OpenPart> = emptyList(),
    val members: List<OpenMember> = emptyList(),
    val takes: List<OpenTake> = emptyList(),
    val chosen: Map<String, String> = emptyMap(),
    val next: String? = null,
    val archive: OpenArchive? = null,
    @SerialName("expires_at") val expiresAt: Long = 0,
)

@Serializable
data class FinishedCredit(val part: String, val name: String = "")

/** One finished ear drama; a credit with an empty [FinishedCredit.name] is a performer who is gone. */
@Serializable
data class FinishedPlay(
    val id: String,
    @SerialName("script_id") val scriptId: String = "",
    val title: String,
    val source: String? = null,
    val credits: List<FinishedCredit> = emptyList(),
    @SerialName("archive_url") val archiveUrl: String,
    /** Milliseconds since 1970 on the Worker's clock. */
    @SerialName("published_at") val publishedAt: Long = 0,
)

/** Newest published first; [nextCursor] goes back as `cursor` for the next page, null ends the list. */
@Serializable
data class FinishedPage(
    val productions: List<FinishedPlay> = emptyList(),
    @SerialName("next_cursor") val nextCursor: String? = null,
)

/** A revoked or expired invite (the Worker's plain 410). */
val PlaysException.isGone: Boolean get() = code == "invite_gone"

class OpenPlaysApi(private val worker: WorkerApi) {
    private val p = "/v1/plays"
    private fun enc(s: String) = URLEncoder.encode(s, "UTF-8").replace("+", "%20")

    private suspend fun read(path: String, headers: Map<String, String> = emptyMap()): ByteArray = try {
        worker.openBytes(path, headers)
    } catch (e: CancellationException) {
        throw e
    } catch (e: WorkerException) {
        throw PlaysException(
            e.code.orEmpty(),
            when (e.status) {
                429 -> PlaysException.Kind.RateLimited
                503 -> PlaysException.Kind.NotConfigured
                else -> PlaysException.Kind.Refused
            },
            e.detail,
        )
    } catch (e: IOException) {
        throw PlaysException("", PlaysException.Kind.Offline)
    }

    private suspend inline fun <reified T> decode(path: String, headers: Map<String, String> = emptyMap()): T =
        ShareJson.decodeFromString(read(path, headers).decodeToString())

    /** The token rides the `x-invite` header, never the path. */
    suspend fun openInvite(token: String): OpenInvite = decode("$p/open/invite", mapOf(INVITE_HEADER to token))

    suspend fun audio(token: String, takeId: String): ByteArray =
        read("$p/open/invite/takes/${enc(takeId)}/audio", mapOf(INVITE_HEADER to token))

    suspend fun finished(limit: Int? = null, cursor: String? = null): FinishedPage {
        val query = listOfNotNull(limit?.let { "limit=$it" }, cursor?.let { "cursor=${enc(it)}" })
        return decode("$p/finished" + if (query.isEmpty()) "" else "?" + query.joinToString("&"))
    }

    suspend fun finished(id: String): FinishedPlay = decode("$p/finished/${enc(id)}")

    companion object {
        const val INVITE_HEADER = "x-invite"
    }
}

/** What the open screens decide from the Worker's answers; pure, so a JVM test holds the rules. */
object OpenPlaysView {
    /** Newest published first, ties by id descending: the Worker's stated order, kept if a page arrives shuffled. */
    fun newestFirst(plays: List<FinishedPlay>): List<FinishedPlay> =
        plays.sortedWith(compareByDescending<FinishedPlay> { it.publishedAt }.thenByDescending { it.id })

    /** The performers' chosen names, once each, in script order. A removed account's empty name is never shown or replaced. */
    fun names(play: FinishedPlay): List<String> =
        play.credits.map { it.name.trim() }.filter { it.isNotEmpty() }.distinct()

    /** The tile's credit line: the first [max] names, then how many more. Null when no one is credited. */
    fun creditLine(play: FinishedPlay, max: Int = 3): String? {
        val all = names(play)
        if (all.isEmpty()) return null
        val shown = all.take(max).joinToString(", ")
        return if (all.size > max) "$shown +${all.size - max}" else shown
    }

    /** The takes to play, in the script's order ([lineOrder]); a part's own takes when [part] is given. Takes the script does not know follow in the Worker's order. */
    fun playOrder(invite: OpenInvite, lineOrder: List<String>, part: String? = null): List<OpenTake> {
        val rank = lineOrder.withIndex().associate { it.value to it.index }
        return invite.takes
            .filter { part == null || it.part == part }
            .withIndex()
            .sortedWith(compareBy({ rank[it.value.lineID] ?: Int.MAX_VALUE }, { it.index }))
            .map { it.value }
    }

    /** "October 2026" for a publish time, in UTC so every device reads one date. */
    fun published(millis: Long): String? =
        if (millis <= 0) null
        else java.time.Instant.ofEpochMilli(millis).atZone(java.time.ZoneOffset.UTC)
            .format(java.time.format.DateTimeFormatter.ofPattern("MMMM yyyy", java.util.Locale.US))

    /** A part that has a take to hear. */
    fun hearable(invite: OpenInvite, part: String): Boolean = invite.takes.any { it.part == part }
}

/** Picks the file a finished drama plays from archive.org's `/metadata/<item>` answer (internet-archive-source section 4). */
object ArchivePick {
    /** The item id: the last path segment of the item's page. */
    fun itemId(archiveUrl: String): String? =
        archiveUrl.substringBefore('?').trimEnd('/').substringAfterLast('/').takeIf { it.isNotEmpty() && "://" !in it }

    /**
     * The `/download/` URL of an MP3 the item holds: never a private file or an old revision, a whole-play
     * file before a numbered per-line one, then by name. Null while no MP3 derivative exists yet.
     */
    fun pick(item: String, metadata: String): String? {
        val files = try {
            ShareJson.parseToJsonElement(metadata).jsonObject["files"]?.jsonArray
        } catch (e: Exception) {
            null
        } ?: return null
        val names = files.mapNotNull { f ->
            val o = f.jsonObject
            val name = o["name"]?.jsonPrimitive?.contentOrNull ?: return@mapNotNull null
            val format = o["format"]?.jsonPrimitive?.contentOrNull.orEmpty()
            val private = o["private"]?.jsonPrimitive?.contentOrNull == "true"
            name.takeIf { !private && "MP3" in format.uppercase() && !name.startsWith("history/") && !name.contains("~") }
        }
        val whole = names.filter { !Regex("^\\d{4}-").containsMatchIn(it) }.sorted()
        val name = whole.firstOrNull() ?: names.sorted().firstOrNull() ?: return null
        return "https://archive.org/download/$item/" + name.split('/').joinToString("/") { URLEncoder.encode(it, "UTF-8").replace("+", "%20") }
    }
}

/** What a drama's Listen can do: the answer is cached on the list for the session. */
sealed interface DramaAudio {
    data object Checking : DramaAudio
    data class Ready(val url: String) : DramaAudio
    /** archive.org holds no MP3 yet (derivatives are made later). */
    data object Deriving : DramaAudio
    data object Failed : DramaAudio
}

/** The finished ear dramas for Home's shelf and Browse's scope, read with no account. */
class FinishedList(private val api: OpenPlaysApi, private val metadata: suspend (String) -> String = { error("no metadata reader") }) {
    private val audio = mutableMapOf<String, DramaAudio>()

    /** The drama's playable file, looked up once per session and kept in memory; a failed lookup is tried again. */
    suspend fun audioFor(play: FinishedPlay): DramaAudio {
        audio[play.id]?.let { return it }
        val item = ArchivePick.itemId(play.archiveUrl) ?: return DramaAudio.Failed
        val found = try {
            ArchivePick.pick(item, metadata(item))?.let { DramaAudio.Ready(it) } ?: DramaAudio.Deriving
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            return DramaAudio.Failed
        }
        if (found is DramaAudio.Ready) audio[play.id] = found
        return found
    }

    sealed interface State {
        data object Loading : State
        data class Ready(val plays: List<FinishedPlay>) : State
        data class Failed(val offline: Boolean) : State
    }

    private val _state = kotlinx.coroutines.flow.MutableStateFlow<State>(State.Loading)
    val state: kotlinx.coroutines.flow.StateFlow<State> = _state

    suspend fun load() {
        _state.value = try {
            State.Ready(OpenPlaysView.newestFirst(api.finished(limit = 50).productions))
        } catch (e: CancellationException) {
            throw e
        } catch (e: PlaysException) {
            State.Failed(e.kind == PlaysException.Kind.Offline)
        } catch (e: Exception) {
            State.Failed(false)
        }
    }
}
