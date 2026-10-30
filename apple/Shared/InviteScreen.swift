#if os(iOS) || os(macOS)
import SwiftUI

// The Invitation (D3-7; DESIGN-LOOP owner ruling 2: "On an invite link, they should be able to see
// everything. They just can't contribute until they sign in."). The play, its parts, who holds each,
// and their takes, playable, with no account. Taking a part is the one ask: tapping it signed out
// opens the native sign-in as a sheet at that moment, never a wall in front of the page.

enum InviteParts {
    /// Who holds a part, by the name they chose; an open part is read by the device voice.
    static func holder(_ part: OpenInvite.Part) -> PartHolder {
        switch part.status {
        case .open: .deviceVoice
        case .silent: .silent
        case .recording, .done: .person(part.performer)
        }
    }

    /// The line under a part's name: the performer and the state, or "Open".
    static func who(_ part: OpenInvite.Part) -> String {
        switch part.status {
        case .open: "Open"
        case .silent: "Left silent"
        case .recording: [part.performer, "Recording"].compactMap { $0 }.joined(separator: " \u{00B7} ")
        case .done: [part.performer, "Recorded"].compactMap { $0 }.joined(separator: " \u{00B7} ")
        }
    }
}

struct InviteScreen: View {
    let token: String
    @Environment(AppStore.self) private var app
    @Environment(PlaysLibrary.self) private var plays
    @Environment(SharedPlays.self) private var shared
    @Environment(AccountStore.self) private var account
    @Environment(CatalogStore.self) private var catalog
    @Environment(AudioPlayer.self) private var player
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    private enum Phase { case loading, loaded(OpenInvite), failed(String) }

    @State private var phase: Phase = .loading
    @State private var live = LiveListenThrough.system()
    @State private var fetching = false
    @State private var line: String?
    @State private var signingInFor: PartID?
    @State private var taking: PartID?
    @State private var name = ""
    @State private var hearing: String?

    private static let scripts = CastableLibrary.load()?.scripts ?? []
    private let api = WorkerOpenPlays(api: .shared)

