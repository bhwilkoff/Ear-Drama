#if os(iOS) || os(macOS)
import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

// Adding a script, and what an own script adds to Record, Search and its own page (iOS-DESIGN §4.21, PLAYS-DESIGN §13;
// Decision 088.3). Every word on these pages is the person's own; nothing here writes one. Not on the TV.

// MARK: - The parts' chips, the parts page's and the casting's

/// A part, or a plain verb, as a chip: 36 pt drawn, 44 pt to the finger.
struct OwnChipStyle: ButtonStyle {
    var hue: String?? = nil
    var selected = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Spacing.s2) {
            if let hue { Circle().fill(Color.genre(hue) ?? Color.brandTextMuted).frame(width: 10, height: 10) }
            configuration.label.labelStyle(.titleAndIcon)
        }
        .font(hue == nil ? TypeRamp.body : TypeRamp.bodyStrong)
        .foregroundStyle(hue == nil ? Color.brandTextMuted : Color.brandText)
        .lineLimit(1)
        .padding(.horizontal, Spacing.s3)
        .frame(minHeight: 36)
        .background(selected ? Color.brandSurfaceAlt : Color.clear, in: Capsule())
        .overlay { Capsule().strokeBorder(selected ? Color.brandPrimary : Color.brandBorder, lineWidth: selected ? 2 : 1) }
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Capsule())
        .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
    }
}

struct OwnPartChip: View {
    let name: String
    let hue: String?
    var count: Int? = nil
    var selected = false
    var verb: String? = nil
    let act: () -> Void

    var body: some View {
        Button(action: act) {
            HStack(spacing: Spacing.s1) {
                Text(verbatim: name)
                if let count { Text(verbatim: OwnText.number(count)).font(TypeRamp.tabular).foregroundStyle(Color.brandTextMuted) }
            }
        }
        .buttonStyle(OwnChipStyle(hue: .some(hue), selected: selected))
        .accessibilityLabel(verb.map { "\($0) \(name)" } ?? name)
        .accessibilityValue(count.map { OwnText.count($0, "line", "lines") } ?? "")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A name field with one button: rename, a new part, the title. `act` answers a refusal's words, or nil.
struct OwnNameForm: View {
    let label: String
    var value = ""
    let button: String
    let act: (String) -> String?
    @State private var text = ""
    @State private var refusal: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            HStack(spacing: Spacing.s2) {
                TextField(label, text: $text)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .onSubmit(press)
                    .submitLabel(.done)
                    .accessibilityIdentifier("own-name")
                Button(button, action: press).pageAction().accessibilityIdentifier("own-name-go")
            }
            if let refusal { OwnRefusalText(refusal) }
        }
        .onAppear { text = value; focused = true }
    }

    private func press() { refusal = act(text) }
}

struct OwnRefusalText: View {
    let words: String
    init(_ words: String) { self.words = words }

    var body: some View {
        Label(words, systemImage: "exclamationmark.triangle")
            .font(TypeRamp.caption)
            .foregroundStyle(Color.semanticError)
            .accessibilityIdentifier("own-refusal")
    }
}

/// A small sheet of one form: New Part, Title, a part's own.
struct OwnSmallSheet<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.s4) { content() }
                    .padding(Spacing.s4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        #if os(macOS)
        .frame(width: 420, height: 260)
        #else
        .presentationDetents([.medium, .large])
        #endif
    }
}

/// The title over its count: the bar's own subtitle on 26 and later, a line of the page before it.
struct OwnTitles: ViewModifier {
    let title: String
    let sub: String

    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 26, *) {
            content.navigationTitle(title).navigationSubtitle(sub).navigationBarTitleDisplayMode(.inline)
        } else {
            content.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 0) {
                            Text(verbatim: title).font(TypeRamp.bodyStrong).lineLimit(1)
                            Text(verbatim: sub).font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted).lineLimit(1)
                        }
                    }
                }
        }
        #else
        content.navigationTitle(title).navigationSubtitle(sub)
        #endif
    }
}

/// A failure over the page, with its way on; the page keeps the work.
struct OwnProblemBar: View {
    let words: String
    let again: () -> Void

    var body: some View {
        HStack {
            Label(words, systemImage: "exclamationmark.triangle").foregroundStyle(Color.semanticError)
            Spacer(minLength: Spacing.s2)
            Button("Try Again", action: again).pageAction()
        }
        .font(TypeRamp.body)
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s2)
        .background(Color.semanticErrorSurface)
    }
}

