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

/// Library's Downloads section: every download, newest first, each removable,
/// with the storage they hold and one Remove All.
struct DownloadsSection: View {
    @Environment(DownloadStore.self) private var downloads
    @State private var confirmingRemoveAll = false

    var body: some View {
        let records = downloads.sortedRecords
        if !records.isEmpty {
            Section {
                ForEach(records) { record in
                    NavigationLink(value: Route.episode(record.episodeID)) {
                        DownloadRowLabel(record: record)
                    }
                    .swipeActions { removeButton(record) }
                    .contextMenu { removeButton(record) }
                }
                Button("Remove All Downloads", role: .destructive) { confirmingRemoveAll = true }
                    .confirmationDialog("Remove all downloads?", isPresented: $confirmingRemoveAll) {
                        Button("Remove All Downloads", role: .destructive) { downloads.removeAll() }
                    }
            } header: {
                Text("Downloads")
            } footer: {
                Text(verbatim: "\(downloads.totalBytes.byteText) on this device")
                    .font(TypeRamp.caption)
                    .foregroundStyle(Color.brandTextMuted)
            }
        }
    }

    private func removeButton(_ record: DownloadRecord) -> some View {
        Button(role: .destructive) { downloads.remove(record.episodeID) } label: {
            Label(record.isActive ? "Cancel Download" : "Remove Download", systemImage: "trash")
        }
    }
}

/// A download row: the record's own title and series, so it stays readable
/// with no network and across catalog swaps.
struct DownloadRowLabel: View {
    let record: DownloadRecord

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            Text(record.title)
                .font(TypeRamp.bodyStrong)
                .foregroundStyle(Color.brandText)
            HStack(spacing: Spacing.s2) {
                Text(record.seriesName)
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
