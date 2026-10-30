package com.example.appname.navigation

/**
 * The website's addresses: the https twins of the app's links (DEEP_LINKS.md).
 * A share always carries the twin, so a person without the app lands on the
 * web page. Mirrors Apple's `SiteLinks`.
 */
object SiteLinks {
    const val ROOT = "https://eardrama.org/"
    const val CREDITS = ROOT + "credits/"
    const val PRIVACY = ROOT + "privacy/"
    const val TAKEDOWN = ROOT + "takedown/"

    val PAGES = listOf("Credits" to CREDITS, "Privacy" to PRIVACY, "Take-down requests" to TAKEDOWN)

    fun episode(id: String): String = ROOT + "episode/" + component(id)

    fun series(key: String): String = ROOT + "series/" + component(key)

    fun drama(id: String): String = ROOT + "drama/" + component(id)

    private const val UNRESERVED = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()"

    /**
     * Percent-encodes exactly as JavaScript's encodeURIComponent (UTF-8, upper
     * hex), which the web's 404.html forwarder reverses with decodeURIComponent.
     * Not `java.net.URLEncoder`: that writes a space as `+` and escapes `~!*'()`.
     */
    fun component(raw: String): String {
        val out = StringBuilder()
        for (byte in raw.toByteArray(Charsets.UTF_8)) {
            val c = (byte.toInt() and 0xFF)
            if (c < 0x80 && c.toChar() in UNRESERVED) out.append(c.toChar())
            else out.append('%').append("0123456789ABCDEF"[c shr 4]).append("0123456789ABCDEF"[c and 0xF])
        }
        return out.toString()
    }
}
