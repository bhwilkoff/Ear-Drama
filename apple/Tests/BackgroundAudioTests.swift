import Foundation
import Testing

struct BackgroundAudioTests {
    /// The app's Info.plist file: a UIBackgroundModes set as an INFOPLIST_KEY build setting never
    /// reached the built plist, and the phone paused playback on leaving the app (iPhone 12, 2026-11-01).
    @Test func theInfoPlistDeclaresBackgroundAudio() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/EarDrama-Info.plist")
        let plist = try #require(NSDictionary(contentsOf: url) as? [String: Any])
        let modes = plist["UIBackgroundModes"] as? [String]
        #expect(modes?.contains("audio") == true, "UIBackgroundModes must carry audio")
    }
}
