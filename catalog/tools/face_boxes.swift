// Face boxes for portrait files, with Apple Vision, on this Mac (contract section 3.3a).
//
//     swiftc -O -o /tmp/face_boxes catalog/tools/face_boxes.swift
//     /tmp/face_boxes a.jpg b.jpg ...     # one JSON line per file on stdout
//
// Run by harvest_people_wikidata.py --phase faces, never by a client: a face box is a fact
// about the file, computed once and published (artwork-presentation-design rule 5). The
// request revision is pinned so a rerun on a later macOS reads the same way. Each line is
// {"path": ..., "faces": [[x, y, w, h, confidence], ...]} with x, y, w, h normalized to the
// image and the origin at its TOP left (Vision's is bottom left), or {"path": ..., "error": ...}.
import Foundation
import ImageIO
import Vision

let revision = VNDetectFaceRectanglesRequestRevision3

func boxes(_ path: String) -> [String: Any] {
    let url = URL(fileURLWithPath: path)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        return ["path": path, "error": "unreadable"]
    }
    let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    let raw = (props?[kCGImagePropertyOrientation] as? UInt32) ?? 1
    let orientation = CGImagePropertyOrientation(rawValue: raw) ?? .up
    let request = VNDetectFaceRectanglesRequest()
    request.revision = revision
    let handler = VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
    do {
        try handler.perform([request])
    } catch {
        return ["path": path, "error": String(describing: error)]
    }
    let faces = (request.results ?? []).map { f -> [Double] in
        let b = f.boundingBox
        return [b.minX, 1 - b.maxY, b.width, b.height, Double(f.confidence)]
            .map { ($0 * 10_000).rounded() / 10_000 }
    }
    return ["path": path, "faces": faces]
}

for path in CommandLine.arguments.dropFirst() {
    let line = boxes(path)
    if let data = try? JSONSerialization.data(withJSONObject: line, options: [.sortedKeys]),
       let text = String(data: data, encoding: .utf8) {
        print(text)
    }
}
