import Compression
import Foundation
import Testing

/// "Last checked" is stamped only when a check truly completes, and what a
/// killed refresh leaves behind is repaired at launch. Mirrors Android's
/// CatalogFilesTest.
nonisolated final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, body) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                           headerFields: ["ETag": "\"v2\""])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

@Suite(.serialized) struct CatalogRefreshStampTests {
    final class Env: @unchecked Sendable {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "stamp-\(UUID().uuidString)"
        let defaults: UserDefaults
        let raw: Data
        let compressed: Data
        init() throws {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defaults = UserDefaults(suiteName: suite)!
            let raw = try Data(contentsOf: try Fixture.make())
            self.raw = raw
            let capacity = raw.count + 1_000_000
            var out = Data(count: capacity)
            let written = out.withUnsafeMutableBytes { dst in
                raw.withUnsafeBytes { src in
                    compression_encode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, capacity,
                                              src.bindMemory(to: UInt8.self).baseAddress!, raw.count,
                                              nil, COMPRESSION_ZLIB)
                }
            }
            compressed = out.prefix(written)
        }
        func service(minimumBytes: Int? = nil) -> CatalogRefreshService {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [StubProtocol.self]
            return CatalogRefreshService(session: URLSession(configuration: config), defaults: UserDefaults(suiteName: suite)!,
                                         directory: dir, minimumBytes: minimumBytes ?? raw.count)
        }
        var stamp: Double { defaults.double(forKey: "catalogLastCheckedAt") }
        func cleanup() {
            try? FileManager.default.removeItem(at: dir)
            defaults.removePersistentDomain(forName: suite)
        }
    }

    struct Offline: Error {}

    @Test func anInterruptedDownloadLeavesNoStamp() async throws {
        let env = try Env(); defer { env.cleanup() }
        StubProtocol.handler = { _ in throw Offline() }
        #expect(await env.service().refresh(force: true) == nil)
        #expect(env.stamp == 0)
        #expect(await env.service().isStale())
    }

    @Test func aTornInflateLeavesNoStamp() async throws {
        let env = try Env(); defer { env.cleanup() }
        let torn = env.compressed.prefix(env.compressed.count / 2)
        StubProtocol.handler = { _ in (200, Data(torn)) }
        #expect(await env.service().refresh(force: true) == nil)
        #expect(env.stamp == 0)
    }

    @Test func aCompletedSwapStampsAndCaches() async throws {
        let env = try Env(); defer { env.cleanup() }
        let body = env.compressed
        StubProtocol.handler = { _ in (200, body) }
        let service = env.service()
        let path = await service.refresh(force: true)
        #expect(path != nil)
        #expect(env.stamp > 0)
        #expect(await service.cachedDatabasePath() == path)
        #expect(await service.isStale() == false)
    }

    @Test func unchangedAndNotPublishedStampButOnlyWithACatalogInUse() async throws {
        let env = try Env(); defer { env.cleanup() }
        StubProtocol.handler = { _ in (404, Data()) }
        #expect(await env.service().refresh(force: true) == nil)
        #expect(env.stamp > 0)
        // No downloaded catalog in use: a launch checks whatever the stamp says.
        #expect(await env.service().isStale())

        let body = env.compressed
        StubProtocol.handler = { _ in (200, body) }
        _ = await env.service().refresh(force: true)
        env.defaults.removeObject(forKey: "catalogLastCheckedAt")
        StubProtocol.handler = { _ in (304, Data()) }
        #expect(await env.service().refresh(force: true) == nil)
        #expect(env.stamp > 0)
        #expect(await env.service().isStale() == false)
    }

    @Test func aServerErrorLeavesNoStamp() async throws {
        let env = try Env(); defer { env.cleanup() }
        StubProtocol.handler = { _ in (503, Data()) }
        #expect(await env.service().refresh(force: true) == nil)
        #expect(env.stamp == 0)
    }

    @Test func aCompleteStagedFileLeftByAKillIsPromoted() async throws {
        let env = try Env(); defer { env.cleanup() }
        // Killed after the rename but before the filename was recorded.
        try env.raw.write(to: env.dir.appendingPathComponent("ear-drama-100.sqlite"))
        let service = env.service()
        await service.recoverStaging()
        #expect(await service.cachedDatabasePath()?.hasSuffix("ear-drama-100.sqlite") == true)
        #expect(await service.isStale() == false)

        // Killed after inflating, before the rename.
        let other = env.service()
        try env.raw.write(to: env.dir.appendingPathComponent("ear-drama-200.sqlite.inflating"))
        await other.recoverStaging()
        #expect(await other.cachedDatabasePath()?.hasSuffix("ear-drama-200.sqlite") == true)
        #expect(!FileManager.default.fileExists(atPath: env.dir.appendingPathComponent("ear-drama-100.sqlite").path))
    }

    @Test func aTruncatedOrSmallStagedFileIsDiscardedAndTheStampKept() async throws {
        let env = try Env(); defer { env.cleanup() }
        let body = env.compressed
        StubProtocol.handler = { _ in (200, body) }
        let service = env.service()
        let live = try #require(await service.refresh(force: true))
        let stamp = env.stamp

        try env.raw.prefix(env.raw.count / 2)
            .write(to: env.dir.appendingPathComponent("ear-drama-9999999999.sqlite.inflating"))
        try Data(count: 10).write(to: env.dir.appendingPathComponent("ear-drama-9999999998.sqlite"))
        await service.recoverStaging()
        #expect(await service.cachedDatabasePath() == live)
        #expect(env.stamp == stamp)
        let left = try FileManager.default.contentsOfDirectory(atPath: env.dir.path)
        #expect(left == [URL(fileURLWithPath: live).lastPathComponent])
    }

    @Test func discardingTheCacheDropsTheStamp() async throws {
        let env = try Env(); defer { env.cleanup() }
        let body = env.compressed
        StubProtocol.handler = { _ in (200, body) }
        let service = env.service()
        _ = await service.refresh(force: true)
        await service.discardCachedDatabase(reason: "test")
        #expect(env.stamp == 0)
        #expect(await service.isStale())
    }
}
