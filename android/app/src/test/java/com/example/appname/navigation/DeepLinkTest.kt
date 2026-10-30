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

    @Test fun `a person link and its twin open the person`() {
        assertEquals(InboxRequest.Person("agnes-moorehead"), DeepLink.parse("https://eardrama.org/person/agnes-moorehead"))
        assertEquals(InboxRequest.Person("orson welles"), DeepLink.parse("eardrama://person/orson%20welles"))
        assertNull(DeepLink.parse("https://eardrama.org/person/"))
    }

    @Test fun `search carries its query and library opens the tab`() {
        assertEquals(InboxRequest.Search("sorry wrong"), DeepLink.parse("https://eardrama.org/search?q=sorry+wrong"))
        assertEquals(InboxRequest.Search("Agnes M"), DeepLink.parse("eardrama://search?q=Agnes%20M#x"))
        assertEquals(InboxRequest.Search(""), DeepLink.parse("eardrama://search"))
        assertEquals(InboxRequest.Tab("Library"), DeepLink.parse("https://eardrama.org/library"))
        assertEquals(InboxRequest.Tab("Library"), DeepLink.parse("https://eardrama.org/library/"))
    }

    @Test fun `a room link fills in its code and the bare root opens nothing`() {
        assertEquals(InboxRequest.Room("7KQ2MX"), DeepLink.parse("https://eardrama.org/?room=7KQ2MX"))
        assertEquals(InboxRequest.Room("7kq-2mx"), DeepLink.parse("https://www.eardrama.org/?room=7kq-2mx"))
        assertEquals(InboxRequest.Room("7KQ2MX"), DeepLink.parse("eardrama://?room=7KQ2MX"))
        assertNull(DeepLink.parse("https://eardrama.org/"))
        assertNull(DeepLink.parse("https://eardrama.org/?room="))
    }

    @Test fun `the template's scheme, other hosts, and unknown paths open nothing`() {
        assertNull(DeepLink.parse("appname://episode/x"))
        assertNull(DeepLink.parse("https://example.com/episode/x"))
        assertNull(DeepLink.parse("https://eardrama.org/credits/"))
        assertNull(DeepLink.parse("eardrama://oauth/callback?code=1"))
        assertNull(DeepLink.parse("eardrama://episode/"))
        assertNull(DeepLink.parse("not a url"))
    }

    @Test fun `an invite link and its twin hold the token`() {
        val token = "A".repeat(43)
        assertEquals(InboxRequest.Invite(token), DeepLink.parse("eardrama://invite#$token"))
        assertEquals(InboxRequest.Invite(token), DeepLink.parse("https://eardrama.org/invite#$token"))
        assertEquals(InboxRequest.Invite(token), DeepLink.parse("https://www.eardrama.org/invite/#$token"))
        assertEquals("the web's forwarder shape", InboxRequest.Invite(token), DeepLink.parse("https://eardrama.org/?view=library&tab=dramas#invite=$token"))
        assertNull("a short token opens nothing", DeepLink.parse("eardrama://invite#short"))
        assertNull("no token opens nothing", DeepLink.parse("eardrama://invite"))
        assertNull("another host is not ours", DeepLink.parse("https://example.org/invite#$token"))
    }

    @Test fun `a finished drama link and its twin open the drama`() {
        assertEquals(InboxRequest.Drama("P1"), DeepLink.parse("eardrama://drama/P1"))
        assertEquals(InboxRequest.Drama("P1"), DeepLink.parse("https://eardrama.org/drama/P1"))
        assertEquals(InboxRequest.Drama("a b"), DeepLink.parse("https://www.eardrama.org/drama/a%20b/"))
        assertNull("no id opens nothing", DeepLink.parse("https://eardrama.org/drama/"))
        assertNull("another host is not ours", DeepLink.parse("https://example.org/drama/P1"))
    }
}
