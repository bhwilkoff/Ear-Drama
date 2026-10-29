#if os(tvOS)
import SwiftUI

// Shared ear dramas on the Apple TV (PLAYS-DESIGN §11.7 rule 12, tvOS-DESIGN
// §4.12): listen and report, nothing else. The TV records, claims, invites,
// and publishes nothing; the takes it fetches live in Caches only.

/// A shared production pushed from Library.
struct SharedPlayRoute: Hashable {
    let id: String
    let title: String
}

/// Library's Ear dramas, signed in: the shared productions this person is in.
struct SharedEarDramasSection_tvOS: View {
    @Environment(AccountStore.self) private var account
    @Environment(CatalogStore.self) private var catalog
    @State private var rows: [RemoteProduction]?
    @State private var refusal: String?
    @State private var load = 0

    var body: some View {
        if account.isSignedIn {
            Section("Ear dramas") {
                if let refusal {
                    Label(catalog.isOnline ? refusal : Connectivity.offlineLine, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color.semanticError)
                    Button("Try Again") { load += 1 }
                } else if let rows {
                    if rows.isEmpty {
                        Text("No ear drama is shared with you.").foregroundStyle(Color.brandTextMuted)
                    }
                    ForEach(rows) { row in
                        NavigationLink(value: SharedPlayRoute(id: row.id, title: row.title)) {
                            Text(row.title).font(TypeRamp.bodyStrong)
                        }
                    }
                } else {
                    ProgressView()
                }
            }
            .task(id: "\(account.isSignedIn)#\(load)") {
                guard !LaunchDoors.current.emptyLibrary else { rows = []; return }
                do {
                    let list = try await WorkerPlays(api: .shared).list()
                    rows = list.sorted { ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0) }
                    refusal = nil
                } catch {
                    refusal = PlaysShare.line(error)
                }
            }
        }
    }
}

/// One shared production at ten feet: Listen Through, the parts, People.
struct SharedPlayScreen_tvOS: View {
    let route: SharedPlayRoute
    @Environment(CatalogStore.self) private var catalog
    @Environment(\.scenePhase) private var scenePhase
    @State private var rec: SharedRecord?
    @State private var refusal: String?
    @State private var line: String?
    @State private var load = 0
    @State private var fetching = false
    @State private var live = LiveListenThrough.system()
    @State private var reporting: SharedRecord.Member?
    @State private var blocking: SharedRecord.Member?
    @FocusState private var listenFocused: Bool

    private static let scripts = CastableLibrary.load()?.scripts ?? []
    private let api = WorkerPlays(api: .shared)
    private var me: String? { APIClient.shared.storedSession()?.userId }

    var body: some View {
        Group {
            if let rec {
                content(rec)
            } else if let refusal {
                EmptyState(catalog.isOnline ? refusal : Connectivity.offlineLine, systemImage: "exclamationmark.triangle",
                           action: .init(title: "Try Again") { load += 1 })
            } else {
                ProgressView()
            }
        }
        .task(id: load) { await read() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, !live.isRunning { load += 1 }
        }
        .onDisappear { live.stop() }
    }

