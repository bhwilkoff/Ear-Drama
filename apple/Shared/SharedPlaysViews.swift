#if os(iOS) || os(macOS)
import SwiftUI

// Shared ear dramas, phase 2 (PLAYS-DESIGN §11.7; iOS-DESIGN §4.12a,
// macOS-DESIGN §4.5a). The verbs are PlaysShare's; these views only offer
// them, with the web's words. The TV offers none of it.

// MARK: - The cast sheet's sharing rows

/// Above the parts: Share, or for a shared production Invite, Upload, People,
/// and the facts the Worker gives. Publish asks the CC0 consent first (`ConsentSheet`).
struct SharedProductionSection: View {
    let production: Production
    let script: PlayScript
    @Environment(PlaysLibrary.self) private var plays
    @Environment(SharedPlays.self) private var shared
    @Environment(AccountStore.self) private var account
    @State private var naming = false
    @State private var name = ""
    @State private var people = false
    @State private var consent: PlaysConsent?
    @State private var asking = false
    @State private var notNow = false

    var body: some View {
        if account.status != .unavailable {
            Section {
                if let rec = shared.record(for: production, in: plays.store) {
                    sharedRows(rec)
                } else if plays.store.share(production.id) != nil {
                    ProgressView()
                } else if account.isSignedIn {
                    Button {
                        name = ""
                        naming = true
                    } label: {
                        Label("Share", systemImage: "person.2.badge.plus")
                    }
                } else {
                    Text("Sharing needs an account.")
                    SignInButtons()
                }
                if let refusal = shared.refusal(production.id) {
                    Label(refusal, systemImage: "exclamationmark.triangle").foregroundStyle(Color.semanticError)
                }
            }
            .disabled(shared.busy.contains(production.id))
            .alert("Share", isPresented: $naming) {
                TextField("Your name", text: $name)
                Button("Share") { Task { await shared.share(production, script: script, store: plays.store, name: name) } }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $people) {
                PeopleSheet(production: production, script: script)
            }
            .task { consent = await shared.consent() }
            .sheet(isPresented: $asking) {
                if let consent {
                    ConsentSheet(consent: consent) {
                        Task { await shared.publish(production.id, store: plays.store, script: script, consent: consent) }
                    }
                }
            }
        }
    }

    @ViewBuilder private func sharedRows(_ rec: SharedRecord) -> some View {
        let me = shared.userID
        if rec.director == me {
            InviteRow(productionID: production.id)
        }
        uploadRow(rec, me: me)
        Button {
            people = true
        } label: {
            Label("People", systemImage: "person.2")
        }
        if rec.hiddenTakes > 0 {
            Text(rec.hiddenTakes == 1 ? "1 take is hidden from you." : "\(rec.hiddenTakes) takes are hidden from you.")
                .foregroundStyle(Color.brandTextMuted)
        }
        if let line = PlaysShare.archiveLine(rec) {
            archiveRow(line, rec)
        } else if shared.queued.contains(rec.id) {
            Text("Queued for archive.org").foregroundStyle(Color.brandTextMuted)
        } else if PlaysShare.needsMyConsent(rec, script, me) {
            if let consent, consent.publishes == true, !notNow {
                ConsentWords(text: consent.text)
                Button("I agree to publish my recording under CC0.") {
                    Task { await shared.agree(production.id, store: plays.store, script: script, consent: consent) }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.brandPrimary)
                Button("Not Now") { notNow = true }
            }
        } else if PlaysShare.canPublish(rec, script, me) {
            if consent?.publishes == true {
                ForEach(PlaysShare.performers(rec)) { m in
                    let agreed = m.consented == true
                    Label(m.displayName ?? "No name", systemImage: agreed ? "checkmark.circle.fill" : "circle")
                        .accessibilityValue(agreed ? "Agreed" : "Not yet")
                }
                Button {
                    asking = true
                } label: {
                    Label("Publish", systemImage: "tray.and.arrow.up")
                }
                .disabled(!PlaysShare.waitingOn(rec).isEmpty)
            } else if consent != nil {
                Text(PlaysShare.publishWaits).foregroundStyle(Color.brandTextMuted)
            }
        }
    }

