import Foundation
import HFRStorage

/// What the picker prints for an archived draft (legacy `ReplyDraftSource.title`, `previewText`, `formattedDate`,
/// `AnswerView.swift:103-121, 1930-1998` @ 87fe0d1c).
enum ArchivedDraftsFormat {
    static func title(of source: ArchivedDraftSource) -> String {
        switch source {
        case .quickReply: "Réponse rapide"
        case .quote: "Citation"
        }
    }

    /// The text on one line (line breaks become spaces), "Brouillon vide" when nothing is left.
    static func preview(of text: String) -> String {
        let line = text
            .replacing("\r\n", with: "\n").replacing("\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return line.isEmpty ? "Brouillon vide" : line
    }

    /// "Aujourd’hui 14:05", "Hier 14:05", else the short date and time.
    static func dateLabel(
        of date: Date, now: Date = .now, calendar: Calendar = .current, locale: Locale = .current
    ) -> String {
        // Legacy's fixed `HH:mm` (`AnswerView.swift:1989`), whatever the device's 12/24-hour setting.
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let time = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        if calendar.isDate(date, inSameDayAs: now) { return "Aujourd’hui \(time)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Hier \(time)"
        }
        let full = Date.FormatStyle(date: .numeric, time: .shortened, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        return date.formatted(full)
    }
}
