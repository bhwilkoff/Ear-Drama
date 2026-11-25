import Foundation
import Testing

/// A CarPlay scene configuration once crashed launch (TestFlight 1.0.59). Until Apple grants
/// `com.apple.developer.carplay-audio` the app declares no car scene and carries no car entitlement:
/// the phone's scene manifest is exactly what it was before CarPlay, and `AppDelegate_iOS` routes only a
/// car scene session to the car (iOS never makes one without the entitlement).
struct CarSceneManifestTests {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private static func text(_ path: String) throws -> String {
        try String(contentsOf: root.appending(path: path), encoding: .utf8)
    }

    @Test func theInfoPlistDeclaresNoCarScene() throws {
        for plist in ["apple/Resources/EarDrama-Info.plist", "apple/Resources/EarDrama-tvOS-Info.plist"] {
            let body = try Self.text(plist)
            #expect(!body.contains("CPTemplateApplicationScene"), "\(plist)")
            #expect(!body.contains("UISceneConfigurations"), "\(plist)")
            #expect(!body.contains("CarPlaySceneDelegate"), "\(plist)")
        }
        #expect(try Self.text("project.yml").contains("INFOPLIST_KEY_UIApplicationSceneManifest_Generation: YES"),
                "the phone's manifest stays generated, with no car role")
    }

    @Test func noEntitlementsFileCarriesTheCarPlayKeyYet() throws {
        let resources = Self.root.appending(path: "apple/Resources")
        let files = try FileManager.default.contentsOfDirectory(atPath: resources.path).filter { $0.hasSuffix(".entitlements") }.sorted()
        #expect(files.contains("EarDrama.entitlements"))
        for file in files {
            #expect(!(try Self.text("apple/Resources/\(file)").contains("carplay")), "\(file)")
        }
        #expect(!(try Self.text("project.yml").contains("carplay-audio")))
    }

    @Test func onlyACarSceneSessionIsRoutedToTheCarDelegate() throws {
        let source = try Self.text("apple/iOS/CarPlay_iOS.swift").split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
        #expect(source.contains("guard connectingSceneSession.role == .carTemplateApplication else"))
        #expect(source.contains("return UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)"))
        #expect(!source.contains("connectingSceneSession.configuration"), "that wraps SwiftUI's own delegate and overflows the stack at launch")
    }

    @Test func controlTheCheckSeesACarSceneInAManifest() {
        #expect("<key>CPTemplateApplicationSceneSessionRoleApplication</key>".contains("CPTemplateApplicationScene"))
    }
}