// MARK: - Add a Script

struct AddScriptScreen: View {
    @Environment(PlaysLibrary.self) private var plays
    @Environment(AppStore.self) private var app
    @State private var title = ""
    @State private var text = ""
    @State private var selection: TextSelection?
    @State private var count: (parts: Int, lines: Int)?
    @State private var kept = false
    @State private var refusal: String?
    @State private var importing = false
    @State private var replacement: OwnIncoming?
    @State private var busy = false
    @State private var loaded = false
    @State private var height: CGFloat = 0
    @State private var drafts: OwnLater?
    @FocusState private var titleFocused: Bool

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $title)
                    .focused($titleFocused)
                    .accessibilityIdentifier("own-title")
            }
            Section {
                TextEditor(text: $text, selection: $selection)
                    .font(TypeRamp.body)
                    .frame(minHeight: max(200, height - 330))
                    .accessibilityLabel("Script")
                    .accessibilityIdentifier("own-text")
            } header: {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Spacing.s2) {
                        Text("Script")
                        Spacer(minLength: Spacing.s2)
                        ways
                    }
                    VStack(alignment: .leading, spacing: Spacing.s2) {
                        Text("Script")
                        FlowLayout(spacing: Spacing.s2, rowSpacing: Spacing.s2) { ways }
                    }
                }
                .font(TypeRamp.body)
                .textCase(nil)
            }
        }
        .formStyle(.grouped)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .safeAreaInset(edge: .bottom, spacing: 0) { foot }
        .navigationTitle("Add a Script")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Next") { Task { await next() } }
                    .disabled(count == nil || busy)
                    .accessibilityIdentifier("own-next")
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, .text]) { result in
            if case let .success(url) = result { app.incomingScript = OwnIncoming(url) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, url.isFileURL else { return false }
            app.incomingScript = OwnIncoming(url)
            return true
        }
        .confirmationDialog("Replace the text?", isPresented: Binding(get: { replacement != nil }, set: { if !$0 { replacement = nil } }),
                            titleVisibility: .visible) {
            Button("Replace", role: .destructive) { if let replacement { put(replacement) } }
        }
        .task(id: text) { await read() }
        .onChange(of: title) { keep() }
        .onChange(of: text) { keep() }
        .onAppear {
            app.isAddingScript = true
            start()
        }
        .onChange(of: app.incomingScript, initial: true) { _, found in
            guard let found else { return }
            app.incomingScript = nil
            receive(found)
        }
        .onChange(of: app.wantsScriptFile, initial: true) { _, wants in
            guard wants else { return }
            app.wantsScriptFile = false
            importing = true
        }
        .onDisappear {
            app.isAddingScript = false
            drafts?.flush()
        }
    }

    @ViewBuilder private var ways: some View {
        PasteButton(payloadType: String.self) { strings in paste(strings.joined(separator: "\n")) }
            .labelStyle(.titleAndIcon)
            .buttonBorderShape(.capsule)
            .fixedSize()
        Button("Open a File", systemImage: "doc") { importing = true }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .fixedSize()
    }

    private var foot: some View {
        let facts = [count.map { OwnText.partsAndLines($0.parts, $0.lines) }, kept ? OwnText.kept : nil].compactMap { $0 }
        return VStack(alignment: .leading, spacing: Spacing.s1) {
            if let refusal { OwnRefusalText(refusal) }
            Text(verbatim: facts.joined(separator: " \u{00B7} "))
                .monospacedDigit()
                .font(TypeRamp.caption)
                .foregroundStyle(Color.brandTextMuted)
                .accessibilityIdentifier("own-count")
        }
        .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s2)
        .background(.bar)
    }

    private func start() {
        guard !loaded else { return }
        if let draft = plays.own.draft() {
            title = draft.title
            text = draft.text
            kept = !draft.text.isEmpty
        }
        loaded = true
        let own = plays.own
        drafts = OwnLater(.milliseconds(400)) {
            guard loaded else { return }
            do {
                try own.setDraft(OwnScripts.Draft(title: title, text: text))
                kept = !text.isEmpty
            } catch {
                kept = false
                refusal = OwnText.notKept(error)
            }
        }
        if title.isEmpty, text.isEmpty, app.incomingScript == nil { titleFocused = true }
    }

    private func keep() {
        guard loaded else { return }
        if refusal == OwnText.say(.no_title), !title.isEmpty { refusal = nil }
        kept = false
        drafts?()
    }

    /// The parts and lines found, as the words are typed.
    private func read() async {
        guard (try? await Task.sleep(for: .milliseconds(180))) != nil else { return }
        let words = text
        let found = await Task.detached(priority: .userInitiated) { () -> (count: (parts: Int, lines: Int)?, why: OwnRefusal?) in
            if let why = OwnScript.textRefusal(words) { return (nil, why) }
            let read = OwnScript.parse(words)
            // Judged on what Done would keep, every line with its id: a text that reads but could never be kept is refused here, not at Done.
            if let why = OwnScript.builtRefusal(read.lines) { return (nil, why) }
            return ((read.parts.count, read.lines.count), nil)
        }.value
        guard !Task.isCancelled else { return }
        count = found.count
        let tooBig = found.why == .too_long || found.why == .too_many_lines
        refusal = tooBig ? OwnText.say(.too_long) : (refusal == OwnText.say(.too_long) ? nil : refusal)
    }

    private func paste(_ words: String) {
        guard !words.isEmpty else { return }
        // At the insertion point, as the system's own paste puts it.
        if case let .selection(range)? = selection?.indices, range.upperBound <= text.endIndex, !text.isEmpty {
            text.replaceSubrange(range, with: words)
        } else {
            text += words
        }
    }

    private func receive(_ found: OwnIncoming) {
        switch found.read() {
        case let .failure(why): refusal = why.words
        case .success:
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { put(found) } else { replacement = found }
        }
    }

    private func put(_ found: OwnIncoming) {
        replacement = nil
        guard case let .success(file) = found.read() else { return }
        refusal = nil
        text = file.text
        if title.trimmingCharacters(in: .whitespaces).isEmpty { title = file.title }
    }

    private func next() async {
        guard count != nil else { return }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            refusal = OwnText.say(.no_title)
            titleFocused = true
            return
        }
        busy = true
        defer { busy = false }
        do {
            let rec = try await plays.own.create(title: String(title.prefix(OwnScript.maxTitle)), text: text)
            try? plays.own.setDraft(nil)
            loaded = false
            app.replaceTop(with: PlayRoute.parts(rec.id))
        } catch {
            refusal = OwnText.notKept(error)
        }
    }
}