    @ViewBuilder private func content(_ rec: SharedRecord) -> some View {
        let script = Self.scripts.first { $0.id == rec.scriptID && $0.revision == rec.scriptRevision }
        List {
            Section {
                Text(rec.title).font(TypeRamp.pageTitle)
                if let script {
                    Button {
                        if live.isRunning { live.stop() } else { Task { await listen(rec, script) } }
                    } label: {
                        Label(live.isRunning ? "Stop" : "Listen Through", systemImage: live.isRunning ? "stop.fill" : "play.fill")
                    }
                    .focused($listenFocused)
                    .disabled(fetching)
                    .accessibilityIdentifier("shared-listen")
                    if fetching { ProgressView() }
                    if let entry = live.current { NowReading_tvOS(entry: entry, script: script) }
                } else {
                    Text(PlaysShare.line(PlaysRefusal.code("revision_mismatch"))).foregroundStyle(Color.brandTextMuted)
                }
                if rec.hiddenTakes > 0 {
                    Text(rec.hiddenTakes == 1 ? "1 take is hidden from you." : "\(rec.hiddenTakes) takes are hidden from you.")
                        .foregroundStyle(Color.brandTextMuted)
                }
                if let line {
                    Label(line, systemImage: "exclamationmark.triangle").foregroundStyle(Color.semanticError)
                }
                if !catalog.isOnline { OfflineNotice() }
            }
            if let script {
                Section("Parts") {
                    ForEach(script.castParts) { part in
                        VStack(alignment: .leading, spacing: Spacing.s1) {
                            Text(part.title).font(TypeRamp.bodyStrong)
                            Text(SharedListen.status(rec, part)).font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
                        }
                        .focusable()
                    }
                }
                .focusSection()
            }
            Section("People") {
                ForEach(rec.members) { member in
                    PersonRow_tvOS(member: member, me: me, report: { reporting = member }, block: { blocking = member })
                }
            }
            .focusSection()
        }
        .defaultFocus($listenFocused, true)
        .confirmationDialog("Report", isPresented: Binding(get: { reporting != nil }, set: { if !$0 { reporting = nil } }),
                            presenting: reporting) { member in
            ForEach(ReportReason.allCases) { reason in
                Button(reason.title) { Task { await report(member, reason) } }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Block \(blocking?.displayName ?? "No name")?",
                            isPresented: Binding(get: { blocking != nil }, set: { if !$0 { blocking = nil } }),
                            presenting: blocking) { member in
            Button("Block", role: .destructive) { Task { await block(member) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("You will no longer hear their takes.")
        }
    }

    // MARK: The Worker and the cache

    private func read() async {
        do {
            rec = try await api.get(route.id)
            refusal = nil
        } catch {
            if rec == nil { refusal = PlaysShare.line(error) } else { line = PlaysShare.line(error) }
        }
    }

    private var folder: URL {
        URL.cachesDirectory.appending(path: "SharedPlays", directoryHint: .isDirectory)
            .appending(path: route.id, directoryHint: .isDirectory)
    }

    /// Take id to cached file name, read from the folder.
    private func cached() -> [String: String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        var out: [String: String] = [:]
        for name in names where name.hasPrefix("m-") {
            out[String(name.dropFirst(2).split(separator: ".").first ?? "")] = name
        }
        return out
    }

    private func listen(_ rec: SharedRecord, _ script: PlayScript) async {
        line = nil
        fetching = true
        var files = cached()
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for id in SharedListen.toFetch(rec, have: Set(files.keys)) {
                let data = try await api.audio(rec.id, takeID: id)
                let name = SharedListen.fileName(id, data)
                try data.write(to: folder.appending(path: name), options: .atomic)
                files[id] = name
            }
        } catch {
            line = PlaysShare.line(error)
        }
        fetching = false
        let plan = SharedListen.plan(rec, script: script, files: files)
        await live.run(plan) { folder.appending(path: $0.file) }
    }

    private func report(_ member: SharedRecord.Member, _ reason: ReportReason) async {
        do {
            try await api.report(route.id, takeID: nil, userID: member.userID, reason: reason, note: nil)
            load += 1
        } catch { line = PlaysShare.line(error) }
    }

    private func block(_ member: SharedRecord.Member) async {
        do {
            try await api.block(member.userID)
            live.stop()
            load += 1
        } catch { line = PlaysShare.line(error) }
    }
}

/// The line being heard: its speaker, and "Device voice" when the device reads it (§5 rule 3).
private struct NowReading_tvOS: View {
    let entry: ListenEntry
    let script: PlayScript

    var body: some View {
        let line = script.lines.first { $0.id == entry.lineID }
        VStack(alignment: .leading, spacing: Spacing.s1) {
            HStack(spacing: Spacing.s2) {
                Text(line?.part.title ?? "").font(TypeRamp.bodyStrong)
                if entry.isDeviceVoice {
                    Text("Device voice").font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
                }
            }
            if let line { Text(line.spokenText).font(TypeRamp.body) }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A member by display name, with "You" and "Director" as tags; Report and
/// Block for everyone else (guideline 1.2).
private struct PersonRow_tvOS: View {
    let member: SharedRecord.Member
    let me: String?
    let report: () -> Void
    let block: () -> Void

    var body: some View {
        let tag = member.userID == me ? "You" : member.director ? "Director" : nil
        HStack(spacing: Spacing.s4) {
            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(member.displayName ?? "No name").font(TypeRamp.bodyStrong)
                if let tag { Text(tag).font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted) }
            }
            Spacer()
            if member.userID != me {
                Button("Report", action: report)
                Button("Block", action: block)
            }
        }
        .focusSection()
    }
}
#endif
