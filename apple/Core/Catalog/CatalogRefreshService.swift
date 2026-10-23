import Foundation
import Compression

// Fetches the full served projection and caches it on disk for CatalogStore
// (docs/CATALOG-CONTRACT.md §2, §7). Ported from Archive Watch's shipped
// CatalogRefreshService: ETag-conditional GET, streaming raw-DEFLATE inflate
// with Apple's Compression framework (no third-party zlib), a size floor, an
// integrity probe, and a swap that publishes a NEW file generation instead of
// overwriting one an open handle may be reading. First paint is the bundled
// seed; until the release URL answers, the seed is the whole catalog.

nonisolated enum CatalogSource {
    /// The one address of the full catalog (contract §2: the rolling
    /// `catalog-latest` Release). Not live yet; an unreachable URL leaves the
    /// app on its seed.
    static let releaseURL = URL(string: "https://github.com/bhwilkoff/Ear-Drama/releases/download/catalog-latest/ear-drama.sqlite.zz")!
    /// The bundled seed's resource name (copied in by the project's
    /// "Bundle catalog seed" build phase; see apple/README.md).
    static let seedResource = "ear-drama-seed"
}

actor CatalogRefreshService {
    static let shared = CatalogRefreshService()

    private static let etagKey = "catalogETag"
    private static let lastCheckedKey = "catalogLastCheckedAt"
    private static let filenameKey = "catalogFilename"
    /// The full catalog is 133 MB on disk; a far smaller inflate is a torn
    /// download, refused before the integrity probe even runs.
    static let minimumBytes = 20_000_000
    static let staleAfter: TimeInterval = 6 * 3600

    private let session: URLSession
    private let defaults: UserDefaults
    private let directory: URL
    private let sourceURL: URL
    private var isDownloading = false

    /// tvOS may write only to Caches and tmp, never Application Support.
    init(session: URLSession = .shared, defaults: UserDefaults = .standard,
         directory: URL? = nil, sourceURL: URL = CatalogSource.releaseURL) {
        self.session = session
        self.defaults = defaults
        self.directory = directory
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.sourceURL = sourceURL
    }

    /// The downloaded catalog in use, if one exists.
    func cachedDatabasePath() -> String? {
        guard let name = defaults.string(forKey: Self.filenameKey) else { return nil }
        let url = directory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url.path : nil
    }

    /// Throw away a cached catalog a read proved bad. The ETag goes with it, or
    /// the next request is answered 304 and the corruption is kept forever.
    func discardCachedDatabase(reason: String) {
        let path = cachedDatabasePath()
        defaults.removeObject(forKey: Self.etagKey)
        defaults.removeObject(forKey: Self.filenameKey)
        if let path { try? FileManager.default.removeItem(atPath: path) }
        print("[CatalogRefresh] discarded cached catalog (\(reason))")
    }

    func isStale(ttl: TimeInterval = staleAfter) -> Bool {
        let last = defaults.double(forKey: Self.lastCheckedKey)
        return last <= 0 || Date().timeIntervalSince1970 - last >= ttl
    }

    /// Returns the path of a NEWER validated catalog, or nil when the release
    /// is unchanged, unreachable, or failed validation. Never throws: every
    /// failure leaves the current catalog in place.
    func refresh(force: Bool = false) async -> String? {
        guard !isDownloading, force || isStale() else { return nil }
        isDownloading = true
        defer { isDownloading = false }
        sweepStaleGenerations()

        var request = URLRequest(url: sourceURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let etag = defaults.string(forKey: Self.etagKey), cachedDatabasePath() != nil {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        do {
            let (tmp, response) = try await session.download(for: request)
            defer { try? FileManager.default.removeItem(at: tmp) }
            guard let http = response as? HTTPURLResponse else { return nil }
            defaults.set(Date().timeIntervalSince1970, forKey: Self.lastCheckedKey)
            guard http.statusCode == 200 else { return nil }   // 304 keeps the cache
            let destination = directory.appendingPathComponent("ear-drama-\(Int(Date().timeIntervalSince1970)).sqlite")
            guard let path = try Self.install(compressed: tmp, to: destination, minimumBytes: Self.minimumBytes)
            else { return nil }
            defaults.set(destination.lastPathComponent, forKey: Self.filenameKey)
            if let etag = http.value(forHTTPHeaderField: "ETag") { defaults.set(etag, forKey: Self.etagKey) }
            return path
        } catch {
            print("[CatalogRefresh] unreachable (\(error.localizedDescription)); staying on the current catalog")
            return nil
        }
    }

    /// Inflate to a staging sibling, gate it (size floor, integrity, schema),
    /// then rename it into place. A half-written catalog never becomes live.
    nonisolated static func install(compressed: URL, to destination: URL, minimumBytes: Int) throws -> String? {
        let staging = destination.appendingPathExtension("inflating")
        try? FileManager.default.removeItem(at: staging)
        try inflate(src: compressed, dst: staging)
        let size = ((try? FileManager.default.attributesOfItem(atPath: staging.path))?[.size] as? Int) ?? 0
        guard size >= minimumBytes, CatalogDatabase.validate(path: staging.path) else {
            try? FileManager.default.removeItem(at: staging)
            return nil
        }
        try FileManager.default.moveItem(at: staging, to: destination)
        return destination.path
    }

    /// Delete every generation but the one in use; run at the START of a
    /// download, when nothing still holds a superseded file.
    private func sweepStaleGenerations() {
        let keep = defaults.string(forKey: Self.filenameKey)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in files where name.hasPrefix("ear-drama-") && name != keep
            && (name.hasSuffix(".sqlite") || name.hasSuffix(".inflating")) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    // MARK: - Streaming raw-DEFLATE inflate

    /// Inflates raw DEFLATE (`zlib.compressobj(9, DEFLATED, -15)`, the
    /// Compression framework's native COMPRESSION_ZLIB input) file to file in
    /// ~64 KB chunks. The framework advances `src_ptr` through a STABLE source
    /// buffer; it is refilled only once fully consumed (re-binding it every
    /// pass silently corrupts well-compressing data).
    nonisolated static func inflate(src: URL, dst: URL) throws {
        let input = try FileHandle(forReadingFrom: src)
        FileManager.default.createFile(atPath: dst.path, contents: nil)
        let output = try FileHandle(forWritingTo: dst)
        defer { try? input.close(); try? output.close() }

        var stream = compression_stream(
            dst_ptr: UnsafeMutablePointer<UInt8>(bitPattern: -1)!, dst_size: 0,
            src_ptr: UnsafePointer<UInt8>(bitPattern: -1)!, src_size: 0, state: nil)
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK
        else { throw CocoaError(.fileReadCorruptFile) }
        defer { compression_stream_destroy(&stream) }

        let cap = 65_536
        let srcBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: cap)
        let dstBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: cap)
        defer { srcBuf.deallocate(); dstBuf.deallocate() }

        stream.src_size = 0
        var atEOF = false
        while true {
            if stream.src_size == 0 && !atEOF {
                let chunk = input.readData(ofLength: cap)
                if chunk.isEmpty {
                    atEOF = true
                } else {
                    chunk.copyBytes(to: srcBuf, count: chunk.count)
                    stream.src_ptr = UnsafePointer(srcBuf)
                    stream.src_size = chunk.count
                }
            }
            stream.dst_ptr = dstBuf
            stream.dst_size = cap
            let flags = atEOF ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0
            let status = compression_stream_process(&stream, flags)
            let produced = cap - stream.dst_size
            if produced > 0 { output.write(Data(bytes: dstBuf, count: produced)) }
            if status == COMPRESSION_STATUS_END { break }
            guard status == COMPRESSION_STATUS_OK else { throw CocoaError(.fileReadCorruptFile) }
            // A truncated stream at EOF that makes no progress would spin.
            if atEOF && produced == 0 && stream.src_size == 0 { throw CocoaError(.fileReadCorruptFile) }
        }
    }
}
