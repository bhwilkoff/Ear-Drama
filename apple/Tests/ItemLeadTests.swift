import Foundation
import Testing

// WEB-DESIGN §6.4g: the same golden cases as js/api.test.js "item pages: the series lead, the pictures row, the play lead",
// plus the head window's shape rules (heroArt) and the marked year on the strip.

struct ItemLeadTests {
    private func pic(_ name: String, _ w: Int? = 600, _ h: Int? = 800, evidence: Bool = true) -> Artwork {
        Artwork(url: URL(string: "https://upload.example/\(name).jpg")!, width: w, height: h,
                evidence: evidence ? URL(string: "https://commons.wikimedia.org/wiki/File:\(name)") : nil)
    }

    @Test func aWideHeroLeadsAnUprightOneDoesNot() {
        #expect(ItemLead.seriesLead(hero: pic("h", 1200, 600), picture: pic("p"))?.url.lastPathComponent == "h.jpg", "a wide hero leads")
        #expect(ItemLead.seriesLead(hero: pic("h", 600, 800), picture: pic("p"))?.url.lastPathComponent == "p.jpg",
                "control: an upright hero is not one; the picture leads")
        #expect(ItemLead.seriesLead(hero: nil, picture: nil) == nil, "nothing: the label")
    }

    @Test func theGalleryDrawsOnlyFromTwoEvidencedPictures() {
        let lead = pic("a")
        #expect(ItemLead.gallery([pic("a"), pic("b"), pic("c")], lead: lead).map { $0.url.lastPathComponent } == ["b.jpg", "c.jpg"],
                "the lead is left out; two remain")
        #expect(ItemLead.gallery([pic("a"), pic("b")], lead: lead).isEmpty, "control: one picture after the lead draws no row")
        #expect(ItemLead.gallery([pic("b"), pic("b"), pic("c", 0, 0)], lead: nil).isEmpty,
                "control: a repeat and a picture with no size do not count")
        #expect(ItemLead.gallery([pic("b", evidence: false), pic("c")], lead: nil).isEmpty,
                "control: a picture with no evidence does not count")
    }

    @Test func aPlayLeadsWithItsTitlePageThenItsAuthor() {
        #expect(ItemLead.playLead(titlePage: pic("t"), authorArt: pic("a"))?.url.lastPathComponent == "t.jpg", "a title page leads a play")
        #expect(ItemLead.playLead(titlePage: nil, authorArt: pic("a", 1, 1))?.url.lastPathComponent == "a.jpg", "else the author")
        #expect(ItemLead.playLead(titlePage: nil, production: pic("p"), authorArt: pic("a"))?.url.lastPathComponent == "p.jpg", "a production photograph leads over the author")
        #expect(ItemLead.playLead(titlePage: pic("t"), production: pic("p"), authorArt: nil)?.url.lastPathComponent == "t.jpg", "control: a title page still leads a production photograph")
        #expect(ItemLead.playLead(titlePage: nil, authorArt: nil) == nil, "control: else its page")
    }

    /// B15b: This Is Your FBI's picture left 13 pt of board beside it on an iPhone 12. Broken control, 2026-11-24:
    /// `nearFill = 1` (the cap always binds) fails the first two.
    @Test func aPictureThatNearlyFillsTheBoardFillsIt() {
        let near = ItemLead.window(art: pic("n", 850, 1000), width: 358)
        #expect(near.size.width == 358 && abs(near.size.height - 358 / 0.85) < 0.01, "0.95 of the board: it spans the board, uncropped")
        let plate = ItemLead.window(art: pic("w", 1200, 1000), width: 440)
        #expect(plate.plate && plate.size.width == 440, "a plate too")
        let narrow = ItemLead.window(art: pic("t", 700, 1000), width: 358)
        #expect(abs(narrow.size.width - 280) < 0.01 && narrow.size.height == 400, "control: an upright print keeps its cap, the board plainly beside it")
        let wide = ItemLead.window(art: pic("w", 1500, 1000), width: 900)
        #expect(wide.size.height == 440 && abs(wide.size.width - 660) < 0.01, "control: a capped plate sits at the start")
        let beside = ItemLead.window(art: pic("n", 850, 1000), width: 900)
        #expect(beside.size.width == 320, "beside the words the column is the slot")
    }

    @Test func aHeadPictureKeepsItsOwnShape() {
        let plate = ItemLead.window(art: pic("w", 1600, 800), width: 390)
        #expect(plate.plate && plate.size.width <= 390 && abs(plate.size.width / plate.size.height - 2) < 0.01, "a wide picture is a plate at its aspect")
        let tall = ItemLead.window(art: pic("u", 600, 900), width: 390)
        #expect(!tall.plate && tall.size.height <= 400 && abs(tall.size.width / tall.size.height - 600.0 / 900) < 0.01,
                "an upright picture stands at its own shape, at most 400 tall")
        let beside = ItemLead.window(art: pic("u", 600, 900), width: 900)
        #expect(beside.size.width <= 320, "beside the words an upright picture is at most 320 wide")
        let label = ItemLead.window(art: nil, width: 390)
        #expect(label.size == CGSize(width: 390, height: 390) && !label.plate, "the label is the column's width on a phone")
        #expect(ItemLead.window(art: nil, width: 900).size == CGSize(width: 320, height: 320), "and 320 beside the words")
        #expect(ItemLead.window(art: pic("s", 150, 150), width: 390).size == CGSize(width: 390, height: 390),
                "control: a short side under 160 px is not shown; the label stands in")
        #expect(ItemLead.shown(pic("n", nil, nil)) == nil, "control: a picture with no published size is not shown")
    }

    @Test func anUploadTaggedTitleGivesWayToTheBroadcastDate() {
        func ep(_ title: String?, date: String?, number: Int? = nil) -> EpisodeRow {
            EpisodeRow(id: "s|\(date ?? "")", seriesKey: "s", seriesName: "Suspense", airDate: date, season: nil, number: number, title: title,
                       lengthSeconds: nil, rights: "unclaimed", rightsBasis: nil, network: nil)
        }
        #expect(ItemLead.episodeTitle(ep("The Lodger", date: "1943-06-17")) == "The Lodger")
        #expect(ItemLead.episodeTitle(ep("AbyM #026 The Telltale Bottle", date: "1943-06-17")).contains("1943"), "a tagged title shows the date")
        #expect(ItemLead.episodeTitle(ep("AbyM #026 X", date: nil, number: 7)) == "No. 7", "else its number")
        #expect(ItemLead.episodeTitle(ep("AbyM #026 X", date: nil)) == "Suspense", "else its show")
    }

    @Test func theMarkedYearIsTheOnlyBarAtFullInk() {
        let n = Double(Grammar.runAxis.hi - Grammar.runAxis.lo + 1)
        let from1942 = Double(1942 - Grammar.runAxis.lo) / n
        let from1943 = Double(1943 - Grammar.runAxis.lo) / n
        #expect(Grammar.barDimmed(from: from1942, markYear: 1942) == false)
        #expect(Grammar.barDimmed(from: from1943, markYear: 1942) == true, "the show's other years sit at 45 %")
        #expect(Grammar.barDimmed(from: from1943, markYear: nil) == false, "control: no marked year dims nothing")
    }
}
