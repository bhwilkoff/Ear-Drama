import Foundation

/// The air date a search names, the same rule on every platform
/// (catalog/tests/golden/search_text.json; web `API.dateQuery`): "1954",
/// "August 1954", "Aug 2, 1954", "2 August 1954", "1954-08", "1954-08-02", or
/// "8/2/1954". `prefix` is YYYY, YYYY-MM, or YYYY-MM-DD, matched against
/// `air_date`; `rest` is the query's other words, which narrow it by title,
/// series, and people.
nonisolated struct DateQuery: Hashable, Sendable {
    let prefix: String
    let rest: String

    static let months = ["January", "February", "March", "April", "May", "June", "July", "August",
                         "September", "October", "November", "December"]

    static func parse(_ query: String) -> DateQuery? {
        let t = query.lowercased().split { $0.isWhitespace || $0 == "," }.map(String.init)
        func at(_ i: Int) -> String? { i < t.count ? t[i] : nil }
        for i in t.indices {
            var y: String?, m = 0, d = 0, used = 1
            let tok = t[i]
            if let iso = iso(tok) {
                guard iso.day == nil || isDay(iso.day) else { continue }
                y = iso.year; m = Int(iso.month) ?? 0; d = iso.day.flatMap { Int($0) } ?? 0
            } else if let us = slashed(tok), isDay(us.day) {
                y = us.year; m = Int(us.month) ?? 0; d = Int(us.day) ?? 0
            } else if month(tok) > 0, isDay(at(i + 1)), isYear(at(i + 2)) {
                m = month(tok); d = Int(t[i + 1]) ?? 0; y = t[i + 2]; used = 3
            } else if month(tok) > 0, isYear(at(i + 1)) {
                m = month(tok); y = t[i + 1]; used = 2
            } else if isDay(tok), month(at(i + 1) ?? "") > 0, isYear(at(i + 2)) {
                d = Int(tok) ?? 0; m = month(t[i + 1]); y = t[i + 2]; used = 3
            } else if isYear(tok) {
                y = tok
            }
            guard let year = y, isYear(year), (0...12).contains(m), d == 0 || m > 0 else { continue }
            var prefix = year
            if m > 0 { prefix += String(format: "-%02d", m) }
            if d > 0 { prefix += String(format: "-%02d", d) }
            let rest = (Array(t[..<i]) + Array(t[(i + used)...])).joined(separator: " ")
            return DateQuery(prefix: prefix, rest: rest)
        }
        return nil
    }

    /// The prefix as a person reads it: "1954", "August 1954", "August 2, 1954".
    static func label(_ prefix: String) -> String {
        let parts = prefix.split(separator: "-").map(String.init)
        guard parts.count > 1, let m = Int(parts[1]), (1...12).contains(m) else { return parts.first ?? prefix }
        let name = months[m - 1]
        if parts.count > 2, let d = Int(parts[2]) { return "\(name) \(d), \(parts[0])" }
        return "\(name) \(parts[0])"
    }

    private static func isYear(_ s: String?) -> Bool {
        guard let s, s.count == 4, s.allSatisfy(\.isASCIIDigit), let n = Int(s) else { return false }
        return (1900...2099).contains(n)
    }

    private static func isDay(_ s: String?) -> Bool {
        guard let s, (1...2).contains(s.count), s.allSatisfy(\.isASCIIDigit), let n = Int(s) else { return false }
        return (1...31).contains(n)
    }

    private static func month(_ token: String) -> Int {
        let s = token.hasSuffix(".") ? String(token.dropLast()) : token
        if s == "sept" { return 9 }
        for (i, m) in months.enumerated() {
            let low = m.lowercased()
            if low == s || (s.count == 3 && low.hasPrefix(s)) { return i + 1 }
        }
        return 0
    }

    /// `1954-08` or `1954-08-02` (one- or two-digit month and day).
    private static func iso(_ s: String) -> (year: String, month: String, day: String?)? {
        let p = s.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard (2...3).contains(p.count), p[0].count == 4, p[0].allSatisfy(\.isASCIIDigit),
              p.dropFirst().allSatisfy({ (1...2).contains($0.count) && $0.allSatisfy(\.isASCIIDigit) })
        else { return nil }
        return (p[0], p[1], p.count == 3 ? p[2] : nil)
    }

    /// `8/2/1954`: month, day, year.
    private static func slashed(_ s: String) -> (year: String, month: String, day: String)? {
        let p = s.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard p.count == 3, (1...2).contains(p[0].count), (1...2).contains(p[1].count), p[2].count == 4,
              p.allSatisfy({ $0.allSatisfy(\.isASCIIDigit) }) else { return nil }
        return (p[2], p[0], p[1])
    }
}

nonisolated private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
