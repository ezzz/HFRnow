import Foundation
import Testing
@testable import HFRParsing

@Suite("HFR dates (Europe/Paris)")
struct HFRDateTests {
    /// Expected instants written as UTC ISO 8601, independent of the code under test.
    static func utc(_ iso: String) -> Date? {
        try? Date(iso, strategy: .iso8601)
    }

    @Test(
        "List and message formats, winter and summer offsets",
        arguments: [
            ("05-01-2026 à 14:07", "2026-01-05T13:07:00Z"),          // CET, +01:00
            ("05-07-2026 à 14:07", "2026-07-05T12:07:00Z"),          // CEST, +02:00
            ("05-01-2026 à 14:07:33", "2026-01-05T13:07:33Z"),
            ("31-12-2025 à 23:59:59", "2025-12-31T22:59:59Z"),
            ("01-01-2026 à 00:00", "2025-12-31T23:00:00Z"),
            ("29-02-2024 à 12:00", "2024-02-29T11:00:00Z"),          // leap day
            ("  05-01-2026 à 14:07\n", "2026-01-05T13:07:00Z"),      // surrounding whitespace
            ("05-01-2026\u{00A0}à\u{00A0}14:07", "2026-01-05T13:07:00Z") // non-breaking spaces from &nbsp;
        ]
    )
    func parsesValidDates(text: String, iso: String) {
        #expect(HFRDate.date(from: text) == Self.utc(iso))
    }

    @Test(
        "DST boundaries: last minute before and first minute after each change",
        arguments: [
            ("30-03-2025 à 01:59", "2025-03-30T00:59:00Z"),
            ("30-03-2025 à 03:00", "2025-03-30T01:00:00Z"),
            ("26-10-2025 à 01:59", "2025-10-25T23:59:00Z"),
            ("26-10-2025 à 03:00", "2025-10-26T02:00:00Z")
        ]
    )
    func dstBoundaries(text: String, iso: String) {
        #expect(HFRDate.date(from: text) == Self.utc(iso))
    }

    @Test("A time skipped by spring-forward does not exist")
    func springForwardGap() {
        #expect(HFRDate.date(from: "30-03-2025 à 02:30") == nil)
        #expect(HFRDate.date(from: "30-03-2025 à 02:00:00") == nil)
    }

    @Test("A time repeated by fall-back resolves to its first occurrence (CEST)")
    func fallBackAmbiguity() {
        #expect(HFRDate.date(from: "26-10-2025 à 02:30") == Self.utc("2025-10-26T00:30:00Z"))
        #expect(HFRDate.date(from: "26-10-2025 à 02:00:00") == Self.utc("2025-10-26T00:00:00Z"))
    }

    @Test(
        "Invalid input gives nil",
        arguments: [
            "",
            "hier à 14:07",
            "05-01-2026 14:07",          // no `à`
            "05-01-2026 a 14:07",        // `a` is not `à`
            "5-01-2026 à 14:07",         // HFR pads days
            "05-1-2026 à 14:07",
            "05-01-26 à 14:07",          // two-digit year
            "05-01-2026 à 4:07",
            "31-02-2026 à 10:00",        // no such day
            "29-02-2025 à 10:00",        // not a leap year
            "00-01-2026 à 10:00",
            "05-13-2026 à 10:00",
            "05-01-2026 à 24:00",
            "05-01-2026 à 10:60",
            "05-01-2026 à 10:00:60",
            "05-01-2026 à 14:07:3",
            "05-01-2026 à 14:07:331",
            "05-01-2026 à 14:07:",
            "05-01-2026 à 14:07 extra",  // `date(from:)` wants the whole string
            "٠٥-٠١-٢٠٢٦ à ١٤:٠٧"          // non-ASCII digits
        ]
    )
    func rejectsInvalid(text: String) {
        #expect(HFRDate.date(from: text) == nil)
    }

    @Test(
        "First date inside a longer text",
        arguments: [
            ("Posté le 05-01-2026 à 14:07:33", "2026-01-05T13:07:33Z"),
            ("Message édité par Pseudo le 05-07-2026 à 09:00:01", "2026-07-05T07:00:01Z"),
            ("05-01-2026 à 14:07 then 06-01-2026 à 14:07", "2026-01-05T13:07:00Z"),
            ("x 31-02-2026 à 10:00 then 06-01-2026 à 14:07", "2026-01-06T13:07:00Z") // invalid first date is skipped
        ]
    )
    func firstDateInText(text: String, iso: String) {
        #expect(HFRDate.firstDate(in: text) == Self.utc(iso))
    }

    @Test(
        "No date in text, or a date glued to other digits",
        arguments: [
            "Posté le", "105-01-2026 à 14:07", "05-01-2026 à 14:071", "",
            "Posté le 05-01-2026 à 14:07:331",   // three-digit seconds: refused, not read as 14:07:00
            "Posté le 05-01-2026 à 14:07:3 x",   // one-digit seconds
            "Posté le 05-01-2026 à 14:07:",      // dangling colon
            "Posté le 05-01-2026 à 14:07:33:12"
        ]
    )
    func noFirstDate(text: String) {
        #expect(HFRDate.firstDate(in: text) == nil)
    }

    @Test("Time zone is Europe/Paris")
    func timeZoneIdentifier() {
        #expect(HFRDate.timeZone?.identifier == "Europe/Paris")
    }
}
