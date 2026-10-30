import Foundation
import Testing

/// D3-7: the rules a finished ear drama's tile, page and bill follow, and the open invite's record.
struct FinishedDramasTests {
    private func play(_ id: String, at ms: Int64, credits: [(String, String)] = []) -> FinishedPlay {
        FinishedPlay(id: id, scriptID: "s", title: "T \(id)", source: nil,
                     credits: credits.map { FinishedPlay.Credit(part: $0.0, name: $0.1) },
                     archiveURL: "https://archive.org/details/eardrama-\(id.lowercased())", publishedAt: ms)
    }

    @Test func newestFirstThenIdDescending() {
        let sorted = FinishedDramas.newestFirst([play("A", at: 1), play("C", at: 5), play("B", at: 5)])
        #expect(sorted.map(\.id) == ["C", "B", "A"])
    }

    @Test func creditsAreTheChosenNamesOnceInScriptOrder() {
        let credits = [("role:A", "Pat"), ("role:B", "Sam"), ("role:C", "Pat"), ("role:D", "Ada")].map {
            FinishedPlay.Credit(part: $0.0, name: $0.1)
        }
        #expect(FinishedDramas.creditLine(credits) == "Pat, Sam, Ada")
        #expect(FinishedDramas.creditLine(credits, limit: 2) == "Pat, Sam and 1 more")
    }

    @Test func aGoneAccountIsUncreditedNeverNamed() {
        let credits = [FinishedPlay.Credit(part: "role:A", name: ""), FinishedPlay.Credit(part: "role:B", name: "  ")]
        #expect(FinishedDramas.named(credits).isEmpty)
        #expect(FinishedDramas.creditLine(credits) == "")
    }

    @Test func theItemsLineFilesPlayInScriptOrderAndSkipDerivatives() {
        let meta = Data("""
        {"files":[{"name":"0002-B.wav"},{"name":"0001-A.flac"},{"name":"0001-A.mp3"},{"name":"eardrama_meta.xml"},{"name":"0010-C Long.wav"}]}
        """.utf8)
        let urls = FinishedDramas.lineFiles(metadata: meta, identifier: "eardrama-x")
        #expect(urls.map(\.lastPathComponent) == ["0001-A.flac", "0002-B.wav", "0010-C Long.wav"])
        #expect(urls.allSatisfy { $0.absoluteString.hasPrefix("https://archive.org/download/eardrama-x/") })
        #expect(FinishedDramas.lineFiles(metadata: Data("nope".utf8), identifier: "x").isEmpty)
    }

    @Test func theIdentifierIsTheItemPagesLastComponent() {
        #expect(FinishedDramas.identifier("https://archive.org/details/eardrama-abc") == "eardrama-abc")
        #expect(FinishedDramas.identifier("https://example.com/details/eardrama-abc") == nil)
    }

    @Test func anOpenInviteReadsAsTheSharedRecord() throws {
        let data = Data("""
        {"id":"P1","scriptID":"s","scriptRevision":"r","title":"T","source":null,
         "parts":[{"id":"role:A","lineCount":3,"status":"done","performer":"Pat"},{"id":"role:B","lineCount":2,"status":"open"}],
         "members":[{"name":"Pat","director":true}],
         "takes":[{"id":"t1","lineID":"l1","part":"role:A","frames":10,"sampleRate":48000,"audio":"/x"},
                  {"id":"t2","lineID":"l0","part":"role:A","frames":10,"sampleRate":48000,"audio":"/y"}],
         "chosen":{"l1":"t1","l0":"t2"},"next":"role:B","archive":null,"expires_at":null}
        """.utf8)
        let inv = try JSONDecoder().decode(OpenInvite.self, from: data)
        let rec = inv.record
        #expect(rec.part(PartID(rawValue: "role:A")).performer == "Pat")
        #expect(rec.part(PartID(rawValue: "role:B")).status == .open)
        #expect(rec.takes.count == 2 && rec.chosen["l1"] == "t1")
        #expect(inv.takeIDs(forPart: "role:A") == ["t2", "t1"])
        #expect(inv.takeIDs(forPart: "role:B").isEmpty)
    }

    @Test func theStoreListsNewestFirstPagesAndSaysWhenARefreshFails() async {
        let fail = Flag()
        let calls = Calls()
        let store = FinishedStore { _, cursor in
            calls.add(cursor)
            if fail.on { throw PlaysRefusal(kind: .unreachable) }
            return cursor == nil
                ? FinishedPage(productions: [self.play("A", at: 1), self.play("B", at: 3)], nextCursor: "c1")
                : FinishedPage(productions: [self.play("C", at: 2), self.play("B", at: 3)], nextCursor: nil)
        }
        await store.load()
        #expect(store.plays.map(\.id) == ["B", "A"] && store.hasMore)
        await store.load()
        #expect(calls.seen == [nil])
        await store.more()
        #expect(store.plays.map(\.id) == ["B", "C", "A"] && !store.hasMore)
        fail.on = true
        await store.load(force: true)
        if case .failed = store.phase {} else { Issue.record("a failed read says so") }
    }

    @Test func aPartCanBeTakenOnlyWhileNoPartRecords() throws {
        func inv(_ statuses: [PartState.Status]) throws -> OpenInvite {
            let parts = statuses.enumerated().map {
                "{\"id\":\"role:\($0.offset)\",\"lineCount\":1,\"status\":\"\($0.element.rawValue)\"}"
            }
            return try JSONDecoder().decode(OpenInvite.self, from: Data("""
            {"id":"P","scriptID":"s","scriptRevision":"r","title":"T","parts":[\(parts.joined(separator: ","))],
             "members":[],"takes":[],"chosen":{}}
            """.utf8))
        }
        let quiet = try inv([.open, .done])
        #expect(InviteRules.canTake(quiet.parts[0], in: quiet))
        #expect(!InviteRules.canTake(quiet.parts[1], in: quiet))
        let busy = try inv([.open, .recording])
        #expect(!InviteRules.canTake(busy.parts[0], in: busy))
    }
}

private final class Flag: @unchecked Sendable { var on = false }
private final class Calls: @unchecked Sendable {
    private(set) var seen: [String?] = []
    func add(_ c: String?) { seen.append(c) }
}
