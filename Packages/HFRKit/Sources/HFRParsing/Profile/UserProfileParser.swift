import Foundation
import SwiftSoup

/// Reads a public profile page, `/hfr/profil-<id>.htm`: labelled fields in sections, avatar, personal smileys, link rows.
///
/// Port of `UserProfileHTMLParser.parse` (`HFRswift/Swift/UserProfileView.swift:113-430`), which cut the page with regular
/// expressions; this version walks the DOM and reproduces its output on the two captures (R56a, R56b, LOT-005 oracle).
/// The page is read the same way for a visitor and a logged-in member; no capture shows another shape. Every URL it returns is
/// resolved against the forum root and kept only when it is `http(s)` (ADR 0006 amendment 1).
public enum UserProfileParser {
    /// Parses one page.
    /// - Parameter html: the page, decoded as UTF-8.
    /// - Throws: `malformedDocument` when the HTML backend cannot read the document; `missingElement` when the page holds
    ///   no profile at all (no section, no pseudo, no avatar, no smiley), for instance a login page or an error notice.
    public static func parse(html: String) throws(ParsingError) -> UserProfile {
        let document = try HTMLDocumentLoader.document(from: html)
        let root: Element = (try? document.select("table.main").first()) ?? document.body() ?? document
        var state = State()
        for row in (try? root.getElementsByTag("tr").array()) ?? [] {
            read(row: row, into: &state)
        }
        let sections = state.sections.filter { !$0.fields.isEmpty }
        let fields = sections.flatMap(\.fields)
        let pseudo = HFRText.normalizedPseudo(value(titled: "Pseudo", in: fields) ?? "")
        guard !sections.isEmpty || !pseudo.isEmpty || state.avatarURL != nil || !state.smileys.isEmpty else {
            throw .missingElement("table.main profile rows")
        }
        let summary = UserProfileSummaryItem.Kind.allCases.compactMap { kind in
            value(titled: kind.fieldTitle, in: fields).map { UserProfileSummaryItem(kind: kind, value: $0) }
        }
        return UserProfile(
            pseudo: pseudo,
            status: value(titled: "Statut", in: fields),
            avatarURL: state.avatarURL,
            messageCount: value(titled: UserProfileSummaryItem.Kind.messageCount.fieldTitle, in: fields).flatMap(count),
            joinDate: value(titled: UserProfileSummaryItem.Kind.joinDate.fieldTitle, in: fields).flatMap(day),
            lastMessageDate: value(titled: UserProfileSummaryItem.Kind.lastMessageDate.fieldTitle, in: fields)
                .flatMap(HFRDate.date(from:)),
            summary: summary,
            sections: sections,
            personalSmilies: state.smileys,
            actions: state.actions
        )
    }

    // MARK: - Implementation

    /// What the row loop accumulates. Sections are filtered afterwards: the index in a section id counts all headers.
    private struct State {
        var sections: [UserProfileSection] = []
        var avatarURL: URL?
        var smileys: [UserProfileSmiley] = []
        var actions: [UserProfileAction] = []
    }

    /// Handles one `tr`: a header opens a section, a `profil` row may carry the avatar, smileys, a link or a field
    /// (`UserProfileView.swift:134-218`). Class tests are substring tests, like the legacy regexes.
    private static func read(row: Element, into state: inout State) {
        let className = row.hasAttr("class") ? (try? row.attr("class")) ?? "" : ""
        if className.contains("cBackHeader") {
            let title = UserProfileText.clean(row)
            if !title.isEmpty {
                state.sections.append(UserProfileSection(id: "section|\(title)|\(state.sections.count)", title: title, fields: []))
            }
            return
        }
        guard className.contains("profil") else { return }

        if state.avatarURL == nil {
            state.avatarURL = avatarURL(in: row)
        }
        for smiley in smileys(in: row) where !state.smileys.contains(where: { $0.id == smiley.id }) {
            state.smileys.append(smiley)
        }
        guard let sectionIndex = state.sections.indices.last else { return }
        readCells(of: row, sectionIndex: sectionIndex, into: &state)
    }

