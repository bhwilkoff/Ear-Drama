package com.example.appname.data

/**
 * The air date a search names, the same rule on every platform
 * (catalog/tests/golden/search_text.json; web `API.dateQuery`): "1954",
 * "August 1954", "Aug 2, 1954", "2 August 1954", "1954-08", "1954-08-02", or
 * "8/2/1954". [prefix] is YYYY, YYYY-MM, or YYYY-MM-DD, matched against
 * `air_date`; [rest] is the query's other words, which narrow it by title,
 * series, and people.
 */
data class DateQuery(val prefix: String, val rest: String) {
    companion object {
        val MONTHS = listOf(
            "January", "February", "March", "April", "May", "June", "July", "August",
            "September", "October", "November", "December",
        )
        private val ISO = Regex("""^(\d{4})-(\d{1,2})(?:-(\d{1,2}))?$""")
        private val SLASHED = Regex("""^(\d{1,2})/(\d{1,2})/(\d{4})$""")

        fun parse(query: String): DateQuery? {
            val t = query.lowercase().split(Regex("""[\s,]+""")).filter { it.isNotEmpty() }
            fun at(i: Int) = t.getOrNull(i)
            for (i in t.indices) {
                var y: String? = null
                var m = 0
                var d = 0
                var used = 1
                val tok = t[i]
                val iso = ISO.matchEntire(tok)
                val us = SLASHED.matchEntire(tok)
                if (iso != null) {
                    val day = iso.groupValues[3].ifEmpty { null }
                    if (day != null && !isDay(day)) continue
                    y = iso.groupValues[1]; m = iso.groupValues[2].toInt(); d = day?.toInt() ?: 0
                } else if (us != null && isDay(us.groupValues[2])) {
                    y = us.groupValues[3]; m = us.groupValues[1].toInt(); d = us.groupValues[2].toInt()
                } else if (month(tok) > 0 && isDay(at(i + 1)) && isYear(at(i + 2))) {
                    m = month(tok); d = t[i + 1].toInt(); y = t[i + 2]; used = 3
                } else if (month(tok) > 0 && isYear(at(i + 1))) {
                    m = month(tok); y = t[i + 1]; used = 2
                } else if (isDay(tok) && month(at(i + 1) ?: "") > 0 && isYear(at(i + 2))) {
                    d = tok.toInt(); m = month(t[i + 1]); y = t[i + 2]; used = 3
                } else if (isYear(tok)) {
                    y = tok
                }
                if (!isYear(y) || m !in 0..12 || (d != 0 && m == 0)) continue
                val prefix = buildString {
                    append(y)
                    if (m > 0) append("-%02d".format(m))
                    if (d > 0) append("-%02d".format(d))
                }
                return DateQuery(prefix, (t.subList(0, i) + t.subList(i + used, t.size)).joinToString(" "))
            }
            return null
        }

        /** The prefix as a person reads it: "1954", "August 1954", "August 2, 1954". */
        fun label(prefix: String): String {
            val p = prefix.split("-")
            val m = p.getOrNull(1)?.toIntOrNull()?.takeIf { it in 1..12 } ?: return p[0]
            val d = p.getOrNull(2)?.toIntOrNull()
            return if (d != null) "${MONTHS[m - 1]} $d, ${p[0]}" else "${MONTHS[m - 1]} ${p[0]}"
        }

        private fun isYear(s: String?) = s != null && s.length == 4 && s.all { it in '0'..'9' } && s.toInt() in 1900..2099

        private fun isDay(s: String?) = s != null && s.length in 1..2 && s.all { it in '0'..'9' } && s.toInt() in 1..31

        private fun month(token: String): Int {
            val s = token.removeSuffix(".")
            if (s == "sept") return 9
            val i = MONTHS.indexOfFirst { val low = it.lowercase(); low == s || (s.length == 3 && low.startsWith(s)) }
            return i + 1
        }
    }
}
