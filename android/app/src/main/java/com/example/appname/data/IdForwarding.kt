package com.example.appname.data

/**
 * Forwarding ids (docs/CATALOG-CONTRACT.md §3.5, catalog DECISIONS 014): the one
 * place Android resolves a stored episode id. An aliased id is the id it now is;
 * a tombstoned id left with no successor; any other id this catalog does not
 * serve is kept, since it may come from a newer catalog (a synced row, a link
 * from a newer app). The open catalog's ([CatalogDatabase.forwarding]) is handed
 * to every store that keeps episode ids, and each rewrites what it kept, once.
 */
data class IdForwarding(val aliases: Map<String, String> = emptyMap(), val tombstones: Set<String> = emptySet()) {
    /** The id [id] now is: itself when it never moved. */
    fun resolve(id: String): String = aliases[id] ?: id

    /** Left the catalog with no successor; it will not come back as itself. */
    fun isGone(id: String): Boolean = id in tombstones

    /** A list of ids forwarded: each resolved, a tombstoned one dropped, a repeat kept once, where it first stood. */
    fun forward(ids: List<String>): List<String> = ids.map(::resolve).filterNot(::isGone).distinct()

    companion object {
        val NONE = IdForwarding()
    }
}
