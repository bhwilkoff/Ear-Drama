import Compression
import Foundation
import SQLite3
import Testing

/// The contract's query verbs (docs/CATALOG-CONTRACT.md §5) against the real
/// clean-only seed. The seed is gitignored pipeline output: build it with
/// `catalog/tools/build_projection.py --clean-only`, or point
/// TEST_RUNNER_CATALOG_SEED_PATH at a copy.
enum Seed {
    static var path: String {
        if let override = ProcessInfo.processInfo.environment["CATALOG_SEED_PATH"] { return override }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("catalog/out/publish-clean/ear-drama.sqlite").path
    }

    static func open() throws -> CatalogDatabase {
        try #require(FileManager.default.fileExists(atPath: path), "No seed at \(path)")
        return try #require(CatalogDatabase(path: path))
    }

    /// A writable copy, for fixtures that need a row the seed lacks.
    static func copy() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("seed-\(UUID().uuidString).sqlite")
        try FileManager.default.copyItem(atPath: path, toPath: url.path)
        return url
    }

    static func exec(_ url: URL, _ sql: String) throws {
        var h: OpaquePointer?
        try #require(sqlite3_open(url.path, &h) == SQLITE_OK)
        defer { sqlite3_close(h) }
        try #require(sqlite3_exec(h, sql, nil, nil, nil) == SQLITE_OK)
    }
}

struct CatalogQueryTests {
    @Test func browseListsEverySeriesByName() throws {
        let db = try Seed.open()
        let all = db.seriesBrowse()
        #expect(all.count > 600)
        #expect(all.allSatisfy { $0.episodeCount > 0 })
        let names = all.map { $0.name.lowercased() }
        #expect(names == names.sorted())
    }

    @Test func browseFiltersByGenreNetworkAndDecade() throws {
        let db = try Seed.open()
        let variety = db.seriesBrowse(genre: "OTR-Variety")
        #expect(Set(variety.map(\.key)) == ["jubilee", "commandperformance", "countryexpress"])
        let afrs = db.seriesBrowse(network: "AFRS")
        #expect(!afrs.isEmpty && afrs.allSatisfy { $0.networks.contains("AFRS") })
        let forties = db.seriesBrowse(decade: 1940)
        #expect(forties.contains { $0.key == "jubilee" })
        #expect(db.seriesBrowse(decade: 1990).allSatisfy { ($0.lastDate ?? "") >= "1990" })
        #expect(db.genres().contains("OTR-Variety"))
    }

    /// R1: oldest first in every series and season; undated rows last.
    @Test func seriesPageIsOldestFirstBySeason() throws {
        let db = try Seed.open()
        let page = try #require(db.seriesPage(key: "jubilee"))
        let dates = page.episodes.compactMap(\.airDate)
        #expect(dates.count > 100)
        #expect(dates == dates.sorted())
        let seasons = page.seasons.compactMap(\.season)
        #expect(seasons == seasons.sorted())
        #expect(page.seasons.allSatisfy { group in group.episodes.allSatisfy { $0.season == group.season } })
        if let undated = page.seasons.firstIndex(where: { $0.season == nil }) {
            #expect(undated == page.seasons.count - 1)
        }
    }

    @Test func undatedSeriesFollowsItsLogNumbers() throws {
        let db = try Seed.open()
        let page = try #require(db.seriesPage(key: "librivox16504"))
        let numbers = page.episodes.compactMap(\.number)
        #expect(numbers.count == page.episodes.count)
        #expect(numbers == numbers.sorted())
        #expect(page.seasons.count == 1 && page.seasons[0].season == nil)
    }

