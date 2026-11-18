import Foundation

/// The relative date of a row, as legacy words it (`Classes/AQTableViewController.m:293-330` @ 87fe0d1c, the same thresholds as
/// `AQPlusView.swift:208-231` @ 87fe0d1c): "il y a 1 h" up to the first hour, hours up to 23, days up to 30, months (31-day) up to
/// 12, then "il y a 1 an" and years.
enum QualityAlertAge {
    /// The label for an alert published at `date`, nil when the feed date could not be read (legacy dated it "now" and showed
    /// "il y a 1 h" forever, `AQPlusView.swift:203`).
    static func label(since date: Date?, now: Date) -> String? {
        guard let date else { return nil }
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        let hours = seconds / 3600
        let days = seconds / (24 * 3600)
        let months = days / 31
        let years = days / 365
        if hours <= 1 { return "il y a 1 h" }
        if hours <= 23 { return "il y a \(hours) h" }
        if days <= 30 { return "il y a \(days) j" }
        if months <= 12 { return "il y a \(months) mois" }
        if years <= 1 { return "il y a 1 an" }
        return "il y a \(years) ans"
    }
}
