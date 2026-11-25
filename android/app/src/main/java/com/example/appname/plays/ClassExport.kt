package com.example.appname.plays

import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull

/** The class export's own-script lines (Decision 084's export, PLAYS-DESIGN §13 item 14): the Worker keeps the text, so the teacher's device adds it. */
object ClassExport {
    private val pretty = Json { prettyPrint = true; prettyPrintIndent = "  " }

    /**
     * [text] with each kept own script's lines added to its production, read by [scriptOf] (production id, script id, revision); and
     * the titles whose lines did not load. A text with nothing to add is answered as it came.
     */
    suspend fun withLines(text: String, scriptOf: suspend (pid: String, id: String, revision: String) -> PlayScript): Pair<String, List<String>> {
        val root = try { ShareJson.parseToJsonElement(text) as? JsonObject } catch (e: Exception) { null } ?: return text to emptyList()
        val productions = root["productions"] as? JsonArray ?: return text to emptyList()
        val without = ArrayList<String>()
        var changed = false
        val next = productions.map { p ->
            val o = p as? JsonObject ?: return@map p
            val script = o["script"] as? JsonObject
            if (script == null || (script["state"] as? JsonPrimitive)?.contentOrNull != "kept") return@map p
            fun field(k: String) = (o[k] as? JsonPrimitive)?.contentOrNull.orEmpty()
            try {
                val got = scriptOf(field("id"), field("script_id"), field("script_revision"))
                changed = true
                JsonObject(o + ("script" to JsonObject(script + ("lines" to OwnScripts.element(OwnShare.linesOf(got))))))
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                without += field("title")
                p
            }
        }
        if (!changed) return text to without
        return pretty.encodeToString(JsonElement.serializer(), JsonObject(root + ("productions" to JsonArray(next)))) + "\n" to without
    }
}