    /// The label and value cells of a `profil` row, or its full-width link cell.
    private static func readCells(of row: Element, sectionIndex: Int, into state: inout State) {
        let sectionTitle = state.sections[sectionIndex].title
        let cells = row.children().array().filter { $0.tagName() == "td" }
        if let wide = cells.first(where: { hasClass($0, "profilCase3") && $0.hasAttr("colspan") }) {
            if let action = action(in: wide, sectionTitle: sectionTitle) {
                append(action, to: &state.actions)
            }
            return
        }
        guard
            let titleCell = cells.first(where: { hasClass($0, "profilCase2") }),
            let valueCell = cells.first(where: { hasClass($0, "profilCase3") })
        else { return }
        let title = UserProfileText.cleanTitle(titleCell)
        guard !title.isEmpty else { return }

        let link = firstLink(in: valueCell)
        if title.localizedCaseInsensitiveContains("Configuration"), hasLink(valueCell) {
            // Classified by the presence of a link, not by its target: a refused target (other host, `javascript:`) drops
            // the row, which is then neither an action nor a field.
            if let target = firstLink(in: valueCell, forumOnly: true) {
                append(configurationAction(title: title, url: target), to: &state.actions)
            }
        } else {
            let value = UserProfileText.clean(valueCell)
            state.sections[sectionIndex].fields.append(
                UserProfileField(id: "field|\(sectionTitle)|\(title)", title: title, value: value, url: link)
            )
        }
    }

    /// Whether the element holds an `a[href]`, whatever its target.
    private static func hasLink(_ element: Element) -> Bool {
        ((try? element.getElementsByTag("a").array()) ?? []).contains { $0.hasAttr("href") }
    }

    /// The hardware configuration row is a link, not a value: it becomes an action named after the row.
    private static func configurationAction(title: String, url: URL) -> UserProfileAction {
        UserProfileAction(
            id: "action|\(UserProfileAction.Kind.configuration.rawValue)|\(url.absoluteString)",
            title: title,
            subtitle: nil,
            url: url,
            kind: .configuration
        )
    }

    private static func append(_ action: UserProfileAction, to actions: inout [UserProfileAction]) {
        if !actions.contains(where: { $0.id == action.id }) {
            actions.append(action)
        }
    }

    private static func hasClass(_ element: Element, _ fragment: String) -> Bool {
        element.hasAttr("class") && ((try? element.attr("class")) ?? "").contains(fragment)
    }

    /// A full-width link cell: kind from the link text, as legacy (`UserProfileView.swift:296-334`). Dropped without a usable
    /// link or text.
    private static func action(in cell: Element, sectionTitle: String) -> UserProfileAction? {
        guard let url = firstLink(in: cell, forumOnly: true) else { return nil }
        let text = UserProfileText.clean(cell)
        guard !text.isEmpty else { return nil }
        let lowered = text.lowercased()
        let kind: UserProfileAction.Kind
        if lowered.contains("message privé") {
            kind = .privateMessage
        } else if lowered.contains("tous ses messages") {
            kind = .allMessages
        } else if lowered.contains("liste de contacts") {
            kind = .addContact
        } else if sectionTitle.lowercased().contains("transaction") || lowered.contains("transaction") {
            kind = .transaction
        } else {
            kind = .link
        }
        let id = "action|\(kind.rawValue)|\(url.absoluteString)"
        return UserProfileAction(id: id, title: text, subtitle: sectionTitle, url: url, kind: kind)
    }

    /// First image of the first `avatar_center` block of the row (`UserProfileView.swift:336-345`).
    private static func avatarURL(in row: Element) -> URL? {
        guard
            let block = row.firstDescendant(matching: .contains("avatar_center")),
            let image = (try? block.getElementsByTag("img").array())?.first(where: { $0.hasAttr("src") }),
            let source = try? image.attr("src")
        else { return nil }
        return resolved(source)
    }

