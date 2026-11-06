import Foundation

/// RSS `pubDate` as `aq.super-h.fr` writes it: `Sun, 11 Oct 2026 10:31:57 +0200` (capture `T01`).
///
/// Legacy used `DateFormatter("E, d MMM yy HH:mm:ss Z")` in `en_US_POSIX` and fell back to *now* on failure
/// (`AQPlusView.swift:119-123, 191-196`); here an unreadable date is nil.
enum RFC822Date {
    private static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

    /// The instant of a date with a four-digit year and a `±hhmm` offset (or `GMT`); nil for any other shape or an impossible date.
    static func date(from text: String) -> Date? {
        guard let match = text.trimmingCharacters(in: .whitespacesAndNewlines).wholeMatch(of: pattern) else { return nil }
        let fields = match.output
        guard
            let day = Int(fields.1), let year = Int(fields.3),
            let month = months.firstIndex(of: fields.2.lowercased()).map({ $0 + 1 }),
            let hour = Int(fields.4), let minute = Int(fields.5), let second = Int(fields.6),
            let offset = offsetSeconds(fields.7), hour < 24, minute < 60, second < 61
        else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        guard let wallClock = calendar.date(from: components),
              calendar.dateComponents([.year, .month, .day], from: wallClock) == DateComponents(year: year, month: month, day: day)
        else { return nil }
        return wallClock.addingTimeInterval(-TimeInterval(offset))
    }

    // MARK: - Implementation

    /// Weekday (ignored, like a lenient formatter), day, month, year, time, zone.
    nonisolated(unsafe) private static let pattern =
        /(?:[A-Za-z]{3},\s*)?([0-9]{1,2})\s+([A-Za-z]{3})\s+([0-9]{4})\s+([0-9]{2}):([0-9]{2}):([0-9]{2})\s+([+-][0-9]{4}|GMT)/

    private static func offsetSeconds(_ zone: Substring) -> Int? {
        if zone == "GMT" { return 0 }
        guard let sign = zone.first, let hours = Int(zone.dropFirst().prefix(2)), let minutes = Int(zone.suffix(2)), minutes < 60 else {
            return nil
        }
        return (sign == "-" ? -1 : 1) * (hours * 3600 + minutes * 60)
    }
}
