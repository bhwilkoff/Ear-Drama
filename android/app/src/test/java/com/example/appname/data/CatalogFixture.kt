package com.example.appname.data

import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import androidx.sqlite.execSQL
import java.io.File

/**
 * A small catalog in the served projection's exact schema
 * (catalog/tools/build_projection.py), with the rows each verb's test needs:
 * a dated series over two seasons plus undated episodes, an alias, a
 * never-recommended broadcast, an unclaimed one, and credits.
 */
object CatalogFixture {
    private val SCHEMA = listOf(
        "CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT)",
        "CREATE TABLE series (key TEXT PRIMARY KEY, name TEXT NOT NULL, genre TEXT, first_date TEXT, " +
            "last_date TEXT, networks TEXT, episodes INTEGER NOT NULL)",
        "CREATE TABLE episodes (id TEXT PRIMARY KEY, series_key TEXT NOT NULL, air_date TEXT, date_source TEXT, " +
            "season TEXT, num INTEGER, title TEXT, aka TEXT, length_s REAL, rights TEXT NOT NULL, rights_basis TEXT, " +
            "no_recommend TEXT, network TEXT, network_source TEXT, has_transcript INTEGER NOT NULL DEFAULT 0, " +
            "gain_db REAL, detail_json TEXT)",
        "CREATE TABLE recordings (episode_id TEXT NOT NULL, rank INTEGER NOT NULL, archive_id TEXT NOT NULL, " +
            "url TEXT NOT NULL, format TEXT, kbps INTEGER, length_s REAL, variant TEXT, " +
            "partial INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (episode_id, rank))",
        "CREATE TABLE people (id TEXT PRIMARY KEY, name TEXT NOT NULL, birth TEXT, death TEXT)",
        "CREATE TABLE credits (episode_id TEXT NOT NULL, person_id TEXT NOT NULL, role TEXT, character TEXT)",
        "CREATE TABLE episode_aliases (old_id TEXT PRIMARY KEY, new_id TEXT NOT NULL)",
        "CREATE VIRTUAL TABLE episodes_fts USING fts5(title, series, people, content='', tokenize='unicode61')",
        "CREATE INDEX episodes_series ON episodes (series_key, air_date)",
    )

    data class Ep(
        val id: String,
        val series: String,
        val date: String?,
        val season: String?,
        val title: String,
        val num: Int? = null,
        val rights: String = "clean",
        val basis: String? = "rec_gov_work",
        val noRecommend: String? = null,
    )

    val EPISODES = listOf(
        // Inserted out of order on purpose: the verbs must sort, not the file.
        Ep("sus|1943-01-07", "suspense", "1943-01-07", "1942-43", "The Hitchhiker"),
        Ep("sus|1942-06-17", "suspense", "1942-06-17", "1941-42", "The Burning Court"),
        Ep("sus|1943-05-25", "suspense", "1943-05-25", "1942-43", "Sorry, Wrong Number"),
        Ep("sus|1943-02-04", "suspense", "1943-02-04", "1942-43", "Banquo's Chair", noRecommend = "fixture reason"),
        Ep("sus|1943-03-11", "suspense", "1943-03-11", "1942-43", "Mr. Sorrowful", rights = "unclaimed",
            basis = "rec_orphan_unclaimed"),
        Ep("sus|u2", "suspense", null, null, "Undated Two", num = 2),
        Ep("sus|u1", "suspense", null, null, "Undated One", num = 1),
        Ep("cp|1943-02-24", "commandperformance", "1943-02-24", "1942-43", "Bob Hope Bing Crosby"),
        Ep("cp|1944-01-07", "commandperformance", "1944-01-07", "1943-44", "Dinah Shore"),
        Ep("cp|1945-02-04", "commandperformance", "1945-02-04", "1944-45", "Frank Sinatra"),
    )

    fun build(dir: File): File {
        val file = File(dir, "fixture.sqlite")
        file.delete()
        val c = BundledSQLiteDriver().open(file.path)
        try {
            SCHEMA.forEach { c.execSQL(it) }
            c.execSQL("INSERT INTO meta VALUES ('schemaVersion', '1')")
            c.execSQL(
                "INSERT INTO series VALUES ('suspense', 'Suspense', 'OTR-Thriller', '1942-06-17', '1943-05-25', " +
                    "'[\"CBS\"]', 7)",
            )
            c.execSQL(
                "INSERT INTO series VALUES ('commandperformance', 'Command Performance', 'OTR-Variety', " +
                    "'1942-03-01', '1944-01-07', '[\"AFRS\"]', 2)",
            )
            c.execSQL("INSERT INTO people VALUES ('p1', 'Agnes Moorehead', NULL, NULL)")
            c.execSQL("INSERT INTO people VALUES ('p2', 'Orson Welles', NULL, NULL)")
            EPISODES.forEach { e ->
                val st = c.prepare(
                    "INSERT INTO episodes (id, series_key, air_date, season, num, title, length_s, rights, " +
                        "rights_basis, no_recommend, network) VALUES (?, ?, ?, ?, ?, ?, 1800, ?, ?, ?, 'CBS')",
                )
                try {
                    st.bindText(1, e.id); st.bindText(2, e.series)
                    if (e.date == null) st.bindNull(3) else st.bindText(3, e.date)
                    if (e.season == null) st.bindNull(4) else st.bindText(4, e.season)
                    if (e.num == null) st.bindNull(5) else st.bindLong(5, e.num.toLong())
                    st.bindText(6, e.title); st.bindText(7, e.rights)
                    if (e.basis == null) st.bindNull(8) else st.bindText(8, e.basis)
                    if (e.noRecommend == null) st.bindNull(9) else st.bindText(9, e.noRecommend)
                    st.step()
                } finally {
                    st.close()
                }
                val seriesName = if (e.series == "suspense") "Suspense" else "Command Performance"
                val people = if (e.title == "Sorry, Wrong Number") "Agnes Moorehead" else ""
                val fts = c.prepare(
                    "INSERT INTO episodes_fts (rowid, title, series, people) " +
                        "SELECT rowid, ?, ?, ? FROM episodes WHERE id = ?",
                )
                try {
                    fts.bindText(1, e.title); fts.bindText(2, seriesName); fts.bindText(3, people); fts.bindText(4, e.id)
                    fts.step()
                } finally {
                    fts.close()
                }
                // Two copies, inserted rank 1 first; Detail must list them rank 0 first.
                c.execSQL(
                    "INSERT INTO recordings VALUES ('${e.id}', 1, 'alt_${e.id.hashCode()}', " +
                        "'https://archive.org/download/alt/b.mp3', 'VBR MP3', 32, 1800, 'AFRS', 1)",
                )
                c.execSQL(
                    "INSERT INTO recordings VALUES ('${e.id}', 0, 'main_${e.id.hashCode()}', " +
                        "'https://archive.org/download/main/a%20b.mp3', 'VBR MP3', 64, 1800, NULL, 0)",
                )
            }
            c.execSQL("INSERT INTO credits VALUES ('sus|1943-05-25', 'p1', 'cast', 'Mrs. Stevenson')")
            c.execSQL("INSERT INTO credits VALUES ('sus|1943-05-25', 'p2', 'host', NULL)")
            c.execSQL("INSERT INTO episode_aliases VALUES ('suspense|sorry-wrong-number', 'sus|1943-05-25')")
        } finally {
            c.close()
        }
        return file
    }
}
