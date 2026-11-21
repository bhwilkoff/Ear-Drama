import AppKit
import SwiftUI
import XCTest

// Student privacy (PLAYS-DESIGN §12.12): the Class section, the school's approval, the publish confirmations, the age
// question and a class row with its idle notice, drawn to PNG through ImageRenderer at iPhone width, light and dark.
// A List, a Form and a compact DatePicker cannot be drawn by ImageRenderer, so the rows are stacked in a plain card the
// way a grouped list shows them. Skipped unless GRAMMAR_RENDER_DIR is set.

nonisolated final class PrivacyRenderTests: XCTestCase {
    @MainActor private func card<V: View>(_ title: String?, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            if let title { Text(title).font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted).textCase(.uppercase) }
            VStack(alignment: .leading, spacing: Spacing.s3) { content() }
                .padding(Spacing.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.brandSurface, in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(Spacing.s4)
    }

    @MainActor private func png<V: View>(_ name: String, width: CGFloat, height: CGFloat, dark: Bool, out: URL,
                                         @ViewBuilder _ content: () -> V) throws {
        let view = content()
            .tint(Color.brandSecondary)
            .frame(width: width, height: height, alignment: .top)
            .background(Color.brandBackground)
            .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage, "\(name) did not render")
        let data = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try data.write(to: out.appending(path: "\(name)-\(Int(width))\(dark ? "-dark" : "").png"))
    }

    @MainActor func testPrivacyFrames() throws {
        guard let path = ProcessInfo.processInfo.environment["GRAMMAR_RENDER_DIR"], !path.isEmpty else {
            throw XCTSkip("GRAMMAR_RENDER_DIR is not set")
        }
        let out = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        for dark in [false, true] {
            try png("apple-class-section", width: 390, height: 300, dark: dark, out: out) {
                card("Class") {
                    ClassSectionRows(name: "Period 3 English", endsOn: "2027-06-04", failure: ReadCore.refusal("end_date_past"),
                                     change: { _ in }, export: {}, delete: {})
                }
            }
            try png("apple-school-approval", width: 390, height: 300, dark: dark, out: out) {
                card("School approval") {
                    SchoolApprovalRows(failure: ReadCore.refusal("reference_required"), record: { _ in })
                }
            }
            try png("apple-publish-confirmations", width: 390, height: 380, dark: dark, out: out) {
                card(nil) {
                    PublishFormFields(credit: .constant("Ms. Rivera"), performers: .constant(true), release: .constant(false),
                                      agreed: .constant(false), terms: "Publishing puts your recording in the public domain.",
                                      canPublish: false, refusal: ReadCore.refusal("confirmations_required"), publish: {})
                }
            }
            try png("apple-age-question", width: 390, height: 260, dark: dark, out: out) {
                card(nil) {
                    Text("What year were you born?").font(TypeRamp.bodyStrong)
                    HStack {
                        Text("Year").font(TypeRamp.body)
                        Spacer()
                        Text("Select").font(TypeRamp.body).foregroundStyle(Color.brandTextMuted)
                        Image(systemName: "chevron.up.chevron.down").foregroundStyle(Color.brandTextMuted)
                    }
                    HStack {
                        Button("Cancel") {}
                        Spacer()
                        Button("Continue") {}.disabled(true)
                    }
                }
            }
            try png("apple-class-list-row", width: 390, height: 190, dark: dark, out: out) {
                card("Classes") {
                    ClassListRow(name: "Period 3 English", code: "KLSM4567", deletesOn: "2027-03-14")
                    Divider()
                    ClassListRow(name: "Drama Club", code: "ABCD2345", waitsForSchool: true)
                }
            }
        }
    }

    func testDaysDoNotShiftWithTheTimeZone() throws {
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        var la = tokyo
        la.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        for cal in [tokyo, la] {
            let d = try XCTUnwrap(ClassDay.date("2027-06-04", calendar: cal))
            XCTAssertEqual(ClassDay.string(d, calendar: cal), "2027-06-04")
        }
        XCTAssertNil(ClassDay.date("soon"))
        XCTAssertEqual(ClassExportFile.filename("Period 3: English/Drama"), "Period 3 EnglishDrama export")
        XCTAssertEqual(ClassExportFile.filename("  "), "Class export")
    }
}
