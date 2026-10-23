package com.example.appname.navigation

import org.junit.Assert.assertEquals
import org.junit.Test

/** Share carries the https twin (DEEP_LINKS.md), encoded exactly as the web's encodeURIComponent. */
class SiteLinksTest {
    /** Goldens printed by node 2026-10-23: `encodeURIComponent(s)` for each key. */
    private val goldens = mapOf(
        "lux-radio|1943-05-25 Café & 'x'(1)!~*/?#" to "lux-radio%7C1943-05-25%20Caf%C3%A9%20%26%20'x'(1)!~*%2F%3F%23",
        "a+b=c;d,e:f@g\$h" to "a%2Bb%3Dc%3Bd%2Ce%3Af%40g%24h",
        "日本 😀" to "%E6%97%A5%E6%9C%AC%20%F0%9F%98%80",
        "100%" to "100%25",
    )

    @Test fun `component matches encodeURIComponent`() {
        goldens.forEach { (raw, encoded) -> assertEquals(raw, encoded, SiteLinks.component(raw)) }
    }

    @Test fun `episode and series shares are the https twins, as Apple's`() {
        assertEquals("https://eardrama.org/episode/lux-radio%7C1943-05-25", SiteLinks.episode("lux-radio|1943-05-25"))
        assertEquals("https://eardrama.org/series/lux-radio", SiteLinks.series("lux-radio"))
    }

    @Test fun `a shared link parses back to the same screen`() {
        val id = "lux-radio|1943-05-25 Café & 'x'(1)"
        assertEquals(InboxRequest.Item(id), DeepLink.parse(SiteLinks.episode(id)))
        assertEquals(InboxRequest.Series("a b"), DeepLink.parse(SiteLinks.series("a b")))
    }
}
