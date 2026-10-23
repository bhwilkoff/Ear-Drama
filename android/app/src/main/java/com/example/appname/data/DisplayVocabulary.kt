package com.example.appname.data

/**
 * docs/CATALOG-CONTRACT.md §5.5, word for word. The pipeline decides every
 * value; this only names it. An unclaimed recording is never called public
 * domain (DECISIONS 055); a clean basis the contract has no words for shows no
 * line rather than words invented here.
 */
object DisplayVocabulary {
    const val UNCLAIMED = "No rights claim known. Removed on request."

    /**
     * The contract's words, for a catalog that predates `meta.rightsLines`.
     * A catalog that publishes the key is read instead ([CatalogDatabase.rightsLines]).
     */
    val CONTRACT_RIGHTS_LINES: Map<String, String> = mapOf(
        "unclaimed" to UNCLAIMED,
        "rec_gov_work" to "Government recording",
        "rec_librivox" to "LibriVox recording",
        "rec_pd_published_age" to "Published before 1926",
        "rec_cc_corroborated" to "Creative Commons recording",
    )

    /** [lines] is the published `meta.rightsLines`, keyed by `unclaimed` and each clean basis. */
    fun rightsLine(rights: String, basis: String?, lines: Map<String, String> = CONTRACT_RIGHTS_LINES): String? =
        when (rights) {
            "unclaimed" -> lines["unclaimed"]
            "clean" -> basis?.takeIf { it != "unclaimed" }?.let(lines::get)
            else -> null
        }

    fun variantLine(variant: String?): String? = when (variant) {
        "AFRS", "AFRTS" -> "Armed Forces Radio rebroadcast"
        else -> null
    }

    const val PARTIAL = "Incomplete copy"

    /** The eight genre codes and their names, as catalog/tools/genres.py `NAMES` gives them. */
    private val GENRES = linkedMapOf(
        "drama" to "Drama",
        "mystery" to "Mystery",
        "scifi" to "Science fiction",
        "western" to "Western",
        "comedy" to "Comedy",
        "news" to "News",
        "documentary" to "Documentary",
        "serial" to "Serials",
    )

    /** A genre's name, or null for a value that is not one of the eight (an older catalog's label). */
    fun genreName(genre: String): String? = GENRES[genre]
}
