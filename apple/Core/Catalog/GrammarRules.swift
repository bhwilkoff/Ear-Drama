import CoreGraphics
import CoreImage
import Foundation

// The grammar's decisions (WEB-DESIGN §6.4b, catalog-experience-design rule 11), as pure
// functions: the web's `API.monogram`, `blockSize`, `nameStep`, `windowFill`, `eventParts`,
// `runSpan` and `gradeOf` with the same golden cases (CatalogQueryTests).

nonisolated enum Grammar {
    private static let monogramStops: Set<String> = [
        "the", "a", "an", "of", "and", "&", "in", "on", "to", "for", "el", "la", "le", "de", "der", "die",
    ]

    /// The title block's monogram: the initials of the first two words that start with a letter
    /// (articles and short joining words skipped), else the first letter or number.
    static func monogram(_ name: String?) -> String {
        let name = name ?? ""
        let separators: Set<Character> = [" ", "\t", "\n", "\r", "-", "\u{2013}", "/"]
        let words = name.split(whereSeparator: { separators.contains($0) }).compactMap { word -> Substring? in
            let rest = word.drop { !$0.isLetter && !$0.isNumber }
            return rest.isEmpty ? nil : rest
        }
        let lettered = words.filter { ($0.first?.isLetter ?? false) && !monogramStops.contains($0.lowercased()) }
        let initials = lettered.prefix(2).compactMap { $0.first.map { String($0).uppercased() } }.joined()
        if !initials.isEmpty { return initials }
        return name.first { $0.isLetter || $0.isNumber }.map { String($0).uppercased() } ?? ""
    }

    /// The monogram's size in hundredths of the window, so it stands inside it: Big Shoulders
    /// capitals are at most 0.50 em wide, M 0.76, W 0.78, J 0.45, I and 1 0.27 (the bundled Bold, the widest cut we ship, measured 2026-10-30); at most 104.
    static func blockSize(_ monogram: String) -> Int {
        let w = monogram.reduce(0.0) { sum, c in
            sum + (c == "M" ? 0.76 : c == "W" ? 0.78 : c == "J" ? 0.45 : "I1".contains(c) ? 0.27 : 0.5) + 0.02
        }
        return w > 0 ? min(104, Int((86 / w).rounded(.down))) : 104
    }

    /// A name's type step: 0 as set, 1 one level down (a word past 10 letters), 2 two (past 14).
    static func nameStep(_ name: String?) -> Int {
        let separators: Set<Character> = [" ", "\t", "\n", "\r", "-", "\u{2013}"]
        let longest = (name ?? "").split(whereSeparator: { separators.contains($0) })
            .map { $0.unicodeScalars.count }.max() ?? 0
        return longest > 14 ? 2 : longest > 10 ? 1 : 0
    }

    enum WindowFill: Equatable {
        case crop(Artwork.CropRect), whole, block
    }

    /// What a window of `slot` points holds: the crop around the face, the picture whole for a wide
    /// one with no face, or the title block for no picture or one under the size floor
    /// (uniform-imagery-design §4: the crop's pixel height at least the slot; a whole picture's
    /// short side at least half of it). An unknown size is a block.
    static func windowFill(_ art: Artwork?, slot: Double) -> WindowFill {
        guard let art, let w = art.width, let h = art.height, w > 0, h > 0 else { return .block }
        guard let rect = art.cropRect() else { return Double(min(w, h)) >= slot / 2 ? .whole : .block }
        return rect.h * Double(h) >= slot ? .crop(rect) : .block
    }

    /// An event line's pieces: each fact with the separator kept at its end, so a line may end on a
    /// dot and never opens with one. Empty facts drop out.
    static func eventParts(_ facts: [String?]) -> [String] {
        let kept = facts.compactMap { $0 }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return kept.enumerated().map { i, fact in i < kept.count - 1 ? "\(fact) \u{00B7}" : fact }
    }

    /// The run strip's fixed axis: every show's strip is the same object.
    static let runAxis = (lo: 1930, hi: 1962)

    /// The strip's bar as fractions of the axis, from the first to the last broadcast year; nil
    /// when undated (the baseline alone).
    static func runSpan(first: String?, last: String?) -> (from: Double, to: Double)? {
        func year(_ d: String?) -> Int? {
            guard let d, d.count >= 4, d.prefix(4).allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            return Int(d.prefix(4))
        }
        guard let a = year(first) else { return nil }
        let b = year(last) ?? a
        let n = Double(runAxis.hi - runAxis.lo + 1)
        func clamped(_ v: Int) -> Double { Double(min(runAxis.hi, max(runAxis.lo, v))) }
        return ((clamped(a) - Double(runAxis.lo)) / n, (clamped(max(a, b)) - Double(runAxis.lo) + 1) / n)
    }

    /// The grade a picture takes (uniform-imagery-design §2): monochrome, then `k * v + o`. The
    /// projection does not publish `art.grade` yet, so an `Artwork` carries none and this is the
    /// documented identity default.
    static func gradeOf(_ art: Artwork?) -> Artwork.Grade { art?.grade ?? .identity }

    /// The date block's two lines: the month and year over the day; an undated numbered episode
    /// says "No." over its number.
    static func dateBlock(date: String?, number: Int?) -> (small: String, big: String) {
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let d = date ?? ""
        let y = String(d.prefix(4))
        let mo = d.count >= 7 ? Int(d.dropFirst(5).prefix(2)) ?? 0 : 0
        let day = d.count >= 10 ? Int(d.dropFirst(8).prefix(2)) ?? 0 : 0
        let month = (1...12).contains(mo) ? months[mo - 1] : nil
        if day > 0, let month { return ("\(month) \(y)", String(day)) }
        if let month { return (y, month) }
        if !y.isEmpty { return ("", y) }
        if let number { return ("No.", String(number)) }
        return ("", "")
    }
}

/// The grade, applied when a picture is decoded (uniform-imagery-design §2): neutral monochrome
/// (`CIColorControls` saturation 0) then the linear levels `k * v + o` (`CIColorMatrix`) on the
/// encoded sRGB values, so it reads as the web's `feColorMatrix` then `feComponentTransfer` with
/// `color-interpolation-filters: sRGB`.
nonisolated enum PictureGrade {
    private final class Box: @unchecked Sendable {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    /// No color management inside the filters: the matrix sees the encoded values.
    private static let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
    nonisolated(unsafe) private static let cache: NSCache<NSString, Box> = {
        let c = NSCache<NSString, Box>()
        c.countLimit = 200
        return c
    }()

    static func apply(_ image: CGImage, grade: Artwork.Grade) -> CGImage {
        let input = CIImage(cgImage: image)
        let mono = input.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
        let k = CGFloat(grade.k), o = CGFloat(grade.o)
        let leveled = mono.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: k, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: k, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: k, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: o, y: o, z: o, w: 0),
        ])
        return context.createCGImage(leveled, from: input.extent) ?? image
    }

    static func cached(_ url: URL, _ grade: Artwork.Grade) -> CGImage? {
        cache.object(forKey: key(url, grade))?.image
    }

    /// The decoded, graded picture at `url`, or nil when it cannot be fetched or decoded.
    static func load(_ url: URL, grade: Artwork.Grade) async -> CGImage? {
        if let hit = cached(url, grade) { return hit }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let graded = apply(decoded, grade: grade)
        cache.setObject(Box(graded), forKey: key(url, grade))
        return graded
    }

    private static func key(_ url: URL, _ grade: Artwork.Grade) -> NSString {
        "\(url.absoluteString)|\(grade.k)|\(grade.o)" as NSString
    }
}
