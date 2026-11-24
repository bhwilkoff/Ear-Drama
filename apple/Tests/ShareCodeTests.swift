import CoreImage
import Foundation
import Testing

// tvOS-DESIGN §3.6: Share on a TV is a QR code of the episode's https twin, the same address
// every other platform's share sheet carries (SiteLinks.episode, DEEP_LINKS.md).

struct ShareCodeTests {
    @Test(arguments: ["the-shadow-1938-09-26", "suspense 1949/05:12 (a&b)"])
    func payloadIsTheCanonicalShareURL(id: String) {
        #expect(ShareCode.payload(episode: id) == SiteLinks.episode(id).absoluteString)
        #expect(ShareCode.payload(episode: id).hasPrefix("https://eardrama.org/episode/"))
    }

    @Test func codeDecodesToThePayload() throws {
        let payload = ShareCode.payload(episode: "suspense 1949/05:12 (a&b)")
        let image = try #require(ShareCode.image(payload))
        let detector = try #require(CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                               options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        let found = detector.features(in: CIImage(cgImage: image)).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
        #expect(found == [payload])
    }

    @Test func shortTextDropsTheScheme() {
        #expect(ShareCode.shortText(URL(string: "https://eardrama.org/episode/x")!) == "eardrama.org/episode/x")
    }
}
