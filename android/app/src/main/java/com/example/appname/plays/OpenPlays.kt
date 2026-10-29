package com.example.appname.plays

import com.example.appname.account.WorkerApi
import com.example.appname.account.WorkerException
import java.io.IOException
import java.net.URLEncoder
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.SerialName
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