    @Test func episodeDetailJoinsCreditsAndRanksRecordings() throws {
        let db = try Seed.open()
        let detail = try #require(db.episodeDetail(id: "jubilee|1946-01-07"))
        #expect(detail.episode.seriesName == "Jubilee")
        #expect(detail.recordings.map(\.rank) == [0, 1])
        #expect(detail.defaultRecording?.archiveID == "jubilee_202008")
        #expect(detail.defaultRecording?.url.absoluteString.hasPrefix("https://archive.org/download/") == true)
        #expect(!detail.credits.isEmpty && detail.credits.allSatisfy { !$0.name.isEmpty })
        #expect(detail.rightsLine == "Government recording")
        #expect(db.episodeDetail(id: "no-such|episode") == nil)
    }

    @Test func aliasesForwardOldIDs() throws {
        let url = try Seed.copy()
        defer { try? FileManager.default.removeItem(at: url) }
        try Seed.exec(url, "INSERT INTO episode_aliases VALUES ('jubilee|old', 'jubilee|1946-01-07');")
        let db = try #require(CatalogDatabase(path: url.path))
        #expect(db.episodeDetail(id: "jubilee|old")?.episode.id == "jubilee|1946-01-07")
        #expect(db.episodes(ids: ["jubilee|old"]).map(\.id) == ["jubilee|1946-01-07"])
    }

    /// §3.4: word-prefix, never substring.
    @Test func searchIsWordPrefixNotSubstring() throws {
        let db = try Seed.open()
        let hits = db.search("sorr").episodes
        #expect(hits.contains { $0.id == "librivox16504|s13" })   // "The Sorrows of Acadia"
        // Control: "orrow" is inside "Sorrows" but starts no word, so a
        // substring match would find it and a word-prefix match must not.
        #expect(db.search("orrow").episodes.contains { $0.id == "librivox16504|s13" } == false)
        #expect(db.search("Jubil").series.contains { $0.key == "jubilee" })
        #expect(db.search("ubilee").series.isEmpty)
    }

    @Test func searchNeverInterpretsTypedSyntax() throws {
        #expect(CatalogDatabase.ftsQuery("sorr") == "\"sorr\"*")
        #expect(CatalogDatabase.ftsQuery("Lone \"Ranger\" OR NEAR(") == "\"Lone\"* \"Ranger\"* \"OR\"* \"NEAR\"*")
        #expect(CatalogDatabase.ftsQuery("  ** ") == nil)
        // An unbalanced quote is dropped, not handed to FTS5 as syntax.
        let db = try Seed.open()
        #expect(db.search("\"sorr").episodes.contains { $0.id == "librivox16504|s13" })
    }

    /// recommendAnd: shelves drop a never-recommended episode; the surfaces
    /// the listener drives (series page, search, Detail) keep it.
    @Test func shelvesApplyRecommendAndOnly() throws {
        let url = try Seed.copy()
        defer { try? FileManager.default.removeItem(at: url) }
        let target = "jubilee|1943-05-24"
        try Seed.exec(url, "UPDATE episodes SET air_date = '1943-07-04' WHERE id = 'jubilee|1943-05-24';")
        let before = try #require(CatalogDatabase(path: url.path))
        #expect(before.shelf(.onThisDay(month: 7, day: 4)).contains { $0.id == target })   // control
        try Seed.exec(url, "UPDATE episodes SET no_recommend = 'test' WHERE id = '\(target)';")
        let db = try #require(CatalogDatabase(path: url.path))
        #expect(db.shelf(.onThisDay(month: 7, day: 4)).contains { $0.id == target } == false)
        #expect(db.shelf(.genreFirsts("OTR-Variety")).contains { $0.id == target } == false)
        #expect(db.seriesPage(key: "jubilee")?.episodes.contains { $0.id == target } == true)
        #expect(db.episodeDetail(id: target) != nil)
    }

    @Test func genreShelfIsEachSeriesFirstEpisode() throws {
        let db = try Seed.open()
        let shelf = db.shelf(.genreFirsts("OTR-Variety"))
        #expect(Set(shelf.map(\.seriesKey)).count == shelf.count)
        for episode in shelf {
            let first = try #require(db.seriesPage(key: episode.seriesKey)?.episodes.first)
            #expect(first.id == episode.id)
        }
    }

