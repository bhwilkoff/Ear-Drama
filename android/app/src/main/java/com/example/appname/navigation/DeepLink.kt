package com.example.appname.navigation

import com.example.appname.plays.PlaysShare

/**
 * DEEP_LINKS.md's URL shapes, parsed into inbox requests. Every
 * `eardrama://` link has its `https://eardrama.org` twin with the same path:
 * `series/{key}`, `episode/{percent-encoded id}`, `search?q=`, `library`.
 * Anything else (the OAuth callback, an unknown path) yields nothing, so the
 * app opens where it was. Pure Kotlin: the manifest's filters stay off until
 * the store records exist, and this is tested without a device.
 */
object DeepLink {
    const val SCHEME = "eardrama"
    private val HOSTS = setOf("eardrama.org", "www.eardrama.org")

    fun parse(url: String): InboxRequest? {
        val schemeEnd = url.indexOf("://").takeIf { it > 0 } ?: return null
        val scheme = url.substring(0, schemeEnd).lowercase()
        val rest = url.substring(schemeEnd + 3).substringBefore('#')
        val fragment = url.substringAfter('#', "")
        val query = rest.substringAfter('?', "")
        val parts = rest.substringBefore('?').split('/')
        val segments = when (scheme) {
            SCHEME -> parts
            "https" -> parts.takeIf { it.first().lowercase() in HOSTS }?.drop(1) ?: return null
            else -> return null
        }.filter { it.isNotEmpty() }.map(::percentDecode)
        // `/?room=CODE`, the web's room link (DEEP_LINKS.md); the sheet normalizes the code.
        // `/?view=library&tab=dramas#invite=TOKEN`, what the web's 404 forwarder leaves.
        if (segments.isEmpty()) {
            PlaysShare.inviteToken("", fragment)?.let { return InboxRequest.Invite(it) }
            return queryParam(query, "room")?.trim()?.takeIf { it.isNotEmpty() && it.length <= 32 }?.let(InboxRequest::Room)
        }
        return when (segments.firstOrNull()) {
            "series" -> segments.getOrNull(1)?.let(InboxRequest::Series)
            "episode" -> segments.getOrNull(1)?.let(InboxRequest::Item)
            "search" -> InboxRequest.Search(queryParam(query, "q").orEmpty())
            "library" -> InboxRequest.Tab(Tab.Library.name)
            // `/invite#TOKEN` (DEEP_LINKS.md): the token rides the fragment; a malformed one opens nothing.
            "invite" -> PlaysShare.inviteToken("/" + segments.joinToString("/"), fragment)?.let(InboxRequest::Invite)
            else -> null
        }
    }

    private fun queryParam(query: String, name: String): String? =
        query.split('&').firstOrNull { it.substringBefore('=') == name }
            ?.substringAfter('=', "")?.replace('+', ' ')?.let(::percentDecode)

    /** `%XX` escapes as UTF-8; a malformed escape is kept as typed. */
    private fun percentDecode(s: String): String {
        if ('%' !in s) return s
        val out = java.io.ByteArrayOutputStream()
        var i = 0
        while (i < s.length) {
            val c = s[i]
            val hex = if (c == '%' && i + 2 <= s.lastIndex) s.substring(i + 1, i + 3).toIntOrNull(16) else null
            if (hex != null) {
                out.write(hex)
                i += 3
            } else {
                out.write(c.toString().toByteArray(Charsets.UTF_8))
                i += 1
            }
        }
        return String(out.toByteArray(), Charsets.UTF_8)
    }
}
