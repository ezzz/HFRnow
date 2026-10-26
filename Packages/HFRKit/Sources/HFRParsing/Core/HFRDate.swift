import Foundation

/// Dates as HFR prints them: `dd-MM-yyyy à HH:mm` (lists, `ObjCTopicListParser.m:421-424`, `Favorite.m:119-123`)
/// or `dd-MM-yyyy à HH:mm:ss` (message toolbar and edit trailer, `ParseMessagesOperation.m:398-401`),
/// always French wall-clock time in `Europe/Paris`.
public enum HFRDate {
    /// The forum's time zone; nil only when the platform has no tz database.
    public static let timeZone = TimeZone(identifier: "Europe/Paris")

    /// Parses a string that is exactly one HFR date (surrounding whitespace allowed); nil otherwise.
    public static func date(from text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = trimmed.wholeMatch(of: pattern) else { return nil }
        return date(from: match.output)
    }

    /// Returns the first HFR date found inside a longer text such as `Posté le 05-01-2026 à 14:07:33`.
    public static func firstDate(in text: String) -> Date? {
        for match in text.matches(of: pattern) where !isPrecededByDigit(match.range, in: text) {
            if let date = date(from: match.output) { return date }
        }
        return nil
    }

    // MARK: - Implementation

    // `Regex` is not `Sendable` (its output type could hold non-Sendable captures). These literals capture
    // only `Substring`s and the compiled program is initialised atomically by the runtime, so sharing is safe.
    /// `dd-MM-yyyy`, whitespace, `à`, whitespace, `HH:mm[:ss]`; digits are ASCII only, `\s` covers U+00A0.
    /// A match followed by a digit or `:` is refused (`14:07:331`, `14:07:3`), so a malformed seconds field
    /// never yields a time with the seconds dropped. Type-erased so the seven captures do not spell a large tuple.
    nonisolated(unsafe) private static let pattern = Regex<AnyRegexOutput>(
        /([0-9]{2})-([0-9]{2})-([0-9]{4})\s+à\s+([0-9]{2}):([0-9]{2})(?::([0-9]{2}))?(?![0-9:])/
    )

    /// Calendar validation (31-02, 24:00…) is delegated to a non-lenient `Date.ParseStrategy` reading
    /// the wall-clock time as if it were UTC; the Paris offset is applied afterwards by `resolve`.
    private static let wallClockStrategy: Date.ParseStrategy = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return Date.ParseStrategy(
            format: """
                \(day: .twoDigits)-\(month: .twoDigits)-\(year: .padded(4)) \
                \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits)
                """,
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: .gmt,
            calendar: calendar,
            isLenient: false
        )
    }()

    /// Captures 1–6 of `pattern`: day, month, year, hour, minute, optional second.
    private static func date(from output: AnyRegexOutput) -> Date? {
        let field = { (index: Int) in output[index].substring.map(String.init) ?? "00" }
        let canonical = "\(field(1))-\(field(2))-\(field(3)) \(field(4)):\(field(5)):\(field(6))"
        guard let zone = timeZone, let wallClock = try? Date(canonical, strategy: wallClockStrategy) else { return nil }
        return resolve(wallClock: wallClock, in: zone)
    }

    /// Turns a wall-clock time (encoded as a UTC instant) into the instant it denotes in `zone`.
    ///
    /// Done by hand so the result does not depend on the platform's DST policy:
    /// a time skipped by the spring-forward change does not exist and gives nil;
    /// a time repeated by the fall-back change is ambiguous and gives its **first** occurrence.
    static func resolve(wallClock: Date, in zone: TimeZone) -> Date? {
        let day: TimeInterval = 86_400
        let offsets = Set([-day, day].map { zone.secondsFromGMT(for: wallClock.addingTimeInterval($0)) })
        let instants = offsets.compactMap { offset -> Date? in
            let instant = wallClock.addingTimeInterval(-TimeInterval(offset))
            return zone.secondsFromGMT(for: instant) == offset ? instant : nil
        }
        return instants.min()
    }

    /// Swift Regex has no look-behind: reject a match glued to a previous digit (`123-04-2025…`).
    private static func isPrecededByDigit(_ range: Range<String.Index>, in text: String) -> Bool {
        guard range.lowerBound > text.startIndex else { return false }
        let previous = text[text.index(before: range.lowerBound)]
        return previous.isASCII && previous.isNumber
    }
}
