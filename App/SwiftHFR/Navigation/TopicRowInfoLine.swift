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
        guard let post = topic.lastPost, let date = post.date else { return nil }
        let when = dateLabel(date, now: now)
        // Legacy prints " - date" without an author (`aAuthorOfLastPost` is ""): the date still shows (#857).
        return post.author.isEmpty ? when : "\(post.author) - \(when)"
    }

    /// Legacy's rules (`ObjCTopicListParser.m:420-454` @ 87fe0d1c): "HH:mm" for a date ahead of the clock, "il y a 1 min" under a
    /// minute, "il y a 13 min", "il y a 3 h" under 24 hours, then "06/11/26"; all in Paris time, the zone HFR serves its dates in.
    static func dateLabel(_ date: Date, now: Date = .now) -> String {
        let elapsed = now.timeIntervalSince(date)
        if elapsed < 0 {
            let parts = parisCalendar.dateComponents([.hour, .minute], from: date)
            return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        }
        if elapsed < 24 * 3600 {
            let minutes = max(1, Int(elapsed / 60))
            return minutes < 60 ? "il y a \(minutes) min" : "il y a \(minutes / 60) h"
        }
        let parts = parisCalendar.dateComponents([.day, .month, .year], from: date)
        return String(format: "%02d/%02d/%02d", parts.day ?? 0, parts.month ?? 0, (parts.year ?? 0) % 100)
    }

    private static var parisCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris") ?? .gmt
        return calendar
    }
}
