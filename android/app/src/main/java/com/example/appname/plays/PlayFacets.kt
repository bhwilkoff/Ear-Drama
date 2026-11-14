package com.example.appname.plays

/**
 * Record's browsing of the castable library (ANDROID-DESIGN §4.9a, Decision 075; js/app.js `renderRecord`):
 * three facets and a sort. A facet's option is counted with the other two applied, and an option with
 * none is hidden unless it is the one chosen.
 */
object PlayFacets {
    val VOICES = linkedMapOf("1-2" to "1 or 2 voices", "3-5" to "3 to 5 voices", "6-10" to "6 to 10 voices", "11+" to "11 or more voices")
    val LENGTH = linkedMapOf("short" to "Under 30 min", "mid" to "30 to 60 min", "long" to "Over an hour")
    val KIND = linkedMapOf("radio" to "Radio play", "stage" to "Stage play")
    val SORT = linkedMapOf("voices" to "Fewest voices", "short" to "Shortest", "name" to "A to Z")

    /** The facets, as the chosen option of each (null for any) and the sort key. */
    data class Filter(
        val voices: String? = null,
        val length: String? = null,
        val kind: String? = null,
        val sort: String = "voices",
    ) {
        val isClear: Boolean get() = voices == null && length == null && kind == null
        fun with(facet: Facet, option: String?): Filter = when (facet) {
            Facet.Voices -> copy(voices = option)
            Facet.Length -> copy(length = option)
            Facet.Kind -> copy(kind = option)
        }
        fun chosen(facet: Facet): String? = when (facet) {
            Facet.Voices -> voices
            Facet.Length -> length
            Facet.Kind -> kind
        }
    }

    enum class Facet { Voices, Length, Kind }

    fun optionOf(script: PlayListing, facet: Facet): String? = when (facet) {
        Facet.Voices -> script.voiceBand
        Facet.Length -> script.lengthBand
        Facet.Kind -> script.kind.takeIf { it in KIND }
    }

    /** The scripts that hold every chosen facet, except [skip]'s (so its own options are counted against the other two). */
    fun <T : PlayListing> matching(scripts: List<T>, filter: Filter, skip: Facet? = null): List<T> =
        scripts.filter { s -> Facet.entries.all { f -> f == skip || filter.chosen(f) == null || optionOf(s, f) == filter.chosen(f) } }

    fun count(scripts: List<PlayListing>, filter: Filter, facet: Facet, option: String): Int =
        matching(scripts, filter, skip = facet).count { optionOf(it, facet) == option }

    /** A facet's options worth offering: those with plays, and the one chosen even with none. */
    fun options(scripts: List<PlayListing>, filter: Filter, facet: Facet, labels: Map<String, String>): List<Triple<String, String, Int>> =
        labels.mapNotNull { (key, label) ->
            val n = count(scripts, filter, facet, key)
            if (n > 0 || filter.chosen(facet) == key) Triple(key, label, n) else null
        }

    private fun name(s: PlayListing) = s.sortName ?: s.title

    fun <T : PlayListing> sorted(scripts: List<T>, sort: String): List<T> {
        val byName = compareBy<T, String>(String.CASE_INSENSITIVE_ORDER) { name(it) }
        return when (sort) {
            "short" -> scripts.sortedWith(compareBy<T> { it.minutes }.then(byName))
            "name" -> scripts.sortedWith(byName)
            else -> scripts.sortedWith(compareBy<T> { it.voices }.then(byName))
        }
    }
}