    /// Images under `/images/perso/` with the `[:code]` text that precedes them (`UserProfileView.swift:347-372`).
    ///
    /// Legacy dropped a repeated smiley only against earlier rows; here a repeat within one row is dropped too.
    private static func smileys(in row: Element) -> [UserProfileSmiley] {
        var found: [UserProfileSmiley] = []
        for image in (try? row.getElementsByTag("img").array()) ?? [] {
            guard
                image.hasAttr("src"), let source = try? image.attr("src"),
                source.contains("/images/perso/"), let url = resolved(source)
            else { continue }
            let alt = image.hasAttr("alt") ? try? image.attr("alt") : nil
            let title = image.hasAttr("title") ? try? image.attr("title") : alt
            var code = codeBefore(image)
            if code.isEmpty {
                code = title.map { "[:\($0)]" } ?? url.lastPathComponent
            }
            let smiley = UserProfileSmiley(id: "smiley|\(code)|\(url.absoluteString)", code: code, imageURL: url, title: title)
            if !found.contains(where: { $0.id == smiley.id }) {
                found.append(smiley)
            }
        }
        return found
    }

    /// The `[:code]` written right before an image, with only whitespace between; empty when there is none.
    private static func codeBefore(_ image: Element) -> String {
        guard let text = image.previousSibling() as? TextNode else { return "" }
        let preceding = text.getWholeText().replacing(/\s+$/, with: "")
        guard let match = preceding.firstMatch(of: /\[:[^\]]+\]$/) else { return "" }
        return UserProfileText.clean(String(match.output))
    }

    /// Absolute URL of the first link, or nil when it has none or the target is refused.
    ///
    /// `forumOnly` is for links the app may follow with the session (actions): only `https://forum.hardware.fr` survives, by the
    /// rule of `HFRURL.forumRelativePath` (LESSONS 37). Without it any `http(s)` URL is kept: field links are member-supplied.
    private static func firstLink(in element: Element, forumOnly: Bool = false) -> URL? {
        guard
            let link = (try? element.getElementsByTag("a").array())?.first(where: { $0.hasAttr("href") }),
            let href = try? link.attr("href")
        else { return nil }
        guard forumOnly else { return resolved(href) }
        return HFRURL.forumRelativePath(href).flatMap { URL(string: $0, relativeTo: HFRURL.base)?.absoluteURL }
    }

    /// Links and image sources are resolved against the forum root. A raw space in a path (personal smiley files, HFR-PROTOCOL
    /// §6b) is percent-encoded first: `URL(string:)` refuses it on some platforms.
    private static func resolved(_ raw: String) -> URL? {
        HFRURL.absolute(raw.trimmingCharacters(in: .whitespacesAndNewlines).replacing(" ", with: "%20"))
    }

    /// Text of the first field whose title is `title` (case and accents ignored) and whose value is not empty.
    private static func value(titled title: String, in fields: [UserProfileField]) -> String? {
        fields.first { field in
            field.title.compare(title, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame && !field.value.isEmpty
        }?.value
    }

    /// Message count written with ASCII digits, optionally grouped by spaces (only `100` is captured).
    private static func count(_ text: String) -> Int? {
        let digits = text.filter { !$0.isWhitespace }
        guard !digits.isEmpty, digits.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        return Int(digits)
    }

    /// `dd/MM/yyyy` as midnight in the forum's time zone; validation is `HFRDate`'s.
    private static func day(_ text: String) -> Date? {
        guard let match = text.wholeMatch(of: /([0-9]{2})\/([0-9]{2})\/([0-9]{4})/) else { return nil }
        return HFRDate.date(from: "\(match.output.1)-\(match.output.2)-\(match.output.3) à 00:00")
    }
}
