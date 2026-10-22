import Testing

/// Trivial smoke test using Swift Testing (the @Test macro successor to
/// XCTest). The AppNameTests target in project.yml compiles apple/Core/
/// straight into the bundle, so Core types are in scope with no
/// `@testable import`. Run: xcodebuild test -project AppName.xcodeproj
/// -scheme AppName -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
///
/// Replace as the data layer grows. For async / actor / network tests
/// see `all-ios-skills:swift-testing`.
struct APIClientTests {
    @Test func clientResolves() async {
        let client = await APIClient.shared
        // Touching the singleton inside an async context confirms the
        // actor is reachable. Real tests assert decoded shape from a
        // mocked URLSession (see swift-testing skill).
        _ = client
    }
}
