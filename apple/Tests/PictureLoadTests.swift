import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

// A portrait must not become a monogram because its fetch was cancelled or throttled (2026-11-04:
// a person's page and iPad Home drew monograms for people whose Voices tiles drew their portraits).
@Suite(.serialized) struct PictureLoadTests {
    private nonisolated final class Stub: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var statuses: [Int] = []
        nonisolated(unsafe) static var requests = 0
        nonisolated(unsafe) static var hang = false

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func stopLoading() {}

        override func startLoading() {
            Self.requests += 1
            if Self.hang { return }
            let status = Self.statuses.isEmpty ? 200 : Self.statuses.removeFirst()
            let headers = status == 429 ? ["Retry-After": "0.01"] : [:]
            guard let url = request.url,
                  let reply = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers) else { return }
            client?.urlProtocol(self, didReceive: reply, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: status == 200 ? PictureLoadTests.png() : Data())
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    private nonisolated static func png() -> Data {
        let context = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        let data = NSMutableData()
        if let image = context?.makeImage(),
           let out = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(out, image, nil)
            CGImageDestinationFinalize(out)
        }
        return data as Data
    }

    private func session(statuses: [Int] = [], hang: Bool = false) -> URLSession {
        Stub.statuses = statuses
        Stub.requests = 0
        Stub.hang = hang
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [Stub.self]
        return URLSession(configuration: config)
    }

    private func picture() -> URL { URL(string: "https://example.test/\(UUID().uuidString).png")! }

    @Test func aThrottledPictureIsTriedAgain() async {
        let outcome = await PictureGrade.load(picture(), grade: .identity, session: session(statuses: [429, 429]))
        guard case .image = outcome else { Issue.record("expected the picture, got \(outcome)"); return }
        #expect(Stub.requests == 3)
    }

    @Test func aCancelledLoadIsNotAFailure() async {
        let hung = session(hang: true)
        let url = picture()
        let load = Task { await PictureGrade.load(url, grade: .identity, session: hung) }
        try? await Task.sleep(for: .milliseconds(100))
        load.cancel()
        let outcome = await load.value
        guard case .cancelled = outcome else { Issue.record("expected cancelled, got \(outcome)"); return }
    }

    @Test func aMissingPictureFailsAtOnce() async {
        let outcome = await PictureGrade.load(picture(), grade: .identity, session: session(statuses: [404]))
        guard case .failed = outcome else { Issue.record("expected failed, got \(outcome)"); return }
        #expect(Stub.requests == 1)
    }

    @Test func retryDelayTakesWhatTheServerAsks() {
        #expect(PictureGrade.retryDelay(attempt: 1, retryAfter: "7") == 7)
        #expect(PictureGrade.retryDelay(attempt: 1, retryAfter: "600") == 30)
        #expect(PictureGrade.retryDelay(attempt: 1, retryAfter: nil) == 1)
        #expect(PictureGrade.retryDelay(attempt: 3, retryAfter: nil) == 4)
    }
}
