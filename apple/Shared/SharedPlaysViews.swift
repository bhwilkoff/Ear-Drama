#if os(iOS) || os(macOS)
import SwiftUI

// Shared ear dramas, phase 2 (PLAYS-DESIGN §11.7; iOS-DESIGN §4.12a,
// macOS-DESIGN §4.5a). The verbs are PlaysShare's; these views only offer
// them, with the web's words. The TV offers none of it.

// MARK: - The cast sheet's sharing rows

/// Above the parts: Share, or for a shared production Invite, Upload, People,
/// Publish, and the facts the Worker gives.
struct SharedProductionSection: View {
    let production: Production
    let script: PlayScript
    @Environment(PlaysLibrary.self) private var plays
    @Environment(SharedPlays.self) private var shared
    @Environment(AccountStore.self) private var account
    @State private var naming = false
    @State private var name = ""
    @State private var people = false

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
        if rec.archive != nil || shared.queued.contains(rec.id) {
            Text("Queued for archive.org").foregroundStyle(Color.brandTextMuted)
        } else if rec.director == me, PlaysShare.complete(rec, script) {
            Button {
                Task { await shared.publish(production.id, store: plays.store) }
            } label: {
                Label("Publish", systemImage: "tray.and.arrow.up")
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
        HStack(spacing: Spacing.s3) {
            Button { open(part.id) } label: {
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Text(verbatim: part.title).font(TypeRamp.bodyStrong).foregroundStyle(Color.brandText)
                    Text(verbatim: status(state, mine: mine))
                        .font(TypeRamp.caption)
                        .foregroundStyle(Color.brandTextMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityElement(children: .combine)
            if mine {
                Button("Record") { open(part.id) }.buttonStyle(.borderedProminent)
                Menu {
                    Button("Done with This Part") { act("done") }
                        .disabled(!PlaysShare.pending(production, script, rec, me).filter { $0.part == part.id }.isEmpty)
                    Button("Release") { act("release") }
                } label: {
                    Image(systemName: "ellipsis.circle").accessibilityLabel("More")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            } else if PlaysShare.canClaim(rec, part.id) {
                if !part.id.isSpeaking {
                    Button("Leave Silent") { act("silent") }.buttonStyle(.bordered)
                }
                if rec.next == part.id.rawValue {
                    Button("Take Part") { claim() }.buttonStyle(.borderedProminent)
                } else {
                    Button("Take Part") { claim() }.buttonStyle(.bordered)
                }
            } else if [.done, .silent].contains(state.status), state.userID == me || rec.director == me {
                Menu {
                    Button("Open Part") { act("reopen") }
                } label: {
                    Image(systemName: "ellipsis.circle").accessibilityLabel("More")
                }
                .menuStyle(.borderlessButton)
                .disabled(PlaysShare.recordingPart(rec) != nil)
                .fixedSize()
            }
        }
        .disabled(shared.busy.contains(production.id))
    }

    private func status(_ state: SharedRecord.Part, mine: Bool) -> String {
        let lines = part.lineCount == 1 ? "1 line" : "\(part.lineCount) lines"
        let name = state.performer.map { " · \($0)" } ?? ""
        switch state.status {
        case .open: return lines
        case .recording where mine:
            let missing = Relay.missingLines(part.id, in: production, script: script).count
            return "\(part.lineCount - missing) of \(lines) recorded\(name)"
        case .recording: return "Recording\(name)"
        case .done: return "Recorded\(name)"
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

// MARK: - The consent (Decision 059)

extension View {
    /// The Worker's consent words, exactly as they arrive, with I Agree and
    /// Not Now; the app writes none of them (§11.7 rule 6).
    func sharedPlaysConsent() -> some View { modifier(ConsentSheet()) }
}

private struct ConsentSheet: ViewModifier {
    @Environment(SharedPlays.self) private var shared

    func body(content: Content) -> some View {
        content.sheet(item: Binding(get: { shared.asking }, set: { if $0 == nil { shared.answerConsent(false) } })) { consent in
            NavigationStack {
                ScrollView {
                    Text(verbatim: consent.text)
                        .font(TypeRamp.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Spacing.s4)
                        .textSelection(.enabled)
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("I Agree") { shared.answerConsent(true) }
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Not Now") { shared.answerConsent(false) }
                    }
                }
            }
            #if os(macOS)
            .frame(minWidth: 420, minHeight: 360)
            #endif
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

// MARK: - Library's Ear dramas: the invitation, the shared productions, classes

/// An opened invite (§11.7 rule 3): the play and its parts; signed out, Sign
/// in to join; signed in, Take Part per open part with an optional name, or
/// Open for a member; Not Now drops the token.
struct InvitationSection: View {
    let token: String
    let open: (Production) -> Void
    @Environment(AppStore.self) private var app
    @Environment(PlaysLibrary.self) private var plays
    @Environment(SharedPlays.self) private var shared
    @Environment(AccountStore.self) private var account
    @State private var taking: PartID?
    @State private var name = ""

    var body: some View {
        Section("Invitation") {
            if !account.isSignedIn {
                Text("Sign in to join")
                SignInButtons()
            } else if let view = shared.invitation {
                Text(verbatim: view.title).font(TypeRamp.bodyStrong)
                if shared.invitationRefusal == nil {
                    if view.member {
                        Button("Open") { Task { if let p = await shared.open(view.id, plays: plays) { finish(p) } } }
                    } else {
                        ForEach(view.parts) { part in
                            partRow(part, view)
                        }
                    }
                }
            } else if shared.invitationRefusal == nil {
                ProgressView()
            }
            if let refusal = shared.invitationRefusal {
                Label(refusal, systemImage: "exclamationmark.triangle").foregroundStyle(Color.semanticError)
            }
            Button("Not Now") {
                app.pendingInvite = nil
                shared.dropInvitation()
            }
        }
        .task(id: "\(token)\(account.isSignedIn)") {
            await plays.load()
            if account.isSignedIn { await shared.viewInvitation(token, plays: plays) }
        }
        .alert("Take this part", isPresented: Binding(get: { taking != nil }, set: { if !$0 { taking = nil } })) {
            TextField("Your name", text: $name)
            Button("Take Part") {
                guard let part = taking else { return }
                Task { if let p = await shared.join(token, part: part, name: name, plays: plays) { finish(p) } }
            }
            Button("Cancel", role: .cancel) { taking = nil }
        }
    }

    @ViewBuilder private func partRow(_ part: InviteView.Part, _ view: InviteView) -> some View {
        let id = PartID(rawValue: part.id)
        let recording = view.parts.contains { $0.status == .recording }
        HStack(spacing: Spacing.s3) {
            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(verbatim: id.title).font(TypeRamp.body)
                Text(verbatim: state(part)).font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
            }
            .accessibilityElement(children: .combine)
            Spacer()
            if part.status == .open && !recording {
                if view.next == part.id {
                    takeButton(id).buttonStyle(.borderedProminent)
                } else {
                    takeButton(id).buttonStyle(.bordered)
                }
            }
        }
    }

    private func takeButton(_ part: PartID) -> some View {
        Button("Take Part") {
            name = ""
            taking = part
        }
    }

    private func state(_ part: InviteView.Part) -> String {
        switch part.status {
        case .open: part.lineCount == 1 ? "1 line" : "\(part.lineCount) lines"
        case .recording: "Recording"
        case .done: "Recorded"
        case .silent: "Left silent"
        }
    }

    private func finish(_ production: Production) {
        app.pendingInvite = nil
        open(production)
    }
}

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
#endif
