import Foundation

/// Codec for `mpstorage_last_rw`, a local-time string `dd-MM-yyyy HH:mm:ss` (`MPStorage.m:969-978`).
/// The legacy value `-` (never synchronised) reads as nil.
enum LastSyncDate {
    private static var style: Date.VerbatimFormatStyle {
        Date.VerbatimFormatStyle(
            format: """
            \(day: .twoDigits)-\(month: .twoDigits)-\(year: .defaultDigits) \
            \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits)
            """,
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: .current,
            calendar: Calendar(identifier: .gregorian)
        )
    }

    /// Parses the stored string.
    static func date(from text: String) -> Date? {
        try? Date(text, strategy: style.parseStrategy)
    }

    /// Formats a date for storage.
    static func string(from date: Date) -> String {
        date.formatted(style)
    }
}
