package com.example.appname.navigation

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** DEEP_LINKS.md's shapes: each `eardrama://` link and its `https://eardrama.org` twin route alike. */
class DeepLinkTest {
    @Test fun `a series link and its twin open the series`() {
        assertEquals(InboxRequest.Series("suspense"), DeepLink.parse("eardrama://series/suspense"))
        assertEquals(InboxRequest.Series("suspense"), DeepLink.parse("https://eardrama.org/series/suspense"))
        assertEquals(InboxRequest.Series("suspense"), DeepLink.parse("https://www.eardrama.org/series/suspense/"))
    }

    @Test fun `an episode id is percent-decoded`() {
        assertEquals(InboxRequest.Item("sus|1943-05-25"), DeepLink.parse("eardrama://episode/sus%7C1943-05-25"))
        assertEquals(InboxRequest.Item("sus|1943-05-25"), DeepLink.parse("https://eardrama.org/episode/sus%7C1943-05-25"))
        assertEquals(InboxRequest.Item("a b|é"), DeepLink.parse("eardrama://episode/a%20b%7C%C3%A9"))
    }

    @Test fun `search carries its query and library opens the tab`() {
        assertEquals(InboxRequest.Search("sorry wrong"), DeepLink.parse("https://eardrama.org/search?q=sorry+wrong"))
        assertEquals(InboxRequest.Search("Agnes M"), DeepLink.parse("eardrama://search?q=Agnes%20M#x"))
        assertEquals(InboxRequest.Search(""), DeepLink.parse("eardrama://search"))
        assertEquals(InboxRequest.Tab("Library"), DeepLink.parse("https://eardrama.org/library"))
    }

    @Test fun `the template's scheme, other hosts, and unknown paths open nothing`() {
        assertNull(DeepLink.parse("appname://episode/x"))
        assertNull(DeepLink.parse("https://example.com/episode/x"))
        assertNull(DeepLink.parse("https://eardrama.org/credits/"))
        assertNull(DeepLink.parse("eardrama://oauth/callback?code=1"))
        assertNull(DeepLink.parse("eardrama://episode/"))
        assertNull(DeepLink.parse("not a url"))
    }
}
