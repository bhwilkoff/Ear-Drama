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

    /// The strip's bars from the run histogram ("first year, count, count..." as `years`): one per year
    /// on the fixed axis, each bar's height its count over the busiest year (0...1); a year with no
    /// episode draws nothing; a year off the axis is held at the nearest edge. nil when the show has
    /// no histogram, and the strip falls back to the first-to-last span.
    static func runBars(years: [Int]?) -> [(from: Double, to: Double, height: Double)]? {
        guard let years, years.count >= 2 else { return nil }
        let counts = years.dropFirst()
        guard counts.contains(where: { $0 > 0 }) else { return nil }
        let n = Double(runAxis.hi - runAxis.lo + 1)
        var bySlot: [Int: Int] = [:]
        for (i, c) in counts.enumerated() where c > 0 {
            let slot = min(runAxis.hi, max(runAxis.lo, years[0] + i)) - runAxis.lo
            bySlot[slot, default: 0] += c
        }
        let top = Double(bySlot.values.max() ?? 1)
        return bySlot.keys.sorted().map { (Double($0) / n, Double($0 + 1) / n, Double(bySlot[$0] ?? 0) / top) }
    }

    /// Parses `series.year_counts` ("1932,3,12,0,4"); nil when absent or malformed.
    static func parseYearCounts(_ text: String?) -> [Int]? {
        guard let text, !text.isEmpty else { return nil }
        let parts = text.split(separator: ",").map { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count >= 2, !parts.contains(where: { $0 == nil }) else { return nil }
        return parts.compactMap { $0 }
    }

    /// An episode with neither a date nor a number: its row's leading slot shows the series' window
    /// rather than an empty date block.
    static func undatedBare(date: String?, number: Int?) -> Bool {
        let dated = date.map { $0.count >= 4 && $0.prefix(4).allSatisfy { $0.isASCII && $0.isNumber } } ?? false
        return !dated && number == nil
    }

    /// Browse's A to Z section letter: the sort key's first letter without accents, A to Z, else "#".
    static func azLetter(_ key: String) -> String {
        let c = key.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: .diacriticInsensitive, locale: nil).uppercased().first
        if let c, c >= "A", c <= "Z" { return String(c) }
        return "#"
    }

    /// The letters that have shows, "#" first (the sort puts numbers and symbols before A).
    static func azLetters(_ keys: [String]) -> [String] {
        let have = Set(keys.map(azLetter))
        return (["#"] + "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map(String.init)).filter(have.contains)
    }

    /// The grade a picture takes (uniform-imagery-design §2): monochrome, then `k * v + o`. The
    /// projection publishes `art.grade` for a picture whose range was measured; any other picture,
    /// and a catalog without the column, takes the identity.
    static func gradeOf(_ art: Artwork?) -> Artwork.Grade { art?.grade ?? .identity }

    /// The picture that leads an episode's head board (WEB-DESIGN §6.4d, the web's `API.leadPicture`):
    /// the show's own image when the series picture is of the show, else the episode's star (the
    /// credit the row names, else the first cast with a picture), else the series' picture, else nil.
    static func leadPicture(series: SeriesRow?, credits: [Credit], star: String?) -> Artwork? {
        if let picture = series?.picture, series?.pictureKind == "show" { return picture }
        let cast = credits.filter { $0.art != nil && ($0.role ?? "cast") == "cast" }
        let pick = star.flatMap { star in cast.first { $0.personID == star } } ?? cast.first
        return pick?.art ?? series?.picture
    }

    /// Who is "On the air": the cast in billing order, each person once, at most `limit`.
    static func onAirOf(_ credits: [Credit], limit: Int = 6) -> [Credit] {
        var seen = Set<String>()
        var out: [Credit] = []
        for credit in credits where (credit.role ?? "cast") == "cast" {
            let key = credit.personID.isEmpty ? credit.name : credit.personID
            if !seen.insert(key).inserted { continue }
            out.append(credit)
            if out.count >= limit { break }
        }
        return out
    }

    /// The facts of an episode's event line: its date (or Undated), network, sponsor, length,
    /// season, and its number when the title does not already say it. `date` and `length` arrive
    /// formatted.
    static func episodeFacts(date: String?, network: String?, sponsor: String?, length: String?,
                             season: String?, title: String?, number: Int?) -> [String] {
        let named = !(title ?? "").isEmpty
        let facts: [String?] = [
            (date ?? "").isEmpty ? "Undated" : date, network, sponsor, length,
            (season ?? "").isEmpty ? nil : "Season \(season ?? "")",
            named ? number.map { "No. \($0)" } : nil,
        ]
        return facts.compactMap { $0 }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

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

// Home and Browse's decisions (WEB-DESIGN §6.4c, R11c): the web's `isShow`, `dayYears`,
// `nightShows`, `decadeField` and `fieldSide`, with the same golden cases (HomeBrowseRulesTests).

nonisolated enum ShowLine {
    /// A show is a series of at least this many episodes (owner, 2026-10-29: "Having more shows is
    /// better, so 5."); the rest are single recordings, counted.
    static let showMin = 5
    static func isShow(_ episodes: Int?) -> Bool { (episodes ?? 0) >= showMin }

    /// The genre order of every stacked mark and legend; a series with no genre stacks last, in no hue.
    static let genreOrder = ["drama", "mystery", "comedy", "serial", "western", "scifi", "documentary", "news"]

    struct Year: Equatable {
        let year: Int
        var total: Int
        var genres: [String: Int]
    }

    struct Day: Equatable {
        let years: [Year]
        let peak: Int?
        let count: Int
        let genres: [String]
    }

    private static func year(_ date: String?) -> Int? {
        guard let date, date.count >= 4, date.prefix(4).allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(date.prefix(4))
    }

    /// One day's broadcasts by year, oldest first; the year with most (the earlier on a tie) is the
    /// peak. A row without a four-digit year is not on the strip; no genre stacks under "".
    static func dayYears<R>(_ rows: [R], date: (R) -> String?, genre: (R) -> String?) -> Day {
        var by: [Int: Year] = [:]
        for row in rows {
            guard let y = year(date(row)) else { continue }
            let g = genre(row) ?? ""
            var entry = by[y] ?? Year(year: y, total: 0, genres: [:])
            entry.total += 1
            entry.genres[g, default: 0] += 1
            by[y] = entry
        }
        let years = by.values.sorted { $0.year < $1.year }
        var peak: Year?
        for y in years where peak == nil || y.total > peak!.total { peak = y }
        let seen = Set(years.flatMap { $0.genres.keys })
        return Day(years: years, peak: peak?.year, count: years.reduce(0) { $0 + $1.total },
                   genres: genreOrder.filter(seen.contains))
    }

    /// One night's rows as shows: a show's first row of the night only (the same title folded once),
    /// singles counted and left out. `episodes` is the row's series' episode count, nil when unknown.
    static func nightShows<R>(_ rows: [R], title: (R) -> String?, episodes: (R) -> Int?) -> (shows: [R], singles: Int) {
        func normal(_ t: String?) -> String {
            String((t ?? "").lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) })
        }
        var seen = Set<String>(), shows: [R] = []
        var singles = 0
        for row in rows {
            guard isShow(episodes(row)) else { singles += 1; continue }
            if seen.insert(normal(title(row))).inserted { shows.append(row) }
        }
        return (shows, singles)
    }

    struct DecadeField: Equatable {
        let decades: [Int]
        let genres: [String]
        let cells: [String: Int]
        let max: Int
        let none: Int
        func count(_ genre: String, _ decade: Int) -> Int { cells["\(genre)|\(decade)"] ?? 0 }
    }

    /// Browse's decade by genre field: the shows per cell, decades in order. A show with no genre or
    /// no first year is counted in `none` and left off the field.
    static func decadeField(_ shows: [(genre: String?, first: String?)]) -> DecadeField {
        var cells: [String: Int] = [:], decades = Set<Int>()
        var none = 0
        for s in shows {
            guard let g = s.genre, !g.isEmpty, let y = year(s.first) else { none += 1; continue }
            let d = y / 10 * 10
            decades.insert(d)
            cells["\(g)|\(d)", default: 0] += 1
        }
        let ds = decades.sorted()
        let genres = genreOrder.filter { g in ds.contains { cells["\(g)|\($0)"] != nil } }
        return DecadeField(decades: ds, genres: genres, cells: cells, max: cells.values.max() ?? 0, none: none)
    }

    /// A cell's mark side: the square root of its share of the biggest cell (so area carries the
    /// count), 6 to 32 points, 0 for an empty cell.
    static func fieldSide(_ n: Int, max: Int) -> Int {
        n > 0 && max > 0 ? Swift.max(6, Int((32 * (Double(n) / Double(max)).squareRoot()).rounded())) : 0
    }
}

