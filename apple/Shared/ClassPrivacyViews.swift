#if os(iOS) || os(macOS)
import SwiftUI
import UniformTypeIdentifiers

// Student privacy on the class page and the sharing doors (PLAYS-DESIGN §12.12, Decision 084): the Class section (when it
// ends, Change date, Export class, Delete class), the school's approval, the two publish confirmations, and the age
// question. The rows are plain children so a List section shows each as a row and a render can stack them.

// MARK: - Dates

nonisolated enum ClassDay {
    /// A `YYYY-MM-DD` day as the start of that day in the person's own calendar, so no time zone moves it.
    static func date(_ day: String, calendar: Calendar = .current) -> Date? {
        let p = day.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }

    static func string(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 1, c.day ?? 1)
    }

    static func text(_ day: String) -> String {
        date(day).map { $0.formatted(.dateTime.day().month(.wide).year()) } ?? day
    }

    /// Today through 400 days ahead.
    static func range(now: Date = .now, calendar: Calendar = .current) -> ClosedRange<Date> {
        let start = calendar.startOfDay(for: now)
        return start...(calendar.date(byAdding: .day, value: 400, to: start) ?? start)
    }
}

// MARK: - Export

struct ClassExportFile: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }

    /// `{class name} export` (the exporter adds `.json`), with characters a file name cannot hold removed.
    static func filename(_ className: String) -> String {
        let bad = CharacterSet(charactersIn: "\\/:*?\"<>|")
        let clean = className.components(separatedBy: bad).joined().trimmingCharacters(in: .whitespaces)
        return "\(clean.isEmpty ? "Class" : clean) export"
    }
}

// MARK: - The Class section

struct ClassSectionRows: View {
    let name: String
    let endsOn: String?
    var failure: String?
    var busy = false
    let change: (String) -> Void
    let export: () -> Void
    let delete: () -> Void
    @State private var pick = Date.now
    @State private var confirming = false

    var body: some View {
        if let endsOn {
            Text("Ends \(ClassDay.text(endsOn))").font(TypeRamp.body)
        }
        HStack {
            DatePicker("End date", selection: $pick, in: ClassDay.range(), displayedComponents: .date).labelsHidden()
            Spacer()
            Button("Change date") { change(ClassDay.string(pick)) }
                .disabled(busy || ClassDay.string(pick) == endsOn)
        }
        .onAppear { if let endsOn, let d = ClassDay.date(endsOn) { pick = max(d, ClassDay.range().lowerBound) } }
        Button("Export class", action: export).disabled(busy)
        Button("Delete class", role: .destructive) { confirming = true }
            .disabled(busy)
            .confirmationDialog("Delete \(name)?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Delete class", role: .destructive, action: delete)
            } message: {
                Text("Its names, casting and notes are deleted. Published plays stay.")
            }
        if let failure { Label(failure, systemImage: "exclamationmark.triangle").foregroundStyle(Color.semanticError) }
    }
}

// MARK: - School approval

struct SchoolApprovalRows: View {
    var failure: String?
    var busy = false
    let record: (String) -> Void
    @State private var approved = false
    @State private var reference = ""

    var body: some View {
        Toggle("My school or district approved Ear Drama for this class.", isOn: $approved)
        TextField("Approved by", text: $reference, prompt: Text("School or district, and the approval"))
            .onChange(of: reference) { _, v in if v.count > 120 { reference = String(v.prefix(120)) } }
        Button("Record") {
            record(approved ? reference.trimmingCharacters(in: .whitespacesAndNewlines) : "")
        }
        .disabled(busy)
        if let failure { Label(failure, systemImage: "exclamationmark.triangle").foregroundStyle(Color.semanticError) }
    }
}

// MARK: - A class in the teacher's list

struct ClassListRow: View {
    let name: String
    let code: String?
    var waitsForSchool = false
    var deletesOn: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            Text(verbatim: name).font(TypeRamp.body)
            if let code {
                Text(verbatim: SharedPlays.grouped(code)).font(TypeRamp.tabular)
            }
            if waitsForSchool {
                Text("Waits for the school\u{2019}s consent").font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
            }
            if let deletesOn {
                Text("Deleted \(ClassDay.text(deletesOn)) unless opened").font(TypeRamp.caption).foregroundStyle(Color.semanticWarning)
            }
        }
    }
}

// MARK: - The publish confirmations

/// Publish under my name for a 13-and-over class: the credit, the two confirmations, then the teacher's own CC0 consent.
struct PublishFormFields: View {
    @Binding var credit: String
    @Binding var performers: Bool
    @Binding var release: Bool
    @Binding var agreed: Bool
    let terms: String?
    var canPublish = true
    var refusal: String?
    var result: String?
    let publish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            TextField("Credit name", text: $credit).textFieldStyle(.roundedBorder)
            Toggle("Every performer agreed to publish.", isOn: $performers)
            Toggle("The school has a media release for each performer under 18.", isOn: $release)
            if let terms {
                Text(verbatim: terms).font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
                Toggle("I agree", isOn: $agreed)
            }
            Button("Publish Under My Name", action: publish)
                .buttonStyle(.borderedProminent)
                .disabled(!canPublish)
            if let refusal { Label(refusal, systemImage: "exclamationmark.triangle").font(TypeRamp.caption).foregroundStyle(Color.semanticError) }
            else if let result { Text(verbatim: result).font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted) }
        }
    }
}

// MARK: - The age question

/// Asks once per device, before a first Share, Invite, Take Part or Publish outside a class. Only "under 13 or not" is kept.
@MainActor @Observable
final class AgeQuestion {
    var asking = false
    var refused = false
    fileprivate var then: (() -> Void)?

    func ask(_ proceed: @escaping () -> Void) {
        switch AgeGate.stored() {
        case true: proceed()
        case false: refused = true
        case nil:
            then = proceed
            asking = true
        }
    }

    func answer(birthYear: Int, year: Int = Calendar.current.component(.year, from: .now)) {
        let over = !AgeGate.isUnder13(birthYear: birthYear, year: year)
        AgeGate.keep(over13: over)
        asking = false
        let go = then
        then = nil
        if over { go?() } else { refused = true }
    }

    func cancel() {
        asking = false
        then = nil
    }
}

struct AgeQuestionSheet: View {
    let years: [Int]
    let cont: (Int) -> Void
    let cancel: () -> Void
    @State private var year: Int?

    var body: some View {
        NavigationStack {
            Form {
                Picker("Year", selection: $year) {
                    Text("Year").tag(Int?.none)
                    ForEach(years, id: \.self) { Text(verbatim: String($0)).tag(Int?.some($0)) }
                }
            }
            .navigationTitle("What year were you born?")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: cancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue") { if let year { cont(year) } }.disabled(year == nil)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 340, minHeight: 180)
        #endif
    }
}

extension View {
    func ageQuestion(_ q: AgeQuestion) -> some View { modifier(AgeQuestionModifier(q: q)) }
}

private struct AgeQuestionModifier: ViewModifier {
    @Bindable var q: AgeQuestion

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $q.asking) {
                AgeQuestionSheet(years: AgeGate.years(now: Calendar.current.component(.year, from: .now)),
                                 cont: { q.answer(birthYear: $0) }, cancel: { q.cancel() })
                    #if os(iOS)
                    .presentationDetents([.medium])
                    #endif
            }
            .alert("Sharing is for 13 and over. Your teacher can add you to a class.", isPresented: $q.refused) {
                Button("OK", role: .cancel) {}
            }
    }
}
#endif
