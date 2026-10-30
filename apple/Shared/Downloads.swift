#if os(iOS) || os(macOS)
import SwiftUI

// Downloads on iPhone, iPad, and Mac. The TV has no durable storage for media
// and shows none of this. A downloaded file is played, never exported: there
// is no share or Files action anywhere (research 04 §11).

extension Int64 {
    var byteText: String { formatted(.byteCount(style: .file)) }
}

/// Episode detail's download row: Download, then progress with Cancel, then
/// Downloaded with Remove.
struct DownloadControl: View {
    let detail: EpisodeDetail
    @Environment(DownloadStore.self) private var downloads

    var body: some View {
        let id = detail.episode.id
        switch downloads.record(for: id)?.state {
        case nil:
            Button { downloads.download(detail) } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }
            .disabled(detail.defaultRecording == nil)
        case .queued, .downloading:
            HStack(spacing: Spacing.s3) {
                progress(downloads.record(for: id))
                Button(role: .cancel) { downloads.cancel(id) } label: {
                    Label("Cancel Download", systemImage: "xmark.circle")
                }
                .fixedSize()
                #if os(iOS)
                // In an iPhone List row the hidden title still took the row's height.
                .labelStyle(.iconOnly)
                #endif
            }
        case .downloaded:
            HStack(spacing: Spacing.s3) {
                Label {
                    Text(verbatim: "Downloaded · \(downloads.record(for: id)?.receivedBytes.byteText ?? "")")
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                }
                .foregroundStyle(Color.brandTextMuted)
                Spacer(minLength: 0)
                Button(role: .destructive) { downloads.remove(id) } label: {
                    Label("Remove Download", systemImage: "trash")
                }
                .fixedSize()
                #if os(iOS)
                // In an iPhone List row the hidden title still took the row's height.
                .labelStyle(.iconOnly)
                #endif
            }
        case .failed:
            HStack(spacing: Spacing.s3) {
                Label("Download failed", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Color.semanticError)
                Spacer(minLength: 0)
                Button { downloads.download(detail) } label: {
                    Label("Try Again", systemImage: "arrow.clockwise")
                }
                .fixedSize()
            }
        }
    }

    @ViewBuilder private func progress(_ record: DownloadRecord?) -> some View {
        if let fraction = record?.fraction {
            ProgressView(value: fraction) { Text("Downloading") }
                .accessibilityValue("\(Int(fraction * 100)) percent")
        } else {
            ProgressView { Text("Downloading") }
        }
    }
}

/// The Downloads place, pushed from Library's one row (iOS-DESIGN §4.8).
enum DownloadsRoute: Hashable { case place }

/// Library's Downloads row: the count and the storage held, pushing the place.
/// A bulk download is hundreds of rows, which would bury the rest of Library.
struct DownloadsSection: View {
    @Environment(DownloadStore.self) private var downloads

    var body: some View {
        let records = downloads.records
        if records.isEmpty {
            Section("Downloads") { SectionCaption("Downloaded episodes play with no network.") }
        } else {
            Section {
                NavigationLink(value: DownloadsRoute.place) {
                    LabeledContent {
                        Text(verbatim: summary(records.count))
                            .monospacedDigit()
                    } label: {
                        Label("Downloads", systemImage: "arrow.down.circle")
                    }
                }
            }
        }
    }

    private func summary(_ count: Int) -> String {
        let episodes = count == 1 ? "1 episode" : "\(count.formatted()) episodes"
        return "\(episodes) · \(downloads.totalBytes.byteText)"
    }
}

/// Every download, by series, each removable; a series' Remove and Remove All
/// ask first; the foot is the storage held on this device.
struct DownloadsScreen: View {
    @Environment(DownloadStore.self) private var downloads
    @State private var confirmingRemoveAll = false
    @State private var removingSeries: String?

