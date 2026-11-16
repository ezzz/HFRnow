import Foundation
import HFRModels

// Port of HFRswift/Swift/MPListView.swift (MPRowView.interlocutorLabel, trailingLabel) @ 87fe0d1c, lines 775-793.
// Differences: a group row shows « ⚑ page / pages » whenever the MPStorage flag is known, and never « Interlocuteurs multiples »
// (the group icon says it; operator, #900); the time is « x min » under 2 h, « x h » under 24 h, the date beyond (legacy printed
// the cell's own text, `aDateOfLastPost`).
/// The one info line under an MP row's title: `leading` on the left, `trailing` (« last poster - time ») on the right.
struct MessageRowInfoLine: Equatable {
    /// The interlocutor of a one-to-one thread; « ⚑ page / pages » of a group thread (nil without a flag).
    var leading: String?
    /// « last poster - time », or the poster alone when the post has no date; nil without a last post.
    var trailing: String?

    /// What the row shows. `flagLabel` is the group's MPStorage position (`MessageListModel.flagLabel(for:)`).
    static func make(thread: PrivateMessageThread, flagLabel: String?, now: Date = .now) -> MessageRowInfoLine {
        let leading: String?
        // The same group test as the avatar: a span without tooltip stays non-group in the parser but reads « Interlocuteurs multiples ».
        if MessageRowView.avatarSubject(of: thread).isGroup {
            leading = flagLabel
        } else {
            let who = thread.summary.starterOrInterlocutors.trimmingCharacters(in: .whitespacesAndNewlines)
            leading = who.isEmpty ? nil : who
        }
        return MessageRowInfoLine(leading: leading, trailing: trailing(of: thread.summary.lastPost, now: now))
    }

    /// « poster - time » (legacy `trailingLabel`, `MPListView.swift:789-792`).
    static func trailing(of post: LastPost?, now: Date) -> String? {
        guard let post else { return nil }
        let author = post.author.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let date = post.date else { return author.isEmpty ? nil : author }
        let time = age(of: date, now: now)
        return author.isEmpty ? time : "\(author) - \(time)"
    }

    /// « x min » under 2 h (at least 1), « x h » under 24 h, the date (dd/MM/yyyy, Paris time as HFR serves it) beyond.
    static func age(of date: Date, now: Date) -> String {
        let seconds = max(now.timeIntervalSince(date), 0)
        let minutes = Int(seconds / 60)
        if minutes < 120 { return "\(max(minutes, 1)) min" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) h" }
        // The locale and the time zone are arguments of the style: its `timeZone(_:)` modifier prints a zone symbol.
        let style = Date.FormatStyle(locale: Locale(identifier: "fr_FR"), timeZone: TimeZone(identifier: "Europe/Paris") ?? .gmt)
            .day(.twoDigits).month(.twoDigits).year()
        return date.formatted(style)
    }
}
