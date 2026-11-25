#if os(iOS) || os(macOS)
import SwiftUI

// A shared own script's cast sheet rows (PLAYS-DESIGN §13 items 11 to 16; iOS-DESIGN §4.21a, macOS-DESIGN §4.11a): who can read
// it, or the refusal that stands in its place, why there is no Publish, Read Together, Edit a Copy, Report Script. The rules are
// `OwnShare`'s; these views only offer them, in the web's words (js/plays-ui.js `ownBox`).

struct OwnShareRows: View {
    let production: Production
    let script: PlayScript
    let rec: SharedRecord
    @Environment(PlaysLibrary.self) private var plays
    @Environment(SharedPlays.self) private var shared
    @Environment(AppStore.self) private var app
    @State private var reporting = false
    @State private var copying = false
    @State private var failure: String?
    @State private var starting = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        rows
            .sheet(isPresented: $reporting) {
                ReportScriptSheet(production: production) { sent in
                    reporting = false
                    if sent { dismiss() }
                }
            }
    }

    @ViewBuilder private var rows: some View {
        let me = shared.userID
        if let own = OwnShare.state(rec.ownScript, me: me) {
            let directs = rec.director == me
            VStack(alignment: .leading, spacing: Spacing.s2) {
                switch own.state {
                case "owed":
                    Label(directs ? OwnShare.notSent : PlaysShare.line(PlaysRefusal.code("no_script")), systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color.semanticError)
                    if directs, let why = shared.notSent[production.id] ?? nil {
                        Text(verbatim: why).font(TypeRamp.caption).foregroundStyle(Color.semanticError)
                    }
                case "removed":
                    Label(PlaysShare.line(PlaysRefusal.code("script_removed")), systemImage: "exclamationmark.triangle").foregroundStyle(Color.semanticError)
                default:
                    Text(verbatim: OwnShare.readersLine(rec, me: me)).font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
                }
                Text(verbatim: OwnShare.neverPublishes(rec) ?? OwnText.cannotPublish).font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
                if let failure { Label(failure, systemImage: "exclamationmark.triangle").font(TypeRamp.caption).foregroundStyle(Color.semanticError) }
            }
            if own.state == "owed", directs {
                Button("Try Again") {
                    Task { await shared.sendAgain(production.id, script: script, store: plays.store, own: plays.own) }
                }
                .accessibilityIdentifier("own-try-again")
            }
            if own.state == "kept", directs, rec.classID == nil {
                Button { Task { await read() } } label: { Label("Read Together", systemImage: "person.2") }
                    .disabled(starting)
                    .accessibilityIdentifier("own-read-together")
            }
            if own.mine {
                Button("Edit a Copy") { Task { await copy() } }
                    .disabled(copying)
                    .accessibilityIdentifier("own-edit-copy")
            } else if own.state == "kept" {
                Button("Report Script") { reporting = true }
                    .accessibilityIdentifier("own-report")
            }
        }
    }

    private func copy() async {
        copying = true
        failure = nil
        defer { copying = false }
        do {
            let made = try await plays.own.copy(script)
            let n = OwnScript.castCount(made.doc)
            if let episode = made.episode?.id, made.ear != nil, n.cast < n.lines { app.push(PlayRoute.cast(episode)) } else { app.push(PlayRoute.parts(made.id)) }
        } catch {
            failure = OwnText.notKept(error)
        }
    }

    /// A reading of an own script carries the production it was shared as (item 13): the room's people read it from there.
    private func read() async {
        starting = true
        failure = nil
        defer { starting = false }
        let session = ReadSession.system()
        do {
            try await session.open(ReadOpening.body(script, productionID: rec.id), teacher: true)
            if let code = session.code { ReadHandover.hold(session); app.push(Route.readRoom(code)) }
        } catch let f as ReadFailure {
            failure = ReadCore.refusal(f.code)
        } catch {
            failure = PlaysShare.line(error)
        }
    }
}

/// Report script: copyright first, then the reasons a take has, and an optional note. The production is then hidden from its reporter.
struct ReportScriptSheet: View {
    let production: Production
    var done: (Bool) -> Void
    @Environment(PlaysLibrary.self) private var plays
    @Environment(SharedPlays.self) private var shared
    @State private var reason = ReportReason.copyright
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("Reason", selection: $reason) {
                    ForEach(ReportReason.forScript) { Text($0.title).tag($0) }
                }
                TextField("Note (optional)", text: $note, axis: .vertical)
                if let line = shared.refusal(production.id) {
                    Label(line, systemImage: "exclamationmark.triangle").foregroundStyle(Color.semanticError)
                }
            }
            .navigationTitle("Report Script")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { done(false) } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Report") {
                        Task { done(await shared.reportScript(production.id, store: plays.store, reason: reason, note: note)) }
                    }
                }
            }
        }
        #if os(macOS)
        .frame(width: 380, height: 300)
        #endif
    }
}
#endif
