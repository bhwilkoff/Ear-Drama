package com.example.appname.data

/**
 * Forwarding ids (docs/CATALOG-CONTRACT.md §3.5, catalog DECISIONS 014): the one
 * place Android resolves a stored episode id or series key. An aliased one is the
 * one it now is; a tombstoned one left with no successor; any other this catalog
 * does not serve is kept, since it may come from a newer catalog (a synced row, a
 * link from a newer app). The open catalog's ([CatalogDatabase.forwarding]) is
 * handed to every store that keeps ids or keys, and each rewrites what it kept, once.
 */
data class IdForwarding(
    val aliases: Map<String, String> = emptyMap(),
    val tombstones: Set<String> = emptySet(),
    val seriesAliases: Map<String, String> = emptyMap(),
    val seriesTombstones: Set<String> = emptySet(),
) {
    /** The id [id] now is: itself when it never moved. */
    fun resolve(id: String): String = aliases[id] ?: id

    /** Left the catalog with no successor; it will not come back as itself. */
    fun isGone(id: String): Boolean = id in tombstones

    /** The series key [key] now is: itself when it never moved. */
    fun resolveSeries(key: String): String = seriesAliases[key] ?: key

    /** A series key that left with no successor. */
    fun isSeriesGone(key: String): Boolean = key in seriesTombstones

    /** A list of ids forwarded: each resolved, a tombstoned one dropped, a repeat kept once, where it first stood. */
    fun forward(ids: List<String>): List<String> = ids.map(::resolve).filterNot(::isGone).distinct()

    companion object {
        val NONE = IdForwarding()
    }
}
