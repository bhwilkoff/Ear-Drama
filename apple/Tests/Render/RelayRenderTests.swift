import AppKit
import SwiftUI
import XCTest

// Relay across time (T6, PLAYS-DESIGN §12.11): a seat's parts at home, drawn to PNG through ImageRenderer so a person can look
// at them: the waiting state ("On this device · sends when Ms. Ortiz is in Ear Drama"), then Sent with the teacher's review,
// light and dark. Skipped unless GRAMMAR_RENDER_DIR is set (xcodebuild: TEST_RUNNER_GRAMMAR_RENDER_DIR=<dir>). Nothing here
// plays sound or touches the network. The screen itself sits in a List, which ImageRenderer cannot draw, so this draws the
// lines the screen is made of (`RelayLinesView`) under its headings.

nonisolated final class RelayRenderTests: XCTestCase {
    @MainActor private func say(_ id: String, _ text: String) -> ScriptLine { ScriptLine(id: id, kind: .speech, role: "LUCY", parts: [.say(text)]) }

    @MainActor private func rows(sent: Bool) -> [RelayCore.Row] {
        let lines = [say("l1", "I thought you had gone out to the garden, Tom."), say("l3", "Then sit with me, and we will read the letter together."),
                     say("l6", "It is only the wind in the chimney, nothing more."), say("l8", "Come, sit. The tea is still warm in the pot.")]
        return lines.enumerated().map { i, l in
            var r = RelayCore.Row(id: l.id, text: RelayCore.excerpt(l))
            if sent {
                if i < 3 { r.state = "Sent" }
                if i == 0 { r.review = "Approved" }
                if i == 1 { r.review = "Again \u{00B7} Slower at the end."; r.again = true }
            } else if i < 3 {
                r.state = RelayCore.wording(.waiting, name: "Ms. Ortiz", fallback: "your teacher")
            }
            return r
        }
    }

    @MainActor private func page(_ rows: [RelayCore.Row]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Lucy \u{00B7} Room 7").font(TypeRamp.caption).foregroundStyle(Color.brandTextMuted)
            Text("The Lost Lady").font(TypeRamp.bodyStrong)
            HStack {
                Text("LUCY \u{00B7} 4 lines").font(TypeRamp.bodyStrong)
                Spacer()
                Text("Record").font(TypeRamp.bodyStrong).padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Color.brandSecondary, in: RoundedRectangle(cornerRadius: 8)).foregroundStyle(.white)
            }
            RelayLinesView(rows: rows)
        }
        .padding(16)
    }

    @MainActor private func png<V: View>(_ name: String, width: CGFloat, height: CGFloat, dark: Bool, out: URL, @ViewBuilder _ content: () -> V) throws {
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

    @MainActor func testRelayStates() throws {
        guard let path = ProcessInfo.processInfo.environment["GRAMMAR_RENDER_DIR"], !path.isEmpty else {
            throw XCTSkip("GRAMMAR_RENDER_DIR is not set")
        }
        let out = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        for dark in [false, true] {
            try png("apple-relay-waiting", width: 390, height: 430, dark: dark, out: out) { page(rows(sent: false)) }
            try png("apple-relay-sent", width: 390, height: 430, dark: dark, out: out) { page(rows(sent: true)) }
        }
    }
}
