import Foundation
import Testing

// iOS-DESIGN §4.3 and §4.1: the series page's Follow button writes the store the
// account sync carries, and Home and Library list the followed series, newest
// follow first, skipping any the catalog does not serve.

struct FollowedSeriesTests {
    private func store() -> FollowedSeries {
        let name = "follow-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return FollowedSeries(defaults: defaults)
    }

    @Test func toggleFollowsThenUnfollowsAsASyncedMarker() {
        let follows = store()
        #expect(follows.toggle("suspense", now: Date(millis: 1000)) == true)
        #expect(follows.isFollowing("suspense"))
        #expect(follows.toggle("suspense", now: Date(millis: 2000)) == false)
        #expect(!follows.isFollowing("suspense"))
        let rows = follows.syncRows()
        #expect(rows.count == 1)
        #expect(rows.first?.following == false)   // a marker, never a dropped row
        #expect(rows.first?.updatedAt == 2000)
    }

    @Test func followedKeysAreNewestFollowFirst() {
        let follows = store()
        follows.setFollowing("suspense", true, now: Date(millis: 1000))
        follows.setFollowing("lux", true, now: Date(millis: 3000))
        follows.setFollowing("gone", true, now: Date(millis: 2000))
        follows.setFollowing("gone", false, now: Date(millis: 2500))
        #expect(follows.followedKeys == ["lux", "suspense"])
    }

    @Test func homeRowIsTheFollowsInOrderMinusWhatTheCatalogLacks() throws {
        let db = try Fixture.open()
        let follows = store()
        follows.setFollowing("suspense", true, now: Date(millis: 1000))
        follows.setFollowing("notinthecatalog", true, now: Date(millis: 2000))
        follows.setFollowing("mrsorrowful", true, now: Date(millis: 3000))
        #expect(db.series(keys: follows.followedKeys).map(\.key) == ["mrsorrowful", "suspense"])
        #expect(db.series(keys: []).isEmpty)
    }
}