    var body: some View {
        let groups = downloads.seriesGroups
        Group {
            if groups.isEmpty {
                EmptyState("No downloads", systemImage: "arrow.down.circle")
            } else {
                List {
                    ForEach(groups, id: \.key) { group in
                        Section {
                            ForEach(group.records) { record in
                                NavigationLink(value: Route.episode(record.episodeID)) {
                                    DownloadRowLabel(record: record, showSeries: false)
                                }
                                .swipeActions { removeButton(record) }
                                .contextMenu { removeButton(record) }
                            }
                        } header: {
                            HStack {
                                Text(group.name)
                                Spacer(minLength: Spacing.s3)
                                Button("Remove", role: .destructive) { removingSeries = group.key }
                                    .font(TypeRamp.caption)
                                    .accessibilityLabel("Remove \(group.name) Downloads")
                            }
                        }
                    }
                    Section {
                        Button("Remove All Downloads", role: .destructive) { confirmingRemoveAll = true }
                    } footer: {
                        Text(verbatim: "\(downloads.totalBytes.byteText) on this device")
                            .font(TypeRamp.caption)
                            .foregroundStyle(Color.brandTextMuted)
                    }
                }
            }
        }
        .navigationTitle("Downloads")
        .confirmationDialog("Remove all downloads?", isPresented: $confirmingRemoveAll) {
            Button("Remove All Downloads", role: .destructive) { downloads.removeAll() }
        }
        .confirmationDialog(
            "Remove this series' downloads?",
            isPresented: Binding(get: { removingSeries != nil }, set: { if !$0 { removingSeries = nil } }),
            presenting: removingSeries
        ) { key in
            Button("Remove Downloads", role: .destructive) { downloads.removeSeries(key) }
        }
    }

    private func removeButton(_ record: DownloadRecord) -> some View {
        Button(role: .destructive) { downloads.remove(record.episodeID) } label: {
            Label(record.isActive ? "Cancel Download" : "Remove Download", systemImage: "trash")
        }
    }
}

/// A series page's Download menu (iOS-DESIGN §4.3): the whole run, a season,
/// or Remove Downloads; a download asks first with the count and the space.
struct SeriesDownloadMenu: View {
    let page: SeriesPage
    @Environment(DownloadStore.self) private var downloads
    @Environment(CatalogStore.self) private var catalog
    @State private var plan: DownloadPlan?
    @State private var confirmingRemove = false

    var body: some View {
        let key = page.series.key
        Menu {
            Button("Download All Episodes") { prepare(page.episodes) }
                .disabled(downloads.missing(page.episodes.map(\.id)).isEmpty)
            if page.seasons.count > 1 {
                Section {
                    ForEach(page.seasons) { season in
                        Button("Download \(season.season ?? "Undated")") { prepare(season.episodes) }
                            .disabled(downloads.missing(season.episodes.map(\.id)).isEmpty)
                    }
                }
            }
            if downloads.hasDownloads(inSeries: key) {
                Button("Remove Downloads", role: .destructive) { confirmingRemove = true }
            }
        } label: {
            Label("Download", systemImage: "arrow.down.circle")
        }
        .confirmationDialog(
            plan.map(Self.title) ?? "",
            isPresented: Binding(get: { plan != nil }, set: { if !$0 { plan = nil } }),
            titleVisibility: .visible,
            presenting: plan
        ) { plan in
            Button("Download") { downloads.download(plan) }
        } message: { plan in
            if let bytes = plan.estimatedBytes { Text(verbatim: "About \(bytes.byteText).") }
        }
        .confirmationDialog("Remove this series' downloads?", isPresented: $confirmingRemove) {
            Button("Remove Downloads", role: .destructive) { downloads.removeSeries(key) }
        }
    }

    static func title(_ plan: DownloadPlan) -> String {
        plan.count == 1 ? "Download 1 episode?" : "Download \(plan.count.formatted()) episodes?"
    }

    private func prepare(_ episodes: [EpisodeRow]) {
        let ids = downloads.missing(episodes.map(\.id))
        Task {
            let next = DownloadPlan(await catalog.downloadRequests(ids), records: downloads.records)
            if next.count > 0 { plan = next }
        }
    }
}

/// A download row: the record's own title and series, so it stays readable
/// with no network and across catalog swaps.
struct DownloadRowLabel: View {
    let record: DownloadRecord
    var showSeries = true

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            Text(record.title)
                .font(TypeRamp.bodyStrong)
                .foregroundStyle(Color.brandText)
            HStack(spacing: Spacing.s2) {
                if showSeries { Text(record.seriesName) }
                switch record.state {
                case .downloaded:
                    Text(verbatim: record.receivedBytes.byteText).monospacedDigit()
                case .queued, .downloading:
                    ProgressView(value: record.fraction ?? 0)
                        .frame(maxWidth: 80)
                        .accessibilityLabel("Downloading")
                case .failed:
                    Text("Download failed").foregroundStyle(Color.semanticError)
                }
            }
            .font(TypeRamp.caption)
            .foregroundStyle(Color.brandTextMuted)
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