    /// The archive.org job in essential words (rule 9): quiet while it waits, the item's link
    /// (the system opens it), or the Worker's reason with Publish Again.
    @ViewBuilder private func archiveRow(_ line: PlaysShare.ArchiveLine, _ rec: SharedRecord) -> some View {
        switch line {
        case let .waiting(text):
            Text(verbatim: text).foregroundStyle(Color.brandTextMuted)
        case let .published(url):
            if let url { Link("On archive.org", destination: url) } else { Text("On archive.org") }
        case let .failed(reason):
            Label(reason, systemImage: "exclamationmark.triangle").foregroundStyle(Color.semanticError)
            if PlaysShare.canPublishAgain(rec, shared.userID) {
                Button("Publish Again") {
                    Task { await shared.publishAgain(production.id, store: plays.store, script: script) }
                }
            }
        }
    }

    /// Upload N Takes; while the owner's switch is off, the warning stands in
    /// its place before anyone records (§11.7 rule 5).
    @ViewBuilder private func uploadRow(_ rec: SharedRecord, me: String?) -> some View {
        if !PlaysShare.uploadsOpen(rec) {
            Label("Uploads are off.", systemImage: "exclamationmark.triangle").foregroundStyle(Color.semanticWarning)
        } else {
            let ready = PlaysShare.pending(production, script, rec, me).count
            if ready > 0 {
                Button {
                    Task { await shared.upload(production.id, store: plays.store, script: script) }
                } label: {
                    Label(ready == 1 ? "Upload 1 Take" : "Upload \(ready) Takes", systemImage: "icloud.and.arrow.up")
                }
            }
            if PlaysShare.flagged(production, script, rec, me) > 0 {
                Label(PlaysShare.line(PlaysRefusal.code("bleed_flagged")), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Color.semanticWarning)
            }
        }
    }
}

// MARK: - Replace or remove a published line (P12, PLAYS-DESIGN §11.7 rule 13)

private struct Removal: Identifiable {
    var change: PlaysShare.Change
    var reason: String
    var id: String { change.id }
}

/// A performer's own lines of a published play offer Replace and Remove; the director's
/// every line offers Remove, and the director picks the reason. Removing asks first with
/// the system's confirmation; the action takes the error color, never red.
struct ChangeLinesSection: View {
    let production: Production
    let script: PlayScript
    let rec: SharedRecord
    let replace: (PartID, String) -> Void
    @Environment(PlaysLibrary.self) private var plays
    @Environment(SharedPlays.self) private var shared
    @State private var removing: Removal?

