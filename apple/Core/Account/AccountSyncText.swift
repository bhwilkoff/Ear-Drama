import Foundation

/// "Synced 4:04 PM" is only the time, so it names the day when it was not today (the system formatter, never a made-up form).
enum AccountSyncText {
    static func line(_ last: Date, now: Date = .now, calendar: Calendar = .current, locale: Locale = .current) -> String {
        var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        if calendar.isDate(last, inSameDayAs: now) {
            style = style.hour().minute()
        } else if calendar.isDate(last, equalTo: now, toGranularity: .year) {
            style = style.month(.abbreviated).day().hour().minute()
        } else {
            style = style.year().month(.abbreviated).day().hour().minute()
        }
        return "Synced " + last.formatted(style)
    }
}
