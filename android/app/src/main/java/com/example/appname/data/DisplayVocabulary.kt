package com.example.appname.data

/**
 * docs/CATALOG-CONTRACT.md §5.5, word for word. The pipeline decides every
 * value; this only names it. An unclaimed recording is never called public
 * domain (DECISIONS 055); a clean basis the contract has no words for shows no
 * line rather than words invented here.
 */
object DisplayVocabulary {
    const val UNCLAIMED = "No rights claim known. Removed on request."

    private val CLEAN_BASIS = mapOf(
        "rec_gov_work" to "Government recording",
        "rec_librivox" to "LibriVox recording",
        "rec_pd_published_age" to "Published before 1926",
    )

    fun rightsLine(rights: String, basis: String?): String? = when (rights) {
        "unclaimed" -> UNCLAIMED
        "clean" -> basis?.let(CLEAN_BASIS::get)
        else -> null
    }

    fun variantLine(variant: String?): String? = when (variant) {
        "AFRS", "AFRTS" -> "Armed Forces Radio rebroadcast"
        else -> null
    }

    const val PARTIAL = "Incomplete copy"

    /** The served genres carry the archive.org collection prefix; the name is what follows it. */
    fun genreName(genre: String): String = genre.removePrefix("OTR-")
}