// MARK: - Your Scripts

/// This device's own scripts: absent when there are none.
struct YourScriptsSection: View {
    @Environment(PlaysLibrary.self) private var plays

    var body: some View {
        let rows = plays.own.rows
        if !rows.isEmpty {
            PageRows("Your Scripts") {
                ForEach(rows) { OwnScriptLink(row: $0).pageRow() }
            }
        }
    }
}

struct OwnScriptLink: View {
    let row: OwnRow
    @Environment(PlaysLibrary.self) private var plays
    @State private var confirming = false

    var body: some View {
        NavigationLink(value: PlayRoute.own(row)) {
            HStack(alignment: .top, spacing: Spacing.s3) {
                ArtTile(name: row.title, genre: PlayScript.boardGenre, face: nil)
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Text(verbatim: row.title).font(TypeRamp.bodyStrong).foregroundStyle(Color.brandText)
                    Text(verbatim: row.facts).font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
                }
            }
            .accessibilityElement(children: .combine)
        }
        #if os(macOS)
        .buttonStyle(.plain)
        #else
        .swipeActions {
            Button(role: .destructive) { confirming = true } label: { Label("Delete", systemImage: "trash") }
        }
        #endif
        .contextMenu {
            Button("Delete", role: .destructive) { confirming = true }
        }
        .deleteOwnScriptDialog(id: row.id, title: row.title, isPresented: $confirming)
        .accessibilityIdentifier("own-row")
    }
}

extension PlayRoute {
    /// Where a script's row goes: its page once Done, else back to what is not finished.
    static func own(_ row: OwnRow) -> PlayRoute {
        if row.done { return .script(row.id) }
        return row.episode.map { .cast($0) } ?? .parts(row.id)
    }
}

extension View {
    func deleteOwnScriptDialog(id: String, title: String, isPresented: Binding<Bool>, then done: @escaping () -> Void = {}) -> some View {
        modifier(DeleteOwnScriptDialog(id: id, title: title, isPresented: isPresented, done: done))
    }
}

private struct DeleteOwnScriptDialog: ViewModifier {
    let id: String
    let title: String
    @Binding var isPresented: Bool
    let done: () -> Void
    @Environment(PlaysLibrary.self) private var plays
    @State private var failed = false

