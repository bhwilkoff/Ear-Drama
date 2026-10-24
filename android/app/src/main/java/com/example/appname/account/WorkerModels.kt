package com.example.appname.account

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * The Worker's JSON (docs/WORKER.md, Endpoints). Times are milliseconds;
 * positions and durations are seconds on the wire and milliseconds on the
 * device. A property left at its default is not sent, so an absent part of an
 * upload is absent, never `null` (the Worker refuses `"history": null`).
 */
internal val WorkerJson = Json {
    ignoreUnknownKeys = true
    encodeDefaults = false
}

/** The build's Worker and sign-in ids. A `REPLACE_WITH` value means the owner has not set it. */
data class WorkerConfig(
    val baseUrl: String,
    val googleWebClientId: String,
    val appleServicesId: String,
    val appleReturnUrl: String,
) {
    val workerReady get() = real(baseUrl)
    val googleReady get() = workerReady && real(googleWebClientId)
    val appleReady get() = workerReady && real(appleServicesId) && real(appleReturnUrl)
    val anySignIn get() = googleReady || appleReady

    companion object {
        fun real(value: String) = value.isNotBlank() && !value.startsWith("REPLACE_WITH")
    }
}

/**
 * Everything kept about the signed-in account, encrypted at rest as one
 * record ([SessionStore]). Signing out or deleting the account clears it all.
 */
@Serializable
data class StoredAccount(
    val accessToken: String,
    val accessExpiresAt: Long,
    val refreshToken: String,
    val refreshExpiresAt: Long,
    val userId: String,
    val provider: String,
    /** The last read's `server_time`: the next read's `since`. */
    val cursor: Long = 0,
    /** True from sign-in until the signed-out history has been merged (DECISIONS 063). */
    val mergePending: Boolean = true,
    val lastSyncAt: Long? = null,
    val lastError: String? = null,
)

@Serializable
data class Session(
    @SerialName("access_token") val accessToken: String,
    @SerialName("access_expires_at") val accessExpiresAt: Long,
    @SerialName("refresh_token") val refreshToken: String,
    @SerialName("refresh_expires_at") val refreshExpiresAt: Long,
    @SerialName("user_id") val userId: String,
    val provider: String? = null,
    val created: Boolean = false,
)

@Serializable
data class HistoryRow(
    @SerialName("episode_id") val episodeId: String,
    val position: Double = 0.0,
    val duration: Double? = null,
    val finished: Boolean = false,
    val deleted: Boolean = false,
    @SerialName("updated_at") val updatedAt: Long,
    val device: String? = null,
)

@Serializable
data class FollowRow(
    @SerialName("series_id") val seriesId: String,
    val following: Boolean = true,
    @SerialName("updated_at") val updatedAt: Long,
    val device: String? = null,
)

@Serializable
data class QueueState(
    val items: List<String>,
    @SerialName("updated_at") val updatedAt: Long,
    val device: String? = null,
)

/** A `PUT /v1/sync` or `POST /v1/sync/merge` body. */
@Serializable
data class SyncUpload(
    val device: String,
    val history: List<HistoryRow>? = null,
    val follows: List<FollowRow>? = null,
    val queue: QueueState? = null,
)

/** `GET /v1/sync?since=`. */
@Serializable
data class SyncAnswer(
    @SerialName("server_time") val serverTime: Long,
    val history: List<HistoryRow> = emptyList(),
    val follows: List<FollowRow> = emptyList(),
    val queue: QueueState? = null,
)

@Serializable
internal data class UploadAnswer(@SerialName("server_time") val serverTime: Long)

@Serializable
internal data class SignInBody(
    @SerialName("id_token") val idToken: String,
    val nonce: String,
    val device: String,
)

@Serializable
internal data class RefreshBody(@SerialName("refresh_token") val refreshToken: String)

@Serializable
internal data class DeleteBody(
    @SerialName("apple_authorization_code") val appleAuthorizationCode: String? = null,
    @SerialName("apple_client_id") val appleClientId: String? = null,
)

@Serializable
internal data class WorkerProblem(val error: String? = null, val detail: kotlinx.serialization.json.JsonElement? = null)

/** A Worker answer outside 2xx, after the one retry a 401 earns. */
class WorkerException(
    val status: Int,
    val code: String?,
    /** The Worker's `detail`, a string or a list (`lines_missing`), kept as sent. */
    val detail: kotlinx.serialization.json.JsonElement? = null,
) : Exception("Worker answered $status ${code.orEmpty()}")

/** No account is signed in on this device (or it just ended). */
class SignedOutException : Exception("Not signed in")
