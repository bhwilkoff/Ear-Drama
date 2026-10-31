package com.example.appname.data

import java.time.Instant
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * Export (Human-Shaped principle 11): a person's own listening history, follows, queue, and takes
 * list as a JSON file, and the history as CSV. Built on the device from what it holds and saved by
 * the system's own save sheet; nothing is uploaded. The same keys as js/export.js and Apple's
 * `DataExport` (docs/EXPORT.md).
 */
data class DataExport(
    val exportedAtMs: Long,
    val history: List<History>,
    val following: List<Follow>,
    val queue: List<Queued>,
    val takes: List<Production>,
) {
    data class History(
        val episode: String,
        val title: String?,
        val seriesName: String?,
        val airDate: String?,
        val listenedAtMs: Long?,
        val positionSeconds: Double?,
        val durationSeconds: Double?,
    )

    data class Follow(val series: String, val name: String?)
    data class Queued(val episode: String, val title: String?, val seriesName: String?, val airDate: String?)
    data class Take(val id: String, val line: String, val part: String, val createdMs: Long, val seconds: Double, val chosen: Boolean)
    data class Production(val id: String, val title: String, val createdMs: Long, val takes: List<Take>)

    fun json(): String {
        fun obj(vararg pairs: Pair<String, JsonElement>) = JsonObject(mapOf(*pairs))
        val root = buildJsonObject {
            put("app", "Ear Drama")
            put("format", 1)
            put("exportedAt", iso(exportedAtMs))
            put("history", JsonArray(history.map { h ->
                obj(
                    "episode" to text(h.episode), "title" to text(h.title), "seriesName" to text(h.seriesName),
                    "airDate" to text(h.airDate), "listenedAt" to text(h.listenedAtMs?.let(::iso)),
                    "positionSeconds" to num(h.positionSeconds), "durationSeconds" to num(h.durationSeconds),
                )
            }))
            put("following", JsonArray(following.map { obj("series" to text(it.series), "name" to text(it.name)) }))
            put("queue", JsonArray(queue.mapIndexed { i, q ->
                obj(
                    "position" to JsonPrimitive(i + 1), "episode" to text(q.episode), "title" to text(q.title),
                    "seriesName" to text(q.seriesName), "airDate" to text(q.airDate),
                )
            }))
            put("takes", JsonArray(takes.map { p ->
                obj(
                    "production" to text(p.id), "title" to text(p.title), "created" to text(iso(p.createdMs)),
                    "takes" to JsonArray(p.takes.map { t ->
                        obj(
                            "id" to text(t.id), "lineID" to text(t.line), "part" to text(t.part),
                            "created" to text(iso(t.createdMs)), "seconds" to num(t.seconds), "chosen" to JsonPrimitive(t.chosen),
                        )
                    }),
                )
            }))
        }
        return PRETTY.encodeToString(JsonObject.serializer(), root)
    }

    fun historyCsv(): String {
        fun whole(v: Double?) = v?.toLong()?.toString()
        val lines = mutableListOf(HISTORY_COLUMNS.joinToString(","))
        for (h in history) {
            lines += listOf(
                h.episode, h.title, h.seriesName, h.airDate, h.listenedAtMs?.let(::iso), whole(h.positionSeconds), whole(h.durationSeconds),
            ).joinToString(",") { cell(it) }
        }
        return lines.joinToString("\r\n") + "\r\n"
    }

    companion object {
        val HISTORY_COLUMNS = listOf("episode", "title", "seriesName", "airDate", "listenedAt", "positionSeconds", "durationSeconds")
        private val PRETTY = kotlinx.serialization.json.Json { prettyPrint = true }

        /** Apple's Codable `Date` (seconds since 2001-01-01 UTC), which `production.json` keeps on both apps. */
        fun fromReferenceDate(seconds: Double): Long = ((seconds + 978_307_200.0) * 1000).toLong()

        fun cell(value: String?): String {
            val text = value ?: ""
            if (text.none { it == ',' || it == '"' || it == '\n' || it == '\r' }) return text
            return "\"" + text.replace("\"", "\"\"") + "\""
        }

        private fun iso(ms: Long) = Instant.ofEpochMilli(ms).toString()
        private fun text(v: String?): JsonElement = v?.let(::JsonPrimitive) ?: JsonNull
        private fun num(v: Double?): JsonElement = v?.let(::JsonPrimitive) ?: JsonNull
    }
}