    func body(content: Content) -> some View {
        let made = plays.own.productions(id)
        content
            .confirmationDialog("Delete \(title)?", isPresented: $isPresented, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { Task { await delete(made.isEmpty) } }
            } message: {
                if !made.isEmpty { Text("Its productions keep their copy.") }
            }
            .alert("This device could not delete it.", isPresented: $failed) {}
    }

    private func delete(_ alone: Bool) async {
        do {
            try await plays.own.remove(id)
            // Its productions still read in these; with none left nothing can.
            if alone {
                VoiceCastBook.forget(VoiceCastBook.scriptKey(id), .defaults())
                try? MarkStore().save(scriptID: id, title: nil, [])
                try? InkStore().save(scriptID: id, title: nil, [])
            }
            done()
        } catch {
            failed = true
        }
    }
}

// MARK: - What an own script's page adds to a play's

/// The script as a text file for the share sheet.
nonisolated struct OwnTextFile: Transferable {
    let name: String
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { file in
            let url = URL.temporaryDirectory.appending(path: file.name)
            try Data(file.text.utf8).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

struct OwnScriptFoot: View {
    let script: PlayScript
    @Environment(PlaysLibrary.self) private var plays
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var app
    @State private var confirming = false
    @State private var copyFailure: String?
    #if os(macOS)
    @State private var exporting = false
    #endif

    var body: some View {
        let row = plays.own.row(script.id)
        let frozen = plays.own.frozen(script.id)
        VStack(alignment: .leading, spacing: Spacing.s3) {
            VStack(alignment: .leading, spacing: Spacing.s1) {
                HStack(spacing: Spacing.s1) {
                    if let episode = script.episode {
                        NavigationLink(value: Route.episode(episode)) { Text(verbatim: script.source.name).underline() }
                            .buttonStyle(.plain)
                    } else {
                        Text(OwnText.addedByYou)
                    }
                    Text(verbatim: "\u{00B7} \(frozen ? "Shared" : OwnText.kept)")
                }
                if let row, row.halfCast { Text(verbatim: row.facts).monospacedDigit() }
                Text(OwnText.cannotPublish)
            }
            .font(TypeRamp.caption)
            .foregroundStyle(Color.brandTextMuted)
            FlowLayout(spacing: Spacing.s2, rowSpacing: Spacing.s2) {
                if let row, row.halfCast, !frozen, let episode = script.episode {
                    NavigationLink("Cast by Ear", value: PlayRoute.cast(episode)).pageAction()
                }
                if frozen {
                    // What people were sent is what it stays (§13 item 12): only a copy changes.
                    Button("Edit a Copy") { Task { await copy() } }.pageAction().accessibilityIdentifier("own-edit-copy")
                } else {
                    NavigationLink("Edit", value: PlayRoute.parts(script.id)).pageAction().accessibilityIdentifier("own-edit")
                }
                ShareLink(item: OwnTextFile(name: OwnBuild.fileName(script.title), text: OwnBuild.asText(script)),
                          preview: SharePreview(script.title)) { Text("Save as Text") }
                    .pageAction()
                    .accessibilityIdentifier("own-save-text")
                #if os(macOS)
                // The Mac's own save panel, beside the share sheet (macOS-DESIGN §4.11): the file goes where the person says.
                Button("Save as Text\u{2026}") { exporting = true }.pageAction().accessibilityIdentifier("own-save-panel")
                    .fileExporter(isPresented: $exporting, item: OwnTextFile(name: OwnBuild.fileName(script.title), text: OwnBuild.asText(script)),
                                  contentTypes: [.plainText], defaultFilename: OwnBuild.fileName(script.title)) { _ in }
                #endif
                Button(role: .destructive) { confirming = true } label: { Text("Delete").foregroundStyle(Color.semanticError) }
                    .pageAction()
                    .deleteOwnScriptDialog(id: script.id, title: script.title, isPresented: $confirming) { dismiss() }
                    .accessibilityIdentifier("own-delete")
            }
            if let copyFailure { Text(verbatim: copyFailure).font(TypeRamp.caption).foregroundStyle(Color.semanticError) }
        }
    }

    private func copy() async {
        copyFailure = nil
        do {
            let made = try await plays.own.copy(script)
            let n = OwnScript.castCount(made.doc)
            if let episode = made.episode?.id, made.ear != nil, n.cast < n.lines { app.push(PlayRoute.cast(episode)) } else { app.push(PlayRoute.parts(made.id)) }
        } catch {
            copyFailure = OwnText.notKept(error)
        }
    }
}
#endif