    var body: some View {
        let items = PlaysShare.changeableLines(rec, script, shared.userID)
        if !items.isEmpty {
            Section(rec.director == shared.userID ? "Lines" : "Your Lines") {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: Spacing.s2) {
                        ScriptLineText(line: item.line)
                        if shared.removed.contains("\(rec.id) \(item.id)") {
                            Text("Removed").font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
                        } else {
                            HStack(spacing: Spacing.s4) {
                                if item.replace {
                                    Button("Replace") { replace(item.line.part, item.id) }
                                }
                                remove(item)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
            .disabled(shared.busy.contains(production.id))
            .confirmationDialog("Remove this line from archive.org?",
                                isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                                titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    guard let r = removing else { return }
                    Task { await shared.removeLine(production.id, lineID: r.change.id, reason: r.reason, store: plays.store) }
                }
            }
        }
    }

    @ViewBuilder private func remove(_ item: PlaysShare.Change) -> some View {
        if item.needsReason {
            Menu {
                ForEach(ReportReason.allCases) { reason in
                    Button(reason.title) { removing = Removal(change: item, reason: reason.rawValue) }
                }
            } label: {
                Text("Remove").foregroundStyle(Color.semanticError)
            }
        } else {
            Button { removing = Removal(change: item, reason: "withdrawn") } label: {
                Text("Remove").foregroundStyle(Color.semanticError)
            }
        }
    }
}

/// The director's Invite: the Worker makes the link once, and the share sheet
/// carries it; the caption is the fact of how long it works.
private struct InviteRow: View {
    let productionID: String
    @Environment(PlaysLibrary.self) private var plays
    @Environment(SharedPlays.self) private var shared

    var body: some View {
        if let invite = shared.lastInvite[productionID] {
            VStack(alignment: .leading, spacing: Spacing.s1) {
                ShareLink(item: PlaysShare.inviteLink(invite.token)) {
                    Label("Invite", systemImage: "square.and.arrow.up")
                }
                let days = PlaysShare.inviteDays(invite)
                Text(days == 1 ? "Works for 1 day." : "Works for \(days) days.")
                    .font(TypeRamp.caption)
                    .foregroundStyle(Color.brandTextMuted)
            }
        } else {
            Button {
                Task { await shared.invite(productionID, store: plays.store) }
            } label: {
                Label("Invite", systemImage: "envelope")
            }
        }
    }
}

// MARK: - A shared part's row

/// One part as the Worker has it (§11.7 rule 4): mine and recording, Record;
/// open while none records, Take Part (the suggestion prominent) and, for
/// sound and directions, Leave Silent; finished, mine or I direct, Open Part.
struct SharedPartRow: View {
    let production: Production
    let script: PlayScript
    let part: CastPart
    let rec: SharedRecord
    let open: (PartID) -> Void
    @Environment(PlaysLibrary.self) private var plays
    @Environment(SharedPlays.self) private var shared

    var body: some View {
        let state = rec.part(part.id)
        let me = shared.userID
        let mine = PlaysShare.isMine(rec, part.id, me)
        PartCard(script: script, part: part, holder: holder(state), recorded: state.status == .done,
                 who: who(state, mine: mine), current: mine && state.status == .recording,
                 onOpen: { open(part.id) }) {
            if mine {
                HStack(spacing: Spacing.s2) {
                    Button("Record") { open(part.id) }.buttonStyle(.play(.ink))
                    Menu {
                        Button("Done with This Part") { act("done") }
                            .disabled(!PlaysShare.pending(production, script, rec, me).filter { $0.part == part.id }.isEmpty)
                        Button("Release") { act("release") }
                    } label: {
                        Image(systemName: "ellipsis.circle").accessibilityLabel("More")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            } else if PlaysShare.canClaim(rec, part.id) {
                HStack(spacing: Spacing.s2) {
                    if !part.id.isSpeaking {
                        Button("Leave silent") { act("silent") }.buttonStyle(.play(.way))
                    }
                    Button("Take part") { claim() }.buttonStyle(.play(rec.next == part.id.rawValue ? .ink : .way))
                }
            } else if [.done, .silent].contains(state.status), state.userID == me || rec.director == me {
                Button("Open part") { act("reopen") }
                    .buttonStyle(.play(.way))
                    .disabled(PlaysShare.recordingPart(rec) != nil)
            }
        }
        .disabled(shared.busy.contains(production.id))
    }

    private func holder(_ state: SharedRecord.Part) -> PartHolder {
        switch state.status {
        case .open: .deviceVoice
        case .recording, .done: .person(state.performer)
        case .silent: .silent
        }
    }

    private func who(_ state: SharedRecord.Part, mine: Bool) -> String {
        let name = state.performer
        switch state.status {
        case .open: return "Open"
        case .recording where mine:
            let missing = Relay.missingLines(part.id, in: production, script: script).count
            return "\(name ?? "You") \u{00B7} \(part.lineCount - missing) of \(part.lineCount)"
        case .recording: return name.map { "\($0) \u{00B7} recording" } ?? "Recording"
        case .done: return name.map { "\($0) \u{00B7} recorded" } ?? "Recorded"
        case .silent: return "Left silent"
        }
    }

    private func act(_ action: String) {
        Task { await shared.act(production.id, part: part.id, action: action, store: plays.store) }
    }

    private func claim() {
        Task {
            await shared.act(production.id, part: part.id, action: nil, store: plays.store)
            if plays.store.production(production.id)?.state(of: part.id).status == .recording { open(part.id) }
        }
    }
}

// MARK: - People: report and block (guideline 1.2)

private struct ReportTarget: Identifiable {
    var takeID: String?
    var userID: String?
    var id: String { takeID ?? userID ?? "" }
}

/// The members by display name, "You" and "Director" as tags; everyone else
/// has Report and Block (§11.7 rule 8).
struct PeopleSheet: View {
    let production: Production
    let script: PlayScript
    @Environment(PlaysLibrary.self) private var plays
    @Environment(SharedPlays.self) private var shared
    @Environment(\.dismiss) private var dismiss
    @State private var reporting: ReportTarget?
    @State private var blocking: SharedRecord.Member?

    var body: some View {
        NavigationStack {
            List {
                if let rec = shared.record(for: production, in: plays.store) {
                    ForEach(rec.members) { member in
                        row(member)
                    }
                }
                if let refusal = shared.refusal(production.id) {
                    Label(refusal, systemImage: "exclamationmark.triangle").foregroundStyle(Color.semanticError)
                }
            }
            .navigationTitle("People")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(item: $reporting) { target in
                ReportSheet(production: production, script: script, takeID: target.takeID, userID: target.userID)
            }
            .confirmationDialog(blocking.map { "Block \(name($0))?" } ?? "",
                                isPresented: Binding(get: { blocking != nil }, set: { if !$0 { blocking = nil } })) {
                Button("Block", role: .destructive) {
                    guard let member = blocking else { return }
                    Task { await shared.block(production.id, store: plays.store, userID: member.userID, script: script) }
                }
            } message: {
                Text("You will no longer hear their takes.")
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 320)
        #endif
    }

    @ViewBuilder private func row(_ member: SharedRecord.Member) -> some View {
        let me = member.userID == shared.userID
        HStack(spacing: Spacing.s3) {
            Text(verbatim: name(member)).font(TypeRamp.body)
            if me {
                Text("You").font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
            } else if member.director {
                Text("Director").font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
            }
            Spacer()
            if !me {
                Button("Report") { reporting = ReportTarget(userID: member.userID) }.buttonStyle(.borderless)
                Button("Block", role: .destructive) { blocking = member }.buttonStyle(.borderless)
            }
        }
    }

    private func name(_ member: SharedRecord.Member) -> String { member.displayName ?? "No name" }
}

/// Report a take or a member: a reason and an optional note.
struct ReportSheet: View {
    let production: Production
    let script: PlayScript
    let takeID: String?
    let userID: String?
    @Environment(PlaysLibrary.self) private var plays
    @Environment(SharedPlays.self) private var shared
    @Environment(\.dismiss) private var dismiss
    @State private var reason: ReportReason = .offensive
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("Reason", selection: $reason) {
                    ForEach(ReportReason.allCases) { Text(verbatim: $0.title).tag($0) }
                }
                TextField("Note", text: $note, axis: .vertical)
            }
            .navigationTitle(takeID == nil ? "Report" : "Report Take")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Report") {
                        Task {
                            await shared.report(production.id, store: plays.store, takeID: takeID, userID: userID,
                                                reason: reason, note: String(note.prefix(500)), script: script)
                        }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 240)
        #endif
    }
}

/// A read-along line voiced by someone else carries Report Take (rule 8).
struct ReportTakeMenu: ViewModifier {
    let production: Production
    let script: PlayScript
    let lineID: String
    @Environment(PlaysLibrary.self) private var plays
    @Environment(SharedPlays.self) private var shared
    @State private var reporting = false

    func body(content: Content) -> some View {
        if let rec = shared.record(for: production, in: plays.store), let takeID = rec.chosen[lineID],
           let take = rec.takes.first(where: { $0.id == takeID }), take.userID != shared.userID {
            content
                .contextMenu { Button("Report Take") { reporting = true } }
                .sheet(isPresented: $reporting) {
                    ReportSheet(production: production, script: script, takeID: takeID, userID: nil)
                }
        } else {
            content
        }
    }
}

// MARK: - Library's Ear dramas: the shared productions, classes

/// A shared production this person is in that this device has not opened:
/// opening it makes it here from the bundle's script (rule 11).
struct RemoteProductionRow: View {
    let remote: RemoteProduction
    let open: (Production) -> Void
    @Environment(PlaysLibrary.self) private var plays
    @Environment(SharedPlays.self) private var shared

    var body: some View {
        Button {
            Task {
                await plays.load()
                if let p = await shared.open(remote.id, plays: plays) { open(p) }
            }
        } label: {
            Text(verbatim: remote.title).font(TypeRamp.bodyStrong).foregroundStyle(Color.brandText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }
}

/// Classes (rule 10): a roster only. A teacher sees each code in two groups of
/// four; an under-13 class waits for the school's consent.
struct ClassesSection: View {
    @Environment(SharedPlays.self) private var shared
    @State private var making = false
    @State private var joining = false
    @State private var name = ""
    @State private var under13 = false
    @State private var code = ""

    var body: some View {
        Section("Classes") {
            if let classes = shared.classes {
                ForEach(classes.teaching) { c in
                    VStack(alignment: .leading, spacing: Spacing.s1) {
                        Text(verbatim: c.name).font(TypeRamp.body)
                        if let code = c.code {
                            Text(verbatim: SharedPlays.grouped(code)).font(TypeRamp.tabular).textSelection(.enabled)
                        }
                        if c.under13 && c.schoolConsent != true {
                            Text("Waits for the school’s consent").font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
                        }
                    }
                }
                ForEach(classes.memberOf) { c in
                    Text(verbatim: c.name).font(TypeRamp.body)
                }
            }
            Button("Make a Class") {
                name = ""
                under13 = false
                making = true
            }
            Button("Join a Class") {
                code = ""
                joining = true
            }
            if let refusal = shared.classRefusal {
                Label(refusal, systemImage: "exclamationmark.triangle").foregroundStyle(Color.semanticError)
            }
        }
        .task { await shared.loadClasses() }
        .sheet(isPresented: $making) {
            NavigationStack {
                Form {
                    TextField("Name", text: $name)
                    Toggle("Under 13", isOn: $under13)
                }
                .navigationTitle("Make a Class")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Make") {
                            making = false
                            Task { await shared.makeClass(name, under13: under13) }
                        }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { making = false } }
                }
            }
            #if os(macOS)
            .frame(minWidth: 360, minHeight: 200)
            #endif
        }
        .alert("Join a Class", isPresented: $joining) {
            TextField("Code", text: $code)
            Button("Join") { Task { await shared.joinClass(code) } }
            Button("Cancel", role: .cancel) {}
        }
    }
}
// MARK: - The CC0 consent (PLAYS-DESIGN §11.7 rule 6)

/// The served consent words as a lead and a bulleted list, none changed.
struct ConsentWords: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            ForEach(Array(ConsentText.blocks(text).enumerated()), id: \.offset) { _, block in
                switch block.kind {
                case .lead:
                    Text(block.text).font(TypeRamp.bodyStrong)
                case .paragraph:
                    Text(block.text).font(TypeRamp.body)
                case .item:
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.s2) {
                        Text("•").accessibilityHidden(true)
                        Text(block.text)
                    }
                    .font(TypeRamp.body)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The Worker's words exactly as served, then the agreement or Not Now.
struct ConsentSheet: View {
    let consent: PlaysConsent
    let onAgree: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                ConsentWords(text: consent.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("Publish")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    dismiss()
                    onAgree()
                } label: {
                    Text("I agree to publish my recording under CC0.").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding()
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 420)
        #endif
    }
}
#endif
