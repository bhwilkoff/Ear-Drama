import Foundation
import Testing

// B15c: a play only the published library holds draws in the shared screen, a shared production on the Apple TV
// and a finished drama's page (they read through LibraryScripts, not the bundle alone); a play the library has
// since revised is not shown at another revision; and Library's Account row names the day when the last sync was
// not today. The fetch is stubbed and the cache is a temp folder.
//
// Seen to fail, 2026-11-24, each mutation run once then restored: the bundle read before the library (the
// library-only and newer-revision cases), the revision check dropped (the changed-play case), the cache never read
// (the offline case), a throw swallowed (the unreachable case), and the time-only line kept for a past day.

nonisolated private func scriptAt(_ id: String, _ revision: String) -> PlayScript {
    let lines = (0..<4).map { ScriptLine(id: "\(id)-\($0)", kind: .speech, role: $0 % 2 == 0 ? "A" : "B", parts: [.say("word")]) }
    return PlayScript(id: id, revision: revision, kind: "radio", title: "T", authors: [],
                      source: .init(name: "S", url: "https://example.org"),
                      rights: .init(bucket: "script_source_cleared", evidence: []),
                      roles: [.init(name: "A", lines: 2, words: 20), .init(name: "B", lines: 2, words: 20)], lines: lines)
}

nonisolated private func libraryIndex(_ ids: [String]) -> Data {
    let rows = ids.map {
        #"{"id":"\#($0)","revision":"r1","title":"Row","kind":"stage","authors":[],"voices":2,"roles":2,"cast":[2,2],"lines":4,"words":40,"minutes":1,"path":"scripts/\#($0).json"}"#
    }
    return Data(#"{"format":1,"count":\#(ids.count),"plays":[\#(rows.joined(separator: ","))]}"#.utf8)
}

nonisolated private func fileOf(_ s: PlayScript) throws -> Data {
    try JSONEncoder().encode(CastableLibrary(format: 1, scripts: [s]))
}

nonisolated private struct Unreachable: Error {}

nonisolated private func cacheDir() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "library-scripts-\(UUID().uuidString)", directoryHint: .isDirectory)
}

nonisolated private func published(_ play: PlayScript) throws -> LibraryScripts.Fetch {
    let index = libraryIndex([play.id])
    let file = try fileOf(play)
    return { path in
        if path == "library/index.json" { return index }
        if path == "library/scripts/\(play.id).json" { return file }
        return nil
    }
}

struct LibraryScriptsTests {
    @Test func aPlayOnlyTheLibraryHoldsResolves() async throws {
        let fetch = try published(scriptAt("gut-3012", "r1"))
        let found = try await LibraryScripts.script(id: "gut-3012", fetch: fetch, cache: cacheDir(), bundled: { [] })
        #expect(found?.id == "gut-3012" && found?.lines.count == 4)
        let exact = try await LibraryScripts.script(id: "gut-3012", revision: "r1", fetch: fetch, cache: cacheDir(), bundled: { [] })
        #expect(exact?.revision == "r1")
    }

    @Test func aPlayNeitherHoldsIsNilAndNoError() async throws {
        let none = try await LibraryScripts.script(id: "gut-9", fetch: { _ in nil }, cache: cacheDir(), bundled: { [scriptAt("other", "r1")] })
        #expect(none == nil)
    }

    @Test func aPlayTheLibraryHasRevisedIsNotShownAtAnotherRevision() async throws {
        let fetch = try published(scriptAt("gut-1", "r2"))
        let changed = try await LibraryScripts.script(id: "gut-1", revision: "r1", fetch: fetch, cache: cacheDir(), bundled: { [] })
        #expect(changed == nil, "the room was cast from r1: the library's r2 is not it")
        let latest = try await LibraryScripts.script(id: "gut-1", fetch: fetch, cache: cacheDir(), bundled: { [] })
        #expect(latest?.revision == "r2", "control: with no revision asked, the library's is the answer")
        let older = try await LibraryScripts.script(id: "gut-1", revision: "r1", fetch: fetch, cache: cacheDir(), bundled: { [scriptAt("gut-1", "r1")] })
        #expect(older?.revision == "r1", "the bundle may hold the revision the production was cast from")
    }

    @Test func theChangedPlayAnswerSaysThePlayChanged() {
        #expect(PlaysShare.line(PlaysRefusal.code("revision_mismatch")) == "This play has changed since it was cast.")
    }

    @Test func anUnreachableLibraryFallsBackToTheBundleElseThrows() async throws {
        let down: LibraryScripts.Fetch = { _ in throw Unreachable() }
        let floor = try await LibraryScripts.script(id: "b-1", fetch: down, cache: cacheDir(), bundled: { [scriptAt("b-1", "r1")] })
        #expect(floor?.id == "b-1")
        await #expect(throws: Unreachable.self) {
            _ = try await LibraryScripts.script(id: "gut-3012", fetch: down, cache: cacheDir(), bundled: { [] })
        }
    }

    @Test func aPlayReadOnceIsReadFromTheCacheOffline() async throws {
        let cache = cacheDir()
        _ = try await LibraryScripts.script(id: "gut-5", fetch: try published(scriptAt("gut-5", "r1")), cache: cache, bundled: { [] })
        let file = cache.appending(path: "scripts/gut-5.json")
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: file.path) { try await Task.sleep(for: .milliseconds(20)) }
        let down: LibraryScripts.Fetch = { _ in throw Unreachable() }
        let again = try await LibraryScripts.script(id: "gut-5", revision: "r1", fetch: down, cache: cache, bundled: { [] })
        #expect(again?.id == "gut-5")
        let never = try? await LibraryScripts.script(id: "gut-6", fetch: down, cache: cache, bundled: { [] })
        #expect(never == nil, "control: a play never read is not in the cache")
    }
}

struct AccountSyncTextTests {
    private static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private static func line(_ last: Date, now: Date) -> String {
        AccountSyncText.line(last, now: now, calendar: calendar, locale: Locale(identifier: "en_US"))
            .replacingOccurrences(of: "\u{202F}", with: " ")
    }

    @Test func todayIsJustTheTime() {
        let now = Self.date(2026, 11, 24, 15, 14)
        #expect(Self.line(Self.date(2026, 11, 24, 16, 4), now: now) == "Synced 4:04 PM", "the same day, even an hour ahead")
        #expect(Self.line(Self.date(2026, 11, 24, 0, 5), now: now) == "Synced 12:05 AM")
    }

    @Test func aPastDayNamesTheDay() {
        let now = Self.date(2026, 11, 24, 15, 14)
        let yesterday = Self.line(Self.date(2026, 11, 23, 16, 4), now: now)
        #expect(yesterday.contains("Nov 23") && yesterday.contains("4:04 PM"), Comment(rawValue: yesterday))
        #expect(!yesterday.contains("2026"), "this year needs no year")
        let late = Self.line(Self.date(2026, 11, 23, 23, 59), now: Self.date(2026, 11, 24, 0, 1))
        #expect(late.contains("Nov 23"), "two minutes ago across midnight is yesterday's")
        #expect(Self.line(Self.date(2026, 11, 23, 16, 4), now: now) != "Synced 4:04 PM", "control: not the time-only form")
    }

    @Test func anotherYearNamesTheYear() {
        let line = Self.line(Self.date(2025, 12, 30, 9, 30), now: Self.date(2026, 1, 2, 9, 0))
        #expect(line.contains("2025") && line.contains("Dec 30"), Comment(rawValue: line))
    }
}
