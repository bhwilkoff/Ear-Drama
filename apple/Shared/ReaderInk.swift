#if os(iOS) || os(macOS)
import PencilKit
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

// Pencil ink in the script reader (PLAYS-DESIGN §2.10 rule 1, iOS-DESIGN §4.15 "Marks"; Decision 076 S5). The rules
// are InkCore.swift's: ink belongs to a line block and moves with its line. On an iPad, Ink mode lays a PKCanvasView
// over each page (the Pencil draws, a finger still turns pages); everywhere else, and with Ink off, the page draws
// the ink read-only from an image of the same strokes. Show Marks hides the ink with the marks, and Hide My Lines
// hides a hidden line's ink.

final class InkImageBox {
    let image: CGImage?
    init(_ image: CGImage?) { self.image = image }
}

enum InkRender {
    /// A drawing as an image (transparent where nothing is drawn), ink colors adapted for the appearance.
    static func image(_ drawing: PKDrawing, rect: CGRect, scale: CGFloat, dark: Bool) -> CGImage? {
        guard rect.width > 0, rect.height > 0 else { return nil }
        var out: CGImage?
        #if os(iOS)
        UITraitCollection(userInterfaceStyle: dark ? .dark : .light).performAsCurrent {
            out = drawing.image(from: rect, scale: scale).cgImage
        }
        #else
        NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            out = drawing.image(from: rect, scale: scale).cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        #endif
        return out
    }

    /// A line's ink for the notebook: the strokes alone, cropped.
    static func thumbnail(_ ink: LineInk, dark: Bool) -> CGImage? {
        guard let d = try? PKDrawing(data: ink.data), !d.bounds.isEmpty else { return nil }
        return image(d, rect: d.bounds.insetBy(dx: -4, dy: -4), scale: 2, dark: dark)
    }
}

extension ReaderModel {
    /// Ink mode is the iPad's: the Pencil draws there. Capability, not layout, so the idiom and not a size class.
    static var canDrawInk: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad
        #else
        false
        #endif
    }

    /// Ink shows with the marks, on Pages, and not on a line Hide My Lines covers.
    private func inkShows(_ line: Int) -> Bool { showMarks && !isHidden(line) }

    /// The blocks of a page whose ink shows.
    func inkBlocks(_ layout: ReaderLayout, page: Int) -> [InkBlock] {
        layout.inkBlocks(page: page).filter { inkShows($0.line) }
    }

    func inkPage(_ layout: ReaderLayout, page: Int) -> InkPage {
        InkCompose.page(inks: inks, blocks: inkBlocks(layout, page: page), ids: script.lines.map(\.id), textWidth: layout.textSize.width)
    }

    /// The page's ink as an image the size of the page's view, for the read-only drawing; nil when it has none.
    func inkImage(_ layout: ReaderLayout, page: Int, dark: Bool, scale: CGFloat) -> CGImage? {
        guard !inks.isEmpty, showMarks, !inkMode else { return nil }
        let key = "\(ObjectIdentifier(layout).hashValue)|\(page)|\(dark)|\(scale)|\(inkVersion)|\(hide)|\(peeked.sorted())|\(part?.roleName ?? "")"
        if let hit = inkImages[key] { return hit.image }
        let composed = inkPage(layout, page: page)
        var out: CGImage?
        if !composed.drawing.strokes.isEmpty {
            let rect = CGRect(x: 0, y: 0, width: layout.pageSize.width, height: layout.pageSize.height + ReaderLayout.headRoom + pageFoot)
            out = InkRender.image(composed.drawing, rect: rect, scale: scale, dark: dark)
        }
        if inkImages.count > 24 { inkImages.removeAll() }
        inkImages[key] = InkImageBox(out)
        return out
    }

    func persistInks() {
        do {
            try inkStore.save(scriptID: script.id, title: script.title, inkOrder + lostInks)
            markNotice = nil
        } catch {
            markNotice = "Ink could not be saved."
        }
    }

    /// Placed ink in script order.
    var inkOrder: [LineInk] {
        inks.values.sorted { (structure.indexByID[$0.line] ?? .max, $0.line) < (structure.indexByID[$1.line] ?? .max, $1.line) }
    }

    /// An edit the canvas made, already drawn there: kept, saved and counted, without redrawing that canvas.
    func applyInk(_ new: [String: LineInk], changed: Set<String>, layout: ReaderLayout) {
        inks = new
        inkVersion += 1
        persistInks()
        let ids = script.lines.map(\.id)
        let multiPage = changed.contains { id in
            guard let i = ids.firstIndex(of: id), i < layout.starts.count else { return false }
            return layout.starts[i] != layout.ends[i]
        }
        if multiPage { inkEpoch += 1 }
    }

    /// DEBUG door: ink on three lines from `index`, in block units (an underline wave, a margin loop, a bracket).
    func seedDemoInk(from index: Int) {
        func pt(_ x: CGFloat, _ y: CGFloat, _ i: Int) -> PKStrokePoint {
            PKStrokePoint(location: CGPoint(x: x, y: y), timeOffset: Double(i) * 0.01, size: CGSize(width: 3, height: 3), opacity: 1,
                          force: 1, azimuth: 0, altitude: .pi / 2)
        }
        var wave: [(CGFloat, CGFloat)] = []
        for n in 0...24 {
            let t = CGFloat(n)
            wave.append((30 + t * 9, 24 + 4 * sin(t * 0.9)))
        }
        var loop: [(CGFloat, CGFloat)] = []
        for n in 0...20 {
            let t = CGFloat(n) * 0.32
            loop.append((-4 + 16 * cos(t), 14 + 14 * sin(t)))
        }
        let bracket: [(CGFloat, CGFloat)] = [(300, 2), (312, 2), (312, 40), (300, 40)]
        let shapes: [[(CGFloat, CGFloat)]] = [wave, loop, bracket]
        for (k, pts) in shapes.enumerated() {
            let i = index + k
            guard i < script.lines.count else { break }
            let line = script.lines[i]
            let text = InkCore.lineText(line)
            let cps = pts.enumerated().map { pt($0.element.0, $0.element.1, $0.offset) }
            #if os(iOS)
            let color = UIColor.black
            #else
            let color = NSColor.black
            #endif
            let stroke = PKStroke(ink: PKInk(.pen, color: color), path: PKStrokePath(controlPoints: cps, creationDate: Date()), transform: .identity, mask: nil)
            inks[line.id] = LineInk(line: line.id, hash: InkCore.hash(text), text: InkCore.preview(text), width: 600,
                                    data: PKDrawing(strokes: [stroke]).dataRepresentation(), strokes: 1,
                                    revision: MarksCore.rev(script), updated: MarksCore.nowMillis())
        }
        inkVersion += 1
        persistInks()
    }

    func deleteLostInk(_ id: String) {
        lostInks.removeAll { $0.id == id }
        persistInks()
    }

    func deleteInk(_ line: String) {
        inks[line] = nil
        inkVersion += 1
        inkEpoch += 1
        persistInks()
    }
}

