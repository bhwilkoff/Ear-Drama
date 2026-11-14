package com.example.appname.plays

import android.content.SharedPreferences
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/**
 * What the reader keeps on this device, in the keys and JSON the web uses (`ed.reader.prefs`, `ed.reader.pos`):
 * the settings, and per script the line and the part last read as, newest 60. No account, nothing uploaded.
 */
class ReaderStore(private val store: SharedPreferences) {
    fun prefs(): ReaderPrefs = decodePrefs(store.getString(PREFS, null))

    fun savePrefs(prefs: ReaderPrefs) = store.edit().putString(PREFS, encodePrefs(prefs)).apply()

    fun position(scriptId: String): Map<String, String?> = decodePositions(store.getString(POS, null))[scriptId].orEmpty()

    fun savePosition(scriptId: String, line: String?, part: String?) {
        val next = ReaderMath.remember(decodePositions(store.getString(POS, null)), scriptId, mapOf("line" to line, "part" to part))
        store.edit().putString(POS, encodePositions(next)).apply()
    }

    /** Volume keys turn pages: off until the person turns it on in Text. */
    var volumeKeys: Boolean
        get() = store.getBoolean(VOLUME, false)
        set(on) = store.edit().putBoolean(VOLUME, on).apply()

    companion object {
        const val PREFS = "ed.reader.prefs"
        const val POS = "ed.reader.pos"
        const val VOLUME = "ed.reader.volume"

        fun decodePrefs(text: String?): ReaderPrefs {
            val o = runCatching { Json.parseToJsonElement(text.orEmpty()).jsonObject }.getOrNull()
            fun prim(key: String): JsonPrimitive? = (o?.get(key) as? JsonPrimitive)?.takeIf { it !is JsonNull }
            val size = prim("size")?.takeIf { !it.isString }?.intOrNull
            return ReaderMath.normalizePrefs(prim("layout")?.takeIf { it.isString }?.contentOrNull, size, prim("spacing")?.takeIf { it.isString }?.contentOrNull)
        }

        private val full = Json { encodeDefaults = true }

        fun encodePrefs(p: ReaderPrefs): String = full.encodeToString(ReaderPrefs.serializer(), p)

        fun decodePositions(text: String?): Map<String, Map<String, String?>> {
            val o = runCatching { Json.parseToJsonElement(text.orEmpty()).jsonObject }.getOrNull() ?: return emptyMap()
            val out = LinkedHashMap<String, Map<String, String?>>()
            for ((id, v) in o) {
                val e = (v as? JsonObject) ?: continue
                out[id] = e.mapValues { (_, x) -> (x as? JsonPrimitive)?.takeIf { it !is JsonNull }?.contentOrNull }
            }
            return out
        }

        fun encodePositions(p: Map<String, Map<String, String?>>): String = JsonObject(
            p.mapValues { (_, e) -> JsonObject(e.mapValues { (_, x) -> if (x == null) JsonNull else JsonPrimitive(x) }) },
        ).toString()
    }
}