    var body: some View {
        Group {
            switch phase {
            case .loading: ProgressView()
            case let .failed(text):
                EmptyState(catalog.isOnline ? text : Connectivity.offlineLine, systemImage: "exclamationmark.triangle",
                           action: .init(title: "Try Again") { Task { await read() } })
            case let .loaded(inv): page(inv)
            }
        }
        .navigationTitle("Invitation")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Not Now") { leave() } }
        }
        .task(id: "\(token)#\(account.isSignedIn)") { await read() }
        .onDisappear { live.stop() }
        .sheet(item: $signingInFor) { part in
            SignInSheet { signingInFor = nil }
                .onChange(of: account.isSignedIn) { _, signedIn in
                    guard signedIn else { return }
                    signingInFor = nil
                    Task {
                        await plays.load()
                        await shared.viewInvitation(token, plays: plays)
                        name = ""
                        taking = part
                    }
                }
        }
        .alert("Take this part", isPresented: Binding(get: { taking != nil }, set: { if !$0 { taking = nil } })) {
            TextField("Your name", text: $name)
            Button("Take Part") {
                guard let part = taking else { return }
                Task { await join(part) }
            }
            Button("Cancel", role: .cancel) { taking = nil }
        }
    }

    private func page(_ inv: OpenInvite) -> some View {
        let script = PlaysShare.scriptFor(Self.scripts, id: inv.scriptID, revision: inv.scriptRevision)
        return ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                HeadBoard(kicker: "Ear drama \u{00B7} In progress", name: inv.title, genre: PlayScript.boardGenre, art: nil,
                          first: nil, last: nil, facts: script.map(PlayHead.facts) ?? [],
                          credits: script?.authorLineWithYears, castScript: script)
                if let script {
                    ActionRow {
                        Button {
                            if live.isRunning { live.stop() } else { Task { await listen(inv, script, part: nil) } }
                        } label: {
                            Label(live.isRunning && hearing == nil ? "Stop" : "Listen through",
                                  systemImage: live.isRunning && hearing == nil ? "stop.fill" : "play.fill")
                        }
                        .pageAction(primary: true)
                        .disabled(fetching)
                        .accessibilityIdentifier("invite-listen")
                        if shared.invitation?.id == inv.id, shared.invitation?.member == true {
                            Button { Task { await openMine(inv.id) } } label: { ActionLabel(title: "Open", systemImage: "arrow.right") }
                                .pageAction()
                        }
                    }
                    if fetching { ProgressView() }
                    if let entry = live.current, let spoken = script.lines.first(where: { $0.id == entry.lineID }) {
                        VStack(alignment: .leading, spacing: Spacing.s1) {
                            if entry.isDeviceVoice {
                                Label("Device voice", systemImage: "waveform").font(TypeRamp.caption)
                                    .foregroundStyle(Color.brandSecondary)
                            }
                            ScriptLineText(line: spoken)
                        }
                    }
                } else {
                    Text(PlaysShare.line(PlaysRefusal.code("revision_mismatch"))).foregroundStyle(Color.brandTextMuted)
                }
                if let line {
                    Label(line, systemImage: "exclamationmark.triangle").foregroundStyle(Color.semanticError)
                }
                Text("Parts").font(TypeRamp.sectionHeader)
                PartGrid {
                    ForEach(inv.parts) { part in
                        card(part, inv, script)
                    }
                }
                if let refusal = shared.invitationRefusal, shared.invitation != nil {
                    Label(refusal, systemImage: "exclamationmark.triangle").foregroundStyle(Color.semanticError)
                }
            }
            .padding(Spacing.s4)
            .modifier(ReadableColumn())
        }
    }

    @ViewBuilder private func card(_ part: OpenInvite.Part, _ inv: OpenInvite, _ script: PlayScript?) -> some View {
        let id = PartID(rawValue: part.id)
        if let script, let cast = script.castParts.first(where: { $0.id == id }) {
            PartCard(script: script, part: cast, holder: InviteParts.holder(part), recorded: part.status == .done,
                     who: InviteParts.who(part)) {
                actions(part, inv, script)
            }
        }
    }

    @ViewBuilder private func actions(_ part: OpenInvite.Part, _ inv: OpenInvite, _ script: PlayScript) -> some View {
        let id = PartID(rawValue: part.id)
        let heard = !inv.takeIDs(forPart: part.id).isEmpty
        if heard {
            Button {
                if live.isRunning { live.stop() } else { Task { await listen(inv, script, part: part.id) } }
            } label: {
                Label(live.isRunning && hearing == part.id ? "Stop" : "Play",
                      systemImage: live.isRunning && hearing == part.id ? "stop.fill" : "play.fill")
            }
            .buttonStyle(.play(.way))
            .disabled(fetching || (live.isRunning && hearing != part.id))
            .accessibilityLabel("Play \(id.title)")
        }
        if InviteRules.canTake(part, in: inv) {
            Button("Take Part") {
                if account.isSignedIn {
                    name = ""
                    Task {
                        if shared.invitation == nil { await shared.viewInvitation(token, plays: plays) }
                        taking = id
                    }
                } else {
                    signingInFor = id
                }
            }
            .buttonStyle(.play(inv.next == part.id ? .ink : .way))
            .accessibilityLabel("Take \(id.title)")
        }
    }

    // MARK: The Worker, the cache, the join

    private func read() async {
        if case .loaded = phase {} else { phase = .loading }
        do {
            phase = .loaded(try await api.openInvite(token))
            await plays.load()
            if account.isSignedIn { await shared.viewInvitation(token, plays: plays) }
        } catch {
            phase = .failed(PlaysShare.line(error))
        }
    }

    private var folder: URL {
        URL.cachesDirectory.appending(path: "OpenInvites", directoryHint: .isDirectory)
            .appending(path: String(token.prefix(12)), directoryHint: .isDirectory)
    }

    private func cached() -> [String: String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        var out: [String: String] = [:]
        for name in names where name.hasPrefix("m-") {
            out[String(name.dropFirst(2).split(separator: ".").first ?? "")] = name
        }
        return out
    }

    /// Fetches the chosen takes the Worker shows (into Caches only), then plays the whole play, or one
    /// part's takes alone. The device voice reads the rest live in a whole listen, labeled.
    private func listen(_ inv: OpenInvite, _ script: PlayScript, part: String?) async {
        line = nil
        fetching = true
        hearing = part
        let rec = inv.record
        var files = cached()
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for id in SharedListen.toFetch(rec, have: Set(files.keys)) where part == nil || inv.takeIDs(forPart: part ?? "").contains(id) {
                let data = try await api.audio(token, takeID: id)
                let file = SharedListen.fileName(id, data)
                try data.write(to: folder.appending(path: file), options: .atomic)
                files[id] = file
            }
        } catch {
            line = PlaysShare.line(error)
        }
        fetching = false
        player.pause()
        var plan = SharedListen.plan(rec, script: script, files: files)
        if let part {
            plan = plan.filter { if case let .take(_, p, _) = $0 { p.rawValue == part } else { false } }
        }
        let dir = folder
        await live.run(plan) { dir.appending(path: $0.file) }
        hearing = nil
    }

    private func join(_ part: PartID) async {
        guard let made = await shared.join(token, part: part, name: name, plays: plays) else {
            line = shared.invitationRefusal
            return
        }
        open(made)
    }

    private func openMine(_ pid: String) async {
        if let made = await shared.open(pid, plays: plays) { open(made) } else { line = shared.invitationRefusal }
    }

    private func open(_ production: Production) {
        app.paths[.home] = NavigationPath()
        #if os(macOS)
        openWindow(id: ProductionWindow_macOS.id, value: production.id)
        #else
        app.selectedTab = .library
        app.push(PlayRoute.production(production.id))
        #endif
    }

    private func leave() {
        live.stop()
        shared.dropInvitation()
        app.paths[.home] = NavigationPath()
    }
}

extension PartID: Identifiable {
    var id: String { rawValue }
}

/// The ask for an account, at the moment of taking a part: the same native sign-in as the Account page.
struct SignInSheet: View {
    let dismiss: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                Text("Taking a part needs an account.").font(TypeRamp.bodyStrong)
                SignInButtons()
                Spacer(minLength: 0)
            }
            .padding(Spacing.s4)
            .navigationTitle("Take part")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: dismiss) }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium])
        #else
        .frame(minWidth: 360, minHeight: 240)
        #endif
    }
}
#endif