    @Test func withPersonListsCreditedEpisodes() throws {
        let db = try Seed.open()
        let detail = try #require(db.episodeDetail(id: "jubilee|1946-01-07"))
        let person = try #require(detail.credits.first)
        #expect(db.withPerson(person.personID).contains { $0.id == "jubilee|1946-01-07" })
    }

    @Test func queueStaysInsideTheSeries() throws {
        let db = try Seed.open()
        let page = try #require(db.seriesPage(key: "jubilee"))
        let first = try #require(page.episodes.first)
        let queue = PlaybackQueue.following(first.id, in: page)
        #expect(queue.first?.id == page.episodes[1].id)
        #expect(queue.allSatisfy { $0.seriesKey == "jubilee" })
        #expect(queue.count <= PlaybackQueue.maximum)
        #expect(PlaybackQueue.following(try #require(page.episodes.last).id, in: page).isEmpty)
    }
}

/// Contract §5.5: the rights line. Unclaimed is never called public domain.
struct RightsDisplayTests {
    @Test func linesFollowTheContract() {
        #expect(RightsDisplay.line(rights: "unclaimed", basis: "rec_orphan_unclaimed")
                == "No rights claim known. Removed on request.")
        #expect(RightsDisplay.line(rights: "clean", basis: "rec_gov_work") == "Government recording")
        #expect(RightsDisplay.line(rights: "clean", basis: "rec_librivox") == "LibriVox recording")
        #expect(RightsDisplay.line(rights: "clean", basis: "rec_pd_published_age") == "Published before 1926")
        for basis in [nil, "rec_cc_corroborated", "rec_orphan_unclaimed", "anything"] {
            for rights in ["clean", "unclaimed", "other"] {
                #expect(!RightsDisplay.line(rights: rights, basis: basis).lowercased().contains("public domain"))
            }
        }
    }
}

/// The refresh swap gate (§2): a torn download never becomes the live file.
struct CatalogInstallTests {
    private func deflate(_ data: Data) throws -> Data {
        let capacity = data.count + 1_000_000
        var out = Data(count: capacity)
        let written = out.withUnsafeMutableBytes { dst in
            data.withUnsafeBytes { src in
                compression_encode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, capacity,
                                          src.bindMemory(to: UInt8.self).baseAddress!, data.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        try #require(written > 0)
        return out.prefix(written)
    }

    @Test func inflatesValidatesAndInstalls() throws {
        let raw = try Data(contentsOf: URL(fileURLWithPath: Seed.path))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let zz = dir.appendingPathComponent("catalog.sqlite.zz")
        let compressed = try deflate(raw)
        try compressed.write(to: zz)

        let good = dir.appendingPathComponent("good.sqlite")
        let installed = try CatalogRefreshService.install(compressed: zz, to: good, minimumBytes: 1_000_000)
        #expect(installed == good.path)
        #expect(try Data(contentsOf: good) == raw)
        #expect(CatalogDatabase(path: good.path) != nil)

        // The size floor refuses a catalog smaller than the full one must be.
        let small = dir.appendingPathComponent("small.sqlite")
        #expect(try CatalogRefreshService.install(compressed: zz, to: small, minimumBytes: raw.count + 1) == nil)
        #expect(!FileManager.default.fileExists(atPath: small.path))

        // A torn download either fails to inflate or fails the integrity gate.
        let torn = dir.appendingPathComponent("torn.sqlite.zz")
        try compressed.prefix(compressed.count / 2).write(to: torn)
        let tornDestination = dir.appendingPathComponent("torn.sqlite")
        let result = try? CatalogRefreshService.install(compressed: torn, to: tornDestination, minimumBytes: 1)
        #expect(result == nil)
        #expect(!FileManager.default.fileExists(atPath: tornDestination.path))
    }
}
