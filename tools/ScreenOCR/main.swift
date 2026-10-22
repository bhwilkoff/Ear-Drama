// Screen OCR for the external-observation harnesses: what text is ACTUALLY on the
// glass? Reads screenshots (devicectl / adb / window captures) and emits one JSON
// line per file:
//
//   file           the basename
//   captionRegion  text in the bottom 30% of the frame, top-to-bottom
//   allText        every line: {text, x, y, w, h} — normalized, origin BOTTOM-left
//                  (Vision's convention; flip y for a top-left caller)
//   centerLuma     {mean, stddev} of the centre 50% of the frame, 0-255 — a loaded
//                  photo/video region has texture; a placeholder or blank does not
//
// Build: swiftc -O tools/ScreenOCR/main.swift -o build/bin/screenocr
//        (tools/devharness.py builds it on first use; one path for every runner)
// Run:   build/bin/screenocr shot1.png shot2.png ...

import Foundation
import Vision
import AppKit

// `w` lets a caller judge CLIPPING: a line whose box runs to the frame edge is
// text the layout could not fit, which no self-report ever reveals.
struct Line: Codable { let text: String; let x: Double; let y: Double; let h: Double; let w: Double }
struct Luma: Codable { let mean: Double; let stddev: Double }
struct Result: Codable {
    let file: String
    let captionRegion: [String]
    let allText: [Line]
    let centerLuma: Luma?
}

/// Mean and standard deviation of luminance over the centre half of the frame,
/// sampled on a small grid (the answer is about texture, not detail). An assertion
/// that reads a field the OCR never emitted reads 0 on every frame and fails a
/// correct screen — this field exists so "the image region loaded" can be graded.
func centerLuma(_ cg: CGImage) -> Luma? {
    let sw = 96, sh = 54
    let cropRect = CGRect(x: cg.width / 4, y: cg.height / 4,
                          width: max(1, cg.width / 2), height: max(1, cg.height / 2))
    guard let crop = cg.cropping(to: cropRect),
          let ctx = CGContext(data: nil, width: sw, height: sh, bitsPerComponent: 8,
                              bytesPerRow: sw, space: CGColorSpaceCreateDeviceGray(),
                              bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
    ctx.interpolationQuality = .medium
    ctx.draw(crop, in: CGRect(x: 0, y: 0, width: sw, height: sh))
    guard let data = ctx.data else { return nil }
    let px = data.bindMemory(to: UInt8.self, capacity: sw * sh)
    var sum = 0.0, sq = 0.0
    let n = Double(sw * sh)
    for i in 0..<(sw * sh) { let v = Double(px[i]); sum += v; sq += v * v }
    let mean = sum / n
    let variance = max(0, sq / n - mean * mean)
    return Luma(mean: (mean * 10).rounded() / 10, stddev: (variance.squareRoot() * 10).rounded() / 10)
}

var failed = 0
for path in CommandLine.arguments.dropFirst() {
    guard let img = NSImage(contentsOfFile: path),
          let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        FileHandle.standardError.write("cannot read \(path)\n".data(using: .utf8)!)
        failed += 1
        continue
    }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false     // report what is drawn, not a guess
    let handler = VNImageRequestHandler(cgImage: cg)
    do {
        try handler.perform([request])
    } catch {
        // Say so: an OCR that failed must not look like a frame with no text.
        FileHandle.standardError.write("OCR failed for \(path): \(error)\n".data(using: .utf8)!)
        failed += 1
        continue
    }
    var lines: [Line] = []
    for obs in request.results ?? [] {
        guard let top = obs.topCandidates(1).first else { continue }
        let b = obs.boundingBox   // normalized, origin bottom-left
        lines.append(Line(text: top.string, x: b.origin.x, y: b.origin.y,
                          h: b.height, w: b.width))
    }
    let caption = lines.filter { $0.y < 0.30 }
        .sorted { $0.y > $1.y }
        .map(\.text)
    let res = Result(file: (path as NSString).lastPathComponent,
                     captionRegion: caption, allText: lines, centerLuma: centerLuma(cg))
    let data = try! JSONEncoder().encode(res)
    print(String(data: data, encoding: .utf8)!)
}
exit(failed > 0 && failed == CommandLine.arguments.count - 1 ? 1 : 0)
