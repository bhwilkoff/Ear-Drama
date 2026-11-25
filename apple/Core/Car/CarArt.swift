import Foundation

/// What a car picture is made from: the served picture when the record has one (and its face box, for a
/// square cut), and the label the item draws for itself otherwise (Decision 081; the views build the
/// `LabelItem` from `subject`).
nonisolated struct CarArtSource: Sendable {
    enum Subject: Sendable {
        case episode(EpisodeRow, series: SeriesRow?)
        case series(SeriesRow)
    }

    let key: String
    let served: Artwork?
    let subject: Subject
}

extension CatalogStore {
    /// The picture's recipe, or nil when the catalog no longer holds the item.
    func carArt(_ art: CarArt) async -> CarArtSource? {
        switch art {
        case let .episode(id):
            guard let row = await episodes([id]).first else { return nil }
            let series = await self.series([row.seriesKey]).first
            return CarArtSource(key: "e:\(row.id)", served: row.seriesWindowArt, subject: .episode(row, series: series))
        case let .series(key):
            guard let row = await series([key]).first else { return nil }
            return CarArtSource(key: "s:\(row.key)", served: row.windowArt, subject: .series(row))
        }
    }
}

/// The car's pictures as files: a served picture is fetched once (at most `maxBytes`) and kept; when it
/// cannot be fetched (offline, refused, too large) the item's own label, drawn on the device, takes its
/// place, so a download shows its art with no signal. The directory is trimmed to `maxFiles` files. The
/// twin of Android's `CarArtStore`.
nonisolated final class CarArtStore: Sendable {
    static let maxBytes = 1_500_000
    static let maxFiles = 200

    private let dir: URL
    private let download: @Sendable (URL) async -> Data?

    init(dir: URL, download: @escaping @Sendable (URL) async -> Data? = CarArtStore.fetch) {
        self.dir = dir
        self.download = download
    }

    static func fetch(_ url: URL) async -> Data? {
        let request = URLRequest(url: url, timeoutInterval: 4)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty, data.count <= maxBytes else { return nil }
        return data
    }

    private static func name(_ s: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in s.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return String(hash, radix: 16)
    }

    /// The picture for `key`: the served one at `served` when it can be had, else the label `label` draws.
    func data(key: String, served: URL?, label: () async -> Data?) async -> Data? {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let served {
            let file = dir.appending(path: Self.name(served.absoluteString) + ".img")
            if let kept = read(file) { return kept }
            if let bytes = await download(served) { return write(file, bytes) }
        }
        let drawn = dir.appending(path: "l-" + Self.name(key) + ".png")
        if let kept = read(drawn) { return kept }
        guard let bytes = await label() else { return nil }
        return write(drawn, bytes)
    }

    private func read(_ file: URL) -> Data? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
        return data
    }

    private func write(_ file: URL, _ bytes: Data) -> Data {
        try? bytes.write(to: file, options: .atomic)
        trim()
        return bytes
    }

    private func trim() {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys) else { return }
        let dated = files.map { ($0, (try? $0.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast) }
        for (file, _) in dated.sorted(by: { $0.1 < $1.1 }).prefix(max(0, files.count - Self.maxFiles)) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
