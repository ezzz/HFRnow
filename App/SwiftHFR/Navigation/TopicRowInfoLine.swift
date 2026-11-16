import Foundation
import HFRModels

/// The info line of the default topic row, as pure rules (#817, #857): "⚑ lue / total" or "N pages" on the left, "dernier posteur - date"
/// on the right.
enum TopicRowInfoLine {
    /// Left side: the flag footer when the flagged page is known (legacy `footerLeft`, `MainWindow.swift:455-466` @ 87fe0d1c), else the
    /// page count with the poll mark ("N page(s) ≣"). `showsFlag` false (flag removed or not a flagged list) skips the footer.
    static func leading(_ topic: TopicSummary, showsFlag: Bool = true) -> String {
        if showsFlag, let footer = TopicRowCues.pageFooter(topic) { return footer }
        let pollSuffix = topic.isPoll ? " \u{2263}" : ""
        return "\(topic.pageCount) \(topic.pageCount > 1 ? "pages" : "page")\(pollSuffix)"
    }

    /// Right side: "<last poster> - <date>", nil unless both are known (legacy `footerRight`, `MainWindow.swift:495-504` @ 87fe0d1c, from
    /// `aAuthorOfLastPost` and `aDateOfLastPost`). The starter is never shown in its place.
    static func trailing(_ topic: TopicSummary, now: Date = .now) -> String? {
        guard let post = topic.lastPost, let date = post.date, !post.author.isEmpty else { return nil }
        return "\(post.author) - \(dateLabel(date, now: now))"
    }

    /// "il y a 13 min" and "il y a 3 h" under 24 hours (a date ahead of the clock reads "il y a 1 min"), then "06/11/26" in Paris time,
    /// the zone HFR serves its dates in.
    static func dateLabel(_ date: Date, now: Date = .now) -> String {
        let elapsed = now.timeIntervalSince(date)
        if elapsed < 24 * 3600 {
            let minutes = max(1, Int(elapsed / 60))
            return minutes < 60 ? "il y a \(minutes) min" : "il y a \(minutes / 60) h"
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris") ?? .gmt
        let parts = calendar.dateComponents([.day, .month, .year], from: date)
        return String(format: "%02d/%02d/%02d", parts.day ?? 0, parts.month ?? 0, (parts.year ?? 0) % 100)
    }
}
