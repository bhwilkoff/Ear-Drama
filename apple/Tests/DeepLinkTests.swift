import Foundation
import Testing

/// DEEP_LINKS.md's shapes: each `eardrama://` link and its Universal Link twin
/// route alike, and the inbox opens the screen the link names.
/// Broken controls, 2026-10-24, each seen to fail before the fix was kept:
///   parse naming every link by its last path component (the old rule): the
///   search, library and person tests fail.
///   drainInbox leaving pendingSearch unset: the search drain test fails.
struct DeepLinkTests {
    private func parse(_ s: String) -> AppStore.InboxRequest? { DeepLink.parse(URL(string: s)!) }

    @Test func aSeriesLinkAndItsTwinOpenTheSeries() {
        #expect(parse("eardrama://series/suspense") == .series("suspense"))
        #expect(parse("https://eardrama.org/series/suspense") == .series("suspense"))
        #expect(parse("https://www.eardrama.org/series/suspense/") == .series("suspense"))
    }

    @Test func anEpisodeIdIsPercentDecoded() {
        #expect(parse("eardrama://episode/sus%7C1943-05-25") == .episode("sus|1943-05-25"))
        #expect(parse("https://eardrama.org/episode/sus%7C1943-05-25") == .episode("sus|1943-05-25"))
        #expect(parse("eardrama://episode/a%20b%7C%C3%A9") == .episode("a b|é"))
        #expect(parse("https://eardrama.org/episode/a%2Fb%7C1") == .episode("a/b|1"))
    }

    @Test func aPersonLinkOpensThePerson() {
        #expect(parse("https://eardrama.org/person/agnes-moorehead") == .person("agnes-moorehead"))
        #expect(parse("eardrama://person/orson%20welles") == .person("orson welles"))
    }

    @Test func searchCarriesItsQueryAndLibraryOpensTheTab() {
        #expect(parse("https://eardrama.org/search?q=sorry+wrong") == .search("sorry wrong"))
        #expect(parse("eardrama://search?q=Agnes%20M") == .search("Agnes M"))
        #expect(parse("eardrama://search") == .search(""))
        #expect(parse("https://eardrama.org/library") == .tab("library"))
        #expect(parse("https://eardrama.org/library/") == .tab("library"))
    }

    @Test func otherHostsUnknownPathsAndCallbacksOpenNothing() {
        for s in ["appname://episode/x", "https://example.com/episode/x", "https://eardrama.org/credits/",
                  "eardrama://oauth/callback?code=1", "eardrama://episode/", "https://eardrama.org/series/",
                  "https://eardrama.org/", "http://eardrama.org/series/x", "https://noteardrama.org/series/x"] {
            #expect(parse(s) == nil, "\(s)")
        }
    }

    @Test func drainingTheInboxOpensEachScreen() {
        let store = AppStore()
        store.selectedTab = .home
        store.post(.series("suspense"))
        store.post(.episode("sus|1943-05-25"))
        store.post(.person("p1"))
        _ = store.drainInbox()
        #expect(store.paths[.home]?.count == 3)

        store.post(.search("Agnes M"))
        _ = store.drainInbox()
        #expect(store.selectedTab == .search)
        #expect(store.pendingSearch == "Agnes M")
    }
}
