#if os(iOS) || os(macOS)
import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

// Export (Human-Shaped principle 11), on the Account screen: the person's own data as a file the
// system's share sheet (or the Mac's share menu) saves wherever they choose. Built on the device;
// nothing is uploaded, and it needs no account.

nonisolated private func exportURL(_ export: DataExport, _ stem: String, _ ext: String) -> URL {
    URL.temporaryDirectory.appending(path: "\(stem)-\(RadioClock.localDate(export.exportedAt)).\(ext)")
}

nonisolated struct ExportJSONFile: Transferable {
    let export: DataExport

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { item in
            let url = exportURL(item.export, "ear-drama", "json")
            try item.export.json().write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

nonisolated struct ExportHistoryFile: Transferable {
    let export: DataExport

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { item in
            let url = exportURL(item.export, "ear-drama-history", "csv")
            try Data(item.export.historyCSV().utf8).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

struct ExportSection: View {
    @Environment(ListeningHistory.self) private var history
    @Environment(ListeningQueue.self) private var queue
    @Environment(FollowedSeries.self) private var follows
    @Environment(CatalogStore.self) private var catalog
    @Environment(PlaysLibrary.self) private var plays
    @State private var export: DataExport?

    var body: some View {
        Section {
            if let export {
                ShareLink(item: ExportJSONFile(export: export), preview: SharePreview("Ear Drama data")) {
                    Label("Export my data", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("export-json")
                ShareLink(item: ExportHistoryFile(export: export), preview: SharePreview("Ear Drama history")) {
                    Label("Export history (CSV)", systemImage: "tablecells")
                }
                .accessibilityIdentifier("export-csv")
            } else {
                ProgressView()
            }
        }
        .task(id: Key(history: history.entries.count, queue: queue.items, follows: follows.followedKeys)) {
            export = await gather()
        }
    }

    private struct Key: Hashable { let history: Int; let queue: [String]; let follows: [String] }

    private func gather() async -> DataExport {
        let ordered = history.entries.sorted { $0.value.updatedAt > $1.value.updatedAt }
        let ids = Array(Set(ordered.map(\.key) + queue.items))
        await catalog.whenReady()
        let episodes = Dictionary(uniqueKeysWithValues: (await catalog.episodes(ids)).map { ($0.id, $0) })
        let series = Dictionary(uniqueKeysWithValues: (await catalog.series(follows.followedKeys)).map { ($0.key, $0) })
        return DataExport(
            exportedAt: Date(),
            history: ordered.map { id, entry in
                DataExport.History(episode: id, title: episodes[id]?.displayTitle, seriesName: episodes[id]?.seriesName,
                                   airDate: episodes[id]?.airDate, listenedAt: entry.updatedAt,
                                   positionSeconds: entry.position, durationSeconds: entry.duration)
            },
            following: follows.followedKeys.map { DataExport.Follow(series: $0, name: series[$0]?.name) },
            queue: queue.items.map {
                DataExport.Queued(episode: $0, title: episodes[$0]?.displayTitle, seriesName: episodes[$0]?.seriesName,
                                  airDate: episodes[$0]?.airDate)
            },
            takes: plays.store.productions.map { p in
                DataExport.Production(id: p.id, title: p.title, created: p.created, takes: p.takes.map { t in
                    DataExport.Take(id: t.id, line: t.lineID, part: t.part.rawValue, created: t.created, seconds: t.seconds,
                                    chosen: p.chosen[t.lineID] == t.id)
                })
            })
    }
}
#endif