/// Browse's layout from the width of its column alone (R11c): the field beside the grid when the grid
/// keeps at least three columns, else stacked above it. Nothing here reads a child, so a wide child
/// can never widen the column that holds it.
nonisolated enum BrowseLayout {
    #if os(tvOS)
    static let labelWidth: CGFloat = 220, cellWidth: CGFloat = 64
    #else
    static let labelWidth: CGFloat = 96, cellWidth: CGFloat = 36
    #endif
    static let gap: CGFloat = 12
    static let sideGap: CGFloat = 24
    static let sideMinColumns = 3

    struct Plan: Equatable {
        let sideBySide: Bool
        let fieldWidth: CGFloat
        let gridWidth: CGFloat
        let columns: Int
        let tileWidth: CGFloat
    }

    static func fieldWidth(decades: Int) -> CGFloat { labelWidth + cellWidth * CGFloat(decades) }

    /// How many tiles of at least `tileMin` fit a row of `width`, one at least.
    static func columns(width: CGFloat, tileMin: CGFloat) -> Int {
        max(1, Int(((width + gap) / (tileMin + gap)).rounded(.down)))
    }

    static func tileWidth(width: CGFloat, columns: Int) -> CGFloat {
        max(1, (width - gap * CGFloat(columns - 1)) / CGFloat(columns))
    }

    static func plan(width: CGFloat, decades: Int, tileMin: CGFloat) -> Plan {
        let field = fieldWidth(decades: decades)
        let beside = decades > 0 && width - field - sideGap >= CGFloat(sideMinColumns) * tileMin + gap * CGFloat(sideMinColumns - 1)
        let grid = beside ? width - field - sideGap : width
        let cols = columns(width: grid, tileMin: tileMin)
        return Plan(sideBySide: beside, fieldWidth: field, gridWidth: grid, columns: cols,
                    tileWidth: tileWidth(width: grid, columns: cols))
    }
}
