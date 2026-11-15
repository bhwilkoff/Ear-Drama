package com.example.appname.plays

import android.content.Context
import android.content.SharedPreferences
import androidx.core.content.edit
import androidx.room.Dao
import androidx.room.Database
import androidx.room.Entity
import androidx.room.Index
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.PrimaryKey
import androidx.room.Query
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.Transaction
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject

// Where a person's marks live (PLAYS-DESIGN §2.10 rule 11): Room on this device, one row a mark keyed by script id,
// private, never uploaded and never in the cloud backup (res/xml/backup_rules.xml, data_extraction_rules.xml) until the
// sync phase. The prefs are the web's `ed.marks.prefs` in SharedPreferences, as ReaderStore keeps the reader's.

@Entity(tableName = "marks", indices = [Index("scriptId")])
data class MarkEntity(
    val scriptId: String,
    val title: String?,
    @PrimaryKey val id: String,
    val kind: String,
    val line: String,
    val start: Int,
    val end: Int,
    val text: String,
    val prefix: String,
    val suffix: String,
    val revision: String?,
    val created: Long,
    val updated: Long,
    val hue: String?,
    val label: String?,
    val note: String?,
    val grp: String?,
) {
    fun toMark(): Mark? = Mark(id, kind, line, start, end, text, prefix, suffix, revision, created, updated, hue, label, note, grp)
        .takeIf(MarksCore::valid)

    companion object {
        fun of(scriptId: String, title: String?, m: Mark) = MarkEntity(
            scriptId, title, m.id, m.kind, m.line, m.start, m.end, m.text, m.prefix, m.suffix, m.revision, m.created, m.updated, m.hue, m.label, m.note, m.group,
        )
    }
}

@Dao
abstract class MarkDao {
    @Query("SELECT * FROM marks WHERE scriptId = :scriptId ORDER BY created")
    abstract suspend fun marksFor(scriptId: String): List<MarkEntity>

    @Query("SELECT * FROM marks ORDER BY scriptId, created")
    abstract suspend fun all(): List<MarkEntity>

    @Query("DELETE FROM marks WHERE scriptId = :scriptId")
    abstract suspend fun deleteFor(scriptId: String)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    abstract suspend fun insertAll(rows: List<MarkEntity>)

    @Transaction
    open suspend fun replaceAll(scriptId: String, rows: List<MarkEntity>) {
        deleteFor(scriptId)
        if (rows.isNotEmpty()) insertAll(rows)
    }
}

@Database(entities = [MarkEntity::class], version = 1, exportSchema = false)
abstract class MarksDatabase : RoomDatabase() {
    abstract fun marks(): MarkDao

    companion object {
        @Volatile private var instance: MarksDatabase? = null

        fun get(context: Context): MarksDatabase = instance ?: synchronized(this) {
            instance ?: Room.databaseBuilder(context.applicationContext, MarksDatabase::class.java, "marks.db").build().also { instance = it }
        }
    }
}

/** Marks and prefs for the person's scripts. A read that fails reads as none; a write that fails says so (§2.6, never swallowed). */
class MarksRepository(private val dao: MarkDao) {
    /** A play's stored marks, in the order made; `[]` when none or unreadable. A row of an unknown kind is dropped. */
    suspend fun load(scriptId: String): List<Mark> =
        try {
            dao.marksFor(scriptId).mapNotNull { it.toMark() }
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: Exception) {
            emptyList()
        }

    /** Stores a play's marks (the placed and the not placed together); false when the device would not keep them. */
    suspend fun save(scriptId: String, title: String?, marks: List<Mark>): Boolean =
        try {
            dao.replaceAll(scriptId, marks.map { MarkEntity.of(scriptId, title, it) })
            true
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: Exception) {
            false
        }

    /** Every play's marks on this device, sorted by script id, for the person's own export (docs/EXPORT.md `marks[]`). */
    suspend fun exportRows(): List<MarksCore.ExportRow> =
        try {
            dao.all().sortedBy { it.scriptId }.mapNotNull { e -> e.toMark()?.let { MarksCore.exportRow(e.scriptId, e.title, it) } }
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: Exception) {
            emptyList()
        }
}

/** Show marks and the last highlight hue, on this device (`ed.marks.prefs`, the web's shape). */
data class MarkPrefs(val show: Boolean = true, val hue: String = MarksCore.HUES[0])

class MarksPrefsStore(private val store: SharedPreferences) {
    fun prefs(): MarkPrefs = decode(store.getString(KEY, null))

    fun save(p: MarkPrefs) = store.edit { putString(KEY, encode(p)) }

    companion object {
        const val KEY = "ed.marks.prefs"

        fun decode(text: String?): MarkPrefs {
            val o = runCatching { Json.parseToJsonElement(text.orEmpty()).jsonObject }.getOrNull() ?: return MarkPrefs()
            val show = (o["show"] as? JsonPrimitive)?.booleanOrNull != false
            val hue = (o["hue"] as? JsonPrimitive)?.contentOrNull?.takeIf { it in MarksCore.HUES } ?: MarksCore.HUES[0]
            return MarkPrefs(show, hue)
        }

        fun encode(p: MarkPrefs): String = JsonObject(mapOf("show" to JsonPrimitive(p.show), "hue" to JsonPrimitive(p.hue))).toString()
    }
}
