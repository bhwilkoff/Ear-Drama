import AppKit
import CoreText
import XCTest

// The Ear Drama page, drawn to PNG through the reader's own Core Text layout (the same `ReaderLayout.draw` the
// Canvas calls), so a person can look at it. Skipped unless READER_RENDER_DIR is set
// (xcodebuild: TEST_RUNNER_READER_RENDER_DIR=<dir>). READER_RENDER_CASES is "id:line:width:scheme[:mine]" separated by commas.

nonisolated final class ReaderPageRenderTests: XCTestCase {
    func testRenderPages() throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["READER_RENDER_DIR"], !dir.isEmpty else { throw XCTSkip("READER_RENDER_DIR is not set") }
        let out = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let repo = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        CTFontManagerRegisterFontsForURL(repo.appending(path: "apple/Resources/Fonts/BigShoulders-Bold.ttf") as CFURL, .process, nil)
        let library = try JSONDecoder().decode(CastableLibrary.self, from: Data(contentsOf: repo.appending(path: "catalog/plays/castable-scripts.json")))
        let cases = (env["READER_RENDER_CASES"] ?? "gut-5071:L0009:375:light").split(separator: ",").map { $0.split(separator: ":", omittingEmptySubsequences: false).map(String.init) }
        for c in cases {
            let script = try XCTUnwrap(library.scripts.first { $0.id == c[0] }, "script \(c[0])")
            let structure = ScriptStructure(script)
            let width = CGFloat(Double(c[2]) ?? 375)
            let dark = c[3] == "dark"
            let mine = c.count > 4 ? c[4...].joined(separator: ":") : nil
            let pageW = min(width - 28 - 0, 17 * 36)
            let size = CGSize(width: pageW, height: 720)
            let layout = try ReaderLayout.build(script, structure: structure, style: ReaderStyle(base: 17, scale: 1, leading: 1.55), pageSize: size)
            let index: Int
            if c[1] == "front" { index = 0 } else { index = structure.indexByID[c[1]] ?? 0 }
            let page = c[1] == "front" ? 0 : c[1].hasPrefix("p") ? (Int(c[1].dropFirst()) ?? 0) : layout.starts[index]
            let view = CGSize(width: size.width, height: size.height + ReaderLayout.headRoom)
            let scale: CGFloat = 2
            let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.width * scale), pixelsHigh: Int(view.height * scale),
                                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            let ctx = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep)).cgContext
            func rgb(_ hex: UInt32) -> CGColor {
                CGColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
            }
            let theme = ReaderLayout.Theme(
                ink: rgb(dark ? 0xF2F2F4 : 0x131316), muted: rgb(dark ? 0xC4C4CC : 0x5C5C66),
                hues: (dark ? [0x8EBBFF, 0x44D5D7, 0xC99580, 0xAA87DE, 0x7CB45A, 0xD4C27E, 0xB4B3B3] : [0x2459A5, 0x007C88, 0x864E37, 0x5A3983, 0x2F6100, 0x816B01, 0x504C3E]).map { rgb(UInt32($0)) },
                background: rgb(dark ? 0x0F0F11 : 0xFFFFFF), block: rgb(dark ? 0x232327 : 0xE8E8EB))
            ctx.setFillColor(theme.background)
            ctx.fill(CGRect(origin: .zero, size: CGSize(width: view.width * scale, height: view.height * scale)))
            ctx.scaleBy(x: scale, y: scale)
            // A Canvas context is top-left, y down; the bitmap's is bottom-left, so flip it first.
            ctx.translateBy(x: 0, y: view.height)
            ctx.scaleBy(x: 1, y: -1)
            let hiding = mine?.hasSuffix("!hide") == true
            let role = mine.flatMap { PartID(rawValue: $0.replacingOccurrences(of: "!hide", with: "")).roleName }
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            layout.draw(page: page, in: ctx, theme: theme, marks: ReaderLayout.Marks(role: role, hide: hiding))
            let name = "\(c[0])-\(c[1])-\(c[3])-\(Int(width))\(mine == nil ? "" : "-mine").png"
            try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: out.appending(path: name))
            print("rendered \(name) page \(page) of \(layout.pageCount) gutter \(layout.gutter) contd \(layout.contd.keys.sorted().prefix(6))")
        }
    }
}