#if os(iOS)
/// The system's tool picker with a small set: pen, pencil, marker, and the eraser that takes a whole stroke.
final class InkTools {
    let picker: PKToolPicker

    init() {
        picker = PKToolPicker(toolItems: [
            PKToolPickerInkingItem(type: .pen, color: .black),
            PKToolPickerInkingItem(type: .pencil, color: .darkGray),
            PKToolPickerInkingItem(type: .marker, color: UIColor(Color.mark("yellow"))),
            PKToolPickerEraserItem(type: .vector),
        ])
        picker.showsDrawingPolicyControls = false
    }
}

/// Ink mode's layer over one page: a canvas the size of the page's view, holding the page's ink in the page's
/// coordinates. A stroke the Pencil adds is handed to the line it starts in (InkCompose.commit).
struct InkOverlay: View {
    let model: ReaderModel
    let layout: ReaderLayout
    let page: Int

    var body: some View {
        if model.inkMode, ReaderModel.canDrawInk {
            InkCanvasLayer(model: model, layout: layout, page: page, epoch: model.inkEpoch, hide: model.hide, peeked: model.peeked)
                .accessibilityIdentifier("ink-canvas")
        }
    }
}

struct InkCanvasLayer: UIViewRepresentable {
    let model: ReaderModel
    let layout: ReaderLayout
    let page: Int
    /// Read so the canvas is put back from the stored ink when these change.
    let epoch: Int
    let hide: Bool
    let peeked: Set<Int>

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isScrollEnabled = false
        canvas.drawingPolicy = model.inkFinger ? .anyInput : .pencilOnly
        canvas.tool = PKInkingTool(.pen, color: .black, width: 4)
        canvas.delegate = context.coordinator
        let picker = model.inkTools.picker
        picker.addObserver(canvas)
        picker.setVisible(true, forFirstResponder: canvas)
        DispatchQueue.main.async { canvas.becomeFirstResponder() }
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.sync(canvas)
    }

    static func dismantleUIView(_ canvas: PKCanvasView, coordinator: Coordinator) {
        let picker = coordinator.parent?.model.inkTools.picker
        picker?.setVisible(false, forFirstResponder: canvas)
        picker?.removeObserver(canvas)
        canvas.resignFirstResponder()
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: InkCanvasLayer?
        private var previous: (strokes: [PKStroke], owners: [String]) = ([], [])
        private var token = ""
        private var applying = false

        func sync(_ canvas: PKCanvasView) {
            guard let p = parent else { return }
            let now = "\(ObjectIdentifier(p.layout).hashValue)|\(p.epoch)|\(p.hide)|\(p.peeked.sorted())"
            guard now != token else { return }
            token = now
            let composed = p.model.inkPage(p.layout, page: p.page)
            applying = true
            canvas.drawing = composed.drawing
            applying = false
            previous = (canvas.drawing.strokes, composed.owners)
        }

        func canvasViewDrawingDidChange(_ canvas: PKCanvasView) {
            guard !applying, let p = parent else { return }
            let r = InkCompose.commit(canvas: canvas.drawing, previous: previous, blocks: p.model.inkBlocks(p.layout, page: p.page),
                                      script: p.model.script, textWidth: p.layout.textSize.width, inks: p.model.inks,
                                      now: MarksCore.nowMillis())
            p.model.applyInk(r.inks, changed: r.changed, layout: p.layout)
            previous = (canvas.drawing.strokes, r.owners)
            if r.needsReset { token = ""; sync(canvas) }
        }
    }
}
#endif
#endif
