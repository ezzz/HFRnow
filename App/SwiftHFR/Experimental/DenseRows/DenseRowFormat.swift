import Foundation
import HFRModels
import SwiftUI

/// EXPERIMENTAL(denseRows, #905, #973): the one formatter of the dense rows, topic and MP, so their rules cannot drift apart.
/// Pure rules, no view: who (the last poster, never the starter), no reply count, « ⚑ x / y » pages, no « il y a », one line.
enum DenseRowFormat {
    /// How a last-post age is written.
    enum AgeStyle {
        /// « 14 minutes », « 3 heures », « 5 jours », « 2 semaines », « 3 mois », « 2 ans » (topic rows, #905 E).
        case wide
        /// « 6 min », « 2 h », then the date (MP rows, #973 D).
        case compact
    }

    /// The weight of the section titles of the topic lists (#905 F): the default section header does not read as bold.
    static let sectionTitleWeight: Font.Weight = .bold

    /// Whether the lists draw the dense rows: the option, off where no settings are in the environment (previews, hosted tests).
    @MainActor static func isOn(_ experimental: ExperimentalSettings?) -> Bool {
        ExperimentalSettings.isOn(.denseRows, in: experimental)
    }

    /// The section titles' weight: bold with the option on, nil (the list's own weight, untouched) with it off.
    @MainActor static func titleWeight(_ experimental: ExperimentalSettings?) -> Font.Weight? {
        isOn(experimental) ? sectionTitleWeight : nil
    }

    /// The info line of a dense topic row: « ⚑ lue / total » when the flag page is known, the last poster, then the age of the
    /// last post. No reply count, no starter, no « il y a ». Nil when nothing is known.
    static func topicInfo(_ topic: TopicSummary, showsFlag: Bool = true, now: Date = .now) -> String? {
        var parts: [String] = []
        if showsFlag, let footer = TopicRowCues.pageFooter(topic) { parts.append(footer) }
        parts.append(contentsOf: lastPost(topic.lastPost, style: .wide, now: now, skipping: nil))
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The info line of a dense MP row (#973): the interlocutor of a one-to-one thread or « ⚑ page / pages » of a group (never
    /// « Interlocuteurs multiples », no reply count), then the last poster and the age. Nil when nothing is known.
    static func messageInfo(thread: PrivateMessageThread, flagLabel: String?, now: Date = .now) -> String? {
        let leading = MessageRowInfoLine.make(thread: thread, flagLabel: flagLabel, now: now).leading
        var parts = leading.map { [$0] } ?? []
        parts.append(contentsOf: lastPost(thread.summary.lastPost, style: .compact, now: now, skipping: leading))
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The age of `date` without « il y a ». A date ahead of the clock reads as the shortest age.
    static func age(of date: Date, now: Date = .now, style: AgeStyle) -> String {
        switch style {
        case .compact:
            return MessageRowInfoLine.age(of: date, now: now)
        case .wide:
            let minutes = max(Int(now.timeIntervalSince(date) / 60), 1)
            if minutes < 60 { return FrenchPlural.count(minutes, "minute", "minutes") }
            let hours = minutes / 60
            if hours < 24 { return FrenchPlural.count(hours, "heure", "heures") }
            let days = hours / 24
            if days < 7 { return FrenchPlural.count(days, "jour", "jours") }
            if days < 30 { return FrenchPlural.count(days / 7, "semaine", "semaines") }
            if days < 365 { return "\(days / 30) mois" }
            return FrenchPlural.count(days / 365, "an", "ans")
        }
    }

    /// One line, ended by « … » when it does not fit. An accessibility text size lifts the limit so nothing is cut off: a deliberate
    /// departure from « never wraps » (#905 E), because a line cut at that size cannot be read at all.
    static func lineLimit(isAccessibilitySize: Bool) -> Int? { isAccessibilitySize ? nil : 1 }

    /// The last poster, then the age; the poster is left out when `skipping` already says it (a one-to-one thread's interlocutor).
    private static func lastPost(_ post: LastPost?, style: AgeStyle, now: Date, skipping: String?) -> [String] {
        guard let post else { return [] }
        let author = post.author.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String] = []
        if !author.isEmpty, author != skipping { parts.append(author) }
        if let date = post.date { parts.append(age(of: date, now: now, style: style)) }
        return parts
    }
}

extension View {
    /// EXPERIMENTAL(denseRows, #905): the dense info line never wraps; SwiftUI ends it with « … » when it does not fit.
    func denseInfoLine(isAccessibilitySize: Bool) -> some View {
        lineLimit(DenseRowFormat.lineLimit(isAccessibilitySize: isAccessibilitySize)).truncationMode(.tail)
    }
}

extension View {
    /// EXPERIMENTAL(denseRows, #905 F): applies `weight` only when there is one, so the off path adds no modifier.
    @ViewBuilder func sectionTitleWeight(_ weight: Font.Weight?) -> some View {
        if let weight { fontWeight(weight) } else { self }
    }
}
