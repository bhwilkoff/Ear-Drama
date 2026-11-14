import Foundation
import Testing

// The play library on a device (contract §4.1, R2 port brief §2): lists read the published index when it loads
// and the bundle otherwise; a script opens from the library's file, else the bundle. The fetch is stubbed; the
// cache is a temp folder, so nothing here touches the network or the person's files.

nonisolated private func playScript(_ id: String, title: String = "T") -> PlayScript {
    let lines = (0..<6).map { ScriptLine(id: "\(id)-\($0)", kind: .speech, role: $0 % 2 == 0 ? "A" : "B", parts: [.say("word")]) }
    return PlayScript(id: id, revision: "r1", kind: "radio", title: title, authors: [],
                      source: .init(name: "S", url: "https://example.org"),
                      rights: .init(bucket: "script_source_cleared", evidence: []),
                      roles: [.init(name: "A", lines: 3, words: 30), .init(name: "B", lines: 3, words: 30)], lines: lines)
}

nonisolated private func indexJSON(_ ids: [String]) -> Data {
    let rows = ids.map {
        #"{"id":"\#($0)","revision":"r1","title":"Row \#($0)","kind":"stage","authors":["A. Author"],"voices":2,"roles":2,"cast":[9,5],"lines":14,"words":400,"minutes":3,"path":"scripts/\#($0).json"}"#
    }
    return Data(#"{"format":1,"count":\#(ids.count),"plays":[\#(rows.joined(separator: ","))]}"#.utf8)
}

nonisolated private func scriptFile(_ s: PlayScript) throws -> Data {
    try JSONEncoder().encode(CastableLibrary(format: 1, scripts: [s]))
}

nonisolated private struct Offline: Error {}

nonisolated private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = true
    var value: Bool {
        get { lock.withLock { flag } }
        set { lock.withLock { flag = newValue } }
    }
}

private func library(bundle: [PlayScript], fetch: @escaping PlaysLibrary.Fetch) -> (PlaysLibrary, URL) {
    let dir = FileManager.default.temporaryDirectory.appending(path: "plays-library-\(UUID().uuidString)")
    let scripts = bundle
    let lib = PlaysLibrary(store: ProductionStore(root: dir.appending(path: "Plays")), fetch: fetch,
                           cache: dir.appending(path: "Cache"), bundled: { CastableLibrary(format: 1, scripts: scripts) })
    return (lib, dir)
}

struct PlaysLibraryTests {
    @Test func theIndexSuppliesTheListsAndTheBundleIsNotReadForThem() async {
        let (lib, _) = library(bundle: [playScript("bundled-1")]) { path in
            path == "library/index.json" ? indexJSON(["gut-1", "gut-2", "gut-3"]) : nil
        }
        await lib.load()
        #expect(lib.state == .ready && lib.fromLibrary)
        #expect(lib.rows.map(\.id) == ["gut-1", "gut-2", "gut-3"])
        #expect(lib.rows.first?.castLines == [9, 5] && lib.rows.first?.title == "Row gut-1")
    }

    @Test func aMissingIndexFallsBackToTheBundlesRows() async {
        let (lib, _) = library(bundle: [playScript("bundled-1"), playScript("bundled-2")]) { _ in nil }
        await lib.load()
        #expect(lib.state == .ready && !lib.fromLibrary)
        #expect(lib.rows.map(\.id) == ["bundled-1", "bundled-2"])
        let (failing, _) = library(bundle: [playScript("bundled-1")]) { _ in throw Offline() }
        await failing.load()
        #expect(failing.rows.map(\.id) == ["bundled-1"], "an unreachable site leaves the bundle")
        let (none, _) = library(bundle: []) { _ in nil }
        await none.load()
        #expect(none.state == .unavailable)
    }

    @Test func aLibraryScriptOpensFromItsFileAndABundledOneFromTheBundle() async throws {
        let remote = playScript("gut-1", title: "From the library")
        let (lib, _) = library(bundle: [playScript("bundled-1", title: "From the bundle")]) { path in
            switch path {
            case "library/index.json": return indexJSON(["gut-1", "bundled-1"])
            case "library/scripts/gut-1.json": return try scriptFile(remote)
            default: return nil
            }
        }
        await lib.load()
        #expect(try await lib.script(id: "gut-1")?.title == "From the library")
        #expect(try await lib.script(id: "bundled-1")?.title == "From the bundle", "the file is missing, the bundle holds it")
        #expect(try await lib.script(id: "nowhere") == nil)
    }

    @Test func anOfflineLibraryScriptThatIsNotBundledSurfacesTheError() async {
        let (lib, _) = library(bundle: []) { path in
            if path == "library/index.json" { return indexJSON(["gut-9"]) }
            throw Offline()
        }
        await lib.load()
        await #expect(throws: Offline.self) { _ = try await lib.script(id: "gut-9") }
    }

    @Test func aScriptSeenOnceIsReadFromTheCacheOffline() async throws {
        let remote = playScript("gut-1", title: "Cached")
        let (lib, dir) = library(bundle: []) { path in
            path == "library/index.json" ? indexJSON(["gut-1"]) : try scriptFile(remote)
        }
        await lib.load()
        #expect(try await lib.script(id: "gut-1")?.title == "Cached")
        try await Task.sleep(for: .milliseconds(400))
        let again = PlaysLibrary(store: ProductionStore(root: dir.appending(path: "Plays2")), fetch: { _ in throw Offline() },
                                 cache: dir.appending(path: "Cache"), bundled: { nil })
        await again.load()
        #expect(again.rows.map(\.id) == ["gut-1"], "the cached index lists it")
        #expect(try await again.script(id: "gut-1")?.title == "Cached", "the cached file opens it")
    }

    @Test func theLivePlaysIndexDecodesIntoRows() throws {
        let json = Data(#"{"format":1,"count":1,"plays":[{"id":"gut-3012","revision":"d8c2","title":"The Acharnians","sort_name":"acharnians","kind":"stage","authors":["Aristophanes"],"voices":13,"roles":34,"lines":468,"words":11811,"minutes":79,"rights":{"bucket":"script_source_cleared","evidence":[{"claim":"Public domain in the USA.","src":"https://www.gutenberg.org/ebooks/3012.rdf"}]},"source":{"name":"Project Gutenberg","url":"https://www.gutenberg.org/ebooks/3012"},"path":"scripts/gut-3012.json"}]}"#.utf8)
        let row = try #require(try JSONDecoder().decode(PlayRowIndex.self, from: json).plays.first)
        #expect(row.sortName == "acharnians" && row.voices == 13 && row.minutes == 79 && row.partCount == 34 && row.lineCount == 468)
        #expect(row.path == "scripts/gut-3012.json" && row.rights?.bucket == "script_source_cleared")
    }
}
